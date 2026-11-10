extends Node3D
class_name TomatoPile
## Pilha de caixas de tomate na parcela quadrada de 10% (FV-HELPER-001).
##
## O ajudante deposita aqui o que colhe (add_units). O fazendeiro, ao pisar na
## parcela, recolhe as caixas para a mochila (process_farmer_position), uma por
## vez, pelo mesmo fluxo de reserva da colheita (HarvestInventory.try_reserve +
## commit). Depois o fluxo é o de sempre: mochila -> balcão -> clientes.
##
## As caixas usam a mesma arte da mochila e do balcão (crate_full/crate_empty),
## viradas para a câmera. FV-STACK-001: UMA única pilha vertical por cultura
## (CrateStack), no máximo VISUAL_MAX caixas visíveis; acima disso a contagem
## lógica continua (capacidade MAX_CRATES) e um contador "x12" fica sobre a pilha.

signal stored_changed(stored_total: int)

const CRATE_FULL_TEXTURE := preload("res://assets/harvest/crate_full.png")
const CRATE_EMPTY_TEXTURE := preload("res://assets/harvest/crate_empty.png")
## Capacidade lógica da parcela (caixas).
const MAX_CRATES := 27
## Altura visual máxima da pilha (caixas).
const VISUAL_MAX := 5
## Distância X (centro a centro) entre as pilhas de culturas diferentes.
const STACK_SPACING := 1.2
## Inclinação da câmera do jogo (para o contador ficar logo acima do topo).
const VIEW_PITCH_DEGREES := 45.0
const CRATE_WIDTH := 1.05
## Camada de cima apoiada na borda da de baixo (mesma razão do balcão).
const LAYER_STEP := CRATE_WIDTH * 0.54
const JUMP_TIME := 0.4
const JUMP_HEIGHT := 1.4
## Intervalo entre duas caixas recolhidas pelo fazendeiro.
const PICKUP_INTERVAL := 0.12
## FV-POLISH-001: pilha organizada da área de coleta dos ajudantes — camadas de
## 3 colunas (horizontal) x 3 fileiras (profundidade), uma camada sobre a outra.
## Com MAX_CRATES = 27 a pilha cheia é um bloco 3 x 3 x 3, sem contador "xN".
const GRID_COLUMNS := 3
const GRID_ROWS := 3
const GRID_CRATE_WIDTH := 1.15
## Centro a centro: X entre colunas e Z entre fileiras (a de trás aparece logo
## acima da da frente na tela, como caixas arrumadas no chão).
const GRID_SPACING := Vector2(1.18, 1.45)

@export_range(1, 64, 1) var units_per_crate: int = 8
@export var item_id: StringName = &"tomato"
## Áreas de estoque próprias de uma cultura (milho, abóbora): a pilha fica no
## meio da parcela em vez do deslocamento por cultura (CrateStack.slot_x).
@export var centered: bool = false
## Folga além da borda da parcela em que o fazendeiro ainda recolhe.
@export_range(0.0, 2.0, 0.05) var pickup_margin: float = 0.4
## FV-WOOD-001: a mesma pilha serve a outros itens (ex.: fardos de madeira no
## balcão). Largura do caixote e capacidade lógica são ajustáveis; a arte vem
## de ItemArt pelo item_id.
@export_range(0.3, 3.0, 0.01) var crate_width: float = CRATE_WIDTH
@export_range(1, 999, 1) var max_crates: int = MAX_CRATES
## FV-POLISH-001: true nas parcelas de estoque dos ajudantes (grade 3 x 3 por
## camada); false no balcão (uma coluna, como antes).
@export var grid_layout: bool = false

## Pegada XZ da parcela (mundo).
var rect := Rect2()
## Registro para testes: {"index", "from", "to", "kind"} ("drop" ou "pickup").
var jump_log: Array[Dictionary] = []
var _stored := 0
var _crates: Array[Node3D] = []
var _in_flight: Dictionary = {}
var _flyers: Array = []
var _camera: Camera3D
var _pickup_cooldown := 0.0
var _count_label: Label3D

