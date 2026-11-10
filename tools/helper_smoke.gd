extends SceneTree
## Testes headless do ajudante FV-HELPER-001 (código de saída 1 em falha).
## Uso: Godot --headless --path . -s tools/helper_smoke.gd
##
## Invariante: tomates na pilha + carga do ajudante + mochila + frutos nos pés
## == produção inicial (o ajudante nunca cria nem perde tomates).

var _failures := 0
var world: FarmWorld
var _initial_total := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures += 1
        push_error("HELPER_SMOKE_FAIL: " + message)

func _run() -> void:
    _test_config()
    await _test_hiring_on_pad()
    await _test_pad_layout()
    await _test_harvest_and_stack()
    await _test_shared_lock_with_farmer()
    await _test_farmer_picks_up_pile()
    await _test_walking_cycle()
    await _test_replant()
    if world:
        world.queue_free()
        await process_frame
    if _failures > 0:
        print("HELPER_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("HELPER_SMOKE_OK")
    quit()

func _load_world(ripe: bool) -> void:
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
    _initial_total = 0
    if ripe:
        for cell in world.planting_grid.cells.values():
            world.spawn_crop_at_stage(cell["id"], CropPlant.STAGES.size() - 1)
            _initial_total += world.planting_grid.get_remaining_yield(cell["id"])
    world.farmer.global_position = Vector3(-20.0, 1.0, -20.0)
    await process_frame

func _remaining_yield() -> int:
    var total := 0
    for cell in world.planting_grid.cells.values():
        total += int(cell["remaining_yield"])
    return total

func _accounted() -> int:
    return world.tomato_pile.get_stored_total() + world.farm_helper.carried + world.harvest_inventory.get_total() + _remaining_yield()

func _test_config() -> void:
    _check(HelperConfig.MAX_GRADE == 5, "5 graduações")
    _check(HelperConfig.UPGRADE_COSTS.size() == HelperConfig.MAX_GRADE, "um custo por graduação")
    for i in range(1, HelperConfig.UPGRADE_COSTS.size()):
        _check(HelperConfig.UPGRADE_COSTS[i] > HelperConfig.UPGRADE_COSTS[i - 1], "custos crescentes")
        _check(HelperConfig.WALK_SPEEDS[i] >= HelperConfig.WALK_SPEEDS[i - 1], "velocidade não cai")
    _check(HelperConfig.next_cost(HelperConfig.MAX_GRADE) == -1, "sem custo no máximo")
    _check(HelperConfig.initial_requirement(&"tomato") == {"item": &"wood", "crates": 20}, "tomate exige 20 fardos")
    _check(HelperConfig.initial_requirement(&"corn") == {"item": &"tomato", "crates": 20}, "milho exige 20 caixas de tomate")
    _check(HelperConfig.initial_requirement(&"pumpkin") == {"item": &"corn", "crates": 20}, "abóbora exige 20 caixas de milho")
    print("HELPER_CONFIG_OK costs=", HelperConfig.UPGRADE_COSTS)

func _step_pad(seconds: float, on_pad: bool) -> int:
    var pad := world.helper_pad
    var pos := Vector3(pad.rect.get_center().x, 1.0, pad.rect.get_center().y) if on_pad else Vector3(pad.rect.end.x + 3.0, 1.0, pad.rect.get_center().y)
    var dt := 1.0 / 60.0
    var paid := 0
    var t := 0.0
    while t < seconds:
        paid += pad.process_farmer_position(pos, dt, world.harvest_inventory)
        t += dt
    return paid

func _test_hiring_on_pad() -> void:
    await _load_world(false)
    var hiring := world.helper_hiring
    var pad := world.helper_pad
    var wallet := world.wallet
    _check(world.hud.get_node_or_null("Root/HelperPanel") == null, "controle não está no HUD")
    _check(not world.farm_helper.visible, "ajudante invisível antes de contratar")
    _check(pad.get_title_text() == "Ajudante", "título " + pad.get_title_text())
    _check(pad.get_grade_text() == "Grau 0/5" and pad.get_grade_shown() == 0, "grau 0")
    _check(pad.get_cost_text() == "100", "preço 100: " + pad.get_cost_text())
    # Sem saldo: nada é cobrado e o HUD avisa quanto falta.
    _check(_step_pad(1.0, true) == 0 and hiring.paid == 0, "sem saldo não cobra")
    _check(world.hud.get_banner_message() == "Faltam 100 para o ajudante.", "aviso: " + world.hud.get_banner_message())
    wallet.add(150, &"test")
    _check(_step_pad(2.0, false) == 0, "fora da plataforma não cobra")
    _check(_step_pad(HelperPad.START_DELAY * 0.9, true) == 0, "espera curta antes de cobrar")
    _step_pad(1.0, false)
    # Paga um pouco, sai: pausa e guarda o que já pagou.
    var first := _step_pad(HelperPad.START_DELAY + 40 * HelperPad.PAY_INTERVAL + 0.001, true)
    _check(first >= 38 and first <= 41, "~40 dinheiros pagos: %d" % first)
    _check(hiring.paid == first and wallet.get_balance() == 150 - first, "Wallet desconta 1 a 1")
    _check(_step_pad(2.0, false) == 0 and hiring.paid == first, "sair pausa sem devolver nem cobrar")
    _check(pad.get_cost_text() == str(100 - first), "plataforma mostra quanto falta")
    _check(absf(pad.get_progress() - float(first) / 100.0) < 0.001, "preenchimento proporcional")
    var unit_spends := 0
    for entry in wallet.history:
        if entry["source"] == &"helper":
            _check(int(entry["amount"]) == -1, "cada dinheiro sai separado")
            unit_spends += 1
    _check(unit_spends == first, "histórico 1 a 1")
    _check(pad.flight_log.size() == first, "um maço voa por dinheiro")
    var grades: Array[int] = []
    pad.purchased.connect(func(g: int) -> void: grades.append(g))
    # Sem os 20 fardos, para em 99/100: não gasta o último dinheiro nem libera.
    var t := 0.0
    while hiring.paid < 99 and t < 5.0:
        _step_pad(0.02, true)
        t += 0.02
    _check(hiring.grade == 0 and hiring.paid == 99 and wallet.get_balance() == 51, "material bloqueia em 99/100")
    _check(world.hud.get_banner_message().contains("20") and world.hud.get_banner_message().contains("Madeira"), "aviso de 20 fardos")
    # HIRE-FIX-001: estoque do balcão não conta; os fardos vêm da mochila.
    world.sales_counter.set_item_total(&"wood", 20 * world.harvest_inventory.units_per_crate)
    _step_pad(HelperPad.START_DELAY + 1.0, true)
    _check(hiring.grade == 0 and world.sales_counter.get_item_total(&"wood") == 160, "estoque do balcão não é consumido")
    world.sales_counter.set_item_total(&"wood", 0)
    await _deliver_wood_in_trips(pad, hiring)
    _step_pad(0.1, false)
    _step_pad(HelperPad.START_DELAY + HelperPad.PAY_INTERVAL * 2.0, true)
    _check(grades.size() == 1 and grades[0] == 1 and hiring.grade == 1, "contratado ao completar 100: %s" % [grades])
    _check(wallet.get_balance() + hiring.paid == 50, "custou exatamente 100: saldo %d" % wallet.get_balance())
    _check(world.harvest_inventory.get_amount(&"wood") == world.harvest_inventory.units_per_crate, "consumiu exatamente 20 fardos (7+7+6, sobra 1 na mochila)")
    await process_frame
    _check(world.farm_helper.visible, "ajudante aparece")
    _check(world.hud.get_banner_message().begins_with("Ajudante contratado"), "aviso de contratação")
    _check(pad.get_grade_text() == "Grau 1/5" and pad.get_grade_shown() == 1, "grau 1 na plataforma")
    # Continua em cima: cobra a próxima graduação até o saldo acabar.
    _step_pad(5.0, true)
    _check(hiring.grade == 1 and hiring.paid == 50 and wallet.get_balance() == 0, "melhoria parcial 50/200")
    _check(pad.get_cost_text() == "150", "faltam 150: " + pad.get_cost_text())
    wallet.add(5000, &"test")
    _step_pad(120.0, true)
    _check(hiring.is_max() and pad.get_cost_text() == "Máximo", "grau máximo")
    _check(wallet.get_balance() == 5150 - 3100, "total 3100: saldo %d" % wallet.get_balance())
    _check(_step_pad(1.0, true) == 0, "no máximo não cobra")
    pad.finish_flights()
    for locale in [["es", "Ayudante", "Grado 5/5", "Máximo"], ["en", "Helper", "Grade 5/5", "Max"], ["pt_BR", "Ajudante", "Grau 5/5", "Máximo"]]:
        TranslationServer.set_locale(locale[0])
        await process_frame
        await process_frame
        _check(pad.get_title_text() == locale[1], "%s título %s" % [locale[0], pad.get_title_text()])
        _check(pad.get_grade_text() == locale[2], "%s grau %s" % [locale[0], pad.get_grade_text()])
        _check(pad.get_cost_text() == locale[3], "%s custo %s" % [locale[0], pad.get_cost_text()])
    print("HELPER_PAD_HIRING_OK first=%d grades=%s spent=3100 locales=pt_BR,es,en" % [first, grades])

## HIRE-FIX-001: 3 viagens de 7/7/7 fardos (mochila com 7 caixas). Cada fardo
## sai da mochila, voa até o ícone de material e o contador "n/20" sobe.
func _deliver_wood_in_trips(pad: HelperPad, hiring: HelperHiring) -> void:
    var inv := world.harvest_inventory
    var upc := inv.units_per_crate
    var log_before := pad.material_log.size()
    _check(pad.get_material_text() == "0/20", "contador inicial do material: " + pad.get_material_text())
    for trip in 3:
        inv.set_amount(&"wood", inv.get_capacity())
        _step_pad(0.2, false)
        # Um fardo por intervalo, não tudo de uma vez.
        _step_pad(HelperPad.START_DELAY + HelperPad.MATERIAL_INTERVAL * 1.5, true)
        var carried_after_one := inv.get_amount(&"wood")
        _check(carried_after_one == inv.get_capacity() - upc, "viagem %d: um fardo descarregado por vez (mochila %d)" % [trip, carried_after_one])
        _check(pad.get_material_flying_count() >= 1, "viagem %d: fardo voando até a plataforma" % trip)
        var last: Dictionary = pad.material_log[pad.material_log.size() - 1]
        _check(last["item"] == &"wood" and int(last["units"]) == upc, "viagem %d: voo registrado do fardo" % trip)
        _check((last["from"] as Vector3).y > (last["to"] as Vector3).y + 1.0, "viagem %d: fardo sai das costas e desce na plataforma" % trip)
        _step_pad(HelperPad.MATERIAL_INTERVAL * 8.0, true)
        # Deixa os voos pousarem (tweens reais) e confere o contador.
        await create_timer(HelperPad.MATERIAL_FLIGHT_TIME + 0.3).timeout
        await process_frame
        var landed := mini(20, (trip + 1) * 7)
        _check(pad.get_material_flying_count() == 0, "viagem %d: todos os fardos pousaram" % trip)
        if trip < 2:
            _check(pad.get_material_text() == "%d/20" % landed, "viagem %d: contador %s" % [trip, pad.get_material_text()])
            _check(hiring.material_units == landed * upc and hiring.grade == 0, "viagem %d: material guardado ao sair" % trip)
            _step_pad(1.0, false)
            _check(hiring.material_units == landed * upc, "viagem %d: sair da plataforma não devolve fardos" % trip)
    _check(pad.material_log.size() - log_before == 20, "20 fardos voaram: %d" % (pad.material_log.size() - log_before))
    print("HELPER_MATERIAL_UNLOAD_OK flights=%d trips=3 left_in_backpack=%d" % [pad.material_log.size() - log_before, inv.get_amount(&"wood") / upc])

func _test_pad_layout() -> void:
    var pad := world.helper_pad
    var plot := world.get_extra_plot_rect()
    var field := world.get_planting_area_rect()
    var r := pad.rect
    _check(is_equal_approx(r.size.y / r.size.x, HelperPad.SCREEN_STRETCH), "quadrada na tela")
    _check(r.position.y > plot.end.y and r.position.y - plot.end.y < 1.5, "logo antes da parcela (lado do balcão)")
    _check(absf(r.get_center().x - plot.get_center().x) < 0.01, "alinhada à parcela")
    _check(not r.intersects(field) and not r.intersects(plot.grow(TomatoPile.new().pickup_margin)), "não invade canteiro nem a pilha")
    var counter := world.sales_counter
    _check(counter.distance_to_counter(Vector3(r.get_center().x, 0, r.end.y)) > 4.0, "longe do balcão")
    var money := world.money_stack.global_position
    _check(not r.grow(1.0).has_point(Vector2(money.x, money.z)), "longe do dinheiro")
    for corner in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
        _check(not world.river_system.is_point_in_water(Vector3(corner.x, 0, corner.y), 2.0), "fora do rio")
    _check(absf(pad.global_position.y) < 0.1, "no chão")
    print("HELPER_PAD_LAYOUT_OK rect=%s plot_end_z=%.2f" % [r, plot.end.y])

func _test_harvest_and_stack() -> void:
    await _load_world(true)
    world.helper_hiring.set_grade(1)
    var helper := world.farm_helper
    var pile := world.tomato_pile
    _check(helper.get_capacity() == 8, "grau 1 carrega 1 caixa")
    var harvested := [0]
    helper.harvested.connect(func(_c: String, u: int) -> void: harvested[0] += u)
    for i in 400:
        helper.step_instant()
        _check(_accounted() == _initial_total, "invariante passo %d" % i)
        if helper.state == FarmHelper.WAIT_PILE:
            break
    pile.finish_jumps()
    _check(pile.is_full(), "pilha encheu: %d/%d" % [pile.get_stored_total(), pile.get_capacity()])
    _check(pile.get_crate_count() == TomatoPile.MAX_CRATES, "27 caixas na contagem lógica")
    # FV-POLISH-001: grade 3 x 3 por camada; cheia = bloco 3 x 3 x 3, todas visíveis e sem contador.
    _check(pile.grid_layout, "pilha do ajudante deveria estar em grade 3x3")
    _check(pile.get_visible_crate_count() == TomatoPile.MAX_CRATES, "pilha 3x3x3 com %d caixas visíveis" % pile.get_visible_crate_count())
    _check(pile.get_count_text() == "", "contador da pilha: '%s'" % pile.get_count_text())
    _check(helper.state == FarmHelper.WAIT_PILE and helper.carried > 0, "espera com a pilha cheia")
    var rect := world.get_extra_plot_rect()
    for index in TomatoPile.MAX_CRATES:
        var p := pile.to_global(pile._slot_local(index))
        _check(rect.has_point(Vector2(p.x, p.z)), "caixa %d dentro da parcela de 10%%" % index)
    var harvested_cells := 0
    for cell in world.planting_grid.cells.values():
        if cell["state"] == PlantingGrid.STATE_HARVESTED:
            harvested_cells += 1
    _check(harvested_cells > 0, "pés colhidos")
    print("HELPER_STACK_OK pile=%d crates=%d harvested=%d cells=%d" % [pile.get_stored_total(), pile.get_crate_count(), harvested[0], harvested_cells])

func _test_shared_lock_with_farmer() -> void:
    await _load_world(true)
    world.helper_hiring.set_grade(1)
    var helper := world.farm_helper
    var grid := world.planting_grid
    # O fazendeiro já está colhendo o pé mais próximo do ajudante.
    var nearest := helper._find_ripe()
    _check(grid.begin_harvest(nearest["id"]), "fazendeiro trava o pé")
    helper.step_instant()
    _check(helper.target_cell != nearest["id"], "ajudante escolhe outro pé")
    # O pé alvo é tomado pelo fazendeiro antes do ajudante chegar.
    var taken := helper.target_cell
    grid.begin_harvest(taken)
    helper.step_instant()
    _check(grid.cells[taken]["state"] == PlantingGrid.STATE_HARVESTING and grid.get_remaining_yield(taken) == 6, "ajudante não mexe no pé travado")
    print("HELPER_LOCK_OK")

func _test_farmer_picks_up_pile() -> void:
    await _load_world(true)
    world.helper_hiring.set_grade(3)
    var helper := world.farm_helper
    var pile := world.tomato_pile
    for i in 60:
        helper.step_instant()
        if pile.get_stored_total() >= 40:
            break
    pile.finish_jumps()
    var before := pile.get_stored_total()
    _check(before >= 40, "pilha com caixas: %d" % before)
    var on_plot := Vector3(pile.rect.get_center().x, 1.0, pile.rect.get_center().y)
    var off_plot := Vector3(pile.rect.position.x - 3.0, 1.0, pile.rect.get_center().y)
    _check(pile.process_farmer_position(off_plot, world.harvest_inventory) == 0, "fora da parcela não recolhe")
    var moved := 0
    for i in 20:
        pile._pickup_cooldown = 0.0
        moved += pile.process_farmer_position(on_plot, world.harvest_inventory, world.backpack.intake_marker)
        _check(_accounted() == _initial_total, "invariante na recolha %d" % i)
    _check(world.harvest_inventory.get_total() == mini(before, world.harvest_inventory.get_capacity()), "mochila recebeu %d" % world.harvest_inventory.get_total())
    _check(pile.get_stored_total() == before - moved, "pilha diminuiu")
    _check(world.hud.get_tomato_text().begins_with(str(world.harvest_inventory.get_total())), "HUD de tomates")
    # Depois, o fluxo de sempre: mochila -> balcão.
    var counter := world.sales_counter
    var deposited := counter.deposit_from(world.harvest_inventory)
    _check(deposited == moved and world.harvest_inventory.get_total() == 0, "balcão recebe a carga da pilha")
    print("HELPER_PICKUP_OK moved=%d pile_left=%d counter=%d" % [moved, pile.get_stored_total(), counter.get_stored_total()])

func _test_walking_cycle() -> void:
    await _load_world(true)
    world.helper_hiring.set_grade(1)
    var helper := world.farm_helper
    var pile := world.tomato_pile
    var start := helper.global_position
    var states: Dictionary = {}
    helper.state_changed.connect(func(s: StringName) -> void: states[s] = true)
    var dt := 1.0 / 30.0
    var seconds := 0.0
    var max_step := 0.0
    var last := helper.global_position
    while seconds < 60.0 and pile.get_stored_total() == 0:
        helper._process(dt)
        max_step = maxf(max_step, (helper.global_position - last).length())
        last = helper.global_position
        seconds += dt
    _check(pile.get_stored_total() == 8, "primeira viagem: 1 caixa (%d)" % pile.get_stored_total())
    _check(states.has(FarmHelper.TO_HARVEST) and states.has(FarmHelper.HARVESTING) and states.has(FarmHelper.TO_PILE), "estados percorridos %s" % [states.keys()])
    _check(max_step <= HelperConfig.walk_speed(1) * dt + 0.001, "anda sem teletransporte (%.3f)" % max_step)
    _check(start.distance_to(pile.get_drop_point() + Vector3(0, 0, 1.6)) < 0.5, "começa ao lado da pilha")
    print("HELPER_WALK_OK first_drop=%.1fs max_step=%.3f" % [seconds, max_step])

func _test_replant() -> void:
    await _load_world(false)
    world.helper_hiring.set_grade(2)
    var helper := world.farm_helper
    var counter := [0]
    helper.planted.connect(func(_c: String) -> void: counter[0] += 1)
    for i in 12:
        helper.step_instant()
    var planted: int = counter[0]
    var seeded := 0
    for cell in world.planting_grid.cells.values():
        if cell["state"] == "SEEDED":
            seeded += 1
    _check(planted >= 3 and seeded == planted, "ajudante semeia covas vazias: %d/%d" % [planted, seeded])
    # Punhado sai das mãos do ajudante e o broto nasce ao pousar.
    await create_timer(2.5).timeout
    # O ajudante continua semeando durante a espera: compara com as covas atuais.
    helper.set_process(false)
    await create_timer(1.0).timeout
    planted = counter[0]
    var sprouts := 0
    for crop in world.crops.values():
        if is_instance_valid(crop):
            sprouts += 1
    _check(sprouts == planted, "brotos nascem: %d" % sprouts)
    print("HELPER_REPLANT_OK planted=%d sprouts=%d" % [planted, sprouts])
