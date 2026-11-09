extends SceneTree
## FV-FARM-008 — capturas do layout: canteiro de tomate a 3x a distância do
## balcão e parcela extra (10% da área). Rodar SEM --headless:
##   godot --path . -s tools/farm_layout_capture.gd -- <pasta de saída absoluta>

var out_dir := "res://docs/evidence/fv-farm-008"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        out_dir = args[0]
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.harvest_controller.enabled = false
    world.sales_controller.set_process(false)
    world.customer_queue.set_process(false)
    # Tomates maduros no sulco do meio de cada tira, para ler a escala do canteiro.
    for cell in world.planting_grid.cells.values():
        if int(cell["column"]) == 1:
            world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
    var field := world.get_planting_area_rect()
    var counter_z := world.sales_counter.position.z
    var views := [
        # Canteiro, parcela extra e balcão no mesmo quadro.
        ["01-canteiro-ate-balcao", Vector3(2.0, 0.0, (field.position.y + counter_z) * 0.5), 34.0],
        # Mapa inteiro: rio e pontes a oeste continuam livres.
        ["02-visao-geral-rio-pontes", Vector3(-6.0, 0.0, 0.0), 52.0],
        # Parcela extra ao lado do canteiro de tomate.
        ["03-parcela-extra", Vector3(world.get_extra_plot_rect().get_center().x - 3.0, 0.0, world.get_extra_plot_rect().get_center().y), 16.0],
        # Visão de jogo inicial (câmera padrão no ponto de nascimento).
        ["04-visao-de-jogo", world.farmer.global_position, world.camera_orthographic_size],
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
    quit()
