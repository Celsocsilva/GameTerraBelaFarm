extends SceneTree
## HELPER-WORKER-001 — a trabalhadora rural 3D como ajudante do canteiro de tomates.
## Rodar SEM --headless (salva PNGs):
##   godot --path . --resolution 1280x720 -s tools/helper_worker_capture.gd -- <pasta absoluta>
## Ajudante contratada com o canteiro maduro; roda em tempo real e fotografa colhendo,
## levando a caixa, empilhando e replantando depois da safra toda colhida.

var out_dir := "res://docs/evidence/helper-worker-001"
var world: FarmWorld
var _shots := 0

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
    world.harvest_controller.enabled = false
    world.sales_controller.set_process(false)
    world.customer_queue.set_process(false)
    var cells := world.planting_grid.cells.values()
    for i in cells.size():
        world.spawn_crop_at_stage(cells[i]["id"], CropPlant.STAGES.size() - 1)
    var helper := world.farm_helper
    world.farmer.global_position = helper.get_idle_point() + Vector3(-6.0, 1.0, 3.0)
    world.helper_hiring.set_grade(5)
    var seen := {}
    var start := Time.get_ticks_msec()
    while Time.get_ticks_msec() - start < 60000:
        await process_frame
        var key := String(helper.state)
        if helper.state == FarmHelper.TO_PILE and helper.carried > 0:
            key = "TO_PILE_CARRY"
        if not seen.has(key) and key in ["HARVESTING", "TO_PILE_CARRY", "TO_HARVEST"]:
            await create_timer(0.35).timeout
            seen[key] = true
            await _shot("%02d-%s" % [_shots + 1, key.to_lower()], helper.global_position)
        if seen.size() >= 3:
            break
    # Termina a safra na hora e deixa a ajudante replantar em tempo real.
    var guard := 0
    while world.planting_grid.has_pending_crop() and guard < 4000:
        if helper.state == FarmHelper.WAIT_PILE or world.tomato_pile.get_free_capacity() <= 0:
            world.tomato_pile.take_units(world.tomato_pile.get_stored_total())   # o fazendeiro recolheu a pilha
        helper.step_instant()
        guard += 1
    print("SAFRA_COLHIDA pending=", world.planting_grid.has_pending_crop(), " can_sow=", world.planting_grid.can_sow())
    start = Time.get_ticks_msec()
    while Time.get_ticks_msec() - start < 20000 and helper.state != FarmHelper.PLANTING:
        await process_frame
    await create_timer(0.1).timeout
    await _shot("%02d-replantando" % (_shots + 1), helper.global_position)
    await create_timer(4.0).timeout
    await _shot("%02d-visao-de-jogo" % (_shots + 1), helper.global_position, world.camera_orthographic_size)
    var seeded := 0
    for cell in world.planting_grid.cells.values():
        if cell["state"] != "EMPTY":
            seeded += 1
    print("REPLANTED cells=", seeded, " helper_state=", helper.state, " anim=", helper.animator.loco_state if helper.animator else "none")
    quit()

func _shot(file_name: String, focus: Vector3, size: float = 9.0) -> void:
    _shots += 1
    world.camera.size = size
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    await process_frame
    await process_frame
    var image := root.get_viewport().get_texture().get_image()
    var path := out_dir.path_join(file_name + ".png")
    image.save_png(path)
    print("CAPTURE ", path, " state=", world.farm_helper.state, " carried=", world.farm_helper.carried)
