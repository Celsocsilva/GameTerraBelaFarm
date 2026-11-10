extends Node3D
class_name PlantingGrid

signal cell_planted(cell_id: String)
## Mudança de estado de colheita: RIPE, HARVESTING ou HARVESTED.
signal cell_state_changed(cell_id: String, state: String)

## Estados de colheita (FV-HARVEST-001): RIPE -> HARVESTING -> HARVESTED,
## ou de volta a RIPE em coleta parcial (mochila cheia ou cancelamento).
const STATE_RIPE := "RIPE"
const STATE_HARVESTING := "HARVESTING"
const STATE_HARVESTED := "HARVESTED"

@export var planting_radius: float = 0.95
## Faixa de semeadura: do pé do fazendeiro até N plantas à frente.
## SEED-002: alcance maior (era 3) para a semeadura a lanço ir mais longe.
@export_range(1, 8, 1) var seed_plants_ahead: int = 5
## SEED-002: a faixa abre em leque à frente e alcança até N sulcos vizinhos de
## cada lado (perto do pé fica só o sulco da caminhada): um mesmo passo do
## fazendeiro espalha semente numa área maior, como semeadura a lanço.
@export_range(0, 3, 1) var seed_lateral_furrows: int = 1
## Máximo de covas semeadas por passo (era 4).
@export_range(1, 16, 1) var seeds_per_step: int = 12
@export var columns: int = 3
## 9 fileiras: mantém ~1,5 m entre covas na tira 1,7x maior.
@export var rows_per_module: int = 9
@export var row_spacing: float = 2.1
@export var test_mode: bool = true
## CROP-CORN-001: cultura das covas desta grade (cada cultura tem a sua grade).
@export var crop_id: String = "tomato"
## FARM-003: enfileiramento orgânico. Cada sulco ondula de leve ao longo das
## fileiras (fração da largura da cova) e cada cova ganha um desvio fixo pequeno
## (X e Z, fração da cova) e um tamanho entre 1 - size_jitter e 1 + size_jitter.
## O desvio máximo fica bem dentro da cova: a grade jogável (ids, linhas,
## colunas, semeadura e colheita) não muda. 0 desliga.
## ROWS-002 (09/11): pedido do Celso — fileiras ainda mais orgânicas em todas
## as culturas (eram sway 0,09, jitter 0,06/0,12, tamanho ±7%). A onda do
## sulco agora mistura duas frequências (curva irregular, não senoide pura).
@export var organic_sway: float = 0.15
@export var organic_jitter: Vector2 = Vector2(0.09, 0.17)
@export var size_jitter: float = 0.10

var cells: Dictionary = {}
var _cell_spacing := 1.0
var _row_step := 1.0
var _last_farmer_position := Vector3.ZERO
var _has_previous_position := false
var _plant_accumulator := 0.0
# Direção do último deslocamento; começa olhando para o canteiro (+Z).
var _facing := Vector3(0.0, 0.0, 1.0)

