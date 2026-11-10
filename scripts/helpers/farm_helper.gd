extends Node3D
class_name FarmHelper
## Ajudante contratado (FV-HELPER-001). Cópia visual do fazendeiro (como os
## clientes) com outras cores; sem física, anda em linha reta pelo canteiro.
##
## Ciclo: procura o pé maduro mais próximo -> colhe (PlantingGrid
## begin_harvest/consume_yield/finish_harvest, a mesma trava da colheita do
## fazendeiro, então os dois nunca colhem o mesmo pé) -> com a carga cheia ou
## sem mais pés maduros, leva as caixas à TomatoPile da parcela de 10% ->
## com a safra toda colhida, replanta as covas vazias. A graduação (HelperHiring)
## define velocidade, caixas por viagem e tempo de colheita.

signal state_changed(state: StringName)
signal harvested(cell_id: String, units: int)
signal dropped(units: int)
signal planted(cell_id: String)

const FARMER_SCENE := preload("res://scenes/player/farmer.tscn")
const CRATE_FULL_TEXTURE := preload("res://assets/harvest/crate_full.png")
const CRATE_EMPTY_TEXTURE := preload("res://assets/harvest/crate_empty.png")
const PICKUP_FX_SCRIPT := preload("res://scripts/vfx/tomato_pickup_fx.gd")
## Macacão amarelo-palha e detalhe verde: não repete o fazendeiro nem os clientes.
const BODY_COLOR := Color(0.96, 0.78, 0.26)
const ACCENT_COLOR := Color(0.20, 0.42, 0.18)
const HANDS_OFFSET := Vector3(0.0, 1.1, -0.55)
const ARRIVE_EPSILON := 0.08
## Distância (XZ) do pé em que o ajudante para para colher/semear.
const WORK_REACH := 0.55

const IDLE := &"IDLE"
const TO_HARVEST := &"TO_HARVEST"
const HARVESTING := &"HARVESTING"
const TO_PILE := &"TO_PILE"
const WAIT_PILE := &"WAIT_PILE"
const TO_PLANT := &"TO_PLANT"
const PLANTING := &"PLANTING"

var grid: PlantingGrid
var crops: Dictionary = {}
var pile: TomatoPile
var hiring: HelperHiring
var world: Node
var units_per_crate := 8
var state: StringName = IDLE
## Tomates carregados agora (vão para a pilha).
var carried := 0
var target_cell := ""
var _target := Vector3.ZERO
var _work_left := 0.0
var _carry_visual: Node3D
var _carry_sprite: Sprite3D
var _camera: Camera3D
var _retry := 0.0

## Monta o ajudante copiando os meshes do fazendeiro e recolorindo-os.
static func create() -> FarmHelper:
    var helper := FarmHelper.new()
    helper.name = "FarmHelper"
    var template := FARMER_SCENE.instantiate()
    for child in template.get_children():
        if child is MeshInstance3D:
            var copy := (child as MeshInstance3D).duplicate() as MeshInstance3D
            var material := StandardMaterial3D.new()
            var source := (child as MeshInstance3D).material_override as StandardMaterial3D
            if source:
                material = source.duplicate() as StandardMaterial3D
            material.albedo_color = ACCENT_COLOR if child.name == "FrontMarker" else BODY_COLOR
            copy.material_override = material
            helper.add_child(copy)
    template.free()
    return helper

func setup(p_grid: PlantingGrid, crop_map: Dictionary, p_pile: TomatoPile, p_hiring: HelperHiring, p_world: Node, crate_units: int) -> void:
    grid = p_grid
    crops = crop_map
    pile = p_pile
    hiring = p_hiring
    world = p_world
    units_per_crate = crate_units
    hiring.grade_changed.connect(_on_grade_changed)
    _on_grade_changed(hiring.grade)

func _ready() -> void:
    _carry_visual = Node3D.new()
    _carry_visual.name = "CarriedCrate"
    _carry_visual.position = Vector3(0.0, 0.75, -0.6)
    add_child(_carry_visual)
    _carry_sprite = Sprite3D.new()
    _carry_sprite.name = "CrateSprite"
    _carry_sprite.texture = CRATE_EMPTY_TEXTURE
    _carry_sprite.pixel_size = 0.9 / float(CRATE_EMPTY_TEXTURE.get_width())
    _carry_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
    _carry_sprite.shaded = false
    _carry_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    _carry_sprite.render_priority = 3
    _carry_visual.add_child(_carry_sprite)
    _carry_visual.visible = false

