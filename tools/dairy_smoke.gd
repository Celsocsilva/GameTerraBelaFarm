extends SceneTree
## Testes headless de DAIRY-001/002/003 e MAP-003: garrafas de leite das vacas para a área do
## leite, recolha para a mochila, venda no balcão e compra de vacas (200 +
## 20 caixas de milho descarregadas da mochila). Código de saída 1 em falha.
## Uso: Godot --headless --path . -s tools/dairy_smoke.gd

var _failures := 0
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures += 1
        push_error("DAIRY_SMOKE_FAIL: " + message)

func _run() -> void:
    await _load_world()
    _test_layout()
    await _test_milk_production()
    await _test_pickup_and_sale()
    await _load_world()
    await _test_cow_purchase()
    await _load_world()
    _test_translations()
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("DAIRY_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("DAIRY_SMOKE_OK")
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
    world.milk_station.enabled = false
    world.farmer.global_position = Vector3(-20.0, 1.0, -20.0)
    await process_frame

func _test_layout() -> void:
    var pen := world.cow_pen
    var milk := world.get_milk_area_rect()
    var pad := world.get_cow_shop_pad_rect()
    var house := world.get_milk_house_rect()
    var feeder := world.get_feeder_rect()
    for r in [milk, pad]:
        _check(not r.intersects(pen.rect), "piso dentro do curral: %s" % r)
        _check(world.get_map_rect().encloses(r), "piso fora do mapa")
        for bush in pen.get_surroundings_points("bush"):
            _check(not r.has_point(Vector2(bush.x, bush.z)), "arbusto em cima de piso")
    _check(not milk.intersects(pad), "pisos sobrepostos")
    # DAIRY-003: casinha 20% maior no canto superior direito (nordeste) do curral.
    _check(pen.rect.grow(0.01).encloses(house) and pen.rect.grow(0.01).encloses(feeder), "casinha/cocho fora do curral")
    _check(absf(house.size.x - 5.4 * 1.2) < 0.01, "casinha deveria ser 20%% maior: %.2f" % house.size.x)
    _check(house.end.x > pen.rect.end.x - 1.0 and house.position.y < pen.rect.position.y + 1.0, "casinha fora do canto nordeste: %s" % house)
    _check(pen.milk_house != null and pen.milk_house.mesh != null, "casinha de ordenha não montada")
    _check(milk.position.x > pen.rect.end.x and milk.position.y < house.end.y and milk.end.y > house.position.y, "área do leite fora do lado da casinha")
    _check(pen.has_node("FenceSouthEast") and not world.has_node("FeedTrough/Floor"), "cerca da frente/piso do cocho")
    # Vacas: nunca escolhem destino na casinha ou no cocho.
    var cow := pen.cows[0]
    for i in 200:
        var target := cow._pick_target()
        for rect in pen.get_cow_avoid_rects():
            _check(not rect.has_point(Vector2(target.x, target.z)), "vaca indo para a casinha/cocho: %s" % target)
    _check(pen.get_cow_count() == 1, "curral deve começar com 1 vaca: %d" % pen.get_cow_count())
    _check(world.cow_shop_pad.get_title_text() == "Vacas", "título da plataforma: %s" % world.cow_shop_pad.get_title_text())
    _check(world.cow_shop_pad.get_grade_text() == "1/7", "contagem de vacas: %s" % world.cow_shop_pad.get_grade_text())
    _check(world.cow_shop_pad.get_cost_text() == "200", "preço da vaca: %s" % world.cow_shop_pad.get_cost_text())
    _check(world.cow_shop_pad.get_material_text() == "0/20", "milho da vaca: %s" % world.cow_shop_pad.get_material_text())
    _check(world.milk_station.get_title_text() == "Leite", "título da área do leite")
    _check(world.sales_counter.get_extra_stack(&"milk") != null, "balcão sem pilha de leite")
    # MAP-003: mapa ~15% maior à esquerda, à direita e no topo; rodapé igual.
    var old := world.get_previous_map_rect()
    var map := world.get_map_rect()
    _check(absf(old.position.x - map.position.x - 77.44 * 0.15) < 0.01 and absf(map.end.x - old.end.x - 77.44 * 0.15) < 0.01 and absf(old.position.y - map.position.y - 77.44 * 0.15) < 0.01 and is_equal_approx(map.end.y, old.end.y), "mapa ampliado: %s" % map)
    var forest := world.border_forest
    _check(forest.points.size() >= 180 and forest.get_count(&"pine") >= 40 and forest.get_count(&"round") >= 40, "floresta nova: %d (pinheiros %d, redondas %d)" % [forest.points.size(), forest.get_count(&"pine"), forest.get_count(&"round")])
    # FOREST-002: árvores 20% maiores e borda externa fechada (sem falhas).
    for index in forest.points.size():
        var base := BorderForest.PINE_WIDTH if forest.kinds[index] == &"pine" else BorderForest.ROUND_WIDTH
        _check(forest.points[index].y >= base * (1.0 - BorderForest.SIZE_JITTER) - 0.01, "árvore pequena demais: %s" % forest.points[index])
    _check(is_equal_approx(BorderForest.ROUND_WIDTH, 3.6 * 1.2) and is_equal_approx(BorderForest.PINE_WIDTH, 2.4 * 1.2), "árvores não estão 20% maiores")
    var edge_samples: Array[Vector2] = []
    var sx := map.position.x + 1.0
    while sx < map.end.x - 1.0:
        edge_samples.append(Vector2(sx, map.position.y + 1.5))
        sx += 2.0
    var sz := map.position.y + 1.0
    while sz < old.end.y - 8.0:
        edge_samples.append(Vector2(map.position.x + 1.5, sz))
        edge_samples.append(Vector2(map.end.x - 1.5, sz))
        sz += 2.0
    for sample in edge_samples:
        if world.river_system.is_point_in_water(Vector3(sample.x, 0.0, sample.y), 2.5):
            continue
        var nearest := 99.0
        for p in forest.points:
            nearest = minf(nearest, Vector2(p.x, p.z).distance_to(sample))
        _check(nearest <= 3.2, "falha na borda do mapa em %s (árvore mais perto a %.1f m)" % [sample, nearest])
    for p in forest.points:
        var xz := Vector2(p.x, p.z)
        _check(map.has_point(xz) and not old.has_point(xz), "árvore nova fora das faixas novas: %s" % xz)
        _check(not world.river_system.is_point_in_water(Vector3(p.x, 0.0, p.z), 0.5), "árvore nova no rio: %s" % xz)
    # O rio continua até a nova borda oeste (entra e sai por ela).
    var touches := 0
    for segment in world.river_system.segments:
        if world.river_system.get_segment_rect(segment).position.x <= map.position.x + 0.5:
            touches += 1
    _check(touches >= 2, "rio não chega à nova borda oeste: %d" % touches)
    # Cercas do balcão até as novas bordas.
    for name in ["CounterBarrier_L", "CounterBarrier_R"]:
        var barrier := world.sales_counter.get_node_or_null(name) as Node3D
        _check(barrier != null, "cerca do balcão ausente: " + name)

func _run_ticks(seconds: float) -> void:
    var t := 0.0
    while t < seconds - 0.0001:
        world.milk_station.tick(0.1)
        t += 0.1
    world.milk_station.finish_flights()

func _test_milk_production() -> void:
    var station := world.milk_station
    var pile := station.pile
    var trough := world.feed_trough
    var cow := world.cow_pen.cows[0]
    _check(pile.get_stored_total() == 0 and trough.get_stored_total() == 0, "leite/cocho devem começar vazios")
    trough.pile.set_stored_total(16)
    station.enabled = true
    # Aquecimento: nada de leite antes de 20 s, mesmo com milho.
    _run_ticks(DairyConfig.MILK_WARMUP - 0.5)
    _check(station.bottle_log.is_empty() and trough.get_stored_total() == 16, "leite antes dos 20 s")
    _run_ticks(1.0)
    _check(station.bottle_log.size() == 1 and trough.get_stored_total() == 15, "primeira garrafa aos 20 s: %d garrafas, cocho %d" % [station.bottle_log.size(), trough.get_stored_total()])
    # Proporção: cada espiga comida vira uma garrafa; acaba o milho, acaba o leite.
    _run_ticks(300.0)
    _check(trough.get_stored_total() == 0, "cocho deveria esvaziar: %d" % trough.get_stored_total())
    _check(station.corn_eaten == 16 and pile.get_stored_total() == 16 and station.bottle_log.size() == 16, "proporção milho/leite: comeu %d, garrafas %d" % [station.corn_eaten, pile.get_stored_total()])
    # Intervalos aleatórios entre as refeições, dentro dos limites.
    _check(station.meal_log.size() == 16, "refeições: %d" % station.meal_log.size())
    var hungry := [0]
    station.hungry.connect(func() -> void: hungry[0] += 1)
    _run_ticks(30.0)
    _check(pile.get_stored_total() == 16 and hungry[0] > 0, "sem milho não pode dar leite (garrafas %d, fome %d)" % [pile.get_stored_total(), hungry[0]])
    # Área do leite cheia: as vacas não comem (o milho fica no cocho).
    pile.set_stored_total(pile.get_capacity())
    trough.pile.set_stored_total(8)
    _run_ticks(40.0)
    _check(trough.get_stored_total() == 8 and pile.get_stored_total() == pile.get_capacity(), "comeu com a área do leite cheia")
    pile.set_stored_total(0)
    # Vaca nova espera os 20 s dela.
    var newcomer := world.cow_pen.add_cow()
    trough.pile.set_stored_total(40)
    var before := station.bottle_log.size()
    _run_ticks(DairyConfig.MILK_WARMUP - 0.5)
    var from_new := 0
    for i in range(before, station.bottle_log.size()):
        if station.bottle_log[i]["cow"] == newcomer:
            from_new += 1
    _check(from_new == 0, "vaca nova deu leite antes de 20 s")
    _run_ticks(1.0)
    _check(_cow_gave_after(newcomer, before), "vaca nova não deu leite aos 20 s")
    station.enabled = false
    # Piso do cocho: descarrega o milho da mochila, até a capacidade do cocho.
    var inv := world.harvest_inventory
    trough.pile.set_stored_total(0)
    inv.set_amount(&"corn", 24)
    var pos := trough.get_fence_point()
    _check(trough.contains_point(pos) and not trough.contains_point(Vector3(pos.x, 1.0, pos.z + 3.0)), "entrega na cerca: alcance errado")
    var moved := 0
    for i in 60:
        moved += trough.process_farmer_position(pos, 1.0 / 30.0, inv)
    _check(moved == 24 and inv.get_amount(&"corn") == 0 and trough.get_stored_total() == 24, "milho para o cocho: %d / mochila %d" % [moved, inv.get_amount(&"corn")])
    trough.pile.set_stored_total(trough.get_capacity() - 3)
    inv.set_amount(&"corn", 16)
    for i in 60:
        trough.process_farmer_position(pos, 1.0 / 30.0, inv)
    _check(trough.get_stored_total() == trough.get_capacity() and inv.get_amount(&"corn") == 13, "cocho cheio: %d, sobra %d" % [trough.get_stored_total(), inv.get_amount(&"corn")])
    inv.set_amount(&"corn", 0)
    trough.pile.set_stored_total(0)

func _cow_gave_after(cow: FarmCow, from_index: int) -> bool:
    for i in range(from_index, world.milk_station.bottle_log.size()):
        if world.milk_station.bottle_log[i]["cow"] == cow:
            return true
    return false

func _test_pickup_and_sale() -> void:
    var pile := world.milk_station.pile
    var inv := world.harvest_inventory
    inv.set_amount(&"tomato", 0)
    pile.set_stored_total(20)
    var pos := Vector3(world.get_milk_area_rect().get_center().x, 1.0, world.get_milk_area_rect().get_center().y)
    var moved := 0
    for i in 40:
        moved += pile.process_farmer_position(pos, inv, null)
        pile._pickup_cooldown = 0.0
    _check(moved == 20 and inv.get_amount(&"milk") == 20 and pile.get_stored_total() == 0, "recolha do leite: moved=%d mochila=%d" % [moved, inv.get_amount(&"milk")])
    # Mochila com outro produto não recolhe leite.
    pile.set_stored_total(8)
    inv.set_amount(&"milk", 0)
    inv.set_amount(&"corn", 8)
    _check(pile.process_farmer_position(pos, inv, null) == 0, "leite entrou com milho na mochila")
    inv.set_amount(&"corn", 0)
    inv.set_amount(&"milk", 16)
    var counter := world.sales_counter
    counter.deposit_from(inv)
    _check(counter.get_item_total(&"milk") == 16 and inv.get_amount(&"milk") == 0, "leite não foi para o balcão")
    _check(world.sales_controller.price_per_crate_of(&"milk") == DairyConfig.PRICE_PER_CRATE, "preço do leite")
    _check(world.sales_controller.price_for_units(8, &"milk") == DairyConfig.PRICE_PER_CRATE, "preço de uma caixa de leite")
    var stack := counter.get_extra_stack(&"milk")
    _check(absf(stack.position.x - SalesCounter.ITEM_SLOT_X[&"milk"]) < 0.01, "pilha do leite fora da vaga")

## Fica na plataforma por `seconds` ou até o curral ter `stop_at_cows` vacas
## (logo depois de uma compra a plataforma já começa a cobrar a próxima vaca).
func _stand_on_pad(seconds: float, stop_at_cows: int = -1) -> void:
    var pad := world.cow_shop_pad
    var center := pad.rect.get_center()
    var pos := Vector3(center.x, 1.0, center.y)
    var t := 0.0
    while t < seconds:
        pad.process_farmer_position(pos, 1.0 / 30.0, world.harvest_inventory)
        t += 1.0 / 30.0
        if stop_at_cows > 0 and world.cow_pen.get_cow_count() >= stop_at_cows:
            break
    pad.finish_flights()

func _test_cow_purchase() -> void:
    var shop := world.cow_shop
    var pad := world.cow_shop_pad
    var inv := world.harvest_inventory
    var wallet := world.wallet
    # Só dinheiro, sem milho: soma o preço inteiro (200/200, HIRE-FIX-002) e não compra até o milho.
    wallet.set_balance(500)
    _stand_on_pad(12.0)
    _check(world.cow_pen.get_cow_count() == 1, "comprou vaca sem milho")
    _check(shop.paid == DairyConfig.COW_PRICE and wallet.get_balance() == 500 - DairyConfig.COW_PRICE and shop.is_waiting_material(), "sem milho deveria guardar 200/200: paid=%d saldo=%d" % [shop.paid, wallet.get_balance()])
    # Milho em 3 viagens (mochila: 7 caixas por vez).
    var trips := 0
    while world.cow_pen.get_cow_count() < 2 and trips < 5:
        inv.set_amount(&"corn", inv.get_capacity())
        _stand_on_pad(3.0, 2)
        trips += 1
    _check(trips == 3, "milho deveria chegar em 3 viagens, foram %d" % trips)
    _check(world.cow_pen.get_cow_count() == 2, "vaca não entrou no curral: %d" % world.cow_pen.get_cow_count())
    _check(shop.grade == 1 and shop.paid == 0 and shop.material_units == 0, "estado após a compra: grade=%d paid=%d material=%d" % [shop.grade, shop.paid, shop.material_units])
    _check(wallet.get_balance() == 300, "saldo após a vaca: %d" % wallet.get_balance())
    # Sobra de milho fica na mochila (20 de 21 caixas descarregadas).
    _check(inv.get_amount(&"corn") == 8, "milho que sobrou na mochila: %d" % inv.get_amount(&"corn"))
    _check(pad.get_grade_text() == "2/%d" % DairyConfig.MAX_COWS and pad.get_material_text() == "0/20" and pad.get_cost_text() == "200", "plataforma depois da compra: %s %s %s" % [pad.get_grade_text(), pad.get_material_text(), pad.get_cost_text()])
    # A nova vaca também dá leite.
    var new_cow := world.cow_pen.cows[1]
    _check(world.milk_station.get_cow_timer(new_cow) < 0.0 or world.milk_station.get_cow_timer(new_cow) >= DairyConfig.MILK_WARMUP - 0.01, "vaca comprada sem a espera de 20 s")
    # Teto: MAX_EXTRA_COWS vacas compradas (MAX_COWS no curral).
    for i in DairyConfig.MAX_EXTRA_COWS - 1:
        shop.material_units = shop.get_requirement_units()
        wallet.set_balance(1000)
        _stand_on_pad(10.0, world.cow_pen.get_cow_count() + 1)
    _check(world.cow_pen.get_cow_count() == DairyConfig.MAX_COWS and shop.is_max(), "teto de vacas: %d" % world.cow_pen.get_cow_count())
    var inner := world.cow_pen.get_inner_rect()
    for cow in world.cow_pen.cows:
        _check(inner.grow(0.05).has_point(Vector2(cow.position.x, cow.position.z)), "vaca fora do curral")
    var before := wallet.get_balance()
    _stand_on_pad(2.0)
    _check(wallet.get_balance() == before, "cobrou com o curral no máximo")
    _check(pad.get_cost_text() == "Máximo", "plataforma no máximo: %s" % pad.get_cost_text())

func _test_translations() -> void:
    for locale in ["en", "es", "pt_BR"]:
        TranslationServer.set_locale(locale)
        for key in ["MILK_AREA_TITLE", "COW_SHOP_TITLE", "COW_BOUGHT", "COW_NO_MONEY", "MILK_NAME", "COWS_HUNGRY"]:
            _check(TranslationServer.translate(key) != key, "%s sem tradução em %s" % [key, locale])
    TranslationServer.set_locale("en")
    _check(TranslationServer.translate("COW_SHOP_TITLE") == "Cows", "inglês")
    TranslationServer.set_locale("es")
    _check(TranslationServer.translate("MILK_AREA_TITLE") == "Leche" and TranslationServer.translate("COW_SHOP_TITLE") == "Vacas", "espanhol")
    TranslationServer.set_locale("pt_BR")
