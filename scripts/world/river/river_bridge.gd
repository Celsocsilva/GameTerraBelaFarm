extends Node3D
class_name RiverBridge

## ENV-002 — Ponte reutilizável sobre o rio (BridgeWood.tscn, BridgeStone.tscn).
##
## O PNG é só a aparência: é desenhado deitado no chão (como o solo e os tiles
## do rio), alongado em Z por 1/sin(45°) para aparecer na proporção da arte na
## câmera da fazenda. A travessia física é uma superfície 3D invisível em arco
## (WalkSurface) com corrimãos invisíveis (Rails) nas duas bordas do tabuleiro.
##
## Coordenadas da arte em px (origem no canto superior esquerdo do PNG):
## - deck_front_px / deck_back_px: bordas sul (frente) e norte (fundo) do
##   tabuleiro, da cabeceira oeste (próxima) até a leste; mesma quantidade.
## - front_mask_px: polígono do que fica NA FRENTE de quem está na ponte
##   (corrimão frontal, postes e lanternas da frente). Vira FrontLayer.
##
## Um ponto do mundo (x, h, z) aparece na tela no mesmo lugar que o ponto do
## chão (x, 0, z - h) nesta câmera (45°, sem giro). Por isso a superfície em
## arco é deslocada +h em Z: os pés do fazendeiro ficam sobre as tábuas da arte.

const FRONT_SHADER := preload("res://assets/bridges/bridge_front_layer.gdshader")
const VIEW_PITCH_DEGREES := 45.0
const DECAL_Y := 0.05
const APPROACH_Y := 0.045

@export var bridge_id: String = "bridge"
@export var art: Texture2D
## Largura no mundo (m) do PNG da ponte.
@export var art_width_m: float = 8.0
@export var deck_front_px: PackedVector2Array
@export var deck_back_px: PackedVector2Array
## Altura máxima (m) do arco no meio da travessia; 0 nas cabeceiras.
@export_range(0.0, 1.0, 0.01) var arch_height: float = 0.3
@export var front_mask_px: PackedVector2Array
@export_range(2, 24, 1) var front_strips: int = 10
@export_range(8, 48, 1) var walk_segments: int = 16
@export var rail_height: float = 1.2
@export var rail_thickness: float = 0.16
## Recuo (m) dos corrimãos para dentro do tabuleiro em cada borda.
@export var rail_inset: float = 0.12

@export_group("Approaches")
## Acessos gramados (opcionais), desenhados no chão e caminháveis.
@export var approach_west: Texture2D
@export var approach_west_position: Vector3
@export var approach_west_width_m: float = 6.0
## Postes do acesso (px no PNG do acesso) que recebem colisão cilíndrica.
@export var approach_west_posts_px: PackedVector2Array
## Caminho do acesso (px no PNG do acesso), da tábua junto à ponte até a ponta.
@export var approach_west_path_px: PackedVector2Array
@export var approach_east: Texture2D
@export var approach_east_position: Vector3
@export var approach_east_width_m: float = 6.0
@export var approach_east_posts_px: PackedVector2Array
@export var approach_east_path_px: PackedVector2Array
@export var approach_post_radius: float = 0.28

var pixel_size := 0.0
var walk_front: PackedVector3Array = PackedVector3Array()
var walk_back: PackedVector3Array = PackedVector3Array()
var _stretch := 1.0 / sin(deg_to_rad(VIEW_PITCH_DEGREES))
var _built := false

func _ready() -> void:
    add_to_group("river_bridge")
    build()

func build() -> void:
    if _built or art == null:
        return
    _built = true
    pixel_size = art_width_m / float(art.get_width())
    _build_art()
    _build_walk_geometry()
    _build_front_layer()
    _build_approaches()

## Ponto do chão (local) que aparece no px (u, v) da arte.
func px_to_local(px: Vector2) -> Vector3:
    return Vector3((px.x - art.get_width() * 0.5) * pixel_size, 0.0,
        (px.y - art.get_height() * 0.5) * pixel_size * _stretch)

