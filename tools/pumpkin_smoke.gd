extends SceneTree
## PUMPKIN-001 — ciclo completo, layout de 6 fileiras, destaque visual,
## colheita/venda e ajudante com custo de milho.

var _failures := 0
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures += 1
        push_error("PUMPKIN_SMOKE_FAIL: " + message)

func _run() -> void:
    _test_assets()
    await _load_world()
    _test_map_and_layout()
    await _test_stages_and_harvest()
    await _load_world()
    _test_helper_requirement_and_cycle()
    if world:
        world.queue_free()
        await process_frame
    if _failures > 0:
        print("PUMPKIN_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("PUMPKIN_SMOKE_OK")
    quit()

func _load_world() -> void:
    if world:
        world.queue_free()
        await process_frame
    TranslationServer.set_locale("pt_BR")
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.harvest_controller.enabled = false
    for controller in world.crop_harvesters.values():
        (controller as HarvestController).enabled = false
    world.sales_controller.set_process(false)
    world.customer_queue.set_process(false)
    world.farmer.global_position = Vector3(-20.0, 1.0, -20.0)

func _test_assets() -> void:
    var stages := CropCatalog.stage_assets(&"pumpkin")
    _check(stages.size() == 4, "abóbora precisa de quatro estágios")
    for path in stages:
        _check(ResourceLoader.exists(path), "asset ausente: " + String(path))
        var image := Image.load_from_file(ProjectSettings.globalize_path(path))
        _check(image != null and image.get_width() == 1254 and image.get_height() == 1254, "dimensão inesperada: " + String(path))
        if image:
            _check(image.get_pixel(0, 0).a < 0.01, "fundo não transparente: " + String(path))
    _check(ItemArt.full_texture(&"pumpkin").resource_path.ends_with("pumpkin_stage_04_ripe.png"), "arte da colheita de abóbora")
    print("PUMPKIN_ASSETS_OK stages=4 size=1254x1254")

func _test_map_and_layout() -> void:
    var map := world.get_map_rect()
    _check(map.size.is_equal_approx(Vector2(77.44, 77.44)), "segunda expansão deve resultar em 77,44 m")
    _check(map.position.is_equal_approx(Vector2(-32.0, -45.44)), "expansão deve ficar à direita e no topo")
    var corn: Rect2 = world.get_crop_area(&"corn")["field"]
    _check(is_equal_approx(corn.position.x, 13.2 + FarmWorld.MAP_LATEST_INCREMENT), "milho não avançou 7,04 m à direita")
    var entry := world.get_crop_area(&"pumpkin")
    var field: Rect2 = entry["field"]
    var grid := world.get_crop_grid(&"pumpkin")
    _check(grid != null, "sem grade de abóbora")
    if grid == null:
        return
    _check(grid.rows_per_module == 6, "abóbora deve ter no máximo 6 fileiras")
    # FARM-003: 2 peças do solo largo (3 sulcos cada) x 6 fileiras = 36 covas.
    var strips := int((entry["area"] as Node3D).get_meta("plot_count", FarmWorld.CROP_AREA_STRIPS))
    _check(strips == 2, "abóbora deve ter 2 peças de solo largo (tem %d)" % strips)
    _check(grid.cells.size() == strips * grid.columns * 6, "esperadas %d posições de abóbora" % (strips * grid.columns * 6))
    var rows := {}
    for cell in grid.cells.values():
        rows[int(cell["row"])] = true
        var p: Vector3 = cell["position"]
        _check(field.has_point(Vector2(p.x, p.z)), "cova fora do campo de abóbora")
    _check(rows.size() == 6, "quantidade real de fileiras: %d" % rows.size())
    _check(absf(field.position.y - (-31.05649)) < 0.01, "abóbora não subiu metade do campo")
    var sign := world.get_crop_sign(&"pumpkin")
    _check(sign != null and sign.position.x < field.position.x, "placa da abóbora deve ficar à esquerda do campo")
    _check(not (entry["pad"] as HelperPad).locked, "plataforma da abóbora ainda bloqueada")
    print("PUMPKIN_LAYOUT_OK cells=%d rows=%d field=%s sign_x=%.2f" % [grid.cells.size(), rows.size(), field, sign.position.x if sign else INF])

func _test_stages_and_harvest() -> void:
    var grid := world.get_crop_grid(&"pumpkin")
    var cell: Dictionary = grid.cells.values()[0]
    var crop := world.spawn_crop_at_stage(cell["id"], 0)
    var widths: Array[float] = []
    var heights: Array[float] = []
    for stage in CropPlant.STAGES.size():
        crop._update_stage(stage)
        var size := crop.get_visible_world_size()
        widths.append(size.x)
        heights.append(size.y)
        _check(crop.sprite.texture.resource_path == CropCatalog.stage_assets(&"pumpkin")[stage], "arte errada no estágio %d" % stage)
    _check(widths[3] >= 2.3, "abóbora madura sem destaque: %.2f m" % widths[3])
    _check(widths[3] > world.planting_grid.cells.values()[0]["cell_width"], "abóbora não se destaca sobre a célula do tomate")
    _check(grid.cells[cell["id"]]["state"] == PlantingGrid.STATE_RIPE, "abóbora madura não ficou RIPE")
    var controller := world.crop_harvesters[&"pumpkin"] as HarvestController
    # O fazendeiro precisa estar perto do pé: longe (> cancel_distance) a
    # colheita é cancelada no primeiro quadro (era a falha antiga deste teste).
    var cell_pos: Vector3 = cell["position"]
    world.farmer.global_position = Vector3(cell_pos.x, 1.0, cell_pos.z + 1.5)
    _check(controller.item_id == &"pumpkin" and controller.request_collect(cell["id"]), "colheita da abóbora não iniciou")
    var elapsed := 0.0
    while controller.get_active_job_count() > 0 and elapsed < 2.0:
        await process_frame
        await create_timer(0.03).timeout
        elapsed += 0.03
    _check(controller.get_active_job_count() == 0, "colheita não terminou")
    _check(world.harvest_inventory.get_amount(&"pumpkin") == CropCatalog.yield_per_crop(&"pumpkin"), "abóbora não entrou na mochila")
    var carried := world.harvest_inventory.get_amount(&"pumpkin")
    _check(world.sales_counter.deposit_from(world.harvest_inventory, null) == carried, "balcão não recebeu abóbora")
    var stack := world.sales_counter.get_extra_stack(&"pumpkin")
    _check(stack != null and stack.get_stored_total() == carried, "pilha de abóbora no balcão")
    _check(world.sales_controller.price_per_crate_of(&"pumpkin") == 6, "preço da caixa de abóbora")
    print("PUMPKIN_STAGES_OK widths=%s heights=%s harvest=%d" % [widths, heights, carried])

func _test_helper_requirement_and_cycle() -> void:
    var entry := world.get_crop_area(&"pumpkin")
    var hiring := entry["hiring"] as HelperHiring
    var helper := entry["helper"] as FarmHelper
    var pad := entry["pad"] as HelperPad
    _check(hiring.requirement_item == &"corn" and hiring.requirement_crates == 20, "custo do ajudante da abóbora")
    world.wallet.add(100)
    _check(not hiring.try_buy(world.wallet), "contratou sem 20 caixas de milho")
    # HIRE-FIX-001: as 20 caixas de milho são descarregadas da mochila na plataforma.
    var inv := world.harvest_inventory
    var center := pad.rect.get_center()
    var delivered := 0
    for trip in 3:
        inv.set_amount(&"corn", mini(inv.get_capacity(), 20 * inv.units_per_crate - delivered))
        var before := inv.get_amount(&"corn")
        for frame in 400:
            pad.process_farmer_position(Vector3(center.x, 1.0, center.y), 1.0 / 30.0, inv)
            if hiring.is_hired() or inv.get_amount(&"corn") == 0:
                break
        delivered += before - inv.get_amount(&"corn")
        pad.process_farmer_position(Vector3(center.x + 20.0, 1.0, center.y), 1.0 / 30.0, inv)
    for frame in 60:
        pad.process_farmer_position(Vector3(center.x, 1.0, center.y), 1.0 / 30.0, inv)
        if hiring.is_hired():
            break
    _check(delivered == 20 * inv.units_per_crate, "caixas de milho descarregadas: %d" % delivered)
    _check(pad.material_log.size() == 20, "20 caixas voaram até a plataforma: %d" % pad.material_log.size())
    _check(hiring.is_hired() and helper.visible, "ajudante da abóbora não foi contratado")
    _check(world.wallet.get_balance() == 0 and inv.get_amount(&"corn") == 0, "contratação não consumiu 100 + 20 caixas de milho")
    var grid := world.get_crop_grid(&"pumpkin")
    var total := 0
    for cell in grid.cells.values():
        world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
        total += grid.get_remaining_yield(cell["id"])
    var pile := entry["pile"] as TomatoPile
    # O ajudante começa a replantar assim que a safra inteira é colhida, às
    # vezes antes da última entrega: o contador liga antes da colheita.
    # Lambdas do GDScript capturam variáveis locais por valor: o contador
    # precisa ser um Array (com int ele ficava sempre 0 — falha antiga).
    var replanted := [0]
    helper.planted.connect(func(_cell_id: String) -> void: replanted[0] += 1)
    for step in 1000:
        helper.step_instant()
        if pile.get_stored_total() == total:
            break
    _check(pile.get_stored_total() == total, "ajudante não colheu todas as abóboras: %d/%d" % [pile.get_stored_total(), total])
    for step in 80:
        helper.step_instant()
    _check(replanted[0] > 0, "ajudante não replantou a abóbora")
    print("PUMPKIN_HELPER_OK harvested=%d replanted=%d" % [total, replanted[0]])
