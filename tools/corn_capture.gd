extends SceneTree
## CROP-CORN-001 — capturas no jogo real (pt_BR): milharal com os 4 estágios,
## milharal maduro com o ajudante, fazendeiro com caixas de milho e o balcão
## com milho, tomate e madeira. Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/corn_capture.gd -- <pasta absoluta>

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/corn-001")
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
    var grid := world.get_crop_grid(&"corn")
    var entry := world.get_crop_area(&"corn")
    var field: Rect2 = entry["field"]
    # 1. Um estágio por faixa de fileiras: broto (trás) -> maduro (frente).
    for cell in grid.cells.values():
        var stage := clampi(int(cell["row"]) * CropPlant.STAGES.size() / FarmWorld.CROP_AREA_ROWS, 0, CropPlant.STAGES.size() - 1)
        world.spawn_crop_at_stage(cell["id"], stage)
    world.farmer.global_position = Vector3(field.end.x + 1.2, 1.0, field.end.y + 1.0)
    await create_timer(0.5).timeout
    await _view(world, Vector3(field.get_center().x, 0.0, field.get_center().y), 13.0, out_dir, "01-milharal-quatro-estagios")
    # 2. Tudo maduro, ajudante contratado e pilha de milho na parcela.
    for cell in grid.cells.values():
        if world.crops.has(cell["id"]):
            (world.crops[cell["id"]] as CropPlant).queue_free()
            world.crops.erase(cell["id"])
        cell["state"] = "EMPTY"
        world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
    (entry["hiring"] as HelperHiring).set_grade(1)
    (entry["pile"] as TomatoPile).set_stored_total(24)
    await create_timer(0.4).timeout
    var pad: Rect2 = entry["pad_rect"]
    var focus := Vector3((field.position.x + pad.end.x) * 0.5, 0.0, (field.position.y + pad.end.y) * 0.5)
    await _view(world, focus, 17.0, out_dir, "02-milharal-maduro-pilha-e-plataforma")
    # 3. Fazendeiro com a mochila de milho.
    world.harvest_inventory.set_amount(&"corn", 40)
    world.farmer.global_position = Vector3(field.get_center().x, 1.0, field.end.y + 1.5)
    await create_timer(0.3).timeout
    await _view(world, world.farmer.global_position, 7.0, out_dir, "03-fazendeiro-com-caixas-de-milho")
    # 4. Balcão: milho (esquerda), tomate (meio) e madeira (direita).
    world.harvest_inventory.set_amount(&"corn", 0)
    var counter := world.sales_counter
    counter.set_item_total(&"corn", 24)
    counter.set_item_total(&"tomato", 16)
    counter.set_item_total(WoodConfig.ITEM, 16)
    counter.finish_jumps()
    world.farmer.global_position = counter.position + Vector3(-1.5, 1.0, -3.2)
    await create_timer(0.3).timeout
    await _view(world, counter.position + Vector3(0.0, 0.0, -1.0), 11.0, out_dir, "04-balcao-milho-tomate-madeira")
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
