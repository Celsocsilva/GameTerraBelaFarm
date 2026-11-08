extends SceneTree
## QA headless ENV-001. Exit 1 on any failed assertion.
## Godot --headless --path PROJECT -s tools/environment_smoke.gd

const ASSET_DIRS := {
    "res://assets/decor/farm_props": 16,
    "res://assets/decor/flowers": 6,
    "res://assets/decor/rocks": 3,
    "res://assets/decor/trees": 4,
    "res://assets/decor/vegetation": 6,
    "res://assets/terrain/grass": 4,
    "res://assets/terrain/patches": 6,
}
const GRASS_NAMES := ["grass_base", "grass_flowers", "grass_pebbles", "grass_mixed"]

var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error("ENVIRONMENT_SMOKE_FAIL: " + message)

func _run() -> void:
    _check_assets()
    var packed := load("res://scenes/world/farm_world.tscn") as PackedScene
    if packed == null:
        _check(false, "FarmWorld scene failed to load")
        quit(1)
        return
    var world := packed.instantiate() as FarmWorld
    if world == null:
        _check(false, "FarmWorld scene failed to instantiate")
        quit(1)
        return
    root.add_child(world)
    await process_frame
    world.set_process(false)
    _check_ground(world)
    _check_placements(world)
    _check_seed(world)
    _check_regression(world)
    if failures == 0:
        print("ENVIRONMENT_SMOKE_OK assets=45 placements=", world.cozy_environment.placements.size())
        quit(0)
    else:
        print("ENVIRONMENT_SMOKE_FAILED failures=", failures)
        quit(1)

func _check_assets() -> void:
    var count := 0
    for directory in ASSET_DIRS:
        var files := DirAccess.get_files_at(directory)
        var png_count := 0
        for filename in files:
            if not filename.to_lower().ends_with(".png"):
                continue
            png_count += 1
            count += 1
            var path: String = directory + "/" + filename
            var image := Image.new()
            var bytes := FileAccess.get_file_as_bytes(path)
            var error := image.load_png_from_buffer(bytes)
            _check(error == OK, "PNG unreadable: " + path)
            if error != OK:
                continue
            _check(image.get_format() == Image.FORMAT_RGBA8, "PNG is not RGBA8: " + path)
            _check(image.get_width() > 0 and image.get_height() > 0, "Empty PNG: " + path)
            if directory.ends_with("/grass"):
                _check(image.get_size() == Vector2i(512, 512), "Grass tile must be 512x512: " + path)
                _check(image.get_pixel(0, 0).a == 1.0, "Grass corner not opaque: " + path)
                _check_seams(image, path)
            else:
                _check(image.get_pixel(0, 0).a < 1.0, "Sprite/patch corner lacks transparency: " + path)
        _check(png_count == int(ASSET_DIRS[directory]), "PNG count in %s: %d" % [directory, png_count])
    _check(count == 45, "Expected 45 PNGs, found %d" % count)
    print("ENV_ASSETS checked=", count)

func _check_seams(image: Image, path: String) -> void:
    var last := image.get_width() - 1
    var horizontal_ok := true
    var vertical_ok := true
    for i in image.get_width():
        horizontal_ok = horizontal_ok and image.get_pixel(0, i) == image.get_pixel(last, i)
        vertical_ok = vertical_ok and image.get_pixel(i, 0) == image.get_pixel(i, last)
    _check(horizontal_ok, "Horizontal seam: " + path)
    _check(vertical_ok, "Vertical seam: " + path)

func _check_ground(world: FarmWorld) -> void:
    var ground := world.get_node_or_null("Ground/GrassSurface") as MeshInstance3D
    _check(ground != null, "GrassSurface missing")
    if ground == null:
        return
    _check(ground.mesh is BoxMesh, "Ground mesh changed")
    if ground.mesh is BoxMesh:
        _check(is_equal_approx((ground.mesh as BoxMesh).size.x, world.farm_size), "Ground width changed")
    var material := ground.material_override as ShaderMaterial
    _check(material != null, "GrassSurface lacks ShaderMaterial")
    if material == null:
        return
    _check(material.shader != null, "Grass shader missing")
    if material.shader != null:
        var code := material.shader.code
        _check(code.contains("world_xz * tiles_per_meter"), "Grass does not tile by world coordinates")
        _check(code.contains("repeat_enable"), "Grass texture repeat disabled in shader")
    for name in GRASS_NAMES:
        var texture := material.get_shader_parameter(name) as Texture2D
        _check(texture != null, "Grass shader parameter missing: " + name)
        if texture != null:
            _check(texture.get_size() == Vector2(512, 512), "Grass texture size: " + name)
    _check(is_equal_approx(float(material.get_shader_parameter("tiles_per_meter")), world.cozy_environment.grass_tiles_per_meter), "Grass tile scale differs from setup")
    for plot in world.get_node("PlantingArea").get_children():
        var soil := plot.get_node("PlowedSoil") as MeshInstance3D
        _check(soil.material_override is StandardMaterial3D, "Cultivation soil material replaced: " + plot.name)
        if soil.material_override is StandardMaterial3D:
            _check((soil.material_override as StandardMaterial3D).albedo_texture == FarmWorld.SOIL_TEXTURE, "Cultivation soil texture replaced: " + plot.name)
    print("ENV_GROUND shader=", material.shader.resource_path, " tiles_per_meter=", material.get_shader_parameter("tiles_per_meter"))