func setup(plot_rect: Rect2, crate_units: int) -> void:
    rect = plot_rect
    units_per_crate = crate_units
    position = Vector3(rect.get_center().x, 0.03, rect.get_center().y)
    for crate in _crates:
        crate.position = _slot_local(int(crate.get_meta("index")))
    if _count_label:
        _count_label.position = _count_label_local()

## Caixas desenhadas: na grade todas (até max_crates); na coluna, VISUAL_MAX.
func get_visual_max() -> int:
    return max_crates if grid_layout else VISUAL_MAX

func _ready() -> void:
    if grid_layout:
        crate_width = GRID_CRATE_WIDTH
    for index in get_visual_max():
        var crate := Node3D.new()
        crate.name = "PileCrate_%02d" % index
        crate.set_meta("index", index)
        crate.position = _slot_local(index)
        crate.visible = false
        add_child(crate)
        var sprite := _make_crate_sprite(ItemArt.full_texture(item_id))
        sprite.name = "CrateSprite"
        sprite.render_priority = index
        crate.add_child(sprite)
        _crates.append(crate)
    _count_label = CrateStack.make_count_label()
    _count_label.position = _count_label_local()
    add_child(_count_label)

func _process(delta: float) -> void:
    _pickup_cooldown = maxf(0.0, _pickup_cooldown - delta)
    _orient_sprites()

func get_capacity() -> int:
    return max_crates * units_per_crate

func get_stored_total() -> int:
    return _stored

func get_free_capacity() -> int:
    return maxi(0, get_capacity() - _stored)

func is_full() -> bool:
    return _stored >= get_capacity()

func get_crate_count() -> int:
    return int(ceil(float(_stored) / float(units_per_crate)))

## Texto do contador acima da pilha ("" enquanto todas as caixas aparecem).
func get_count_text() -> String:
    return _count_label.text if _count_label and _count_label.visible else ""

func get_count_label() -> Label3D:
    return _count_label

## Posição local da base de uma caixa (índices além do limite ficam no topo).
func get_slot_local(index: int) -> Vector3:
    return _slot_local(index)

func get_visible_crate_count() -> int:
    var count := 0
    for crate in _crates:
        if crate.visible:
            count += 1
    return count

## Ponto onde o ajudante para para descarregar: borda oeste da parcela (lado
## do canteiro), na altura do centro.
func get_drop_point() -> Vector3:
    return Vector3(rect.position.x - 0.35, 0.0, rect.get_center().y)

## Recebe tomates do ajudante. Retorna quantos couberam. Com from_pos, cada
## caixa nova pula das mãos do ajudante até o seu lugar.
func add_units(units: int, from_pos: Variant = null) -> int:
    var accepted := mini(maxi(units, 0), get_free_capacity())
    if accepted <= 0:
        return 0
    var before := get_crate_count()
    _stored += accepted
    var after := get_crate_count()
    if from_pos is Vector3 and is_inside_tree():
        for index in range(before, after):
            _launch(index, from_pos, to_global(_slot_local(index)), float(index - before) * 0.08, "drop")
    _refresh()
    stored_changed.emit(_stored)
    return accepted

## Retira tomates (recolha do fazendeiro / testes). Nunca negativo.
func take_units(units: int) -> int:
    var taken := clampi(units, 0, _stored)
    if taken <= 0:
        return 0
    _stored -= taken
    _refresh()
    stored_changed.emit(_stored)
    return taken

## Restauração de save / testes.
func set_stored_total(total: int) -> void:
    _stored = clampi(total, 0, get_capacity())
    _refresh()
    stored_changed.emit(_stored)

func contains_point(world_pos: Vector3) -> bool:
    return rect.grow(pickup_margin).has_point(Vector2(world_pos.x, world_pos.z))

