extends SceneTree
## FARM-003 — capturas no jogo real. Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/farm003_capture.gd -- <pasta absoluta>
## Gera: visão geral, abóbora com solo largo, fileiras orgânicas, placas,
## casa do fazendeiro, curral (2 momentos), barris e o HUD em pt_BR/es/en.

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/farm-003")
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
    world.wallet.set_balance(1250)
    world.wallet.set_gold(35)
    # Plantas em estágios variados para mostrar o enfileiramento orgânico.
    var stage := 0
    for grid in [world.planting_grid, world.get_crop_grid(&"pumpkin"), world.get_crop_grid(&"corn")]:
        for cell_id in (grid as PlantingGrid).cells:
            world.spawn_crop_at_stage(cell_id, 2 + (stage % 2))
            stage += 1
    await create_timer(0.5).timeout
    world.farmer.global_position = Vector3(-24.0, 1.0, -20.0)
    await _view(world, Vector3(4.0, 0.0, -7.0), 80.0, out_dir, "01-visao-geral")
    var pumpkin: Rect2 = world.get_crop_area(&"pumpkin")["field"]
    await _view(world, Vector3(pumpkin.get_center().x + 1.5, 0.0, pumpkin.get_center().y + 1.0), 22.0, out_dir, "02-abobora-solo-largo")
    var tomato := world.get_planting_area_rect()
    await _view(world, Vector3(tomato.get_center().x, 0.0, tomato.get_center().y), 18.0, out_dir, "03-fileiras-organicas-tomate")
    await _view(world, Vector3(6.0, 0.0, -18.0), 34.0, out_dir, "04-placas-milho-abobora")
    var house := world.get_farmhouse_rect()
    await _view(world, Vector3(house.get_center().x + 2.0, 0.0, house.get_center().y), 20.0, out_dir, "05-casa-do-fazendeiro")
    var pen := world.cow_pen.rect
    var focus := Vector3(pen.get_center().x + 1.0, 0.0, pen.get_center().y + 1.5)
    await _view(world, focus, 20.0, out_dir, "06-curral-vacas")
    await create_timer(4.0).timeout
    await _view(world, focus, 20.0, out_dir, "07-curral-vacas-4s-depois")
    await _view(world, focus + Vector3(-3.0, 0.0, 0.0), 9.0, out_dir, "08-vacas-de-perto")
    var nearest: Node3D = null
    for child in world.cozy_environment.get_node("FarmDecorations").get_children():
        if String(child.name).begins_with("barrel"):
            nearest = child
    if nearest:
        world.farmer.global_position = nearest.global_position + Vector3(-1.6, 1.0, 0.6)
        await _view(world, nearest.global_position, 10.0, out_dir, "09-barril-20-menor-e-fazendeiro")
    world.farmer.global_position = Vector3(0.0, 1.0, world.PLANTING_NEAR_EDGE_Z - 2.0)
    world.harvest_inventory.set_amount(&"tomato", world.harvest_inventory.get_capacity())
    var popup := world.hud.show_sale_popup(24, 2)
    popup.lifetime = 60.0
    for locale in ["pt_BR", "es", "en"]:
        world.hud.settings_modal.choose_language(locale)
        await _view(world, world.farmer.global_position, 16.0, out_dir, "10-hud-%s" % locale)
        world.hud.settings_button.pressed.emit()
        await _view(world, world.farmer.global_position, 16.0, out_dir, "11-configuracoes-%s" % locale)
        world.hud.settings_modal.close_settings()
        world.hud.store_button.pressed.emit()
        await _view(world, world.farmer.global_position, 16.0, out_dir, "12-loja-%s" % locale)
        world.hud.shop_modal.close_shop()
    world.hud.settings_modal.choose_language("pt_BR")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(FarmSettings.PATH))
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
