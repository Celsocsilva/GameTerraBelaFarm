extends Node3D
class_name EucalyptusGrove
## Plantações de eucalipto nas bordas dos canteiros e junto ao rio (FV-WOOD-001).
##
## - Estação: a arte de todas as árvores segue SeasonClock (data e hemisfério
##   do aparelho; configurável por hemisphere_mode / forced_season ou pelas
##   chaves terrabela/seasons/* do projeto). Revisada a cada season_check_seconds.
## - Corte (FV-WOOD-002): parado perto (WoodConfig.CHOP_REACH) de um eucalipto
##   em pé, o fazendeiro dá CHOP_HITS golpes com o machado animado (quadros do
##   axe_only_animation.gif). Cada golpe, no quadro de impacto, avança um
##   estágio da arte: entalhe, corte fundo, inclinada. Depois a árvore cai
##   (FALL_SECONDS), vira o toco com as toras (LOGS_SECONDS) e as toras
##   (LOGS_PER_TREE) voam para a mochila pelo mesmo fluxo de reserva da colheita
##   (HarvestInventory.try_reserve + commit). O toco some e a árvore rebrota.
##   Saindo de perto antes da inclinação, o corte cancela.
## - A mochila leva um produto por vez: com tomates nela, o corte não começa e
##   chop_blocked avisa a HUD.

signal tree_felled(tree: EucalyptusTree, logs: int)
signal logs_delivered(units: int, total: int)
signal chop_blocked(reason: StringName)
signal season_changed(season: StringName)

const TREE_SCRIPT := preload("res://scripts/forestry/eucalyptus_tree.gd")
const FLYER_TEXTURE := preload("res://assets/items/logs/log_bundle_4.png")
const FLIGHT_TIME := 0.45
const FLIGHT_HEIGHT := 1.6
const AXE_FRAMES: Array[Texture2D] = [
    preload("res://assets/vfx/axe/axe_chop_01.png"),
    preload("res://assets/vfx/axe/axe_chop_02.png"),
    preload("res://assets/vfx/axe/axe_chop_03.png"),
    preload("res://assets/vfx/axe/axe_chop_04.png"),
    preload("res://assets/vfx/axe/axe_chop_05.png"),
    preload("res://assets/vfx/axe/axe_chop_06.png"),
    preload("res://assets/vfx/axe/axe_chop_07.png"),
    preload("res://assets/vfx/axe/axe_chop_08.png"),
]
## Altura do machado na tela (m) e posição: entre o fazendeiro e a árvore.
const AXE_SIZE := 1.25
const AXE_HEIGHT := 1.15

## "auto" (locale do aparelho), "north" ou "south". Vazio usa a configuração do projeto.
@export var hemisphere_mode: String = ""
## Força uma estação ("spring", "summer", "autumn", "winter"); vazio = data real.
@export var forced_season: String = ""
@export_range(5.0, 600.0, 5.0) var season_check_seconds: float = 30.0

var trees: Array[EucalyptusTree] = []
var season: StringName = &""
## Registro para testes: {"tree", "logs", "from", "to"}.
var flight_log: Array[Dictionary] = []
var _inventory: HarvestInventory
var _intake: Node3D
var _chop_tree: EucalyptusTree
## Segundos desde o começo do corte atual.
var _chop_time := 0.0
var _hits_done := 0
## Fase depois dos golpes: &"" (golpeando), &"leaning", &"fallen".
var _fall_phase: StringName = &""
var _phase_time := 0.0
var _farmer_pos := Vector3.ZERO
var axe: Sprite3D
var _reservation: HarvestInventory.Reservation
var _flights: Array[Dictionary] = []
var _season_timer := 0.0
var _blocked_notified := false

## Planta um eucalipto em cada ponto (XZ do mundo; y é ignorado).
func setup(points: Array[Vector3], inventory: HarvestInventory, intake: Node3D) -> void:
    _inventory = inventory
    _intake = intake
    axe = Sprite3D.new()
    axe.name = "Axe"
    axe.texture = AXE_FRAMES[0]
    axe.pixel_size = AXE_SIZE / float(AXE_FRAMES[0].get_height())
    axe.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    axe.shaded = false
    axe.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    axe.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    axe.render_priority = 6
    axe.no_depth_test = true
    axe.top_level = true
    axe.visible = false
    add_child(axe)
    for index in points.size():
        var tree := TREE_SCRIPT.new() as EucalyptusTree
        tree.name = "Eucalyptus_%02d" % index
        tree.position = Vector3(points[index].x, 0.0, points[index].z)
        add_child(tree)
        trees.append(tree)
    refresh_season(true)

func get_tree_count() -> int:
    return trees.size()

func count_in_state(state: StringName) -> int:
    var count := 0
    for tree in trees:
        if tree.state == state:
            count += 1
    return count