## CROP-CORN-001: produto deste ajudante (o da pilha dele: tomate ou milho).
func get_item_id() -> StringName:
    return pile.item_id if pile else &"tomato"

func get_capacity() -> int:
    return HelperConfig.carry_crates(hiring.grade) * units_per_crate if hiring else units_per_crate

func get_free_carry() -> int:
    return maxi(0, get_capacity() - carried)

func get_hands_position() -> Vector3:
    return global_transform * HANDS_OFFSET

## Ponto de descanso: ao lado da pilha, sem pisar no canteiro.
func get_idle_point() -> Vector3:
    return pile.get_drop_point() + Vector3(0.0, 0.0, 1.6) if pile else Vector3.ZERO

func _on_grade_changed(grade: int) -> void:
    var was_visible := visible
    visible = grade > 0
    set_process(grade > 0)
    if grade > 0 and not was_visible:
        global_position = get_idle_point()
        _set_state(IDLE)

func _process(delta: float) -> void:
    if grid == null or hiring == null or not hiring.is_hired():
        return
    match state:
        IDLE, WAIT_PILE:
            _retry = maxf(0.0, _retry - delta)
            if _retry <= 0.0:
                _retry = 0.25
                _choose_task()
            if state == IDLE:
                _walk_to(get_idle_point(), delta)
        TO_HARVEST:
            if not _cell_is(target_cell, PlantingGrid.STATE_RIPE):
                _choose_task()
            elif _walk_to(_target, delta):
                _begin_harvest()
        HARVESTING:
            _work_left -= delta
            if _work_left <= 0.0:
                _finish_harvest()
        TO_PILE:
            if _walk_to(pile.get_drop_point(), delta):
                _drop_at_pile()
        TO_PLANT:
            if not _cell_is(target_cell, "EMPTY"):
                _choose_task()
            elif _walk_to(_target, delta):
                _set_state(PLANTING)
                _work_left = HelperConfig.PLANT_SECONDS
        PLANTING:
            _work_left -= delta
            if _work_left <= 0.0:
                _plant_target()
    _update_carry_visual()

## Decide a próxima tarefa a partir do estado atual do canteiro.
func _choose_task() -> void:
    target_cell = ""
    if carried > 0 and (get_free_carry() <= 0 or _find_ripe().is_empty()):
        if pile.get_free_capacity() > 0:
            _set_state(TO_PILE)
        else:
            _set_state(WAIT_PILE)
        return
    if get_free_carry() > 0:
        var ripe := _find_ripe()
        if not ripe.is_empty():
            _go_to_cell(ripe, TO_HARVEST)
            return
    if HelperConfig.REPLANTS and carried == 0:
        var empty := _find_nearest_cell("EMPTY")
        if not empty.is_empty():
            _go_to_cell(empty, TO_PLANT)
            return
    _set_state(IDLE)

func _find_ripe() -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    var here := Vector2(global_position.x, global_position.z)
    for cell in grid.cells.values():
        if cell["state"] != PlantingGrid.STATE_RIPE or int(cell["remaining_yield"]) <= 0:
            continue
        var p: Vector3 = cell["position"]
        var d := here.distance_to(Vector2(p.x, p.z))
        if d < best_distance - 0.001 or (absf(d - best_distance) <= 0.001 and String(cell["id"]) < String(best.get("id", ""))):
            best = cell
            best_distance = d
    return best

func _find_nearest_cell(cell_state: String) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    var here := Vector2(global_position.x, global_position.z)
    for cell in grid.cells.values():
        if cell["state"] != cell_state:
            continue
        var p: Vector3 = cell["position"]
        var d := here.distance_to(Vector2(p.x, p.z))
        if d < best_distance:
            best = cell
            best_distance = d
    return best

func _go_to_cell(cell: Dictionary, next_state: StringName) -> void:
    target_cell = String(cell["id"])
    var p: Vector3 = cell["position"]
    # Para ao lado do pé (lado da câmera, +Z), sem cobrir a planta.
    _target = Vector3(p.x, 0.0, p.z + WORK_REACH)
    _set_state(next_state)

func _cell_is(cell_id: String, cell_state: String) -> bool:
    return grid.cells.has(cell_id) and grid.cells[cell_id]["state"] == cell_state

