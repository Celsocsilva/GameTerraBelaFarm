extends Node3D
class_name RiverSystem

## ENV-002 — Rio modular montado com os tiles ilustrados de res://assets/river_tiles/.
##
## O curso é uma lista ordenada de segmentos (course). Cada segmento entra pela
## abertura oposta à saída do anterior; a escala do tile é escolhida para que a
## largura da água na entrada seja igual à largura de saída do anterior, e o
## tile é posicionado para que as duas linhas d'água se sobreponham em
## junction_overlap metros. Nada é esticado de forma não uniforme: a única
## correção em Z é o 1/sin(45°) usado em todo o chão do jogo (solo, tiles).
##
## As aberturas e a máscara de água de cada PNG vêm de
## res://data/river/river_tile_meta.json (gerado por tools/river_tile_bake.gd).
##
## Nós filhos (criados se não existirem na cena):
##   RiverSegments   — um MeshInstance3D por tile (shader de água animada)
##   RiverBanks      — faixas decorativas de margem (bank_strip_*.png)
##   WaterSurface    — faixa contínua de água sob os tiles (cobre frestas)
##   RiverCollisions — um StaticBody3D por segmento, só sobre a água, com
##                     vãos onde há pontes (grupo "river_bridge")
##
## Para estender o rio, chame add_segment({"tile": ...}): só o novo segmento é
## criado; os anteriores, as pontes e as colisões já existentes não mudam.

signal segment_added(index: int)

