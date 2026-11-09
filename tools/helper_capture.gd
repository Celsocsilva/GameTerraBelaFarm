extends SceneTree
## FV-HELPER-001 — capturas do ajudante: plataforma no chão antes da parcela de
## 10%, pagamento dinheiro a dinheiro, ajudante colhendo/empilhando e recolha.
## Rodar SEM --headless:
##   godot --path . -s tools/helper_capture.gd -- <pasta de saída absoluta> [locale]

var out_dir := "res://docs/evidence/fv-helper-001"
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        out_dir = args[0]
    if args.size() > 1:
        TranslationServer.set_locale(args[1])
    else:
        TranslationServer.set_locale("pt_BR")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.harvest_controller.enabled = false
    world.sales_controller.set_process(false)
    world.customer_queue.set_process(false)
    for cell in world.planting_grid.cells.values():
        world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
    var pad := world.helper_pad
    var plot := world.get_extra_plot_rect()
    var pad_center := Vector3(pad.rect.get_center().x, 1.0, pad.rect.get_center().y)
    var area_focus := Vector3(plot.get_center().x - 2.0, 0.0, (plot.get_center().y + pad.rect.end.y) * 0.5)

    # 01: plataforma antes da parcela, ainda não contratado (preço 100).
    world.farmer.global_position = pad_center + Vector3(-3.2, 0.0, 0.6)
    world.farmer.rotation.y = deg_to_rad(-90.0)
    world.wallet.add(130, &"capture")
    await _shot("01-plataforma-antes-da-parcela", area_focus, 16.0)

    # 02: fazendeiro em cima da plataforma, saldo saindo dinheiro a dinheiro.
    world.farmer.global_position = pad_center
    await _drive_pad(pad_center, 1.25)
    await _shot("02-pagando-dinheiro-a-dinheiro", area_focus, 16.0, false)

    # 03: sai no meio: pausa e guarda o que pagou.
    world.farmer.global_position = pad_center + Vector3(-3.2, 0.0, 0.6)
    await _drive_pad(world.farmer.global_position, 0.8)
    await _shot("03-saiu-pausa-guarda-pago", area_focus, 16.0)

    # 04: volta e completa os 100: ajudante contratado, plataforma cobra o grau 2.
    world.farmer.global_position = pad_center
    while world.helper_hiring.grade == 0:
        await _drive_pad(pad_center, 0.1)
    world.farmer.global_position = pad_center + Vector3(-3.2, 0.0, 0.6)
    await create_timer(0.5).timeout
    await _shot("04-ajudante-contratado", area_focus, 16.0)

    # 05: ajudante colhendo e empilhando na parcela de 10% (acelerado até ~10 caixas).
    var helper := world.farm_helper
    world.helper_hiring.set_grade(3)
    while world.tomato_pile.get_crate_count() < 10:
        helper.step_instant()
    world.tomato_pile.finish_jumps()
    await create_timer(1.6).timeout
    await _shot("05-ajudante-colhe-e-empilha", Vector3(plot.position.x - 2.0, 0.0, plot.get_center().y), 18.0)

    # 06: fazendeiro recolhe as caixas da pilha para a mochila.
    helper.set_process(false)
    world.farmer.global_position = Vector3(plot.get_center().x, 1.0, plot.get_center().y + 1.2)
    world.farmer.rotation.y = 0.0
    var t := 0.0
    while t < 0.35:
        world.tomato_pile.process_farmer_position(world.farmer.global_position, world.harvest_inventory, world.backpack.intake_marker)
        await process_frame
        t += root.get_process_delta_time() if root.get_process_delta_time() > 0.0 else 0.016
    await _shot("06-fazendeiro-recolhe-da-pilha", Vector3(plot.get_center().x - 1.0, 0.0, plot.get_center().y), 16.0, false)

    # 07: visão de jogo (câmera padrão) com tudo junto.
    helper.set_process(true)
    await create_timer(1.0).timeout
    await _shot("07-visao-de-jogo", Vector3(plot.position.x - 3.0, 0.0, plot.get_center().y + 1.0), world.camera_orthographic_size)
    quit()

## Roda a cobrança da plataforma em tempo real (o FarmWorld está pausado).
func _drive_pad(farmer_pos: Vector3, seconds: float) -> void:
    var start := Time.get_ticks_msec()
    var last := start
    while Time.get_ticks_msec() - start < int(seconds * 1000.0):
        await process_frame
        var now := Time.get_ticks_msec()
        world.helper_pad.process_farmer_position(farmer_pos, float(now - last) / 1000.0)
        last = now

func _shot(file_name: String, focus: Vector3, size: float, settle: bool = true) -> void:
    world.camera.size = size
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    if settle:
        await create_timer(0.5).timeout
    else:
        await process_frame
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    var path := out_dir.path_join(file_name + ".png")
    image.save_png(path)
    print("CAPTURE ", path, " grade=", world.helper_hiring.grade, " paid=", world.helper_hiring.paid, " wallet=", world.wallet.get_balance(), " pile=", world.tomato_pile.get_stored_total())
