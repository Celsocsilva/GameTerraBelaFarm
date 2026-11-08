extends SceneTree
## Uso com --write-movie: -- --view=grass|field|overview|debug

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.harvest_controller.enabled = false
    var view := "overview"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--view="):
            view = arg.trim_prefix("--view=")
    var focus := Vector3(0.0, 0.0, 9.0)
    var size := 34.0
    match view:
        "grass":
            focus = Vector3(-13.0, 0.0, -5.0)
            size = 13.0
        "field":
            focus = Vector3(0.0, 0.0, 13.0)
            size = 25.0
            for cell in world.planting_grid.cells.values():
                if int(cell["column"]) == 1:
                    world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
        "debug":
            _add_debug_grid(world)
        "overview":
            pass
        _:
            push_error("Unknown view: " + view)
            quit(1)
            return
    world.camera.size = size
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    print("ENV_CAPTURE view=", view, " decorations=", world.cozy_environment.placements.size())
    for frame in 7:
        await process_frame
    quit()

func _add_debug_grid(world: FarmWorld) -> void:
    var allowed := _debug_material(Color(0.15, 0.95, 0.15, 0.55))
    var blocked := _debug_material(Color(1.0, 0.1, 0.1, 0.55))
    for x in range(-24, 25, 3):
        for z in range(-24, 25, 3):
            var point := Vector3(float(x), 0.07, float(z))
            var marker := MeshInstance3D.new()
            var mesh := BoxMesh.new()
            mesh.size = Vector3(0.50, 0.01, 0.50)
            marker.mesh = mesh
            marker.material_override = allowed if world.cozy_environment.is_allowed_position(point, 0.4) else blocked
            marker.position = point
            world.add_child(marker)

func _debug_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    return material