func configure(modules: Array[Area3D]) -> void:
    for module_index in modules.size():
        var module := modules[module_index]
        var shape := (module.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
        var module_width := shape.size.x
        var module_length := shape.size.z
        var cell_width := module_width / float(columns)
        var cell_length := module_length / float(rows_per_module)
        _row_step = cell_length
        for row in rows_per_module:
            for column in columns:
                var cell_id := "%s_r%02d_c%02d" % [module.name, row, column]
                if cells.has(cell_id):
                    continue
                var organic := get_organic_offset(module_index, row, column)
                var local_offset := Vector3(
                    (column + 0.5 + organic.x) * cell_width - module_width * 0.5,
                    0.12,
                    (row + 0.5 + organic.y) * cell_length - module_length * 0.5
                )
                cells[cell_id] = {
                    "id": cell_id,
                    "module_id": module.name,
                    "row": row,
                    "column": column,
                    "crop_id": crop_id,
                    "cell_width": cell_width,
                    "size_factor": 1.0 + (_hash(module_index, row, column, 3.3) * 2.0 - 1.0) * size_jitter,
                    "cell_length": cell_length,
                    "position": module.to_global(local_offset),
                    "state": "EMPTY",
                    "planted_at": 0.0,
                    "remaining_yield": 0
                }
    _cell_spacing = INF
    var all_cells := cells.values()
    for i in all_cells.size():
        var a: Vector3 = all_cells[i]["position"]
        for j in range(i + 1, all_cells.size()):
            var b: Vector3 = all_cells[j]["position"]
            var distance := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
            if distance > 0.001:
                _cell_spacing = minf(_cell_spacing, distance)
    if _cell_spacing == INF:
        _cell_spacing = 1.0

## FARM-003: desvio orgânico (em frações da cova) de uma cova: onda suave do
## sulco ao longo das fileiras + desvio fixo por cova. |x| <= sway + jitter.x.
func get_organic_offset(module_index: int, row: int, column: int) -> Vector2:
    var phase := float(module_index) * 2.1 + float(column) * 1.37
    var sway := (sin(float(row) * 0.85 + phase) * 0.7 + sin(float(row) * 1.9 + phase * 2.3) * 0.3) * organic_sway
    var jx := (_hash(module_index, row, column, 1.1) * 2.0 - 1.0) * organic_jitter.x
    var jz := (_hash(module_index, row, column, 2.2) * 2.0 - 1.0) * organic_jitter.y
    return Vector2(sway + jx, jz)

## Valor fixo em [0, 1) por cova (mesmo canteiro a cada carga, sem sorteio).
static func _hash(module_index: int, row: int, column: int, salt: float) -> float:
    return fposmod(sin(float(module_index) * 91.7 + float(row) * 12.9898 + float(column) * 78.233 + salt * 37.719) * 43758.5453, 1.0)

func process_farmer_position(world_position: Vector3, delta: float) -> void:
    if not _has_previous_position:
        _last_farmer_position = world_position
        _has_previous_position = true
    _plant_accumulator += delta
    if _plant_accumulator < 0.35:
        return
    _plant_accumulator = 0.0
    var travel := world_position - _last_farmer_position
    var flat_travel := Vector3(travel.x, 0.0, travel.z)
    if flat_travel.length() > 0.05:
        _facing = flat_travel.normalized()
    for cell in get_seed_band_cells(world_position, _facing):
        plant_cell(cell["id"])
    _last_farmer_position = world_position

## Comprimento da faixa à frente: seed_plants_ahead fileiras + meia fileira de folga.
func get_seed_band_length() -> float:
    return (float(seed_plants_ahead) + 0.5) * _row_step

## Covas vazias do pé do fazendeiro até seed_plants_ahead plantas à frente,
## num leque (SEED-002): o sulco da caminhada inteiro e, a partir de ~1/3 da
## faixa, também os sulcos vizinhos. Ordem: da mais próxima para a mais distante.
func get_seed_band_cells(origin: Vector3, facing: Vector3) -> Array[Dictionary]:
    var forward := Vector2(facing.x, facing.z)
    forward = forward.normalized() if forward.length() > 0.001 else Vector2(0.0, 1.0)
    var band_start := -0.5 * _row_step
    var band_end := get_seed_band_length()
    var candidates: Array = []
    for cell in cells.values():
        if cell["state"] != "EMPTY":
            continue
        var offset := Vector2(cell["position"].x - origin.x, cell["position"].z - origin.z)
        var along := offset.dot(forward)
        if along < band_start or along > band_end:
            continue
        # Largura do sulco: a da cova (a cova orgânica pode sair até ~0,2 dela).
        var furrow := float(cell.get("cell_width", _cell_spacing))
        var fan := clampf((along - band_end * 0.3) / (band_end * 0.45), 0.0, 1.0)
        var lateral_limit := furrow * (0.55 + float(seed_lateral_furrows) * fan)
        if absf(offset.cross(forward)) <= lateral_limit:
            candidates.append([along + absf(offset.cross(forward)) * 0.35, cell])
    candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    var result: Array[Dictionary] = []
    for entry in candidates.slice(0, seeds_per_step):
        result.append(entry[1])
    return result

func get_cell_at_world(world_pos: Vector3) -> Dictionary:
    var nearest: Dictionary = {}
    var nearest_distance := planting_radius
    for cell in cells.values():
        var distance := Vector2(cell["position"].x, cell["position"].z).distance_to(Vector2(world_pos.x, world_pos.z))
        if distance <= nearest_distance:
            nearest = cell
            nearest_distance = distance
    return nearest

func get_available_cells_near(world_pos: Vector3, radius: float) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for cell in cells.values():
        var distance := Vector2(cell["position"].x, cell["position"].z).distance_to(Vector2(world_pos.x, world_pos.z))
        if distance <= radius and cell["state"] == "EMPTY":
            result.append(cell)
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var da: Vector3 = a["position"]
        var db: Vector3 = b["position"]
        return Vector2(da.x, da.z).distance_to(Vector2(world_pos.x, world_pos.z)) < Vector2(db.x, db.z).distance_to(Vector2(world_pos.x, world_pos.z)))
    return result

func get_cell_world_position(cell_id: String) -> Vector3:
    return cells[cell_id]["position"] if cells.has(cell_id) else Vector3.ZERO

func get_next_unplanted_cell() -> Dictionary:
    for cell in cells.values():
        if cell["state"] == "EMPTY":
            return cell
    return {}

func get_planting_progress() -> Dictionary:
    var planted := 0
    for cell in cells.values():
        if cell["state"] != "EMPTY":
            planted += 1
    return {"total": cells.size(), "planted": planted, "remaining": cells.size() - planted}

