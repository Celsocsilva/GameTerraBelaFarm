extends SceneTree
## Testes headless de FV-WOOD-001 (eucaliptos, estações, corte, toras e venda).
## Código de saída 1 em falha. Uso: Godot --headless --path . -s tools/wood_smoke.gd

const STEP := 0.1

var _failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures += 1
        push_error("WOOD_SMOKE_FAIL: " + message)
        print("WOOD_SMOKE_FAIL ", message)

func _run() -> void:
    _test_season_rules()
    _test_translations()
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    var grove := world.eucalyptus_grove
    grove.set_process(false)
    _test_placement(world, grove)
    _test_seasons(grove)
    await _test_chop_cycle(world, grove)
    _test_one_product(world, grove)
    await _test_counter_and_sale(world)
    var trees := grove.get_tree_count()
    world.queue_free()
    await process_frame
    TranslationServer.set_locale("pt_BR")
    if _failures > 0:
        print("WOOD_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("WOOD_SMOKE_OK trees=%d" % trees)
    quit()

func _test_season_rules() -> void:
    _check(SeasonClock.season_for(11, &"south") == SeasonClock.SPRING, "novembro no sul deveria ser primavera")
    _check(SeasonClock.season_for(11, &"north") == SeasonClock.AUTUMN, "novembro no norte deveria ser outono")
    _check(SeasonClock.season_for(1, &"south") == SeasonClock.SUMMER, "janeiro no sul deveria ser verão")
    _check(SeasonClock.season_for(7, &"south") == SeasonClock.WINTER, "julho no sul deveria ser inverno")
    _check(SeasonClock.season_for(1, &"north") == SeasonClock.WINTER, "janeiro no norte deveria ser inverno")
    _check(SeasonClock.season_for(4, &"north") == SeasonClock.SPRING, "abril no norte deveria ser primavera")
    _check(SeasonClock.hemisphere_from_locale("pt_BR") == &"south", "pt_BR deveria ser sul")
    _check(SeasonClock.hemisphere_from_locale("es-AR") == &"south", "es-AR deveria ser sul")
    _check(SeasonClock.hemisphere_from_locale("es_ES") == &"north", "es_ES deveria ser norte")
    _check(SeasonClock.hemisphere_from_locale("en") == &"north", "en sem país deveria ser norte")
    _check(SeasonClock.current_hemisphere("south") == &"south" and SeasonClock.current_hemisphere("north") == &"north", "modo de hemisfério fixo ignorado")
    _check(SeasonClock.current_season("", "winter") == SeasonClock.WINTER, "estação forçada ignorada")

func _test_translations() -> void:
    for locale in ["pt_BR", "es", "en"]:
        TranslationServer.set_locale(locale)
        for key in ["WOOD_NAME", "WOOD_BACKPACK_BUSY", "WOOD_BACKPACK_FULL", "WOOD_SELL_FIRST", "SEASON_SPRING", "SEASON_SUMMER", "SEASON_AUTUMN", "SEASON_WINTER", "SEASON_CHANGED"]:
            _check(TranslationServer.translate(key) != key, "%s sem tradução em %s" % [key, locale])
    TranslationServer.set_locale("pt_BR")
    _check(TranslationServer.translate("SEASON_AUTUMN") == "Outono", "outono em pt_BR")

func _test_placement(world: FarmWorld, grove: EucalyptusGrove) -> void:
    _check(grove.get_tree_count() >= 15, "poucas árvores: %d" % grove.get_tree_count())
    var near_river := 0
    var near_field := 0
    var fields: Array[Rect2] = [world.get_planting_area_rect()]
    for entry in world.crop_areas:
        fields.append(entry["field"] as Rect2)
    for tree in grove.trees:
        var p := Vector2(tree.position.x, tree.position.y)
        p = Vector2(tree.position.x, tree.position.z)
        _check(absf(p.x) < world.farm_size * 0.5 - 1.0 and absf(p.y) < world.farm_size * 0.5 - 1.0, "%s fora do terreno" % tree.name)
        _check(not world.river_system.is_point_in_water(tree.position, 0.3), "%s dentro do rio" % tree.name)
        for field in fields:
            _check(not field.has_point(p), "%s dentro de um canteiro" % tree.name)
            if field.grow(2.6).has_point(p):
                near_field += 1
        if world.river_system.blocks_decoration(tree.position, 3.0):
            near_river += 1
        _check(tree.get_node_or_null("Art") is Sprite3D, "%s sem sprite" % tree.name)
        _check(tree.find_children("*", "CollisionShape3D").is_empty(), "%s não deveria fechar a passagem" % tree.name)
    _check(near_field >= 8, "poucas árvores nas bordas dos canteiros: %d" % near_field)
    # FV-WOOD-002: floresta no canto sudoeste, ao sul do rio, dos dois lados da cerca do balcão.
    var forest := 0
    var below_fence := 0
    for tree in grove.trees:
        if FarmWorld.EUCALYPTUS_FOREST.has_point(Vector2(tree.position.x, tree.position.z)):
            forest += 1
            if tree.position.z > world.sales_counter.position.z + 0.6:
                below_fence += 1
    _check(forest >= 25, "floresta do canto com poucas árvores: %d" % forest)
    _check(below_fence >= 8, "poucas árvores abaixo da cerca: %d" % below_fence)
    print("WOOD_FOREST corner=%d below_fence=%d" % [forest, below_fence])
    _check(near_river >= 4, "poucas árvores junto ao rio: %d" % near_river)
    # Nada no corredor de acesso ao canteiro nem perto do balcão.
    for tree in grove.trees:
        _check(Vector2(tree.position.x, tree.position.z).distance_to(Vector2(world.sales_counter.position.x, world.sales_counter.position.z)) > 7.0, "%s perto do balcão" % tree.name)
    print("WOOD_PLACEMENT trees=%d near_field=%d near_river=%d" % [grove.get_tree_count(), near_field, near_river])

func _test_seasons(grove: EucalyptusGrove) -> void:
    for season in SeasonClock.ALL:
        grove.set_forced_season(String(season))
        _check(grove.season == season, "grove não mudou para %s" % season)
        for tree in grove.trees:
            if tree.get_current_texture() != EucalyptusTree.SEASON_TEXTURES[season]:
                _check(false, "%s sem a arte de %s" % [tree.name, season])
                break
    grove.set_forced_season("")
    _check(grove.season == SeasonClock.current_season(), "estação real não voltou")

func _walk_and_chop(world: FarmWorld, grove: EucalyptusGrove, tree: EucalyptusTree) -> void:
    var pos := tree.global_position + Vector3(0.6, 0.0, 0.4)
    world.farmer.global_position = pos
    var t := 0.0
    while tree.state != EucalyptusTree.STUMP and t < 8.0:
        grove.process_farmer_position(pos, STEP)
        t += STEP

func _test_chop_cycle(world: FarmWorld, grove: EucalyptusGrove) -> void:
    var inventory := world.harvest_inventory
    inventory.set_amount(&"tomato", 0)
    var tree := grove.trees[0]
    var felled := []
    grove.tree_felled.connect(func(t: EucalyptusTree, logs: int) -> void: felled.append(logs))
    # Passar longe não corta.
    grove.process_farmer_position(tree.global_position + Vector3(0.0, 0.0, -5.0), STEP)
    _check(not grove.is_chopping(), "cortou de longe")
    # FV-WOOD-002: estágios da queda no ritmo do machado.
    var pos := tree.global_position + Vector3(0.6, 0.0, 0.4)
    var stages: Array[Texture2D] = []
    var axe_frames := {}
    var hit_times: Array[float] = []
    var t := 0.0
    var last_hits := 0
    while tree.state != EucalyptusTree.STUMP and t < 6.0:
        grove.process_farmer_position(pos, 0.02)
        t += 0.02
        if grove.get_axe_frame() >= 0:
            axe_frames[grove.get_axe_frame()] = true
        if grove.get_hits_done() != last_hits:
            last_hits = grove.get_hits_done()
            hit_times.append(t)
        var texture := tree.get_current_texture()
        if stages.is_empty() or stages[-1] != texture:
            stages.append(texture)
    var expected: Array[Texture2D] = [EucalyptusTree.SEASON_TEXTURES[grove.season]]
    expected.append_array(EucalyptusTree.FALL_TEXTURES.slice(1))
    _check(stages == expected, "sequência da queda: %s" % [stages.map(func(x): return x.resource_path.get_file() if x else "-")])
    _check(axe_frames.size() == EucalyptusGrove.AXE_FRAMES.size(), "machado não passou por todos os quadros: %s" % [axe_frames.keys()])
    _check(hit_times.size() == WoodConfig.CHOP_HITS, "golpes: %d" % hit_times.size())
    if hit_times.size() >= 2:
        _check(absf(hit_times[1] - hit_times[0] - EucalyptusGrove.get_swing_seconds()) < 0.05, "golpes fora do ritmo do machado")
        _check(absf(hit_times[0] - EucalyptusGrove.get_impact_offset()) < 0.05, "primeiro golpe fora do quadro de impacto")
    _check(absf(t - EucalyptusGrove.get_total_chop_seconds()) < 0.08, "tempo do corte %.2f s (esperado %.2f s)" % [t, EucalyptusGrove.get_total_chop_seconds()])
    _check(not grove.axe.visible, "machado ficou na tela")
    print("WOOD_FALL stages=%d hits=%s total=%.2fs" % [stages.size(), hit_times, t])
    _check(tree.state == EucalyptusTree.STUMP, "árvore não virou toco")
    _check(tree.get_current_texture() == EucalyptusTree.STUMP_TEXTURE, "toco sem a arte cortada")
    _check(felled == [WoodConfig.LOGS_PER_TREE], "toras da árvore: %s" % [felled])
    _check(grove.get_flying_count() == 1, "toras não voaram para a mochila")
    _check(inventory.get_amount(WoodConfig.ITEM) == 0, "toras entraram antes de chegar")
    await create_timer(0.7).timeout
    _check(grove.get_flying_count() == 0, "voo das toras não terminou")
    _check(inventory.get_amount(WoodConfig.ITEM) == WoodConfig.LOGS_PER_TREE, "mochila com %d toras" % inventory.get_amount(WoodConfig.ITEM))
    var backpack := world.backpack
    _check(backpack.item_id == WoodConfig.ITEM and backpack.get_visible_crate_count() == 1, "mochila não mostra o fardo")
    var sprite := backpack.stack_root.get_child(0).get_node("CrateSprite") as Sprite3D
    _check(sprite.texture == ItemArt.LOG_BUNDLE_4, "fardo parcial deveria ser o de 4 toras")
    # Um toco não é cortado de novo.
    grove.process_farmer_position(tree.global_position, STEP)
    _check(not grove.is_chopping(), "cortou um toco")
    # Segunda árvore: fardo cheio de 8 toras.
    _walk_and_chop(world, grove, grove.trees[1])
    grove.finish_flights()
    _check(inventory.get_amount(WoodConfig.ITEM) == 8, "duas árvores deveriam dar 8 toras")
    _check(sprite.texture == ItemArt.LOG_BUNDLE_8, "fardo cheio deveria ser o de 8 toras")
    # Sair de perto no meio do corte cancela e devolve a reserva.
    var third := grove.trees[2]
    grove.process_farmer_position(third.global_position, STEP)
    grove.process_farmer_position(third.global_position, 0.3)
    _check(grove.is_chopping() and third.state == EucalyptusTree.CHOPPING and third.cut_stage == 1, "corte não começou")
    grove.process_farmer_position(third.global_position + Vector3(6.0, 0.0, 0.0), STEP)
    _check(not grove.is_chopping() and third.state == EucalyptusTree.GROWN and third.cut_stage == 0 and inventory.get_pending_reservation_count() == 0, "cancelamento do corte")
    _check(third.get_current_texture() == EucalyptusTree.SEASON_TEXTURES[grove.season], "árvore cancelada não voltou inteira")
    # Toco some e a árvore rebrota.
    tree.tick(WoodConfig.STUMP_SECONDS + 0.05)
    _check(tree.state == EucalyptusTree.GONE and not tree.sprite.visible, "toco não sumiu")
    tree.tick(WoodConfig.REGROW_SECONDS - 1.0)
    _check(tree.state == EucalyptusTree.GONE, "rebrotou cedo")
    tree.tick(1.1)
    _check(tree.state == EucalyptusTree.GROWN and tree.sprite.visible and tree.get_current_texture() == EucalyptusTree.SEASON_TEXTURES[grove.season], "árvore não rebrotou com a arte da estação")

func _test_one_product(world: FarmWorld, grove: EucalyptusGrove) -> void:
    var inventory := world.harvest_inventory
    # Com toras na mochila, o tomate não entra.
    var reservation := inventory.try_reserve(&"tomato", 6)
    _check(not reservation.is_valid(), "tomate entrou com toras na mochila")
    # Com tomates na mochila, o corte não começa e avisa o motivo.
    var wood := inventory.get_amount(WoodConfig.ITEM)
    inventory.set_amount(WoodConfig.ITEM, 0)
    inventory.set_amount(&"tomato", 10)
    var reasons := []
    grove.chop_blocked.connect(func(reason: StringName) -> void: reasons.append(reason))
    var tree := grove.trees[3]
    grove.process_farmer_position(tree.global_position, STEP)
    grove.process_farmer_position(tree.global_position, STEP)
    _check(not grove.is_chopping() and tree.state == EucalyptusTree.GROWN, "cortou com tomates na mochila")
    _check(reasons == [&"other_item"], "aviso de mochila ocupada: %s" % [reasons])
    _check(world.backpack.item_id == &"tomato", "mochila não voltou a mostrar tomates")
    inventory.set_amount(&"tomato", 0)
    inventory.set_amount(WoodConfig.ITEM, wood)

func _test_counter_and_sale(world: FarmWorld) -> void:
    var counter := world.sales_counter
    var inventory := world.harvest_inventory
    var stack := counter.get_extra_stack(WoodConfig.ITEM)
    _check(stack != null, "balcão sem pilha de madeira")
    if stack == null:
        return
    var tomato_before := counter.get_stored_total()
    var deposited := counter.deposit_from(inventory, world.get_farmer_hands_position())
    _check(deposited == 8 and inventory.get_total() == 0, "balcão não recebeu as toras: %d" % deposited)
    _check(counter.get_item_total(WoodConfig.ITEM) == 8 and counter.get_stored_total() == tomato_before, "estoque de madeira no balcão")
    _check(stack.get_flying_crate_count() == 1, "fardo não pulou das mãos")
    counter.finish_jumps()
    _check(stack.get_visible_crate_count() == 1, "fardo não aparece no balcão")
    var sprite := stack.get_child(0).get_node("CrateSprite") as Sprite3D
    _check(sprite.texture == ItemArt.LOG_BUNDLE_8, "fardo do balcão sem a arte de 8 toras")
    _check(absf(stack.position.x - SalesCounter.EXTRA_SLOT_X[WoodConfig.ITEM]) < 0.01, "pilha da madeira fora da vaga")
    # Venda: um cliente compra o fardo pelo preço da madeira.
    var sales := world.sales_controller
    _check(sales.price_for_units(8, WoodConfig.ITEM) == WoodConfig.PRICE_PER_BUNDLE, "preço do fardo")
    _check(sales.price_for_units(4, WoodConfig.ITEM) == int(ceil(WoodConfig.PRICE_PER_BUNDLE * 0.5)), "preço do meio fardo")
    var queue := world.customer_queue
    queue.set_seed(20261109)
    sales.set_seed(3)
    var balance_before := world.money_stack.get_balance()
    var sold := []
    sales.item_sold.connect(func(item: StringName, _c: Customer, crates: int, units: int, money: int) -> void: sold.append([item, crates, units, money]))
    var t := 0.0
    while t < 60.0 and counter.get_item_total(WoodConfig.ITEM) > 0:
        queue.tick(STEP)
        for child in queue.get_children():
            if child is Customer and is_instance_valid(child):
                (child as Customer).step(STEP)
        sales.tick(STEP)
        t += STEP
    _check(counter.get_item_total(WoodConfig.ITEM) == 0, "madeira não foi vendida em 60 s")
    _check(sold.size() == 1 and sold[0] == [WoodConfig.ITEM, 1, 8, WoodConfig.PRICE_PER_BUNDLE], "venda da madeira: %s" % [sold])
    _check(world.money_stack.get_balance() == balance_before + WoodConfig.PRICE_PER_BUNDLE, "dinheiro da madeira")
    var last: Dictionary = sales.sales_log[-1]
    _check(last["item"] == WoodConfig.ITEM and last["carried"] == 1, "cliente não levou o fardo")
    print("WOOD_SALE %s time=%.1fs" % [sold, t])
