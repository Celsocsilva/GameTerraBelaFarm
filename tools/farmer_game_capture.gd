extends SceneTree
## FARMER-GAME-001 — fazendeiro 3D jogando de verdade (precisa de janela; não use --headless):
##   godot --path . --resolution 1280x720 -s tools/farmer_game_capture.gd -- <pasta absoluta>
## O fazendeiro anda com Input.action_press (mesmo caminho do teclado/joystick). Cada contexto salva a
## vista da câmera do jogo e um close (mesma câmera, zoom ortográfico menor).

const CLOSE_SIZE := 6.5

var out_dir := ""
var world: FarmWorld
var log_lines: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var args := OS.get_cmdline_user_args()
    out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/farmer-game-001")
    DirAccess.make_dir_recursive_absolute(out_dir)
    TranslationServer.set_locale("pt_BR")
    await _ctx_walk_path()
    await _ctx_sow()
    await _ctx_harvest()
    await _ctx_backpack_to_counter()
    await _ctx_cow_pen()
    var f := FileAccess.open(out_dir.path_join("capture_log.txt"), FileAccess.WRITE)
    f.store_string("\n".join(log_lines))
    print("FARMER_GAME_CAPTURE_OK ", out_dir)
    quit(0)


func _load_world(all_ripe := false) -> void:
    if world:
        world.queue_free()
        await process_frame
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    if all_ripe:
        for cell_id in world.planting_grid.cells:
            world.spawn_crop_at_stage(cell_id, CropPlant.STAGES.size() - 1)
    world.customer_queue.set_process(false)


func _anim() -> FarmerAnimator:
    return world.farmer.animator


func _state() -> String:
    var a := _anim()
    return "loco=%s action=%s busy=%s speed=%.2f" % [a.loco_state, a.last_action, a.is_busy(), world.farmer.get_horizontal_speed()]


func _hold(action: String, seconds: float) -> void:
    Input.action_press(action)
    await create_timer(seconds).timeout


func _release_all() -> void:
    for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
        Input.action_release(a)


func _shot(name: String) -> void:
    await process_frame
    _save(name + "-camera-jogo")
    # close: mesma câmera ortográfica, centrada no fazendeiro, sem HUD
    var cam := world.camera
    var old_size := cam.size
    var old_xf := cam.global_transform
    world.set_process(false)
    world.hud.visible = false
    var p := world.farmer.global_position
    cam.size = CLOSE_SIZE
    cam.global_position = p + Vector3(0.0, world.camera_height, world.camera_distance)
    cam.look_at(p + Vector3(0.0, 1.2, 0.0), Vector3.UP)
    await process_frame
    await process_frame
    _save(name + "-close")
    # 3/4 baixo: mostra rosto/postura
    cam.size = 4.2
    cam.global_position = p + Vector3(4.0, 3.2, 6.0)
    cam.look_at(p + Vector3(0.0, 1.2, 0.0), Vector3.UP)
    await process_frame
    await process_frame
    _save(name + "-34")
    cam.size = old_size
    cam.global_transform = old_xf
    world.hud.visible = true
    world.set_process(true)
    log_lines.append("%s: %s" % [name, _state()])

func _save(name: String) -> void:
    var img := root.get_texture().get_image()
    var path := out_dir.path_join(name + ".png")
    img.save_png(path)
    print("CAPTURA ", path)


## 1. Correndo pelo caminho de terra, mochila vazia.
func _ctx_walk_path() -> void:
    await _load_world()
    world.farmer.global_position = Vector3(-4.0, 0.0, world.FARMER_SPAWN.z)
    await create_timer(0.5).timeout
    await _hold("ui_left", 1.1)
    await _shot("01-correndo-no-caminho")
    _release_all()
    await create_timer(0.8).timeout
    await _shot("01b-parado-idle")


