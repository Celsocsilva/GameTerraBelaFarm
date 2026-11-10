extends SceneTree
## FV-POLISH-001 — capturas no jogo real (pt_BR): visão geral do mapa, caixas
## do fazendeiro x balcão, pilha 3x3 dos ajudantes, props ampliados, áreas de
## milho/abóbora e pinheiros. Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/polish_capture.gd -- <pasta absoluta>

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/fv-polish-001")
    var prefix := args[1] if args.size() > 1 else ""
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
    await create_timer(0.4).timeout
    # 1. Visão geral do mapa inteiro.
    await _view(world, Vector3(0.0, 0.0, 0.0), 70.0, out_dir, prefix + "01-visao-geral")
    await _view(world, Vector3(0.0, 0.0, -16.0), 40.0, out_dir, prefix + "02-fundos-norte")
    await _view(world, Vector3(18.0, 0.0, 0.0), 40.0, out_dir, prefix + "03-lado-leste")
    # 4. Fazendeiro com tomates na frente do balcão com tomates.
    var counter := world.sales_counter
    counter.set_item_total(&"tomato", 24)
    counter.set_item_total(&"corn", 16)
    counter.finish_jumps()
    world.harvest_inventory.set_amount(&"tomato", 28)
    world.farmer.global_position = counter.position + Vector3(-1.0, 1.0, -4.2)
    await create_timer(0.3).timeout
    await _view(world, counter.position + Vector3(0.0, 0.0, -2.5), 12.0, out_dir, prefix + "04-caixas-fazendeiro-e-balcao")
    world.harvest_inventory.set_amount(&"tomato", 0)
    # 5. Pilha dos ajudantes (tomate e milho).
    world.tomato_pile.set_stored_total(8 * 14)
    var corn := world.get_crop_area(&"corn")
    (corn["pile"] as TomatoPile).set_stored_total(8 * 7)
    world.tomato_pile.finish_jumps() if world.tomato_pile.has_method("finish_jumps") else null
    await create_timer(0.3).timeout
    var r := world.get_extra_plot_rect()
    await _view(world, Vector3(r.get_center().x, 0.0, r.get_center().y), 10.0, out_dir, prefix + "05-pilha-ajudante-tomate")
    var s: Rect2 = corn["stock"]
    await _view(world, Vector3(s.get_center().x, 0.0, s.get_center().y), 10.0, out_dir, prefix + "06-pilha-ajudante-milho")
    # 7. Props perto do fazendeiro.
    world.farmer.global_position = Vector3(0.0, 1.0, world.PLANTING_NEAR_EDGE_Z - 2.0)
    await _view(world, world.farmer.global_position, 16.0, out_dir, prefix + "07-props-e-fazendeiro")
    # 8. Áreas de cultivo lado a lado.
    await _view(world, Vector3(6.0, 0.0, -10.0), 46.0, out_dir, prefix + "08-areas-de-cultivo")
    quit()

func _view(world: FarmWorld, focus: Vector3, size: float, out_dir: String, file: String) -> void:
    world.camera.size = size
    world.camera.far = 400.0
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    for frame in 8:
        await process_frame
    var image := root.get_texture().get_image()
    image.save_png(out_dir.path_join(file + ".png"))
    print("CAPTURE ", out_dir.path_join(file + ".png"))
