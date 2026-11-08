extends Node3D
class_name CozyEnvironment

## Ambientação visual determinística, independente das regras de cultivo.
## As densidades são instâncias por 100 m² de mapa; a seed reproduz a cena.
@export var placement_seed: int = 1701
@export_range(0.0, 5.0, 0.1) var flower_density: float = 1.7
@export_range(0.0, 5.0, 0.1) var tuft_density: float = 1.5
@export_range(0.0, 2.0, 0.05) var rock_density: float = 0.30
@export_range(0.0, 2.0, 0.05) var bush_density: float = 0.25
@export_range(0.0, 1.0, 0.05) var tree_density: float = 0.10
@export_range(0.0, 1.0, 0.05) var prop_density: float = 0.15
@export_range(0.15, 1.0, 0.05) var grass_tiles_per_meter: float = 0.23

const GRASS_SHADER := preload("res://assets/terrain/grass/cozy_ground.gdshader")
const GRASS_BASE := preload("res://assets/terrain/grass/grass_base_seamless_512.png")
const GRASS_FLOWERS := preload("res://assets/terrain/grass/grass_flowers_sparse_seamless_512.png")
const GRASS_PEBBLES := preload("res://assets/terrain/grass/grass_pebbles_sparse_seamless_512.png")
const GRASS_MIXED := preload("res://assets/terrain/grass/grass_mixed_sparse_seamless_512.png")

const FLOWERS := [
    "res://assets/decor/flowers/daisies_white.png",
    "res://assets/decor/flowers/flowers_yellow.png",
    "res://assets/decor/flowers/flowers_purple.png",
    "res://assets/decor/flowers/flowers_red.png",
    "res://assets/decor/flowers/sunflowers.png"
]
const TUFTS := [
    "res://assets/decor/vegetation/grass_tuft_broad.png",
    "res://assets/decor/vegetation/grass_tuft_spiky.png"
]
const ROCKS := [
    "res://assets/decor/rocks/rock_cluster_small.png",
    "res://assets/decor/rocks/rock_cluster_medium.png",
    "res://assets/decor/rocks/rock_cluster_large.png"
]
const BUSHES := [
    "res://assets/decor/vegetation/bush_white_flowers.png",
    "res://assets/decor/vegetation/bush_red_berries.png",
    "res://assets/decor/vegetation/bush_purple_flowers.png"
]
const TREES := [
    "res://assets/decor/trees/tree_green.png",
    "res://assets/decor/trees/tree_pine.png",
    "res://assets/decor/trees/tree_pink_blossom.png",
    "res://assets/decor/trees/tree_orchard.png"
]
const PROPS := [
    "res://assets/decor/farm_props/hay_bale.png",
    "res://assets/decor/farm_props/barrel_wood.png",
    "res://assets/decor/farm_props/wood_logs.png",
    "res://assets/decor/farm_props/lantern_post.png"
]

var placements: Array[Dictionary] = []
## Áreas reservadas por outros sistemas (ex.: RiverSystem, ENV-002). Cada item
## expõe blocks_decoration(point: Vector3, radius: float) -> bool.
var reserved_areas: Array[Object] = []
var _farm_size := 0.0
var _plot_half_width := 0.0
var _plot_start_z := 0.0
var _plot_end_z := 0.0
var _sales_position := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

func setup(ground_mesh: MeshInstance3D, farm_size: float, plot_half_width: float,
        plot_start_z: float, plot_end_z: float, sales_position: Vector3) -> void:
    _farm_size = farm_size
    _plot_half_width = plot_half_width
    _plot_start_z = plot_start_z
    _plot_end_z = plot_end_z
    _sales_position = sales_position
    _rng.seed = placement_seed
    _apply_grass(ground_mesh)
    _place_category("Flowers", FLOWERS, flower_density, 0.42, 0.75)
    _place_category("GrassTufts", TUFTS, tuft_density, 0.50, 0.85)
    _place_category("Rocks", ROCKS, rock_density, 0.60, 1.25)
    _place_category("Bushes", BUSHES, bush_density, 0.95, 1.45)
    _place_category("Trees", TREES, tree_density, 2.4, 3.1)
    _place_category("FarmDecorations", PROPS, prop_density, 0.75, 1.30)

