extends SceneTree
## FARM-004 (09/11) — capturas no jogo real. Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/farm004_capture.gd -- <pasta absoluta>
## Contratação com descarregamento de fardos, semeadura a lanço, cercas,
## ipês, casa, curral com vegetação, solo largo/fileiras orgânicas e mochila.

var world: FarmWorld
var out_dir := ""

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/farm-004")
    DirAccess.make_dir_recursive_absolute(out_dir)
    TranslationServer.set_locale("pt_BR")
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.farmer.set_physics_process(false)
    world.harvest_controller.enabled = false
    for controller in world.crop_harvesters.values():
        (controller as HarvestController).enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    world.wallet.set_balance(60)
    world.farmer.global_position = Vector3(-24.0, 1.0, -20.0)
    await _hiring()
    await _seeding()
    # Culturas maduras para mostrar solo largo, fileiras e o milho maior.
    var stage := 0
    for grid in [world.planting_grid, world.get_crop_grid(&"pumpkin"), world.get_crop_grid(&"corn")]:
        for cell_id in (grid as PlantingGrid).cells:
            if (grid as PlantingGrid).cells[cell_id]["state"] == "EMPTY":
                world.spawn_crop_at_stage(cell_id, 2 + (stage % 2) if grid == world.planting_grid else 3)
            stage += 1
    await create_timer(0.4).timeout
    world.farmer.global_position = Vector3(-24.0, 1.0, -20.0)
    await _view(Vector3(4.0, 0.0, -7.0), 80.0, "01-visao-geral")
    var corn: Rect2 = world.get_crop_area(&"corn")["field"]
    await _view(Vector3(corn.get_center().x, 0.0, corn.get_center().y + 1.0), 20.0, "08-milho-32-maior-solo-largo")
    var pumpkin: Rect2 = world.get_crop_area(&"pumpkin")["field"]
    await _view(Vector3(pumpkin.get_center().x, 0.0, pumpkin.get_center().y + 1.0), 22.0, "09-abobora-fileiras-organicas")
    var house := world.get_farmhouse_rect()
    await _view(Vector3(house.get_center().x + 6.0, 0.0, house.get_center().y - 2.0), 26.0, "05-casa-oeste-do-rio-entre-pontes")
    await _view(Vector3(house.get_center().x + 3.0, 0.0, house.get_center().y - 1.0), 18.0, "05b-casa-de-perto")
    var pen := world.cow_pen.rect
    await _view(Vector3(pen.get_center().x + 2.5, 0.0, pen.get_center().y + 0.5), 26.0, "06-curral-menor-com-pinheiros-e-arbustos")
    await _view(Vector3(world.FENCE_POSITION.x, 0.0, world.FENCE_POSITION.z), 12.0, "07a-cerca-organica-20-maior")
    await _view(Vector3(-16.0, 0.0, world.sales_counter.position.z), 16.0, "07b-cercas-do-balcao")
    var ipe := _find_ipe()
    if ipe:
        await _view(ipe.global_position, 14.0, "04-ipe-20-maior")
    # Mochila cheia de abóboras (sem listras/cintilação entre as caixas).
    world.harvest_inventory.set_amount(&"pumpkin", world.harvest_inventory.get_capacity() - 3)
    world.farmer.global_position = Vector3(-14.0, 1.0, 6.0)
    await _view(world.farmer.global_position + Vector3(0.0, 1.0, 0.0), 8.0, "10-mochila-abobora-sem-cintilacao")
    quit()

func _hiring() -> void:
    var pad := world.helper_pad
    var inv := world.harvest_inventory
    inv.set_amount(&"wood", inv.get_capacity())
    var center := pad.rect.get_center()
    var pos := Vector3(center.x, 1.0, center.y)
    world.farmer.global_position = pos
    # Paga e descarrega por ~1,1 s em quadros reais (as animações rodam).
    var t := 0.0
    while t < HelperPad.START_DELAY + 1.1:
        pad.process_farmer_position(pos, 1.0 / 60.0, inv)
        world.backpack._orient_crates()
        await process_frame
        t += 1.0 / 60.0
    await _view(pos + Vector3(0.0, 0.0, -0.5), 11.0, "02a-contratacao-descarregando-fardos")
    for frame in 60:
        pad.process_farmer_position(pos, 1.0 / 60.0, inv)
        await process_frame
    await create_timer(0.7).timeout
    await _view(pos + Vector3(0.0, 0.0, -0.5), 11.0, "02b-contratacao-contagem-7-de-20")
    world.farmer.global_position = Vector3(-24.0, 1.0, -20.0)

func _seeding() -> void:
    var grid := world.planting_grid
    var field := world.get_planting_area_rect()
    var pos := Vector3(field.get_center().x, 1.0, field.position.y + 0.8)
    world.farmer.global_position = pos
    grid.process_farmer_position(pos - Vector3(0.0, 0.0, 0.4), 0.0)
    grid.process_farmer_position(pos, 0.4)
    await create_timer(0.38).timeout
    await _view(pos + Vector3(0.0, 0.0, 3.0), 14.0, "03a-semeadura-a-lanco-no-ar")
    await create_timer(0.7).timeout
    await _view(pos + Vector3(0.0, 0.0, 3.0), 14.0, "03b-semeadura-graos-no-solo")

func _find_ipe() -> Node3D:
    for child in world.cozy_environment.get_node("Trees").get_children():
        if String(child.name).begins_with("tree_pink_blossom"):
            return child
    return null

func _view(focus: Vector3, size: float, file: String) -> void:
    world.camera.size = size
    world.camera.far = 400.0
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    for frame in 3:
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    image.save_png(out_dir.path_join(file + ".png"))
    print("CAPTURE ", out_dir.path_join(file + ".png"))