## Recalcula a estação e troca a arte se mudou (ou sempre, com force).
func refresh_season(force: bool = false) -> void:
    var now := SeasonClock.current_season(hemisphere_mode, forced_season)
    if now == season and not force:
        return
    season = now
    for tree in trees:
        tree.set_season(season)
    season_changed.emit(season)

func set_forced_season(value: String) -> void:
    forced_season = value
    refresh_season(true)

func _process(delta: float) -> void:
    _season_timer += delta
    if _season_timer >= season_check_seconds:
        _season_timer = 0.0
        refresh_season()
    for tree in trees:
        tree.tick(delta)

## Árvore em pé mais próxima dentro do alcance (null se nenhuma).
func get_tree_in_reach(world_pos: Vector3, reach: float = WoodConfig.CHOP_REACH) -> EucalyptusTree:
    var best: EucalyptusTree = null
    var best_distance := reach
    for tree in trees:
        if not tree.is_choppable():
            continue
        var distance := Vector2(tree.global_position.x - world_pos.x, tree.global_position.z - world_pos.z).length()
        if distance <= best_distance:
            best = tree
            best_distance = distance
    return best

func is_chopping() -> bool:
    return _chop_tree != null

## Duração de um ciclo do machado (um golpe) em segundos.
static func get_swing_seconds() -> float:
    var total := 0
    for ms in WoodConfig.AXE_FRAME_MS:
        total += ms
    return float(total) / 1000.0 / WoodConfig.AXE_SPEED

## Momento (s, dentro do ciclo) em que a lâmina bate no tronco.
static func get_impact_offset() -> float:
    var total := 0
    for i in WoodConfig.AXE_FRAME_MS.size():
        if i == WoodConfig.AXE_IMPACT_FRAME:
            break
        total += WoodConfig.AXE_FRAME_MS[i]
    return float(total) / 1000.0 / WoodConfig.AXE_SPEED

## Quadro do machado no tempo t (s) de um ciclo.
static func axe_frame_at(t: float) -> int:
    var ms := fposmod(t, get_swing_seconds()) * 1000.0 * WoodConfig.AXE_SPEED
    for i in WoodConfig.AXE_FRAME_MS.size():
        ms -= WoodConfig.AXE_FRAME_MS[i]
        if ms < 0.0:
            return i
    return WoodConfig.AXE_FRAME_MS.size() - 1

## Tempo total de um corte, do primeiro quadro do machado até as toras saírem.
static func get_total_chop_seconds() -> float:
    return get_swing_seconds() * (WoodConfig.CHOP_HITS - 1) + get_impact_offset() + WoodConfig.FALL_SECONDS + WoodConfig.LOGS_SECONDS

func get_hits_done() -> int:
    return _hits_done

## Chame por frame com a posição do fazendeiro.
func process_farmer_position(world_pos: Vector3, delta: float) -> void:
    if _inventory == null:
        return
    _farmer_pos = world_pos
    if _chop_tree:
        _advance_chop(world_pos, delta)
        return
    var tree := get_tree_in_reach(world_pos)
    if tree == null:
        _blocked_notified = false
        return
    var reason := get_block_reason()
    if reason != &"":
        if not _blocked_notified:
            _blocked_notified = true
            chop_blocked.emit(reason)
        return
    _reservation = _inventory.try_reserve(WoodConfig.ITEM, WoodConfig.LOGS_PER_TREE)
    if not _reservation.is_valid():
        return
    _chop_tree = tree
    _chop_time = 0.0
    _hits_done = 0
    _fall_phase = &""
    _phase_time = 0.0
    tree.start_chop()
    _update_axe()

func _advance_chop(world_pos: Vector3, delta: float) -> void:
    if _fall_phase == &"":
        var away := Vector2(_chop_tree.global_position.x - world_pos.x, _chop_tree.global_position.z - world_pos.z).length()
        if away > WoodConfig.CHOP_REACH * 1.3:
            _cancel_chop()
            return
        _chop_time += delta
        var swing := get_swing_seconds()
        var impact := get_impact_offset()
        # Um golpe a cada ciclo, no quadro de impacto.
        while _hits_done < WoodConfig.CHOP_HITS and _chop_time >= impact + swing * _hits_done:
            _hits_done += 1
            _chop_tree.hit()
        if _hits_done >= WoodConfig.CHOP_HITS:
            _fall_phase = &"leaning"
            _phase_time = _chop_time - (impact + swing * (WoodConfig.CHOP_HITS - 1))
        _update_axe()
        return
    _phase_time += delta
    if _fall_phase == &"leaning" and _phase_time >= WoodConfig.FALL_SECONDS:
        _fall_phase = &"fallen"
        _phase_time -= WoodConfig.FALL_SECONDS
        _chop_tree.fall()
    if _fall_phase == &"fallen" and _phase_time >= WoodConfig.LOGS_SECONDS:
        _finish_chop()
    _update_axe()