func _apply_grass(ground_mesh: MeshInstance3D) -> void:
    var material := ShaderMaterial.new()
    material.shader = GRASS_SHADER
    material.set_shader_parameter("grass_base", GRASS_BASE)
    material.set_shader_parameter("grass_flowers", GRASS_FLOWERS)
    material.set_shader_parameter("grass_pebbles", GRASS_PEBBLES)
    material.set_shader_parameter("grass_mixed", GRASS_MIXED)
    material.set_shader_parameter("tiles_per_meter", grass_tiles_per_meter)
    ground_mesh.material_override = material

func _place_category(category: String, paths: Array, density: float,
        min_width: float, max_width: float) -> void:
    var group := Node3D.new()
    group.name = category
    add_child(group)
    var target := roundi(density * _farm_size * _farm_size / 100.0)
    var placed := 0
    for attempt in target * 45:
        if placed >= target:
            break
        var point := _sample_position()
        var width := _rng.randf_range(min_width, max_width)
        var solid := category in ["Trees", "FarmDecorations"] or (category == "Rocks" and width > 0.95)
        var clearance := width * (0.65 if solid else 0.55)
        if not is_allowed_position(point, clearance):
            continue
        if _too_close_to_existing(point, clearance):
            continue
        var path: String = paths[_rng.randi_range(0, paths.size() - 1)]
        var node := _make_sprite(path, width, point, solid)
        group.add_child(node)
        placements.append({"category": category, "asset": path, "position": point, "clearance": clearance})
        placed += 1

func _sample_position() -> Vector3:
    var limit := _farm_size * 0.5 - 2.5
    # A maior parte dos detalhes fica no entorno do campo; o resto povoa as bordas.
    var center_bias := _rng.randf() < 0.65
    var spread := minf(limit, 21.0) if center_bias else limit
    return Vector3(_rng.randf_range(-spread, spread), 0.02,
        _rng.randf_range(-spread, spread))

## Máscara espacial pública para a cena de QA e futuros módulos de expansão.
func is_allowed_position(point: Vector3, radius: float = 0.0) -> bool:
    var edge := _farm_size * 0.5 - 1.0
    if absf(point.x) + radius > edge or absf(point.z) + radius > edge:
        return false
    if absf(point.x) < _plot_half_width + 1.5 + radius and \
            point.z > _plot_start_z - 1.8 - radius and point.z < _plot_end_z + 1.8 + radius:
        return false
    # Acesso do fazendeiro pela frente e circulação entre campo e balcão.
    if absf(point.x) < 3.2 + radius and point.z > -8.0 - radius:
        return false
    if Vector2(point.x - _sales_position.x, point.z - _sales_position.z).length() < 7.0 + radius:
        return false
    if point.z > _sales_position.z - 6.0 - radius and absf(point.x) < 12.0 + radius:
        return false
    # Construção, cerca e árvore já existentes na cena.
    if absf(point.x - 5.0) < 3.0 + radius and absf(point.z + 3.0) < 2.8 + radius:
        return false
    if absf(point.x + 5.0) < 3.8 + radius and absf(point.z + 2.0) < 1.5 + radius:
        return false
    if Vector2(point.x + 10.0, point.z - 10.0).length() < 2.7 + radius:
        return false
    for area in reserved_areas:
        if is_instance_valid(area) and area.blocks_decoration(point, radius):
            return false
    # Espaço de expansão ao norte do mapa, sem decoração sólida.
    if point.z < -23.0 and radius > 0.7:
        return false
    return true

func _too_close_to_existing(point: Vector3, radius: float) -> bool:
    for entry in placements:
        var other: Vector3 = entry["position"]
        var other_clearance: float = entry["clearance"]
        if Vector2(point.x, point.z).distance_to(Vector2(other.x, other.z)) < radius + other_clearance:
            return true
    return false

func _make_sprite(path: String, width: float, point: Vector3, solid: bool) -> Node3D:
    var root := StaticBody3D.new() if solid else Node3D.new()
    root.name = path.get_file().get_basename()
    root.position = point
    var sprite := Sprite3D.new()
    var texture := load(path) as Texture2D
    sprite.name = "Art"
    sprite.texture = texture
    sprite.pixel_size = width / float(texture.get_width())
    sprite.centered = false
    sprite.offset = Vector2(-texture.get_width() * 0.5, 0.0)
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.shaded = false
    sprite.double_sided = true
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.alpha_scissor_threshold = 0.20
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    root.add_child(sprite)
    if solid:
        var collision := CollisionShape3D.new()
        var shape := CylinderShape3D.new()
        shape.radius = width * 0.22
        shape.height = 1.0 if width < 2.0 else 1.8
        collision.shape = shape
        collision.position.y = shape.height * 0.5
        root.add_child(collision)
    return root