const META_PATH := "res://data/river/river_tile_meta.json"
const TILE_DIR := "res://assets/river_tiles/"
const BANK_DIR := "res://assets/banks/"
const WATER_SHADER := preload("res://assets/river_tiles/river_water.gdshader")
const JUNCTION_SHADER := preload("res://assets/river_tiles/river_water_junction.gdshader")
## Fatias do meio dos tiles retos usadas como peças de junção (px do PNG):
## tile, faixa ao longo do fluxo [início, fim) e trecho de água transversal.
const JUNCTION_SLICES := {
    "vertical": {"tile": "river_straight_vertical", "from": 136, "to": 192, "water_from": 74, "water_to": 174},
    "horizontal": {"tile": "river_straight_horizontal", "from": 250, "to": 340, "water_from": 91, "water_to": 201},
}
const JUNCTION_Y := 0.038
const VIEW_PITCH_DEGREES := 45.0
const OPPOSITE := {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}
const FLOW := {"top": Vector3(0, 0, -1), "bottom": Vector3(0, 0, 1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}
const TILE_BASE_Y := 0.02
const TILE_STEP_Y := 0.002
const SURFACE_Y := 0.012
const BANK_Y := 0.044

## Centro (local) da abertura de entrada do primeiro segmento.
@export var anchor_position: Vector3 = Vector3.ZERO
## Largura (m, no mundo) da água nessa abertura.
@export var anchor_width: float = 3.0
## Segmentos em ordem de fluxo. Chaves: tile (nome do PNG sem extensão),
## entry (só no primeiro: borda de entrada), length_px (opcional, só em retos:
## encurta o tile ao longo do fluxo; útil para terminar na borda do mapa) e
## trim_entry (opcional: corta a margem transparente antes da linha de entrada).
@export var course: Array[Dictionary] = []
## Sobreposição (m) entre linhas d'água de segmentos vizinhos.
@export var junction_overlap: float = 0.08
## Faixas de margem: {asset, position (Vector3 local), width (m)}.
@export var bank_strips: Array[Dictionary] = []
@export var blocker_height: float = 1.6
## Margem (m) ao redor das pontes onde a água deixa de bloquear.
@export var bridge_gap_margin: float = 0.05
## Animação da água (desligar para capturas estáticas ou aparelhos fracos).
@export var water_animation: bool = true

var segments: Array[Dictionary] = []
var _meta: Dictionary = {}
var _stretch := 1.0 / sin(deg_to_rad(VIEW_PITCH_DEGREES))
var _segments_root: Node3D
var _banks_root: Node3D
var _surface_root: Node3D
var _collisions_root: Node3D
var _bridges: Array[RiverBridge] = []
var _built := false

func _ready() -> void:
    build()

func build() -> void:
    if _built:
        return
    _built = true
    _meta = load_meta()
    _segments_root = _ensure_child("RiverSegments")
    _banks_root = _ensure_child("RiverBanks")
    _surface_root = _ensure_child("WaterSurface")
    _collisions_root = _ensure_child("RiverCollisions")
    _bridges.clear()
    for node in get_children():
        if node is RiverBridge:
            (node as RiverBridge).build()
            _bridges.append(node)
    for spec in course:
        _append_segment(spec)
    for strip in bank_strips:
        _add_bank_strip(strip)

static func load_meta() -> Dictionary:
    var text := FileAccess.get_file_as_string(META_PATH)
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("RiverSystem: invalid " + META_PATH)
        return {}
    return parsed

func _ensure_child(node_name: String) -> Node3D:
    var node := get_node_or_null(node_name) as Node3D
    if node == null:
        node = Node3D.new()
        node.name = node_name
        add_child(node)
    return node

## Acrescenta um segmento ao fim do rio (expansão). Retorna o índice.
func add_segment(spec: Dictionary) -> int:
    if not _built:
        build()
    course.append(spec)
    return _append_segment(spec)

func get_bridges() -> Array[RiverBridge]:
    return _bridges

func get_tile_meta(tile: String) -> Dictionary:
    return (_meta.get("tiles", {}) as Dictionary).get(tile, {})

# --- montagem --------------------------------------------------------------

func _opening_center_px(opening: Dictionary, edge: String) -> Vector2:
    var mid := (float(opening["from"]) + float(opening["to"])) * 0.5
    var line := float(opening["line"])
    return Vector2(mid, line) if edge in ["top", "bottom"] else Vector2(line, mid)

func _opening_span_px(opening: Dictionary) -> float:
    return float(opening["to"]) - float(opening["from"]) + 1.0

## Largura (m, no mundo) de uma abertura com escala p.
func _opening_width_world(opening: Dictionary, edge: String, p: float) -> float:
    var span := _opening_span_px(opening) * p
    return span if edge in ["top", "bottom"] else span * _stretch

func _px_to_local(px: Vector2, p: float) -> Vector3:
    return Vector3(px.x * p, 0.0, px.y * p * _stretch)

func _append_segment(spec: Dictionary) -> int:
    var tile: String = spec.get("tile", "")
    var meta := get_tile_meta(tile)
    if meta.is_empty():
        push_error("RiverSystem: unknown tile " + tile)
        return -1
    var openings: Dictionary = meta["openings"]
    var index := segments.size()
    var entry: String
    var entry_point: Vector3
    var width: float
    if index == 0:
        entry = spec.get("entry", "left")
        entry_point = anchor_position
        width = anchor_width
    else:
        var previous: Dictionary = segments[index - 1]
        if previous["exit"] == "":
            push_error("RiverSystem: previous segment has no exit")
            return -1
        entry = OPPOSITE[previous["exit"]]
        width = previous["exit_width"]
        # A nova linha d'água começa um pouco "rio acima" para sobrepor a anterior.
        entry_point = (previous["exit_point"] as Vector3) - (FLOW[previous["exit"]] as Vector3) * junction_overlap
    if not openings.has(entry):
        push_error("RiverSystem: tile %s has no %s opening" % [tile, entry])
        return -1
    var entry_opening: Dictionary = openings[entry]
    var span := _opening_span_px(entry_opening)
    var p := width / span if entry in ["top", "bottom"] else width / (span * _stretch)
    var size := Vector2(meta["size"][0], meta["size"][1])
    var exit := ""
    for edge in openings.keys():
        if edge != entry:
            exit = edge
    var exit_opening: Dictionary = openings[exit] if exit != "" else {}
    # Região do PNG usada (recorte só em retos, ao longo do fluxo).
    var region := Rect2(Vector2.ZERO, size)
    var entry_line := float(entry_opening["line"])
    if spec.has("length_px") and exit != "":
        var length := float(spec["length_px"])
        exit_opening = exit_opening.duplicate()
        match entry:
            "left":
                exit_opening["line"] = entry_line + length
                region = Rect2(0, 0, entry_line + length, size.y)
            "right":
                exit_opening["line"] = entry_line - length
                region = Rect2(entry_line - length, 0, size.x - (entry_line - length), size.y)
            "top":
                exit_opening["line"] = entry_line + length
                region = Rect2(0, 0, size.x, entry_line + length)
            "bottom":
                exit_opening["line"] = entry_line - length
                region = Rect2(0, entry_line - length, size.x, size.y - (entry_line - length))
    # trim_entry: o tile começa exatamente na linha d'água de entrada (borda do mapa).
    if spec.get("trim_entry", false):
        match entry:
            "left":
                region = Rect2(entry_line, region.position.y, region.end.x - entry_line, region.size.y)
            "right":
                region = Rect2(region.position.x, region.position.y, entry_line - region.position.x, region.size.y)
            "top":
                region = Rect2(region.position.x, entry_line, region.size.x, region.end.y - entry_line)
            "bottom":
                region = Rect2(region.position.x, region.position.y, region.size.x, entry_line - region.position.y)
    var origin := entry_point - _px_to_local(_opening_center_px(entry_opening, entry), p)
    var segment := {
        "index": index,
        "tile": tile,
        "entry": entry,
        "exit": exit,
        "scale": p,
        "origin": origin,
        "size_px": size,
        "region_px": region,
        "entry_point": entry_point,
        "entry_width": width,
        "exit_point": origin + _px_to_local(_opening_center_px(exit_opening, exit), p) if exit != "" else entry_point,
        "exit_width": _opening_width_world(exit_opening, exit, p) if exit != "" else 0.0,
    }
    segments.append(segment)
    _build_tile_mesh(segment)
    if index > 0:
        _build_junction(segments[index - 1], segment)
    _build_surface(segment)
    _build_blockers(segment, meta)
    segment_added.emit(index)
    return index

func _build_tile_mesh(segment: Dictionary) -> void:
    var tile: String = segment["tile"]
    var texture := load(TILE_DIR + tile + ".png") as Texture2D
    var p: float = segment["scale"]
    var region: Rect2 = segment["region_px"]
    var size: Vector2 = segment["size_px"]
    var mesh := MeshInstance3D.new()
    mesh.name = "Segment_%02d_%s" % [segment["index"], tile.trim_prefix("river_")]
    var quad := QuadMesh.new()
    quad.size = Vector2(region.size.x * p, region.size.y * p * _stretch)
    mesh.mesh = quad
    mesh.rotation_degrees.x = -90.0
    mesh.position = (segment["origin"] as Vector3) + _px_to_local(region.get_center(), p)
    mesh.position.y = TILE_BASE_Y + TILE_STEP_Y * (int(segment["index"]) % 8)
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := ShaderMaterial.new()
    material.shader = WATER_SHADER
    material.set_shader_parameter("albedo_tex", texture)
    material.set_shader_parameter("uv_offset", region.position / size)
    material.set_shader_parameter("uv_scale", region.size / size)
    material.set_shader_parameter("texel_size", Vector2.ONE / size)
    material.set_shader_parameter("speed", 1.0 if water_animation else 0.0)
    mesh.material_override = material
    _segments_root.add_child(mesh)
    segment["node"] = mesh

## Peça complementar sobre o encontro de dois segmentos (ver shader de junção).
func _build_junction(previous: Dictionary, segment: Dictionary) -> void:
    var entry: String = segment["entry"]
    var vertical: bool = entry in ["top", "bottom"]
    var slice: Dictionary = JUNCTION_SLICES["vertical" if vertical else "horizontal"]
    var texture := load(TILE_DIR + String(slice["tile"]) + ".png") as Texture2D
    var size := Vector2(texture.get_width(), texture.get_height())
    var water_span := float(slice["water_to"]) - float(slice["water_from"]) + 1.0
    var water_mid := (float(slice["water_from"]) + float(slice["water_to"])) * 0.5
    var width: float = segment["entry_width"]
    var flow: Vector3 = FLOW[previous["exit"]]
    var center: Vector3 = (previous["exit_point"] as Vector3) - flow * junction_overlap * 0.5
    var along := float(slice["to"]) - float(slice["from"])
    var region: Rect2
    var p: float
    var offset: Vector3
    if vertical:
        p = width / water_span
        region = Rect2(0.0, float(slice["from"]), size.x, along)
        offset = Vector3((size.x * 0.5 - water_mid) * p, 0.0, 0.0)
    else:
        p = width / (water_span * _stretch)
        region = Rect2(float(slice["from"]), 0.0, along, size.y)
        offset = Vector3(0.0, 0.0, (size.y * 0.5 - water_mid) * p * _stretch)
    var mesh := MeshInstance3D.new()
    mesh.name = "Junction_%02d" % segment["index"]
    var quad := QuadMesh.new()
    quad.size = Vector2(region.size.x * p, region.size.y * p * _stretch)
    mesh.mesh = quad
    mesh.rotation_degrees.x = -90.0
    mesh.position = center + offset
    mesh.position.y = JUNCTION_Y
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := ShaderMaterial.new()
    material.shader = JUNCTION_SHADER
    material.set_shader_parameter("albedo_tex", texture)
    material.set_shader_parameter("uv_offset", region.position / size)
    material.set_shader_parameter("uv_scale", region.size / size)
    material.set_shader_parameter("texel_size", Vector2.ONE / size)
    material.set_shader_parameter("speed", 1.0 if water_animation else 0.0)
    material.set_shader_parameter("fade_axis", 0 if vertical else 1)
    mesh.material_override = material
    _segments_root.add_child(mesh)
    segment["junction_node"] = mesh
    _build_junction_blocker(segment, center, flow, width)

## A borda pintada de cada PNG pode ter água mais clara que a máscara não
## reconhece: uma caixa extra fecha a junção (exceto sob pontes).
func _build_junction_blocker(segment: Dictionary, center: Vector3, flow: Vector3, width: float) -> void:
    var polygons := _bridge_polygons()
    var side := Vector3(-flow.z, 0.0, flow.x)
    var pieces := 6
    var piece := width * 0.96 / pieces
    var body := StaticBody3D.new()
    body.name = "JunctionBlocker_%02d" % segment["index"]
    var count := 0
    for i in pieces:
        var offset := (float(i) + 0.5) * piece - width * 0.48
        var point := center + side * offset
        if _in_any_polygon(Vector2(point.x, point.z), polygons):
            continue
        var collision := CollisionShape3D.new()
        collision.name = "Piece_%d" % i
        var shape := BoxShape3D.new()
        var along := 1.0
        shape.size = Vector3(absf(side.x) * piece + absf(flow.x) * along, blocker_height, absf(side.z) * piece + absf(flow.z) * along)
        collision.shape = shape
        collision.position = point + Vector3(0.0, blocker_height * 0.5 - 0.1, 0.0)
        body.add_child(collision)
        count += 1
    segment["junction_blocker_boxes"] = count
    _collisions_root.add_child(body)

## Linha central da água no segmento (local), da entrada à saída.
func get_segment_centerline(segment: Dictionary, samples: int = 12) -> PackedVector3Array:
    var line := PackedVector3Array()
    var a: Vector3 = segment["entry_point"]
    if segment["exit"] == "":
        line.append(a)
        return line
    var b: Vector3 = segment["exit_point"]
    var din: Vector3 = -(FLOW[segment["entry"]] as Vector3)
    var dout: Vector3 = FLOW[segment["exit"]]
    var handle := a.distance_to(b) * 0.5
    for i in samples + 1:
        var t := float(i) / samples
        var c1 := a + din * handle
        var c2 := b - dout * handle
        var u := 1.0 - t
        line.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
    return line

## Faixa contínua de água sob o tile (só aparece onde houver fresta).
func _build_surface(segment: Dictionary) -> void:
    if segment["exit"] == "":
        return
    var line := get_segment_centerline(segment)
    var w0: float = segment["entry_width"]
    var w1: float = segment["exit_width"]
    var vertices := PackedVector3Array()
    var uvs := PackedVector2Array()
    for i in line.size():
        var t := float(i) / (line.size() - 1)
        var forward := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)])
        forward.y = 0.0
        forward = forward.normalized()
        var side := Vector3(-forward.z, 0.0, forward.x)
        var half := lerpf(w0, w1, t) * 0.42
        vertices.append(line[i] + side * half + Vector3(0, SURFACE_Y, 0))
        vertices.append(line[i] - side * half + Vector3(0, SURFACE_Y, 0))
        uvs.append(Vector2(0, t))
        uvs.append(Vector2(1, t))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
    var node := MeshInstance3D.new()
    node.name = "Surface_%02d" % segment["index"]
    node.mesh = mesh
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := ShaderMaterial.new()
    material.shader = WATER_SHADER
    material.set_shader_parameter("surface_only", true)
    material.set_shader_parameter("speed", 1.0 if water_animation else 0.0)
    node.material_override = material
    _surface_root.add_child(node)

