extends SceneTree
## Evidência visual de MAP-HELPER-002. Executar sem --headless:
## godot --path . --resolution 1280x720 -s tools/map_helpers_capture.gd -- <pasta>

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://docs/evidence/map-helper-002")
    DirAccess.make_dir_recursive_absolute(out_dir)
    TranslationServer.set_locale("pt_BR")
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.harvest_controller.enabled = false
    for controller in world.crop_harvesters.values():
        (controller as HarvestController).enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    world.hud.visible = false
    await create_timer(0.4).timeout

    var map := world.get_map_rect()
    await _capture(world, Vector3(map.get_center().x, 0.0, map.get_center().y), 76.0, out_dir, "01-mapa-expandido-areas-organicas")

    world.hud.visible = true
    var tomato_pad := world.helper_pad
    await _capture(world, tomato_pad.global_position, 9.0, out_dir, "02-custo-ajudante-tomate-madeira")

    var corn := world.get_crop_area(&"corn")
    var corn_pad := corn["pad"] as HelperPad
    await _capture(world, corn_pad.global_position, 9.0, out_dir, "03-custo-ajudante-milho-tomate")

    world.harvest_inventory.set_amount(&"corn", world.harvest_inventory.units_per_crate * 3)
    world.farmer.global_position = Vector3(4.0, 1.0, -7.0)
    world.backpack._orient_crates()
    await _capture(world, world.farmer.global_position, 7.0, out_dir, "04-caixas-milho-estaveis")
    quit()

func _capture(world: FarmWorld, focus: Vector3, size: float, out_dir: String, file_name: String) -> void:
    world.camera.size = size
    world.camera.far = 400.0
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    for frame in 8:
        await process_frame
    var path := out_dir.path_join(file_name + ".png")
    root.get_texture().get_image().save_png(path)
    print("CAPTURE ", path)
