extends SceneTree
## FLICK-001 — capturas da mochila carregada (tomate, milho, abóbora, madeira)
## em quadros seguidos com o fazendeiro andando. Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/flicker_capture.gd -- <pasta absoluta>

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/flick-001")
    DirAccess.make_dir_recursive_absolute(out_dir)
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
    var start := Vector3(-14.0, 1.0, 6.0)
    for item in [&"pumpkin", &"corn", &"tomato", &"wood"]:
        world.harvest_inventory.set_amount(&"pumpkin", 0)
        world.harvest_inventory.set_amount(&"corn", 0)
        world.harvest_inventory.set_amount(&"tomato", 0)
        world.harvest_inventory.set_amount(&"wood", 0)
        world.harvest_inventory.set_amount(item, world.harvest_inventory.get_capacity() - 3)
        for frame in 4:
            world.farmer.global_position = start + Vector3(0.11 * frame, 0.0, 0.07 * frame)
            world.farmer.rotation.y = 0.15 * frame
            world.camera.size = 8.0
            var focus := world.farmer.global_position + Vector3(0.0, 1.0, 0.0)
            world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
            world.camera.look_at(focus, Vector3.UP)
            await process_frame
            await process_frame
            await RenderingServer.frame_post_draw
            var image := root.get_texture().get_image()
            image.save_png(out_dir.path_join("%s-%d.png" % [item, frame]))
    quit()
