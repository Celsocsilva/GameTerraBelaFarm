extends SceneTree
## FV-PROPS-001 — capturas da banca de feira (balcão de vendas) e das placas de
## cultura nos terrenos. Rodar SEM --headless:
##   godot --path . -s tools/stall_signs_capture.gd -- <pasta de saída absoluta> [pt_BR|es|en]
## Mostra o balcão com caixas empilhadas, dinheiro na base ao lado e a fila de
## clientes, além do canteiro com a placa da cultura.

var out_dir := "res://docs/evidence/fv-props-001"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        out_dir = args[0]
    var locale := String(args[1]) if args.size() > 1 else "pt_BR"
    TranslationServer.set_locale(locale)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.harvest_controller.enabled = false
    world.sales_controller.set_process(false)
    world.customer_queue.set_process(false)
    # 18 caixas no balcão (12 na camada de baixo + 6 na segunda) e dinheiro na base.
    world.harvest_inventory.set_amount(&"tomato", 56)
    world.sales_counter.deposit_from(world.harvest_inventory)
    world.harvest_inventory.set_amount(&"tomato", 56)
    world.sales_counter.deposit_from(world.harvest_inventory)
    world.harvest_inventory.set_amount(&"tomato", 32)
    world.sales_counter.deposit_from(world.harvest_inventory)
    world.sales_counter.finish_jumps()
    world.money_stack.add_money(24)
    # Clientes chegando na fila (movimento em passos determinísticos).
    world.customer_queue.set_seed(7)
    for step in 400:
        world.customer_queue.tick(0.1)
    # Tomates maduros no sulco do meio, para ler a placa junto da cultura.
    for cell in world.planting_grid.cells.values():
        if int(cell["column"]) == 1:
            world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
    var counter := world.sales_counter.global_position
    var field := world.get_planting_area_rect()
    var views := [
        ["01-banca-caixas-dinheiro-%s" % locale, counter + Vector3(1.5, 0.0, -0.5), 16.0],
        ["02-banca-fila-clientes-%s" % locale, counter + Vector3(0.0, 0.0, 3.5), 22.0],
        ["03-placa-canteiro-%s" % locale, Vector3(field.position.x + 3.0, 0.0, field.end.y - 1.0), 12.0],
        ["04-canteiro-ate-banca-%s" % locale, Vector3(0.0, 0.0, (field.end.y + counter.z) * 0.5), 30.0],
    ]
    for view in views:
        var focus: Vector3 = view[1]
        world.camera.size = view[2]
        world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
        world.camera.look_at(focus, Vector3.UP)
        await create_timer(0.6).timeout
        var image := root.get_viewport().get_texture().get_image()
        var path := out_dir.path_join(String(view[0]) + ".png")
        image.save_png(path)
        print("CAPTURE ", path)
    # Prévia das 3 placas (milho e abóbora ainda não têm terreno no jogo): placas
    # extras só nesta captura, na grama abaixo do canteiro.
    var sign := world.get_crop_sign(&"tomato")
    if sign:
        var row := Vector3(field.position.x + 4.0, 0.0, field.end.y + 4.5)
        var crops := [&"tomato", &"corn", &"pumpkin"]
        for index in crops.size():
            var preview := CropSign.new()
            preview.name = "PreviewSign_%s" % crops[index]
            preview.crop_id = crops[index]
            preview.position = row + Vector3(index * 3.0, 0.0, 0.0)
            world.add_child(preview)
        var focus := row + Vector3(3.0, 0.0, -0.8)
        world.camera.size = 9.0
        world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
        world.camera.look_at(focus, Vector3.UP)
        (world.get_node("HUD") as CanvasLayer).visible = false
        await create_timer(0.6).timeout
        var path := out_dir.path_join("05-placas-tomate-milho-abobora-%s.png" % locale)
        root.get_viewport().get_texture().get_image().save_png(path)
        print("CAPTURE ", path)
    quit()