func _check_placements(world: FarmWorld) -> void:
    var env := world.cozy_environment
    _check(env != null, "CozyEnvironment missing")
    if env == null:
        return
    _check(not env.placements.is_empty(), "No decorations placed")
    var categories := {}
    for entry in env.placements:
        var category: String = entry["category"]
        var asset: String = entry["asset"]
        var point: Vector3 = entry["position"]
        var radius: float = entry["clearance"]
        categories[category] = int(categories.get(category, 0)) + 1
        _check(FileAccess.file_exists(asset), "Placement asset missing: " + asset)
        _check(radius > 0.0, "Nonpositive clearance: " + asset)
        _check(is_equal_approx(point.y, 0.02), "Decoration not grounded: " + asset)
        _check(env.is_allowed_position(point, radius), "Forbidden placement: " + asset + " at " + str(point))
        _check(absf(point.x) + radius <= world.farm_size * 0.5 - 1.0 and absf(point.z) + radius <= world.farm_size * 0.5 - 1.0, "Placement crosses world boundary: " + asset)
        for plot in world.get_node("PlantingArea").get_children():
            var shape := (plot.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
            var dx := absf(point.x - plot.global_position.x)
            var dz := absf(point.z - plot.global_position.z)
            _check(dx > shape.size.x * 0.5 + radius or dz > shape.size.z * 0.5 + radius, "Placement overlaps cultivation plot: " + asset + " / " + plot.name)
    for i in env.placements.size():
        var a: Dictionary = env.placements[i]
        for j in range(i + 1, env.placements.size()):
            var b: Dictionary = env.placements[j]
            var pa: Vector3 = a["position"]
            var pb: Vector3 = b["position"]
            var distance := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
            _check(distance >= float(a["clearance"]) + float(b["clearance"]) - 0.001, "Decorations overlap: %d / %d" % [i, j])
    for category in categories:
        var group := env.get_node_or_null(category)
        _check(group != null, "Placement group missing: " + category)
        if group != null:
            _check(group.get_child_count() == int(categories[category]), "Placement node count differs: " + category)
            for decoration in group.get_children():
                var art := decoration.get_node_or_null("Art") as Sprite3D
                _check(art != null, "Decoration lacks Sprite3D art: " + decoration.name)
                if art != null:
                    _check(art.texture != null and art.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "Sprite transparency config: " + decoration.name)
                    _check(not art.centered and is_zero_approx(art.offset.y), "Sprite base anchor: " + decoration.name)
                    _check(not art.no_depth_test, "Sprite ignores depth: " + decoration.name)
    _check(categories.size() == 6, "Expected all six decoration categories")
    print("ENV_PLACEMENTS count=", env.placements.size(), " categories=", categories)

func _check_seed(world: FarmWorld) -> void:
    var original := world.cozy_environment
    var duplicate := CozyEnvironment.new()
    duplicate.placement_seed = original.placement_seed
    duplicate.flower_density = original.flower_density
    duplicate.tuft_density = original.tuft_density
    duplicate.rock_density = original.rock_density
    duplicate.bush_density = original.bush_density
    duplicate.tree_density = original.tree_density
    duplicate.prop_density = original.prop_density
    duplicate.grass_tiles_per_meter = original.grass_tiles_per_meter
    var mesh := MeshInstance3D.new()
    duplicate.setup(mesh, world.farm_size, world.get_planting_area_half_width(),
        FarmWorld.PLANTING_NEAR_EDGE_Z,
        FarmWorld.PLANTING_NEAR_EDGE_Z + world.planting_plot_size.y,
        world.sales_counter.position)
    _check(duplicate.placements.size() == original.placements.size(), "Same seed changed placement count")
    for i in mini(duplicate.placements.size(), original.placements.size()):
        var a: Dictionary = original.placements[i]
        var b: Dictionary = duplicate.placements[i]
        _check(a["category"] == b["category"] and a["asset"] == b["asset"] and a["position"] == b["position"] and is_equal_approx(float(a["clearance"]), float(b["clearance"])), "Same seed changed placement %d" % i)
    duplicate.free()
    mesh.free()
    print("ENV_SEED seed=", original.placement_seed, " compared=", original.placements.size())

func _check_regression(world: FarmWorld) -> void:
    _check(world.farmer != null and world.farmer is CharacterBody3D, "Farmer missing")
    _check(world.camera != null and world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Camera changed")
    _check(world.get_node_or_null("HUD/VirtualJoystick") != null, "Virtual joystick missing")
    _check(world.hud != null, "HUD missing")
    _check(world.sales_counter != null and world.customer_queue != null, "Sales/queue missing")
    var expected := FarmWorld.PLANTING_PLOT_COUNT * world.planting_grid.columns * world.planting_grid.rows_per_module
    _check(world.planting_grid.cells.size() == expected, "Cultivation cell count changed")
    var cell: Dictionary = world.planting_grid.cells.values()[0]
    world.planting_grid.cell_planted.disconnect(world._on_grid_cell_planted)
    _check(world.planting_grid.plant_cell(cell["id"]), "Basic planting failed")
    _check(world.planting_grid.cells[cell["id"]]["state"] == "SEEDED", "Planted cell state incorrect")
    world.harvest_inventory.set_amount(&"tomato", 8)
    var deposited := world.sales_counter.deposit_from(world.harvest_inventory)
    _check(deposited == 8 and world.sales_counter.get_stored_total() == 8, "Basic sales deposit failed")
    print("ENV_REGRESSION cells=", expected, " planted=1 deposited=", deposited)
