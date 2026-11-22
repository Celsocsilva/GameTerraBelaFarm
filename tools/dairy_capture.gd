extends SceneTree
## DAIRY-001/002 (10/11) — capturas no jogo real. Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/dairy_capture.gd -- <pasta absoluta>
## Área do leite (garrafas voando das vacas), recolha para a mochila, leite no
## balcão e compra de vacas (dinheiro + 20 caixas de milho da mochila).

var world: FarmWorld
var out_dir := ""

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/dairy-001")
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
    var milk := world.get_milk_area_rect()
    var pad := world.get_cow_shop_pad_rect()
    var pen := world.cow_pen.rect
    var house := world.get_milk_house_rect()
    # DAIRY-002: começa com 1 vaca; para a vista geral, 3 vacas compradas.
    for i in 3:
        world.cow_pen.add_cow()
    world.farmer.global_position = Vector3(milk.end.x + 2.0, 1.0, milk.end.y + 0.5)
    world.milk_station.pile.set_stored_total(10 * 8 + 3)
    world.feed_trough.pile.set_stored_total(5 * 8)
    await create_timer(0.5).timeout
    await _view(Vector3(pen.get_center().x + 2.0, 0.0, pen.get_center().y + 1.0), 26.0, "01-curral-casinha-cocho-leite-e-vacas")
    # Fazendeiro encosta na cerca com milho: as caixas voam para o cocho.
    var fpos := world.feed_trough.get_fence_point()
    world.farmer.global_position = fpos
    world.harvest_inventory.set_amount(&"corn", world.harvest_inventory.get_capacity())
    var t := 0.0
    while t < FeedTrough.START_DELAY + 0.5:
        world.feed_trough.process_farmer_position(fpos, 1.0 / 60.0, world.harvest_inventory, world.backpack.intake_marker.global_position)
        world.backpack._orient_crates()
        await process_frame
        t += 1.0 / 60.0
    await _view(Vector3(fpos.x + 1.0, 0.0, pen.end.y), 12.0, "02-milho-encostando-na-cerca")
    for frame in 60:
        world.feed_trough.process_farmer_position(fpos, 1.0 / 60.0, world.harvest_inventory, world.backpack.intake_marker.global_position)
        await process_frame
    world.feed_trough.pile.finish_jumps()
    # Vacas comendo: espiga voa do cocho até a vaca, garrafa voa da vaca até a área do leite.
    world.farmer.global_position = Vector3(milk.end.x + 2.0, 1.0, milk.end.y + 0.5)
    for cow in world.cow_pen.cows:
        world.milk_station._timers[cow] = 0.05 + 0.25 * float(world.cow_pen.cows.find(cow))
    t = 0.0
    while world.milk_station._cob_flyers.is_empty() and t < 5.0:
        await process_frame
        t += 1.0 / 60.0
    await create_timer(0.2).timeout
    await _view(Vector3(pen.get_center().x + 2.0, 0.0, pen.get_center().y + 1.0), 18.0, "03a-vaca-comendo-milho")
    t = 0.0
    while world.milk_station.get_flying_bottle_count() == 0 and t < 5.0:
        await process_frame
        t += 1.0 / 60.0
    await create_timer(0.25).timeout
    await _view(Vector3(milk.get_center().x - 3.0, 0.0, milk.get_center().y + 1.0), 14.0, "03b-garrafa-voando-para-o-leite")
    # Fazendeiro recolhe o leite para a mochila.
    var pos := Vector3(milk.get_center().x, 1.0, milk.get_center().y + 0.3)
    world.farmer.global_position = pos
    for frame in 40:
        world.milk_station.pile.process_farmer_position(pos, world.harvest_inventory, world.backpack.intake_marker)
        world.backpack._orient_crates()
        await process_frame
    await _view(pos + Vector3(0.0, 0.0, -0.8), 11.0, "04-fazendeiro-recolhe-leite")
    # Leite no balcão (5 vagas: milho, tomate, abóbora, leite, madeira).
    world.harvest_inventory.set_amount(&"milk", 0)
    world.sales_counter.set_item_total(&"milk", 3 * 8)
    world.sales_counter.set_item_total(&"corn", 2 * 8)
    world.sales_counter.set_item_total(&"tomato", 3 * 8)
    world.sales_counter.set_item_total(&"wood", 2 * 8)
    world.farmer.global_position = world.sales_counter.position + Vector3(0.0, 1.0, -3.0)
    await _view(world.sales_counter.position + Vector3(0.0, 0.0, -0.5), 14.0, "05-leite-no-balcao")
    # Compra de vaca: dinheiro + milho descarregado da mochila.
    world.wallet.set_balance(260)
    world.harvest_inventory.set_amount(&"corn", world.harvest_inventory.get_capacity())
    world.cow_shop.material_units = 13 * 8
    world.cow_shop_pad._refresh()
    var center := world.cow_shop_pad.rect.get_center()
    pos = Vector3(center.x, 1.0, center.y)
    world.farmer.global_position = pos
    t = 0.0
    var target_cows := world.cow_pen.get_cow_count() + 1
    while t < HelperPad.START_DELAY + 0.75:
        world.cow_shop_pad.process_farmer_position(pos, 1.0 / 60.0, world.harvest_inventory)
        world.backpack._orient_crates()
        await process_frame
        t += 1.0 / 60.0
    await _view(pos + Vector3(0.0, 0.0, -0.8), 11.0, "06-placa-vacas-descarregando-milho")
    while world.cow_pen.get_cow_count() < target_cows and t < 30.0:
        world.cow_shop_pad.process_farmer_position(pos, 1.0 / 60.0, world.harvest_inventory)
        await process_frame
        t += 1.0 / 60.0
    world.farmer.global_position = pos + Vector3(0.0, 0.0, 3.5)
    await create_timer(0.3).timeout
    await _view(Vector3(pen.get_center().x + 1.5, 0.0, pen.get_center().y + 2.0), 22.0, "07-vaca-comprada")
    for locale in ["en", "es"]:
        TranslationServer.set_locale(locale)
        await create_timer(0.2).timeout
        await _view(Vector3(pad.get_center().x + 2.2, 0.0, pad.get_center().y), 11.0, "08-placas-%s" % locale)
    # MAP-003: mapa ampliado com a floresta nova nas bordas.
    TranslationServer.set_locale("pt_BR")
    var map := world.get_map_rect()
    await _view(Vector3(map.get_center().x, 0.0, map.get_center().y), 100.0, "09-mapa-ampliado-visao-geral")
    await _view(Vector3(map.position.x + 12.0, 0.0, -8.0), 34.0, "10-faixa-oeste-rio-e-arvores")
    await _view(Vector3(map.get_center().x, 0.0, map.position.y + 10.0), 40.0, "11-faixa-do-topo-arvores")
    await _view(Vector3(map.end.x - 12.0, 0.0, -10.0), 34.0, "12-faixa-leste-arvores")
    quit()

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