func _decal_material(texture: Texture2D) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_texture = texture
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.5
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    return material

func _flat_quad(node_name: String, texture: Texture2D, width_m: float, y: float) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    mesh.name = node_name
    var quad := QuadMesh.new()
    var px := width_m / float(texture.get_width())
    quad.size = Vector2(width_m, texture.get_height() * px * _stretch)
    mesh.mesh = quad
    mesh.material_override = _decal_material(texture)
    mesh.rotation_degrees.x = -90.0
    mesh.position.y = y
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mesh

func _build_art() -> void:
    add_child(_flat_quad("Art", art, art_width_m, DECAL_Y))

## Amostra uma polilinha (px) por fração do comprimento.
static func _sample_polyline(points: PackedVector2Array, t: float) -> Vector2:
    if points.size() == 1:
        return points[0]
    var total := 0.0
    for i in points.size() - 1:
        total += points[i].distance_to(points[i + 1])
    var target := clampf(t, 0.0, 1.0) * total
    for i in points.size() - 1:
        var length := points[i].distance_to(points[i + 1])
        if target <= length or i == points.size() - 2:
            return points[i].lerp(points[i + 1], clampf(target / maxf(length, 0.0001), 0.0, 1.0))
        target -= length
    return points[points.size() - 1]

func _arch(t: float) -> float:
    return arch_height * sin(PI * clampf(t, 0.0, 1.0))

## Ponto da superfície de caminhada (local) na fração t de uma borda.
func _walk_point(edge_px: PackedVector2Array, t: float) -> Vector3:
    var ground := px_to_local(_sample_polyline(edge_px, t))
    var h := _arch(t)
    return ground + Vector3(0.0, h, h)

func _build_walk_geometry() -> void:
    walk_front.clear()
    walk_back.clear()
    for i in walk_segments + 1:
        var t := float(i) / walk_segments
        walk_front.append(_walk_point(deck_front_px, t))
        walk_back.append(_walk_point(deck_back_px, t))
    var body := StaticBody3D.new()
    body.name = "WalkSurface"
    add_child(body)
    var faces := PackedVector3Array()
    for i in walk_segments:
        var f0 := walk_front[i]
        var f1 := walk_front[i + 1]
        var b0 := walk_back[i]
        var b1 := walk_back[i + 1]
        faces.append_array([f0, b0, f1, f1, b0, b1])
    var shape := ConcavePolygonShape3D.new()
    shape.backface_collision = true
    shape.set_faces(faces)
    var collision := CollisionShape3D.new()
    collision.name = "Deck"
    collision.shape = shape
    body.add_child(collision)
    var rails := StaticBody3D.new()
    rails.name = "Rails"
    add_child(rails)
    _add_rail(rails, "Front", walk_front, walk_back)
    _add_rail(rails, "Back", walk_back, walk_front)

func _add_rail(body: StaticBody3D, label: String, edge: PackedVector3Array, other: PackedVector3Array) -> void:
    for i in edge.size() - 1:
        var inward0 := (other[i] - edge[i]).normalized() * rail_inset
        var inward1 := (other[i + 1] - edge[i + 1]).normalized() * rail_inset
        var a := edge[i] + inward0
        var b := edge[i + 1] + inward1
        var direction := b - a
        var length := direction.length()
        if length < 0.01:
            continue
        var collision := CollisionShape3D.new()
        collision.name = "%s_%02d" % [label, i]
        var shape := BoxShape3D.new()
        # Um pouco mais longo para não deixar fresta entre segmentos inclinados.
        shape.size = Vector3(rail_thickness, rail_height, length + rail_thickness)
        collision.shape = shape
        var forward := Vector3(direction.x, 0.0, direction.z).normalized()
        collision.basis = Basis.looking_at(forward, Vector3.UP)
        collision.position = (a + b) * 0.5 + Vector3(0.0, rail_height * 0.5, 0.0)
        body.add_child(collision)