## Chame por frame. Pisando na parcela, o fazendeiro recolhe a caixa do topo
## para a mochila (uma por PICKUP_INTERVAL), até a mochila encher.
## `target` é o nó onde as caixas pousam (mochila); só visual.
func process_farmer_position(world_pos: Vector3, inventory: HarvestInventory, target: Node3D = null) -> int:
    if inventory == null or _stored <= 0 or _pickup_cooldown > 0.0 or not contains_point(world_pos):
        return 0
    var top_units := _stored - (get_crate_count() - 1) * units_per_crate
    var reservation := inventory.try_reserve(item_id, top_units)
    if not reservation.is_valid():
        return 0
    var top_index := get_crate_count() - 1
    var from := to_global(_slot_local(top_index))
    var moved := take_units(reservation.amount)
    inventory.commit(reservation, moved)
    inventory.cancel(reservation)
    _pickup_cooldown = PICKUP_INTERVAL
    if target and is_instance_valid(target) and is_inside_tree():
        _launch(-1, from, target.global_position, 0.0, "pickup", target)
    return moved

func _refresh() -> void:
    var count := get_crate_count()
    var shown := mini(count, get_visual_max())
    var partial := _stored % units_per_crate != 0
    for index in _crates.size():
        var crate := _crates[index]
        crate.visible = index < shown and not _in_flight.has(index)
        var sprite := crate.get_node("CrateSprite") as Sprite3D
        var top_units := _stored - (count - 1) * units_per_crate
        var texture: Texture2D = ItemArt.partial_texture(item_id, top_units, units_per_crate) if partial and index == shown - 1 else ItemArt.full_texture(item_id)
        if sprite.texture != texture:
            _apply_texture(sprite, texture)
    if _count_label:
        var text := CrateStack.count_text(count, get_visual_max())
        _count_label.text = text
        _count_label.visible = text != ""

## Pilha única da cultura (item_id), no centro da parcela; índices além do
## limite visual pousam no topo.
func _slot_local(index: int) -> Vector3:
    if grid_layout:
        return _grid_slot_local(index)
    var layer := CrateStack.visual_index(index, VISUAL_MAX)
    var spacing := STACK_SPACING
    if rect.size.x > 0.0:
        spacing = minf(spacing, (rect.size.x - crate_width) * 0.5)
    var x := 0.0 if centered else CrateStack.slot_x(item_id, spacing)
    return Vector3(x, float(layer) * crate_width * 0.54, float(layer) * 0.03)

## Grade 3 x 3 por camada: preenche a fileira de trás primeiro (da esquerda
## para a direita), depois a do meio e a da frente; a camada seguinte sobe
## apoiada na borda das de baixo. A última caixa é sempre a do topo, que o
## fazendeiro recolhe primeiro.
func _grid_slot_local(index: int) -> Vector3:
    var per_layer := GRID_COLUMNS * GRID_ROWS
    var clamped := clampi(index, 0, maxi(max_crates - 1, 0))
    var layer := clamped / per_layer
    var within := clamped % per_layer
    var row := within / GRID_COLUMNS
    var column := within % GRID_COLUMNS
    var spacing := GRID_SPACING
    if rect.size.x > 0.0:
        spacing.x = minf(spacing.x, (rect.size.x - crate_width * 0.9) / float(GRID_COLUMNS - 1))
        spacing.y = minf(spacing.y, (rect.size.y - 0.6) / float(GRID_ROWS))
    return Vector3(
        (float(column) - (GRID_COLUMNS - 1) * 0.5) * spacing.x,
        float(layer) * crate_width * 0.54,
        (float(row) - (GRID_ROWS - 1) * 0.5) * spacing.y + float(layer) * 0.03
    )

func _count_label_local() -> Vector3:
    var art := ItemArt.full_texture(item_id)
    var crate_height := crate_width * float(art.get_height()) / float(art.get_width())
    var stretch := 1.0 / cos(deg_to_rad(VIEW_PITCH_DEGREES))
    return _slot_local(get_visual_max() - 1) + Vector3(0.0, crate_height * stretch + 0.35, 0.2)

