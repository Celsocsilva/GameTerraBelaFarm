extends SceneTree
## FV-HUD-002 — capturas no jogo real (pt_BR): HUD novo (bloco translúcido de
## dinheiro + ouro, engrenagem acima da Loja), loja e configurações por cima de
## toda a UI (inclusive o joystick), base da pilha de dinheiro, props em dobro e
## árvores orgânicas. Rodar SEM --headless, uma vez por resolução:
##   godot --path . --resolution 1280x720 -s tools/hud002_capture.gd -- <pasta absoluta> [prefixo]

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/fv-hud-002")
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
    world.wallet.set_balance(1250)
    world.wallet.set_gold(35)
    await create_timer(0.4).timeout
    var portrait := root.get_visible_rect().size.y > root.get_visible_rect().size.x
    if not portrait:
        await _view(world, Vector3(0.0, 0.0, 0.0), 70.0, out_dir, prefix + "01-visao-geral-arvores")
        await _view(world, Vector3(0.0, 0.0, -24.0), 30.0, out_dir, prefix + "02-pinheiros-norte")
        await _view(world, Vector3(22.0, 0.0, 2.0), 30.0, out_dir, prefix + "03-pinheiros-leste")
        await _view(world, Vector3(-20.0, 0.0, 18.0), 30.0, out_dir, prefix + "04-floresta-sudoeste")
    # Base da pilha de dinheiro: vazia e com dinheiro.
    var money := world.money_stack
    await _view(world, money.global_position + Vector3(-2.0, 0.0, 0.3), 10.0, out_dir, prefix + "05-base-dinheiro-vazia")
    money.add_money(42)
    await _view(world, money.global_position + Vector3(-2.0, 0.0, 0.3), 10.0, out_dir, prefix + "06-base-dinheiro-com-macos")
    # Props em dobro perto do fazendeiro.
    var props := world.cozy_environment.get_node("FarmDecorations")
    var nearest: Node3D = null
    for child in props.get_children():
        var n := child as Node3D
        if n.name.begins_with("barrel") and (nearest == null or n.position.length() < nearest.position.length()):
            nearest = n
    if nearest:
        world.farmer.global_position = nearest.global_position + Vector3(-1.6, 1.0, 0.6)
        await _view(world, nearest.global_position, 12.0, out_dir, prefix + "07-barril-dobro-e-fazendeiro")
    world.farmer.global_position = Vector3(0.0, 1.0, world.PLANTING_NEAR_EDGE_Z - 2.0)
    await _view(world, world.farmer.global_position, 16.0, out_dir, prefix + "08-hud-novo")
    world.hud.store_button.pressed.emit()
    await _view(world, world.farmer.global_position, 16.0, out_dir, prefix + "09-loja-sobre-toda-ui")
    world.hud.shop_modal.close_shop()
    world.hud.settings_button.pressed.emit()
    await _view(world, world.farmer.global_position, 16.0, out_dir, prefix + "10-configuracoes")
    world.hud.settings_modal.choose_language("en")
    await _view(world, world.farmer.global_position, 16.0, out_dir, prefix + "11-configuracoes-en")
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
