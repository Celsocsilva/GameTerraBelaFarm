extends SceneTree
## FV-STACK-001 — uma única pilha de caixas por cultura no balcão e na parcela de 10%.
## Uso: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/crate_stack_smoke.gd
## Confere: pilha vertical única com altura visual limitada, contador "xN" acima
## do limite, contagem lógica correta, pilha dentro do balcão/parcela, vagas
## das culturas sem sobreposição e pulos com mais caixas que o limite visual.

var _failed := false

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failed = true
        push_error("CRATE_STACK_SMOKE_FAIL " + message)
        print("CRATE_STACK_SMOKE_FAIL ", message)

func _run() -> void:
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    _test_counter(world)
    await _test_counter_jumps(world)
    _test_pile(world)
    if _failed:
        print("CRATE_STACK_SMOKE_FAIL")
        quit(1)
        return
    print("CRATE_STACK_SMOKE_OK")
    quit(0)

func _test_counter(world: FarmWorld) -> void:
    var counter := world.sales_counter
    var units := counter.units_per_crate
    var half := counter.get_half_extents()
    counter.set_stored_total(15 * units)
    _check(counter.get_stock_crates() == 15 and counter.get_displayed_crates() == 15, "contagem lógica 15: %d" % counter.get_displayed_crates())
    _check(counter.get_visible_crate_count() == SalesCounter.MAX_VISUAL_CRATES, "pilha visual limitada: %d" % counter.get_visible_crate_count())
    _check(counter.get_count_text() == "x15", "contador '%s'" % counter.get_count_text())
    _check(counter.get_count_label().visible, "contador visível")
    var base := counter.get_crate_slot_position(0) - counter.global_position
    for index in 15:
        var slot := counter.get_crate_slot_position(index) - counter.global_position
        _check(is_equal_approx(slot.x, base.x), "caixa %d fora da pilha única (x %.2f)" % [index, slot.x])
        _check(absf(slot.z) <= half.y, "caixa %d fora do fundo do balcão" % index)
    _check(counter.get_crate_slot_position(14).is_equal_approx(counter.get_crate_slot_position(SalesCounter.MAX_VISUAL_CRATES - 1)), "caixas extras não pousam no topo")
    var label_y := counter.get_count_label().position.y
    _check(label_y > (counter.get_crate_slot_position(SalesCounter.MAX_VISUAL_CRATES - 1) - counter.global_position).y, "contador abaixo do topo")
    # Vagas dos 3 cultivos + madeira: dentro do balcão e sem sobrepor.
    var xs: Array[float] = []
    for item in [&"corn", &"tomato", &"pumpkin", &"wood"]:
        var x: float = SalesCounter.ITEM_SLOT_X[item]
        _check(absf(x) + SalesCounter.CRATE_WIDTH * 0.5 <= half.x, "pilha de %s estoura o balcão" % item)
        for other in xs:
            _check(absf(x - other) >= SalesCounter.CRATE_WIDTH + 0.1, "pilhas sobrepostas (%s)" % item)
        xs.append(x)
    # Venda: contagem lógica cai e o contador some no limite.
    _check(counter.take_units(11 * units) == 11 * units, "take_units")
    _check(counter.get_stock_crates() == 4 and counter.get_visible_crate_count() == 4, "4 caixas depois da venda")
    _check(counter.get_count_text() == "" and not counter.get_count_label().visible, "contador deveria sumir com 4 caixas")
    counter.set_stored_total(2 * units + 3)
    _check(counter.get_visible_crate_count() == 3 and counter.get_crate_texture(2) == SalesCounter.CRATE_EMPTY_TEXTURE, "caixa parcial no topo")
    counter.set_stored_total(0)
    _check(counter.get_visible_crate_count() == 0 and counter.get_count_text() == "", "balcão vazio")
    print("COUNTER_STACK visual_max=%d x=%.2f base_y=%.2f label_y=%.2f slots=%s" % [SalesCounter.MAX_VISUAL_CRATES, base.x, base.y, label_y, xs])