func _begin_harvest() -> void:
    if not grid.begin_harvest(target_cell):
        _choose_task()
        return
    _set_state(HARVESTING)
    _work_left = HelperConfig.harvest_seconds(hiring.grade)
    var crop: CropPlant = crops.get(target_cell)
    if crop and is_instance_valid(crop):
        crop.play_harvest_shake()
        if is_inside_tree():
            var fx := PICKUP_FX_SCRIPT.new() as TomatoPickupFX
            fx.name = "HelperPickupFX_" + target_cell
            fx.use_trail = false
            if get_item_id() != &"tomato":
                fx.fruit_texture = CropCatalog.fruit_texture(get_item_id())
                fx.fruit_height = CropCatalog.fruit_height(get_item_id())
            (world if world else get_parent()).add_child(fx)
            fx.launch(crop.get_harvest_origins(3, _get_camera()), _carry_visual)

## Conclui a colheita do pé: leva o que couber; sobra fica no pé (RIPE).
func _finish_harvest() -> void:
    var cell_id := target_cell
    var units := mini(grid.get_remaining_yield(cell_id), get_free_carry())
    grid.consume_yield(cell_id, units)
    carried += units
    var result := grid.finish_harvest(cell_id)
    if result == PlantingGrid.STATE_HARVESTED:
        var crop: CropPlant = crops.get(cell_id)
        if crop and is_instance_valid(crop):
            crop.set_harvested()
    harvested.emit(cell_id, units)
    _choose_task()

func _drop_at_pile() -> void:
    var accepted := pile.add_units(carried, get_hands_position())
    carried -= accepted
    if accepted > 0:
        dropped.emit(accepted)
    if carried > 0:
        _set_state(WAIT_PILE)
    else:
        _choose_task()

func _plant_target() -> void:
    var cell_id := target_cell
    var ok := false
    if world and world.has_method("plant_cell_from"):
        ok = world.plant_cell_from(cell_id, get_hands_position())
    else:
        ok = grid.plant_cell(cell_id)
    if ok:
        planted.emit(cell_id)
    _choose_task()

## Anda em linha reta (XZ) até o alvo. Retorna true ao chegar.
func _walk_to(point: Vector3, delta: float) -> bool:
    var flat := Vector3(point.x, global_position.y, point.z)
    var offset := flat - global_position
    offset.y = 0.0
    if offset.length() <= ARRIVE_EPSILON:
        return true
    var step := HelperConfig.walk_speed(hiring.grade) * delta
    var direction := offset.normalized()
    rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, delta * 12.0))
    if step >= offset.length():
        global_position = flat
        return true
    global_position += direction * step
    return false

## Termina a tarefa atual na hora (testes): anda até o alvo e conclui o trabalho.
func step_instant() -> void:
    match state:
        TO_HARVEST:
            global_position = Vector3(_target.x, global_position.y, _target.z)
            _begin_harvest()
        HARVESTING:
            _work_left = 0.0
            _finish_harvest()
        TO_PILE:
            global_position = pile.get_drop_point()
            _drop_at_pile()
        TO_PLANT:
            global_position = Vector3(_target.x, global_position.y, _target.z)
            _set_state(PLANTING)
        PLANTING:
            _plant_target()
        _:
            _choose_task()

## Troca de cena no meio da colheita: o pé volta a RIPE com o que sobrou.
func _exit_tree() -> void:
    if state == HARVESTING and grid and grid.cells.has(target_cell):
        grid.finish_harvest(target_cell)

func _set_state(new_state: StringName) -> void:
    if state == new_state:
        return
    state = new_state
    state_changed.emit(state)

func _update_carry_visual() -> void:
    if _carry_visual == null:
        return
    _carry_visual.visible = carried > 0
    var texture: Texture2D = ItemArt.full_texture(get_item_id()) if carried >= units_per_crate else ItemArt.partial_texture(get_item_id(), carried, units_per_crate)
    if _carry_sprite.texture != texture:
        _carry_sprite.texture = texture
        _carry_sprite.pixel_size = 0.9 * ItemArt.width_scale(get_item_id()) / float(texture.get_width())

func _get_camera() -> Camera3D:
    if _camera == null or not is_instance_valid(_camera):
        _camera = get_viewport().get_camera_3d() if is_inside_tree() else null
    return _camera