## Polígono XZ (local) ocupado pela travessia: usado para abrir o bloqueio da
## água e para manter decorações fora do caminho.
func get_walk_polygon_local() -> PackedVector2Array:
    var polygon := PackedVector2Array()
    for point in walk_front:
        polygon.append(Vector2(point.x, point.z))
    for i in range(walk_back.size() - 1, -1, -1):
        polygon.append(Vector2(walk_back[i].x, walk_back[i].z))
    return polygon

func get_walk_polygon_global() -> PackedVector2Array:
    var polygon := PackedVector2Array()
    for point in get_walk_polygon_local():
        var world := global_transform * Vector3(point.x, 0.0, point.y)
        polygon.append(Vector2(world.x, world.z))
    return polygon

## Pontos (globais) no meio das cabeceiras oeste e leste, ao nível do chão.
func get_endpoints_global() -> Array[Vector3]:
    var west := (walk_front[0] + walk_back[0]) * 0.5
    var east := (walk_front[walk_front.size() - 1] + walk_back[walk_back.size() - 1]) * 0.5
    return [global_transform * west, global_transform * east]

## Linha central da travessia (global), da cabeceira oeste à leste.
func get_centerline_global(samples: int = 24) -> PackedVector3Array:
    var line := PackedVector3Array()
    for i in samples + 1:
        var t := float(i) / samples
        var point := (_walk_point(deck_front_px, t) + _walk_point(deck_back_px, t)) * 0.5
        line.append(global_transform * point)
    return line

## Caminho de um acesso no chão (global), da ponte para fora. Sem acesso,
## devolve um prolongamento reto de 2 m da travessia.
func get_approach_path_global(east: bool) -> PackedVector3Array:
    var texture := approach_east if east else approach_west
    var path_px := approach_east_path_px if east else approach_west_path_px
    var center := approach_east_position if east else approach_west_position
    var width := approach_east_width_m if east else approach_west_width_m
    var result := PackedVector3Array()
    if texture == null or path_px.size() < 2:
        var line := get_centerline_global(8)
        var a := line[line.size() - 1] if east else line[0]
        var b := line[line.size() - 2] if east else line[1]
        var out := Vector3(a.x - b.x, 0.0, a.z - b.z).normalized()
        result.append(Vector3(a.x, 0.0, a.z) + out * 0.8)
        result.append(Vector3(a.x, 0.0, a.z) + out * 2.0)
        return result
    var px := width / float(texture.get_width())
    for point in path_px:
        var local := center + Vector3((point.x - texture.get_width() * 0.5) * px, 0.0,
            (point.y - texture.get_height() * 0.5) * px * _stretch)
        result.append(global_transform * local)
    return result

## Área (global, XZ) que o PNG da ponte e os acessos cobrem no chão.
func get_footprint_rects_global() -> Array[Rect2]:
    var rects: Array[Rect2] = []
    var art_size := Vector2(art_width_m, art.get_height() * pixel_size * _stretch)
    rects.append(Rect2(Vector2(global_position.x, global_position.z) - art_size * 0.5, art_size))
    for entry in [[approach_west, approach_west_position, approach_west_width_m],
            [approach_east, approach_east_position, approach_east_width_m]]:
        var texture := entry[0] as Texture2D
        if texture == null:
            continue
        var width: float = entry[2]
        var size := Vector2(width, texture.get_height() * width / texture.get_width() * _stretch)
        var center := global_transform * (entry[1] as Vector3)
        rects.append(Rect2(Vector2(center.x, center.z) - size * 0.5, size))
    return rects