func plant_cell(cell_id: String) -> bool:
    if not cells.has(cell_id) or cells[cell_id]["state"] != "EMPTY":
        return false
    cells[cell_id]["state"] = "SEEDED"
    cells[cell_id]["planted_at"] = Time.get_ticks_msec() / 1000.0
    cell_planted.emit(cell_id)
    return true

## Reabre a plantação somente depois de colher todas as células da safra.
func reset_if_fully_harvested() -> bool:
    if cells.is_empty():
        return false
    for cell in cells.values():
        if cell["state"] != STATE_HARVESTED or int(cell["remaining_yield"]) != 0:
            return false
    for cell in cells.values():
        cell["state"] = "EMPTY"
        cell["planted_at"] = 0.0
        cell["remaining_yield"] = 0
        cell_state_changed.emit(cell["id"], "EMPTY")
    return true

# --- Colheita (FV-HARVEST-001) -------------------------------------------

## Menor distância entre centros de células vizinhas (base do raio de colheita).
func get_cell_spacing() -> float:
    return _cell_spacing

## A planta amadureceu: passa a RIPE com `units` frutos colhíveis.
func mark_ripe(cell_id: String, units: int) -> void:
    if not cells.has(cell_id) or cells[cell_id]["state"] == STATE_HARVESTED:
        return
    cells[cell_id]["remaining_yield"] = maxi(0, units)
    _set_state(cell_id, STATE_RIPE if units > 0 else STATE_HARVESTED)

## Células RIPE com frutos dentro do raio, ordem determinística (distância, id).
func get_ripe_cells_near(world_pos: Vector3, radius: float) -> Array[Dictionary]:
    var origin := Vector2(world_pos.x, world_pos.z)
    var result: Array[Dictionary] = []
    for cell in cells.values():
        if cell["state"] != STATE_RIPE or int(cell["remaining_yield"]) <= 0:
            continue
        var p: Vector3 = cell["position"]
        if Vector2(p.x, p.z).distance_to(origin) <= radius:
            result.append(cell)
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var pa: Vector3 = a["position"]
        var pb: Vector3 = b["position"]
        var da := Vector2(pa.x, pa.z).distance_to(origin)
        var db := Vector2(pb.x, pb.z).distance_to(origin)
        if not is_equal_approx(da, db):
            return da < db
        return String(a["id"]) < String(b["id"]))
    return result

func get_remaining_yield(cell_id: String) -> int:
    return int(cells[cell_id]["remaining_yield"]) if cells.has(cell_id) else 0

## Trava a célula para uma única coleta simultânea.
func begin_harvest(cell_id: String) -> bool:
    if not cells.has(cell_id) or cells[cell_id]["state"] != STATE_RIPE:
        return false
    _set_state(cell_id, STATE_HARVESTING)
    return true

## Retira da planta as unidades que acabaram de ser confirmadas na mochila.
## Chamado a cada fruto que chega, para que planta + mochila sempre somem a
## produção original (inclusive num save feito no meio do voo).
func consume_yield(cell_id: String, units: int) -> void:
    if cells.has(cell_id):
        cells[cell_id]["remaining_yield"] = maxi(0, get_remaining_yield(cell_id) - maxi(units, 0))

## Encerra a coleta: sem frutos -> HARVESTED; sobras (mochila cheia ou
## cancelamento) mantêm a planta coletável em RIPE.
func finish_harvest(cell_id: String) -> String:
    if not cells.has(cell_id) or cells[cell_id]["state"] != STATE_HARVESTING:
        return ""
    _set_state(cell_id, STATE_RIPE if get_remaining_yield(cell_id) > 0 else STATE_HARVESTED)
    return cells[cell_id]["state"]

func set_remaining_yield(cell_id: String, units: int) -> void:
    if cells.has(cell_id):
        cells[cell_id]["remaining_yield"] = maxi(0, units)

## Estado por célula para retomada. HARVESTING é salvo como RIPE: as reservas
## pendentes não são persistidas, então o fruto continua na planta.
func get_harvest_state() -> Dictionary:
    var data := {}
    for cell in cells.values():
        if cell["state"] in [STATE_RIPE, STATE_HARVESTING, STATE_HARVESTED]:
            data[cell["id"]] = {
                "state": STATE_RIPE if cell["state"] == STATE_HARVESTING else cell["state"],
                "remaining_yield": int(cell["remaining_yield"])
            }
    return data

func apply_harvest_state(data: Dictionary) -> void:
    for cell_id in data:
        if not cells.has(cell_id):
            continue
        var entry: Dictionary = data[cell_id]
        cells[cell_id]["remaining_yield"] = maxi(0, int(entry.get("remaining_yield", 0)))
        _set_state(cell_id, String(entry.get("state", STATE_RIPE)))

func _set_state(cell_id: String, state: String) -> void:
    if cells[cell_id]["state"] == state:
        return
    cells[cell_id]["state"] = state
    cell_state_changed.emit(cell_id, state)
