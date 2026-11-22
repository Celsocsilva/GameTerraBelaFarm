extends SceneTree
## FARM-005 (10/11) — capturas do terreno inteiro e das áreas de cultivo.
##   godot --path . --resolution 1600x1200 -s tools/layout_capture.gd -- <pasta absoluta>

var world: FarmWorld
var out_dir := ""

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/farm-005")
    DirAccess.make_dir_recursive_absolute(out_dir)
    TranslationServer.set_locale("pt_BR")
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    for child in world.get_children():
        if child is CanvasLayer:
            (child as CanvasLayer).visible = false
    await create_timer(0.3).timeout
    var map := world.get_map_rect()
    await _view(Vector3(map.get_center().x, 0.0, map.get_center().y), map.size.y * 0.78, "01-mapa-inteiro")
    var index := 2
    for crop in [&"tomato", &"corn", &"pumpkin"]:
        var r: Rect2 = world.get_planting_area_rect() if crop == &"tomato" else world.get_crop_area(crop).get("field", Rect2())
        if r.has_area():
            await _view(Vector3(r.get_center().x, 0.0, r.get_center().y), maxf(r.size.y, r.size.x * 0.75) + 10.0, "%02d-area-%s" % [index, crop])
            index += 1
    # Construções e caminhos de perto.
    for spec in FarmWorld.BUILDINGS:
        var base: Vector2 = spec[2]
        await _view(Vector3(base.x, 0.0, base.y - 2.5), 20.0, "%02d-construcao-%s" % [index, String(spec[0]).to_lower()])
        index += 1
    await _view(Vector3(-22.0, 0.0, -3.0), 26.0, "%02d-casa-galinheiro-caminhos" % index)
    index += 1
    await _view(Vector3(-12.0, 0.0, -32.0), 26.0, "%02d-curral-leite-caminhos" % index)
    quit()

func _view(focus: Vector3, size: float, file: String) -> void:
    world.camera.size = size
    world.camera.far = 600.0
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance).normalized() * 200.0
    world.camera.look_at(focus, Vector3.UP)
    for frame in 3:
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    image.save_png(out_dir.path_join(file + ".png"))
    print("CAPTURE ", out_dir.path_join(file + ".png"))
