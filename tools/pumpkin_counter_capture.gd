extends SceneTree
## PUMPKIN-STACK-001 — abóboras empilhadas no balcão ao lado das caixas de tomate.
## Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/pumpkin_counter_capture.gd -- <pasta absoluta>

var out_dir := "res://docs/evidence/pumpkin-stack-001"
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        out_dir = args[0]
    TranslationServer.set_locale("pt_BR")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_process(false)
    world.sales_controller.set_process(false)
    world.customer_queue.set_process(false)
    var counter := world.sales_counter
    var focus := counter.global_position
    for shot in [[3, 3], [5, 5], [10, 10]]:
        counter.set_stored_total(int(shot[0]) * counter.units_per_crate)
        counter.set_item_total(&"pumpkin", int(shot[1]))
        counter.finish_jumps()
        counter.get_extra_stack(&"pumpkin").finish_jumps()
        await _shot("balcao-tomate%d-abobora%d" % shot, focus, 12.0)
    quit()

func _shot(file_name: String, focus: Vector3, size: float) -> void:
    world.camera.size = size
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    await create_timer(0.4).timeout
    var image := root.get_viewport().get_texture().get_image()
    var path := out_dir.path_join(file_name + ".png")
    image.save_png(path)
    print("CAPTURE ", path)
