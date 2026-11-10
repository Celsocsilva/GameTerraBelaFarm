extends SceneTree
## Testes headless de CROP-CORN-001: plantio, 4 estágios, colheita, mochila,
## pilha, ajudante e venda do milho no balcão (código de saída 1 em falha).
## Uso: Godot --headless --path . -s tools/corn_smoke.gd

var _failures := 0
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures += 1
        push_error("CORN_SMOKE_FAIL: " + message)

func _run() -> void:
    _test_catalog()
    await _load_world()
    _test_layout()
    await _test_planting_and_stages()
    await _test_farmer_harvest_and_sale()
    await _load_world()
    await _test_backpack_one_product()
    _test_backpack_motion_stability()
    await _load_world()
    await _test_helper()
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("CORN_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("CORN_SMOKE_OK")
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
    world.sales_controller.set_process(false)
    world.customer_queue.set_process(false)
    world.farmer.global_position = Vector3(-20.0, 1.0, -20.0)
    await process_frame

func _corn_grid() -> PlantingGrid:
    return world.get_crop_grid(&"corn")

func _test_catalog() -> void:
    var stages := CropCatalog.stage_assets(&"corn")
    _check(stages.size() == CropPlant.STAGES.size(), "milho deve ter %d estágios" % CropPlant.STAGES.size())
    for path in stages:
        _check(String(path).begins_with("res://assets/crops/corn/stages/") and ResourceLoader.exists(path), "arte do estágio ausente: " + str(path))
    var heights := CropCatalog.stage_heights(&"corn")
    for i in range(1, heights.size()):
        _check(heights[i] > heights[i - 1], "alturas do milho devem crescer")
    _check(ItemArt.full_texture(&"corn").resource_path == "res://assets/harvest/crate_corn_full.png", "caixa cheia de milho")
    _check(ItemArt.full_texture(&"tomato").resource_path == "res://assets/harvest/crate_full.png", "caixa de tomate mudou")
    print("CORN_CATALOG_OK stages=", stages.size())

func _test_layout() -> void:
    var grid := _corn_grid()
    _check(grid != null, "sem PlantingGrid de milho")
    if grid == null:
        return
    var entry := world.get_crop_area(&"corn")
    var field: Rect2 = entry["field"]
    _check(grid.cells.size() == FarmWorld.CROP_AREA_STRIPS * grid.columns * FarmWorld.CROP_AREA_ROWS, "covas de milho: %d" % grid.cells.size())
    for cell in grid.cells.values():
        var p: Vector3 = cell["position"]
        _check(field.has_point(Vector2(p.x, p.z)), "cova de milho fora do canteiro")
        _check(not world.planting_grid.cells.has(cell["id"]), "id de cova repetido com o tomate")
    _check(not (entry["pad"] as HelperPad).locked, "plataforma do milho ainda bloqueada")
    _check(not (world.get_crop_area(&"pumpkin")["pad"] as HelperPad).locked, "abóbora plantável não deveria estar bloqueada")
    _check(world.crop_harvesters.has(&"corn") and (world.crop_harvesters[&"corn"] as HarvestController).item_id == &"corn", "colheita do milho")
    print("CORN_LAYOUT_OK cells=", grid.cells.size())

func _test_planting_and_stages() -> void:
    var grid := _corn_grid()
    var cell: Dictionary = grid.cells.values()[0]
    # Fazendeiro andando sobre o milharal semeia como no tomate.
    var p: Vector3 = cell["position"]
    var before := grid.get_planting_progress()["planted"] as int
    for frame in 30:
        world.farmer.global_position = Vector3(p.x, 1.0, p.z + float(frame) * 0.05)
        grid.process_farmer_position(world.farmer.global_position, 0.05)
    _check(int(grid.get_planting_progress()["planted"]) > before, "andar no milharal não semeou")
    await create_timer(1.2).timeout
    var crop: CropPlant = world.crops.get(cell["id"])
    _check(crop != null and crop.crop_id == &"corn", "broto de milho não nasceu")
    if crop:
        _check(crop.sprite.texture.resource_path == CropCatalog.stage_assets(&"corn")[0], "broto com a arte errada")
        var heights: Array[float] = []
        for stage in CropPlant.STAGES.size():
            crop._update_stage(stage)
            _check(crop.sprite.texture.resource_path == CropCatalog.stage_assets(&"corn")[stage], "estágio %d com a arte errada" % stage)
            heights.append(crop.get_visible_world_size().y)
        for i in range(1, heights.size()):
            _check(heights[i] > heights[i - 1], "milho não cresce do estágio %d para %d" % [i - 1, i])
        _check(grid.cells[cell["id"]]["state"] == PlantingGrid.STATE_RIPE, "milho maduro não ficou RIPE")
        _check(grid.get_remaining_yield(cell["id"]) == CropCatalog.yield_per_crop(&"corn"), "rendimento do milho")
        print("CORN_STAGES_OK heights=", heights)

func _ripen_all_corn() -> int:
    var grid := _corn_grid()
    var total := 0
    for cell in grid.cells.values():
        if not world.crops.has(cell["id"]):
            world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
        total += grid.get_remaining_yield(cell["id"])
    return total

func _test_farmer_harvest_and_sale() -> void:
    var grid := _corn_grid()
    var total := _ripen_all_corn()
    var controller := world.crop_harvesters[&"corn"] as HarvestController
    var inventory := world.harvest_inventory
    # Colhe andando por cima das covas maduras até a mochila encher.
    for cell in grid.cells.values():
        var p: Vector3 = cell["position"]
        world.farmer.global_position = Vector3(p.x, 1.0, p.z)
        for frame in 8:
            await process_frame
        if inventory.is_full():
            break
    for frame in 90:
        await process_frame
    var carried := inventory.get_amount(&"corn")
    _check(carried > 0, "fazendeiro não colheu milho")
    _check(inventory.get_amount(&"tomato") == 0, "milho entrou como tomate")
    _check(world.backpack.item_id == &"corn", "mochila não mostra caixas de milho")
    var left := 0
    for cell in grid.cells.values():
        left += grid.get_remaining_yield(cell["id"])
    _check(left + carried == total, "milho criado/perdido: %d + %d != %d" % [left, carried, total])
    controller.cancel_all()
    # Descarrega no balcão: pilha própria na vaga do milho (esquerda).
    var counter := world.sales_counter
    var deposited := counter.deposit_from(inventory, null)
    counter.finish_jumps()
    _check(deposited == carried and inventory.get_total() == 0, "balcão não recebeu o milho")
    var stack := counter.get_extra_stack(&"corn")
    _check(stack != null and stack.get_stored_total() == carried, "pilha de milho no balcão")
    if stack:
        _check(is_equal_approx(stack.position.x, SalesCounter.ITEM_SLOT_X[&"corn"]), "milho fora da vaga reservada")
    var wood_stack := counter.get_extra_stack(WoodConfig.ITEM)
    _check(wood_stack != null and not is_equal_approx(wood_stack.position.x, stack.position.x if stack else 0.0), "madeira e milho na mesma vaga")
    _check(counter.get_stocked_items().has(&"corn"), "milho não está à venda")
    # Venda: cliente leva milho e paga o preço do milho.
    var sales := world.sales_controller
    _check(sales.price_per_crate_of(&"corn") == CropCatalog.price_per_crate(&"corn"), "preço do milho")
    sales.set_seed(7)
    world.customer_queue.set_seed(7)
    var sold := 0
    # Tempo simulado (como sales_counter_smoke): até 3 minutos de jogo.
    for step in 3600:
        world.customer_queue.tick(0.05)
        for child in world.customer_queue.get_children():
            if child is Customer and is_instance_valid(child):
                (child as Customer).step(0.05)
        sales.tick(0.05)
        for log in sales.sales_log:
            if log["item"] == &"corn":
                sold += 1
        if sold > 0:
            break
    _check(sold > 0, "nenhum cliente comprou milho")
    for log in sales.sales_log:
        if log["item"] == &"corn":
            _check(int(log["money"]) == sales.price_for_units(int(log["units"]), &"corn"), "valor pago pelo milho")
            print("CORN_SALE_OK units=%d money=%d" % [log["units"], log["money"]])
            break

func _test_backpack_one_product() -> void:
    _ripen_all_corn()
    world.harvest_inventory.set_amount(&"tomato", 8)
    var cell: Dictionary = _corn_grid().cells.values()[0]
    var p: Vector3 = cell["position"]
    world.farmer.global_position = Vector3(p.x, 1.0, p.z)
    for frame in 20:
        await process_frame
    _check(world.harvest_inventory.get_amount(&"corn") == 0, "milho misturado com tomate na mochila")
    world.set_process(true)
    await process_frame
    await process_frame
    _check(world.hud.get_node("Root").find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.visible and l.text.contains("milho")), "aviso de mochila ocupada no milharal")
    world.set_process(false)
    print("CORN_ONE_PRODUCT_OK")

