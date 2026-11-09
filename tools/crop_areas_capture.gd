extends SceneTree
## CROP-AREAS-001 + ENV-FENCE-001 — capturas no jogo real (pt_BR): visão geral
## com as três áreas de cultura, cada área nova de perto (placa, canteiro,
## parcela de estoque e plataforma do ajudante) e as cercas com a arte de madeira.
## Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/crop_areas_capture.gd -- <pasta absoluta>

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/crop-areas-001")
    DirAccess.make_dir_recursive_absolute(out_dir)
    TranslationServer.set_locale("pt_BR")
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    # As pilhas das áreas novas ficam vazias: ainda não há arte de caixa de
    # milho/abóbora (crate_full.png mostra tomates).
    await create_timer(0.4).timeout
    world.hud.visible = false
    await _view(world, Vector3(0.0, 0.0, -2.0), 60.0, 3.0, out_dir, "01-visao-geral-tres-areas")
    world.hud.visible = true
    for entry in world.crop_areas:
        var field: Rect2 = entry["field"]
        var pad: Rect2 = entry["pad_rect"]
        var focus := Vector3((field.position.x + pad.end.x) * 0.5, 0.0, (field.position.y + pad.end.y) * 0.5)
        await _view(world, focus, 17.0, 1.0, out_dir, "02-area-%s" % String(entry["crop"]))
    var fence := world.get_node("Fence") as Node3D
    await _view(world, Vector3(fence.position.x, 0.0, fence.position.z), 9.0, 1.0, out_dir, "03-cerca-de-madeira")
    var counter := world.sales_counter
    await _view(world, counter.position + Vector3(-12.0, 0.0, -1.0), 12.0, 1.0, out_dir, "04-cerca-do-balcao")
    quit()

func _view(world: FarmWorld, focus: Vector3, size: float, distance_factor: float, out_dir: String, file: String) -> void:
    world.camera.size = size
    world.camera.far = 400.0
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance) * distance_factor
    world.camera.look_at(focus, Vector3.UP)
    for frame in 6:
        await process_frame
    var image := root.get_texture().get_image()
    image.save_png(out_dir.path_join(file + ".png"))
    print("CAPTURE ", out_dir.path_join(file + ".png"))