func _bridge_polygons() -> Array[PackedVector2Array]:
    var polygons: Array[PackedVector2Array] = []
    for bridge in _bridges:
        var polygon := bridge.get_walk_polygon_global()
        if bridge_gap_margin > 0.0:
            var grown := Geometry2D.offset_polygon(polygon, bridge_gap_margin)
            if not grown.is_empty():
                polygon = grown[0]
        # Para o espaço local do RiverSystem.
        var local := PackedVector2Array()
        for point in polygon:
            var p := global_transform.affine_inverse() * Vector3(point.x, 0.0, point.y)
            local.append(Vector2(p.x, p.z))
        polygons.append(local)
    return polygons

func _in_any_polygon(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
    for polygon in polygons:
        if Geometry2D.is_point_in_polygon(point, polygon):
            return true
    return false

## Bloqueio físico só sobre a água: células da máscara agrupadas em caixas.
func _build_blockers(segment: Dictionary, meta: Dictionary) -> void:
    var cell := float(_meta.get("cell_px", 8))
    var p: float = segment["scale"]
    var origin: Vector3 = segment["origin"]
    var region: Rect2 = segment["region_px"]
    var mask: Array = meta["mask"]
    var polygons := _bridge_polygons()
    var rows := mask.size()
    var cols := int(meta["mask_cols"])
    # Linhas de células -> trechos contínuos [início, fim] de água.
    var runs_by_row: Array = []
    for row in rows:
        var runs: Array[Vector2i] = []
        var line: String = mask[row]
        var start := -1
        for col in cols + 1:
            var on := col < cols and line[col] == "1"
            if on:
                var center_px := Vector2((col + 0.5) * cell, (row + 0.5) * cell)
                if not region.has_point(center_px):
                    on = false
                else:
                    var world := origin + _px_to_local(center_px, p)
                    if _in_any_polygon(Vector2(world.x, world.z), polygons):
                        on = false
            if on and start < 0:
                start = col
            elif not on and start >= 0:
                runs.append(Vector2i(start, col - 1))
                start = -1
        runs_by_row.append(runs)
    # Junta linhas consecutivas com o mesmo trecho em retângulos.
    var rects: Array[Rect2i] = []
    var open := {}
    for row in rows + 1:
        var current: Array = runs_by_row[row] if row < rows else []
        var next_open := {}
        for run in current:
            var key := "%d_%d" % [run.x, run.y]
            if open.has(key):
                next_open[key] = open[key]
            else:
                next_open[key] = row
        for key in open.keys():
            if not next_open.has(key) or row == rows:
                var parts: PackedStringArray = (key as String).split("_")
                var start_row: int = open[key]
                rects.append(Rect2i(int(parts[0]), start_row, int(parts[1]) - int(parts[0]) + 1, row - start_row))
        open = next_open
    var body := StaticBody3D.new()
    body.name = "Blockers_%02d" % segment["index"]
    body.set_meta("river_segment", segment["index"])
    for i in rects.size():
        var rect := rects[i]
        var collision := CollisionShape3D.new()
        collision.name = "Water_%03d" % i
        var shape := BoxShape3D.new()
        shape.size = Vector3(rect.size.x * cell * p, blocker_height, rect.size.y * cell * p * _stretch)
        collision.shape = shape
        var center_px := Vector2((rect.position.x + rect.size.x * 0.5) * cell, (rect.position.y + rect.size.y * 0.5) * cell)
        collision.position = origin + _px_to_local(center_px, p) + Vector3(0.0, blocker_height * 0.5 - 0.1, 0.0)
        body.add_child(collision)
    segment["blocker_boxes"] = rects.size()
    _collisions_root.add_child(body)

func _add_bank_strip(strip: Dictionary) -> void:
    var asset: String = strip.get("asset", "bank_strip_left_flowers")
    var texture := load(BANK_DIR + asset + ".png") as Texture2D
    if texture == null:
        push_error("RiverSystem: missing bank strip " + asset)
        return
    var width: float = strip.get("width", 4.0)
    var mesh := MeshInstance3D.new()
    mesh.name = "Bank_%02d_%s" % [_banks_root.get_child_count(), asset.trim_prefix("bank_strip_")]
    var quad := QuadMesh.new()
    quad.size = Vector2(width, texture.get_height() * width / texture.get_width() * _stretch)
    mesh.mesh = quad
    mesh.rotation_degrees.x = -90.0
    mesh.position = strip.get("position", Vector3.ZERO)
    mesh.position.y = BANK_Y
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := StandardMaterial3D.new()
    material.albedo_texture = texture
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.5
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    mesh.material_override = material
    _banks_root.add_child(mesh)

# --- consultas -------------------------------------------------------------

## Retângulo (local, XZ) coberto pela arte do segmento (água + margens).
func get_segment_rect(segment: Dictionary) -> Rect2:
    var p: float = segment["scale"]
    var region: Rect2 = segment["region_px"]
    var a := (segment["origin"] as Vector3) + _px_to_local(region.position, p)
    var b := (segment["origin"] as Vector3) + _px_to_local(region.end, p)
    return Rect2(Vector2(a.x, a.z), Vector2(b.x - a.x, b.z - a.z))

## Verdadeiro se o ponto (global) cai em célula de água de algum segmento.
## margin (m) amplia a checagem para as células vizinhas.
func is_point_in_water(global_point: Vector3, margin: float = 0.0) -> bool:
    var point := global_transform.affine_inverse() * global_point
    var cell := float(_meta.get("cell_px", 8))
    for segment in segments:
        var meta := get_tile_meta(segment["tile"])
        var p: float = segment["scale"]
        var local := point - (segment["origin"] as Vector3)
        var px := Vector2(local.x / p, local.z / (p * _stretch))
        var region: Rect2 = segment["region_px"]
        var reach := int(ceil(margin / (p * cell)))
        var mask: Array = meta["mask"]
        var col := int(floor(px.x / cell))
        var row := int(floor(px.y / cell))
        for dr in range(-reach, reach + 1):
            for dc in range(-reach, reach + 1):
                var r := row + dr
                var c := col + dc
                if r < 0 or r >= mask.size() or c < 0 or c >= int(meta["mask_cols"]):
                    continue
                if not region.has_point(Vector2((c + 0.5) * cell, (r + 0.5) * cell)):
                    continue
                if (mask[r] as String)[c] == "1":
                    return true
    return false

## Máscara para decoração e futuros canteiros: rio (com margens ilustradas),
## pontes, acessos e uma folga para circular nas cabeceiras.
func blocks_decoration(global_point: Vector3, radius: float = 0.0) -> bool:
    var point := global_transform.affine_inverse() * global_point
    var p2 := Vector2(point.x, point.z)
    for segment in segments:
        if get_segment_rect(segment).grow(radius).has_point(p2):
            return true
    for bridge in _bridges:
        for rect in bridge.get_footprint_rects_global():
            if rect.grow(radius + 0.6).has_point(Vector2(global_point.x, global_point.z)):
                return true
        for end in bridge.get_endpoints_global():
            if Vector2(global_point.x - end.x, global_point.z - end.z).length() < 2.2 + radius:
                return true
    return false

## Canteiros, sementes e tomateiros nunca podem ficar no rio nem nas margens.
func is_planting_allowed(global_point: Vector3, radius: float = 0.3) -> bool:
    return not blocks_decoration(global_point, radius)

func get_total_blocker_boxes() -> int:
    var total := 0
    for segment in segments:
        total += int(segment.get("blocker_boxes", 0)) + int(segment.get("junction_blocker_boxes", 0))
    return total
