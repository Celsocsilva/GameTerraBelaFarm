extends SceneTree
## FV-WOOD-001 — capturas no jogo real (pt_BR): eucaliptos nas bordas e junto
## ao rio, as 4 estações, o corte (toco + toras voando), o fardo na mochila e
## a madeira à venda no balcão.
## Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/wood_capture.gd -- <pasta absoluta>

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/wood-001")
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
    var grove := world.eucalyptus_grove
    await create_timer(0.4).timeout
    world.hud.visible = false
    await _view(world, Vector3(4.0, 0.0, -9.0), 62.0, 3.0, out_dir, "01-visao-geral-eucaliptos-%s" % grove.season)
    var edge := Vector3(-8.0, 0.0, -1.0)
    for season in SeasonClock.ALL:
        grove.set_forced_season(String(season))
        await _view(world, edge, 16.0, 1.0, out_dir, "02-estacao-%s" % season)
    grove.set_forced_season("")
    world.hud.visible = true
    world.hud.info_banner.hide_message()
    # Corte (FV-WOOD-002): o machado e os estágios da queda, uma captura por estágio.
    var tree: EucalyptusTree = grove.trees[7]
    var stand := tree.global_position + Vector3(1.1, 0.0, 0.5)
    world.farmer.global_position = Vector3(stand.x, world.farmer.global_position.y, stand.z)
    var focus := tree.global_position + Vector3(0.6, 0.0, 0.3)
    var shots := 0
    var last: Texture2D = tree.get_current_texture()
    await _view(world, focus, 8.0, 1.0, out_dir, "03-queda-1-inteira")
    var t := 0.0
    while tree.state != EucalyptusTree.STUMP and t < 6.0:
        grove.process_farmer_position(world.farmer.global_position, 0.02)
        t += 0.02
        if tree.get_current_texture() != last:
            last = tree.get_current_texture()
            shots += 1
            await _view(world, focus, 8.0, 1.0, out_dir, "03-queda-%d-%s" % [shots + 1, String(tree.state) + ("-%d" % tree.cut_stage if tree.state == EucalyptusTree.CHOPPING else "")])
    grove.finish_flights()
    # Segunda árvore: fardo cheio de 8 toras nas costas.
    var other: EucalyptusTree = grove.trees[4]
    world.farmer.global_position = Vector3(other.global_position.x + 0.9, world.farmer.global_position.y, other.global_position.z + 0.5)
    t = 0.0
    while other.state != EucalyptusTree.STUMP and t < 3.0:
        grove.process_farmer_position(world.farmer.global_position, 0.05)
        t += 0.05
    grove.finish_flights()
    world.farmer.global_position = Vector3(-5.5, world.farmer.global_position.y, 10.5)
    await _view(world, Vector3(-6.0, 0.0, 6.5), 11.0, 1.0, out_dir, "04-fazendeiro-com-fardo-de-toras")
    # Balcão: tomates e madeira à venda, cada um na sua pilha.
    world.sales_counter.set_stored_total(24)
    world.farmer.global_position = Vector3(-4.2, world.farmer.global_position.y, world.sales_counter.position.z - 2.6)
    world.sales_counter.deposit_from(world.harvest_inventory, world.get_farmer_hands_position())
    world.sales_counter.finish_jumps()
    world.harvest_inventory.set_amount(WoodConfig.ITEM, 0)
    await _view(world, world.sales_counter.position + Vector3(0.0, 0.0, -1.0), 13.0, 1.0, out_dir, "05-balcao-madeira-e-tomate")
    # Floresta do canto sudoeste e as pontes novas.
    world.hud.visible = false
    await _view(world, Vector3(-21.0, 0.0, 19.0), 24.0, 1.6, out_dir, "06-floresta-canto-sudoeste")
    await _view(world, Vector3(-15.0, 0.0, -9.6), 12.0, 1.0, out_dir, "07-ponte-de-madeira")
    await _view(world, Vector3(-14.2, 0.0, 1.6), 10.0, 1.0, out_dir, "08-ponte-de-pedra")
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