func _launch(index: int, from: Vector3, to: Vector3, delay: float, kind: String, follow: Node3D = null) -> void:
    if index >= 0:
        index = CrateStack.visual_index(index, get_visual_max())
        _in_flight[index] = int(_in_flight.get(index, 0)) + 1
    var flyer := Node3D.new()
    flyer.name = "FlyingCrate_%s_%d" % [kind, jump_log.size()]
    flyer.top_level = true
    add_child(flyer)
    flyer.global_position = from
    flyer.set_meta("grow", 1.0 if kind == "pickup" else 0.7)
    var sprite := _make_crate_sprite(ItemArt.full_texture(item_id))
    sprite.name = "CrateSprite"
    sprite.render_priority = get_visual_max() + 1
    flyer.add_child(sprite)
    _flyers.append(flyer)
    jump_log.append({"index": index, "from": from, "to": to, "kind": kind})
    flyer.visible = delay <= 0.0
    var tween := create_tween()
    if delay > 0.0:
        tween.tween_interval(delay)
        tween.tween_callback(flyer.show)
    tween.tween_method(_move_flyer.bind(flyer, from, to, follow, kind), 0.0, 1.0, JUMP_TIME)
    tween.tween_callback(_land.bind(index, flyer))

func _move_flyer(t: float, flyer, from: Vector3, to: Vector3, follow, kind: String) -> void:
    if not is_instance_valid(flyer):
        return
    var target: Vector3 = follow.global_position if follow != null and is_instance_valid(follow) else to
    flyer.global_position = from.lerp(target, t) + Vector3(0.0, 4.0 * t * (1.0 - t) * JUMP_HEIGHT, 0.0)
    # Recolhida: chega à mochila no tamanho das caixas do fazendeiro/balcão.
    flyer.set_meta("grow", lerpf(1.0, SalesCounter.CRATE_WIDTH / crate_width, t) if kind == "pickup" else lerpf(0.7, 1.0, t))

func _land(index: int, flyer) -> void:
    _flyers.erase(flyer)
    if is_instance_valid(flyer):
        flyer.queue_free()
    if index >= 0:
        var left := int(_in_flight.get(index, 1)) - 1
        if left > 0:
            _in_flight[index] = left
        else:
            _in_flight.erase(index)
    _refresh()

## Termina todos os voos na hora (testes e capturas).
func finish_jumps() -> void:
    for flyer in _flyers:
        if is_instance_valid(flyer):
            flyer.queue_free()
    _flyers.clear()
    _in_flight.clear()
    _refresh()

func get_flying_crate_count() -> int:
    return _flyers.size()

## Billboard só no eixo Y, altura compensada pela inclinação da câmera (igual
## às caixas do balcão e da mochila).
func _sprite_basis() -> Basis:
    if _camera == null or not is_instance_valid(_camera):
        _camera = get_viewport().get_camera_3d() if is_inside_tree() else null
    if _camera == null:
        return Basis.IDENTITY
    var toward := _camera.global_basis.z
    toward.y = 0.0
    if toward.length() < 0.001:
        return Basis.IDENTITY
    toward = toward.normalized()
    var right := Vector3.UP.cross(toward).normalized()
    var stretch := 1.0 / maxf(0.3, _camera.global_basis.y.y)
    return Basis(right, Vector3.UP * stretch, toward)

func _orient_sprites() -> void:
    if not is_inside_tree():
        return
    var basis := _sprite_basis()
    for crate in _crates:
        if crate.visible:
            (crate.get_node("CrateSprite") as Node3D).global_basis = basis
    for flyer in _flyers:
        if is_instance_valid(flyer):
            var grow: float = flyer.get_meta("grow", 1.0)
            (flyer.get_node("CrateSprite") as Node3D).global_basis = Basis(basis.x * grow, basis.y * grow, basis.z)

func _make_crate_sprite(texture: Texture2D) -> Sprite3D:
    var sprite := Sprite3D.new()
    _apply_texture(sprite, texture)
    sprite.centered = false
    sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
    sprite.shaded = false
    sprite.double_sided = true
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.alpha_scissor_threshold = 0.5
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    return sprite

func _apply_texture(sprite: Sprite3D, texture: Texture2D) -> void:
    sprite.texture = texture
    sprite.pixel_size = crate_width * ItemArt.width_scale(item_id) / float(texture.get_width())
    sprite.offset = Vector2(-texture.get_width() * 0.5, 0.0)