## Machado entre o fazendeiro e a árvore, virado para o lado da árvore; some
## depois do último golpe.
func _update_axe() -> void:
    if axe == null:
        return
    var swinging := _chop_tree != null and _fall_phase == &""
    var after_last_hit := _chop_tree != null and _fall_phase == &"leaning" and _phase_time < 0.15
    axe.visible = swinging or after_last_hit
    if not axe.visible:
        return
    var frame := axe_frame_at(_chop_time) if swinging else WoodConfig.AXE_IMPACT_FRAME
    axe.texture = AXE_FRAMES[frame]
    var tree_pos := _chop_tree.global_position
    var toward := Vector3(tree_pos.x - _farmer_pos.x, 0.0, tree_pos.z - _farmer_pos.z)
    var reach := minf(toward.length() * 0.55, 0.8)
    toward = toward.normalized() if toward.length() > 0.01 else Vector3.LEFT
    # A arte do GIF bate para a esquerda; árvore à direita espelha o machado.
    axe.flip_h = toward.x > 0.0
    axe.global_position = Vector3(_farmer_pos.x, AXE_HEIGHT, _farmer_pos.z) + toward * reach

func get_axe_frame() -> int:
    return AXE_FRAMES.find(axe.texture) if axe and axe.visible else -1

func get_fall_phase() -> StringName:
    return _fall_phase

## Por que o corte não pode começar agora: &"other_item" (mochila com outro
## produto), &"full" (sem espaço para as toras de uma árvore) ou &"" (pode).
func get_block_reason() -> StringName:
    if not _inventory.can_accept(WoodConfig.ITEM):
        return &"other_item"
    if _inventory.get_free_capacity() < WoodConfig.LOGS_PER_TREE:
        return &"full"
    return &""

func _cancel_chop() -> void:
    if _chop_tree:
        _chop_tree.cancel_chop()
    _chop_tree = null
    _fall_phase = &""
    _hits_done = 0
    if _reservation:
        _inventory.cancel(_reservation)
    _reservation = null
    _update_axe()

func _finish_chop() -> void:
    var tree := _chop_tree
    var reservation := _reservation
    _chop_tree = null
    _reservation = null
    _fall_phase = &""
    _update_axe()
    tree.fell()
    tree_felled.emit(tree, reservation.amount)
    _launch_logs(tree, reservation)

## As toras saem do toco e voam até o topo da mochila; só entram no inventário
## ao chegar (como os tomates da colheita).
func _launch_logs(tree: EucalyptusTree, reservation: HarvestInventory.Reservation) -> void:
    var from := tree.global_position + Vector3(0.0, 0.6, 0.0)
    var to := _intake.global_position if _intake and is_instance_valid(_intake) else from
    var flyer := Sprite3D.new()
    flyer.name = "FlyingLogs_%d" % flight_log.size()
    flyer.texture = FLYER_TEXTURE
    flyer.pixel_size = 0.9 / float(FLYER_TEXTURE.get_width())
    flyer.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    flyer.shaded = false
    flyer.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    flyer.top_level = true
    flyer.render_priority = 5
    add_child(flyer)
    flyer.global_position = from
    var flight := {"tree": tree, "logs": reservation.amount, "from": from, "to": to, "flyer": flyer, "reservation": reservation}
    _flights.append(flight)
    flight_log.append({"tree": tree, "logs": reservation.amount, "from": from, "to": to})
    var tween := create_tween()
    tween.tween_method(_move_flyer.bind(flight), 0.0, 1.0, FLIGHT_TIME)
    tween.tween_callback(_land.bind(flight))
    flight["tween"] = tween

func _move_flyer(t: float, flight: Dictionary) -> void:
    var flyer = flight["flyer"]
    if not is_instance_valid(flyer):
        return
    var target: Vector3 = _intake.global_position if _intake and is_instance_valid(_intake) else flight["to"]
    flyer.global_position = (flight["from"] as Vector3).lerp(target, t) + Vector3(0.0, 4.0 * t * (1.0 - t) * FLIGHT_HEIGHT, 0.0)
    flyer.scale = Vector3.ONE * lerpf(1.0, 0.7, t)

func _land(flight: Dictionary) -> void:
    if not _flights.has(flight):
        return
    _flights.erase(flight)
    var tween = flight.get("tween")
    if tween is Tween and (tween as Tween).is_valid():
        (tween as Tween).kill()
    var flyer = flight["flyer"]
    if is_instance_valid(flyer):
        flyer.queue_free()
    var units := _inventory.commit(flight["reservation"])
    _inventory.cancel(flight["reservation"])
    logs_delivered.emit(units, _inventory.get_amount(WoodConfig.ITEM))

func get_flying_count() -> int:
    return _flights.size()

## Termina os voos na hora (testes e capturas).
func finish_flights() -> void:
    for flight in _flights.duplicate():
        _land(flight)

## Pula o toco e a rebrota de todas as árvores (testes e capturas).
func regrow_all() -> void:
    for tree in trees:
        if tree.state != EucalyptusTree.GROWN and tree.state != EucalyptusTree.CHOPPING:
            tree.regrow()