func _test_backpack_motion_stability() -> void:
    var backpack := world.backpack
    backpack.set_amount(&"corn", 1)
    var crate: Node3D = backpack._crates[0]
    var partial_texture := (crate.get_node("CrateSprite") as Sprite3D).texture
    _check(not crate.top_level, "caixa de milho não pode ser top_level")
    var max_error := 0.0
    for step in 40:
        world.farmer.global_position += Vector3(0.13, 0.0, -0.09)
        world.farmer.rotation.y += 0.07
        backpack._orient_crates()
        var expected := backpack.stack_root.to_global(backpack._slot_position(0, 1))
        max_error = maxf(max_error, crate.global_position.distance_to(expected))
    backpack.set_amount(&"corn", backpack.units_per_crate)
    var full_texture := (crate.get_node("CrateSprite") as Sprite3D).texture
    _check(max_error < 0.0001, "caixa atrasou do fazendeiro durante deslocamento: %.6f" % max_error)
    _check(partial_texture == full_texture and full_texture == ItemArt.full_texture(&"corn"), "milho alterna textura parcial/cheia")
    print("CORN_CRATE_STABILITY_OK max_error=%.6f texture=%s" % [max_error, full_texture.resource_path])

func _test_helper() -> void:
    var entry := world.get_crop_area(&"corn")
    var helper := world.crop_helpers.get(&"corn") as FarmHelper
    _check(helper != null, "sem ajudante do milho")
    if helper == null:
        return
    var hiring := entry["hiring"] as HelperHiring
    var pad := entry["pad"] as HelperPad
    # HIRE-FIX-001: as 20 caixas de tomate saem da mochila na plataforma.
    var inv := world.harvest_inventory
    world.wallet.add(HelperConfig.next_cost(0))
    var center := pad.rect.get_center()
    var delivered := 0
    for trip in 3:
        inv.set_amount(&"tomato", mini(inv.get_capacity(), 20 * inv.units_per_crate - delivered))
        var before := inv.get_amount(&"tomato")
        for frame in 400:
            pad.process_farmer_position(Vector3(center.x, 1.0, center.y), 1.0 / 30.0, inv)
            if hiring.is_hired() or inv.get_amount(&"tomato") == 0:
                break
        delivered += before - inv.get_amount(&"tomato")
        pad.process_farmer_position(Vector3(center.x + 20.0, 1.0, center.y), 1.0 / 30.0, inv)
    for frame in 60:
        pad.process_farmer_position(Vector3(center.x, 1.0, center.y), 1.0 / 30.0, inv)
        if hiring.is_hired():
            break
    _check(hiring.is_hired() and helper.visible, "ajudante do milho não foi contratado na plataforma")
    _check(delivered == 20 * inv.units_per_crate and pad.material_log.size() == 20, "contratação do milho não descarregou 20 caixas de tomate")
    _check(not world.helper_hiring.is_hired(), "contratar o milho contratou o tomate")
    var total := _ripen_all_corn()
    var pile := entry["pile"] as TomatoPile
    # FV-POLISH-001: o milharal (tamanho do tomate) rende mais que a parcela
    # comporta (27 caixas): a pilha cheia é esvaziada no meio do teste, como o
    # fazendeiro faria, e o total empilhado é somado.
    var stacked := 0
    for step in 800:
        helper.step_instant()
        if pile.is_full():
            stacked += pile.take_units(pile.get_stored_total())
        if stacked + pile.get_stored_total() == total:
            break
    _check(stacked + pile.get_stored_total() == total, "ajudante não empilhou todo o milho: %d/%d" % [stacked + pile.get_stored_total(), total])
    if pile.get_stored_total() == 0:
        pile.add_units(16)
    _check(world.tomato_pile.get_stored_total() == 0, "milho foi para a pilha do tomate")
    # Fazendeiro recolhe a pilha de milho na parcela.
    var drop := pile.get_drop_point()
    for frame in 30:
        pile.process_farmer_position(Vector3(drop.x, 1.0, drop.z), world.harvest_inventory, world.backpack.intake_marker)
        await process_frame
    _check(world.harvest_inventory.get_amount(&"corn") > 0, "fazendeiro não recolheu a pilha de milho")
    # Com a safra colhida, o ajudante replanta o milharal.
    var planted := [0]
    helper.planted.connect(func(_id: String) -> void: planted[0] += 1)
    for step in 60:
        helper.step_instant()
    _check(planted[0] > 0, "ajudante do milho não replantou")
    print("CORN_HELPER_OK stacked=%d replanted=%d" % [total, planted[0]])