## 2. Semeando: entra no canteiro de tomate vazio e semeia a cada passo (gesto de lançar no tronco).
func _ctx_sow() -> void:
    await _load_world()
    var sown := [0, -1]
    for grid in [world.planting_grid]:
        (grid as PlantingGrid).cell_planted.connect(func(_c: String) -> void:
            sown[0] += 1
            if sown[1] < 0:
                sown[1] = Time.get_ticks_msec())
    world.farmer.global_position = world.FARMER_SPAWN
    await create_timer(0.4).timeout
    Input.action_press("ui_down")
    var t := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t < 4000:
        await process_frame
        if sown[1] > 0 and Time.get_ticks_msec() - sown[1] > 350 and _anim().is_busy():
            break
    await _shot("02-semeando-no-canteiro")
    _release_all()
    log_lines.append("02: covas semeadas=%d" % sown[0])


## 3. Colhendo: canteiro maduro, o fazendeiro atravessa as fileiras e colhe (abaixa e pega).
func _ctx_harvest() -> void:
    await _load_world(true)
    world.harvest_controller.enabled = false
    var ids: Array = world.planting_grid.cells.keys()
    var near: String = ids[0]
    for id in ids:
        if world.planting_grid.get_cell_world_position(id).distance_to(world.FARMER_SPAWN) < world.planting_grid.get_cell_world_position(near).distance_to(world.FARMER_SPAWN):
            near = id
    world.farmer.global_position = world.planting_grid.get_cell_world_position(near) + Vector3(0.0, 0.0, 1.2)
    await create_timer(0.6).timeout
    world.harvest_controller.enabled = true
    var started := [-1]
    world.harvest_controller.harvest_started.connect(func(_c: String, _u: int) -> void:
        if started[0] < 0:
            started[0] = Time.get_ticks_msec())
    Input.action_press("ui_up")
    var t := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t < 5000:
        await process_frame
        if started[0] > 0 and Time.get_ticks_msec() - started[0] > 250:
            break
    Input.action_release("ui_up")
    await create_timer(0.05).timeout
    await _shot("03-colhendo-tomates")
    _release_all()
    # parado no meio do canteiro: colheita de corpo inteiro
    await create_timer(1.0).timeout
    _anim().play_harvest()
    await create_timer(0.35).timeout
    await _shot("03b-colhendo-parado")
    log_lines.append("03: tomates na mochila=%d" % world.harvest_inventory.get_total())


## 4. Mochila cheia de caixas indo ao balcão e entregando.
func _ctx_backpack_to_counter() -> void:
    await _load_world()
    world.harvest_inventory.set_amount(&"tomato", 40)
    var counter := world.sales_counter.global_position
    world.farmer.global_position = Vector3(counter.x + 1.5, 0.0, counter.z - 9.0)
    await create_timer(0.6).timeout
    var delivered := [-1]
    world.sales_counter.deposited.connect(func(_u: int, _t: int) -> void:
        if delivered[0] < 0:
            delivered[0] = Time.get_ticks_msec())
    Input.action_press("ui_down")
    await create_timer(0.9).timeout
    await _shot("04-mochila-indo-ao-balcao")
    var t := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t < 6000:
        await process_frame
        if delivered[0] > 0 and Time.get_ticks_msec() - delivered[0] > 200:
            break
    _release_all()
    await _shot("04b-entregando-no-balcao")
    log_lines.append("04: entregue=%s mochila=%d" % [delivered[0] > 0, world.harvest_inventory.get_total()])


## 5. Perto do curral, andando devagar com milho na mochila.
func _ctx_cow_pen() -> void:
    await _load_world()
    var pen: Rect2 = world.cow_pen.rect
    world.harvest_inventory.set_amount(&"corn", 16)
    world.farmer.global_position = Vector3(pen.get_center().x + 1.0, 0.0, pen.end.y + 3.0)
    await create_timer(0.6).timeout
    await _hold("ui_right", 0.9)
    await _shot("05-curral-com-milho")
    _release_all()