func _test_counter_jumps(world: FarmWorld) -> void:
    var counter := world.sales_counter
    counter.set_stored_total(2 * counter.units_per_crate)
    world.harvest_inventory.set_amount(&"tomato", 5 * counter.units_per_crate)
    counter.deposit_from(world.harvest_inventory, world.get_farmer_hands_position())
    _check(counter.get_displayed_crates() == 7, "7 caixas lógicas: %d" % counter.get_displayed_crates())
    _check(counter.get_flying_crate_count() == 5, "5 caixas pulando: %d" % counter.get_flying_crate_count())
    var waited := 0.0
    while counter.get_flying_crate_count() > 0 and waited < 4.0:
        await process_frame
        waited += 1.0 / 60.0
        await create_timer(1.0 / 60.0).timeout
    _check(counter.get_flying_crate_count() == 0, "pulos não terminaram")
    _check(counter.get_visible_crate_count() == SalesCounter.MAX_VISUAL_CRATES, "depois dos pulos: %d visíveis" % counter.get_visible_crate_count())
    _check(counter.get_count_text() == "x7", "contador depois dos pulos '%s'" % counter.get_count_text())
    print("COUNTER_STACK_JUMPS crates=7 visible=%d waited=%.2fs" % [counter.get_visible_crate_count(), waited])

## FV-POLISH-001: a parcela do ajudante empilha em grade 3 colunas x 3
## fileiras por camada, camadas para cima; 27 caixas = bloco 3 x 3 x 3.
func _test_pile(world: FarmWorld) -> void:
    var pile := world.tomato_pile
    var units := pile.units_per_crate
    var rect := world.get_extra_plot_rect()
    _check(pile.grid_layout, "parcela deveria usar a grade 3x3")
    pile.set_stored_total(TomatoPile.MAX_CRATES * units)
    _check(pile.get_crate_count() == TomatoPile.MAX_CRATES, "parcela 27 caixas lógicas")
    _check(pile.get_visible_crate_count() == TomatoPile.MAX_CRATES, "parcela: %d visíveis" % pile.get_visible_crate_count())
    _check(pile.get_count_text() == "", "contador da parcela '%s'" % pile.get_count_text())
    var xs := {}
    var zs := {}
    var ys := {}
    for index in TomatoPile.MAX_CRATES:
        var local := pile.get_slot_local(index)
        xs[snappedf(local.x, 0.01)] = true
        zs[snappedf(local.z - floorf(index / 9.0) * 0.03, 0.01)] = true
        ys[snappedf(local.y, 0.01)] = true
        var p := pile.to_global(local)
        _check(rect.has_point(Vector2(p.x, p.z)), "parcela: caixa %d fora da parcela" % index)
        _check(p.x - pile.crate_width * 0.5 >= rect.position.x - 0.2 and p.x + pile.crate_width * 0.5 <= rect.end.x + 0.2, "parcela: caixa %d passa da borda" % index)
    _check(xs.size() == 3 and zs.size() == 3 and ys.size() == 3, "grade 3x3x3: colunas=%d fileiras=%d camadas=%d" % [xs.size(), zs.size(), ys.size()])
    # A última caixa (a recolhida primeiro) está na camada de cima.
    _check(pile.get_slot_local(TomatoPile.MAX_CRATES - 1).y >= pile.get_slot_local(0).y + 0.01, "topo da pilha")
    _check(pile.take_units(23 * units) == 23 * units and pile.get_crate_count() == 4, "parcela depois de recolher")
    _check(pile.get_visible_crate_count() == 4 and pile.get_count_text() == "", "parcela com 4 caixas sem contador")
    pile.set_stored_total(0)
    print("PILE_GRID columns=%d rows=%d layers=%d capacity=%d" % [xs.size(), zs.size(), ys.size(), TomatoPile.MAX_CRATES])