func _build_front_layer() -> void:
    if front_mask_px.size() < 3:
        return
    var layer := Node3D.new()
    layer.name = "FrontLayer"
    add_child(layer)
    var w := float(art.get_width())
    var h := float(art.get_height())
    var polygon_uv := PackedVector2Array()
    for point in front_mask_px:
        polygon_uv.append(Vector2(point.x / w, point.y / h))
    var min_u := w
    var max_u := 0.0
    for point in front_mask_px:
        min_u = minf(min_u, point.x)
        max_u = maxf(max_u, point.x)
    var to_camera := Vector3(0.0, sin(deg_to_rad(VIEW_PITCH_DEGREES)), cos(deg_to_rad(VIEW_PITCH_DEGREES)))
    var strip_width := (max_u - min_u) / front_strips
    for i in front_strips:
        var u0 := min_u + i * strip_width
        var u1 := u0 + strip_width
        var uc := (u0 + u1) * 0.5
        # Profundidade: borda frontal do tabuleiro na coluna desta faixa.
        var depth_point := _front_edge_point_at_u(uc)
        var ground_center := px_to_local(Vector2(uc, h * 0.5)) + Vector3(0.0, DECAL_Y, 0.0)
        var center := ground_center + to_camera * (depth_point - ground_center).dot(to_camera)
        var mesh := MeshInstance3D.new()
        mesh.name = "FrontStrip_%02d" % i
        var quad := QuadMesh.new()
        # Pequena sobreposição entre faixas para não abrir frestas de 1 px.
        quad.size = Vector2(strip_width * pixel_size * 1.02, h * pixel_size)
        mesh.mesh = quad
        mesh.rotation_degrees.x = -VIEW_PITCH_DEGREES
        mesh.position = center
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var material := ShaderMaterial.new()
        material.shader = FRONT_SHADER
        material.set_shader_parameter("albedo_tex", art)
        material.set_shader_parameter("uv_offset", Vector2(u0 / w, 0.0))
        material.set_shader_parameter("uv_scale", Vector2(strip_width * 1.02 / w, 1.0))
        material.set_shader_parameter("polygon_size", polygon_uv.size())
        material.set_shader_parameter("front_polygon", polygon_uv)
        mesh.material_override = material
        layer.add_child(mesh)

## Ponto da borda frontal da travessia (local, já com o arco) na coluna u da arte.
func _front_edge_point_at_u(u: float) -> Vector3:
    var first := deck_front_px[0]
    var last := deck_front_px[deck_front_px.size() - 1]
    if u <= first.x:
        return _walk_point(deck_front_px, 0.0)
    if u >= last.x:
        return _walk_point(deck_front_px, 1.0)
    var best_t := 0.0
    var best_d := INF
    for i in 65:
        var t := float(i) / 64.0
        var d := absf(_sample_polyline(deck_front_px, t).x - u)
        if d < best_d:
            best_d = d
            best_t = t
    return _walk_point(deck_front_px, best_t)

func _build_approaches() -> void:
    _build_approach("ApproachWest", approach_west, approach_west_position, approach_west_width_m, approach_west_posts_px)
    _build_approach("ApproachEast", approach_east, approach_east_position, approach_east_width_m, approach_east_posts_px)

func _build_approach(label: String, texture: Texture2D, local_position: Vector3, width_m: float, posts: PackedVector2Array) -> void:
    if texture == null:
        return
    var quad := _flat_quad(label, texture, width_m, APPROACH_Y)
    quad.position.x = local_position.x
    quad.position.z = local_position.z
    add_child(quad)
    if posts.is_empty():
        return
    var body := StaticBody3D.new()
    body.name = label + "Posts"
    add_child(body)
    var px := width_m / float(texture.get_width())
    for i in posts.size():
        var local := Vector3((posts[i].x - texture.get_width() * 0.5) * px, 0.0,
            (posts[i].y - texture.get_height() * 0.5) * px * _stretch)
        var collision := CollisionShape3D.new()
        collision.name = "Post_%02d" % i
        var shape := CylinderShape3D.new()
        shape.radius = approach_post_radius
        shape.height = 1.2
        collision.shape = shape
        collision.position = Vector3(local_position.x, 0.6, local_position.z) + local
        body.add_child(collision)
