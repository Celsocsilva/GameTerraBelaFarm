extends SceneTree
## FARM-005/006 + SOW-CYCLE-002: ciclo da semeadura POR CULTIVO. Plantando:
## pode semear o canteiro todo. Colhendo (começou a colheita naquele cultivo):
## ninguém semeia nele (fazendeiro nem ajudante). Tudo colhido naquele cultivo:
## reabre e semeia de novo, mesmo com outro cultivo ainda crescendo.
##   godot --headless --path . -s tools/sow_rule_smoke.gd

var _failures := 0
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures += 1
        push_error("SOW_RULE_FAIL: " + message)

func _first_cell(grid: PlantingGrid, state: String) -> String:
    for cell in grid.cells.values():
        if cell["state"] == state:
            return String(cell["id"])
    return ""

## SOW-CYCLE-004 (regra do Celso para TODOS os cultivos): semear -> desenvolver
## -> amadurecer -> colher tudo -> só então reinicia. Para cada cultivo: semeia
## parte do canteiro, as plantas começam a crescer e a semeadura para; daí em
## diante nenhuma cova vazia recebe semente (fazendeiro andando, plant_cell
## direto, ajudante), nem com colheita parcial em várias viagens; colhido tudo,
## reabre e semeia de novo.
func _test_strict_cycle_all_crops() -> void:
    var w := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(w)
    await process_frame
    w.set_process(false)
    for crop in [&"tomato", &"corn", &"pumpkin"]:
        var g := w.get_crop_grid(crop)
        var ids: Array[String] = []
        for cell in g.cells.values():
            ids.append(String(cell["id"]))
        ids.sort()
        var half := ids.size() / 2
        for i in half:
            _check(g.plant_cell(ids[i]), "%s: semeia a 1ª metade" % crop)
        _check(g.can_sow(), "%s: semeando, ainda pode semear" % crop)
        # As plantas começam a se desenvolver e a semeadura parou há mais de 3 s.
        w._on_crop_stage_changed(ids[0], CropPlant.STAGES[1])
        w._last_sow_by_grid[g] = Time.get_ticks_msec() / 1000.0 - FarmWorld.SOW_SESSION_GRACE - 1.0
        _check(not g.can_sow(), "%s: plantas crescendo deveriam fechar a semeadura" % crop)
        _check(not g.plant_cell(ids[half]), "%s: semeou cova vazia com plantas crescendo" % crop)
        var pos := g.get_cell_world_position(ids[ids.size() - 1])
        for k in 8:
            g.process_farmer_position(pos + Vector3(0.0, 0.0, -0.4 * k), 0.4, Vector3(0.0, 0.0, 1.0))
        _check(g.get_planting_progress()["planted"] == half, "%s: fazendeiro andando semeou (%d plantadas)" % [crop, g.get_planting_progress()["planted"]])
        var helper: FarmHelper = w.farm_helper if crop == &"tomato" else w.crop_helpers.get(crop) as FarmHelper
        if helper:
            helper.carried = 0
            helper._choose_task()
            _check(helper.state != FarmHelper.TO_PLANT, "%s: ajudante foi semear com plantas crescendo" % crop)
        # Amadurece tudo; colhe em várias viagens (parcial deixa o pé maduro).
        for i in half:
            g.mark_ripe(ids[i], 4)
        g.begin_harvest(ids[0])
        g.consume_yield(ids[0], 2)
        g.finish_harvest(ids[0])
        await process_frame
        _check(g.cells[ids[0]]["state"] == PlantingGrid.STATE_RIPE and not g.can_sow(), "%s: colheita parcial não libera" % crop)
        for i in half:
            g.begin_harvest(ids[i])
            g.consume_yield(ids[i], g.get_remaining_yield(ids[i]))
            g.finish_harvest(ids[i])
            if i < half - 1:
                _check(not g.can_sow(), "%s: liberou antes de colher tudo (%d/%d)" % [crop, i + 1, half])
        await process_frame
        _check(g.can_sow() and g.get_planting_progress()["planted"] == 0, "%s: tudo colhido deveria reabrir" % crop)
        var again := 0
        for id in ids:
            if g.plant_cell(id):
                again += 1
        _check(again == ids.size(), "%s: novo ciclo semeou %d de %d" % [crop, again, ids.size()])
    w.queue_free()
    await process_frame
    print("SOW_STRICT_CYCLE_OK crops=tomato,corn,pumpkin")

func _run() -> void:
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    var tomato := world.get_crop_grid(&"tomato")
    var corn := world.get_crop_grid(&"corn")
    var pumpkin := world.get_crop_grid(&"pumpkin")
    _check(tomato != null and corn != null and pumpkin != null, "grades de tomate, milho e abóbora")
    _check(world.can_sow(), "no começo pode semear")
    # 1) Plantando: pode semear o terreno todo enquanto nenhum pé amadureceu.
    #    SOW-CYCLE-003: o primeiro pé MADURO fecha a semeadura daquele cultivo.
    for grid in [tomato, corn, pumpkin]:
        var g := grid as PlantingGrid
        var planted := 0
        for cell in g.cells.values():
            if cell["state"] == "EMPTY" and g.plant_cell(String(cell["id"])):
                planted += 1
        _check(planted > 0 and g.get_next_unplanted_cell().is_empty(), "plantando: %s não semeou o terreno todo (%d)" % [g.crop_id, planted])
    # Pé maduro com covas ainda vazias: não semeia mais nada até colher tudo.
    var ripe_id := _first_cell(corn, "SEEDED")
    var empty_tomato := _first_cell(tomato, "SEEDED")
    tomato.cells[empty_tomato]["state"] = "EMPTY"
    var tomato_ripe := _first_cell(tomato, "SEEDED")
    tomato.mark_ripe(tomato_ripe, 3)
    _check(world.is_harvest_phase(tomato) and not tomato.can_sow(), "pé maduro deveria travar a semeadura do tomate")
    _check(not tomato.plant_cell(empty_tomato), "semeou cova vazia com pé maduro por colher")
    _check(corn.can_sow(), "tomate maduro não trava o milho")
    tomato.begin_harvest(tomato_ripe)
    tomato.consume_yield(tomato_ripe, 3)
    tomato.finish_harvest(tomato_ripe)
    corn.mark_ripe(ripe_id, 3)
    # 2) Colhendo: começou a colheita, ninguém semeia.
    _check(corn.begin_harvest(ripe_id), "começa a colher")
    _check(world.harvest_phase and not corn.can_sow(), "colhendo: deveria travar a semeadura do milho")
    _check(pumpkin.can_sow() and not tomato.can_sow(), "colher milho não trava a abóbora (tomate segue travado com pés por colher)")
    corn.consume_yield(ripe_id, 3)
    corn.finish_harvest(ripe_id)
    await process_frame
    _check(corn.cells[ripe_id]["state"] == PlantingGrid.STATE_HARVESTED, "cova colhida não deveria reabrir com o resto por colher")
    _check(not corn.plant_cell(ripe_id), "colhendo: semeou a cova colhida")
    var cell_pos := corn.get_cell_world_position(ripe_id)
    for i in 6:
        corn.process_farmer_position(cell_pos + Vector3(0.0, 0.0, -0.3 * i), 0.4)
    _check(corn.cells[ripe_id]["state"] == PlantingGrid.STATE_HARVESTED, "colhendo: fazendeiro semeou")
    if world.farm_helper:
        world.farm_helper.carried = 0
        world.farm_helper._choose_task()
        _check(world.farm_helper.state != FarmHelper.TO_PLANT, "colhendo: ajudante foi replantar")
    # 3) Colhe o tomate por completo: o tomate reabre e semeia de novo mesmo
    #    com milho e abóbora ainda por colher (um cultivo não trava o outro).
    for grid in [tomato, corn, pumpkin]:
        var g := grid as PlantingGrid
        for cell in g.cells.values():
            var id := String(cell["id"])
            if cell["state"] == "SEEDED":
                g.mark_ripe(id, 1)
            if g.cells[id]["state"] == PlantingGrid.STATE_RIPE:
                g.begin_harvest(id)
                g.consume_yield(id, g.get_remaining_yield(id))
                g.finish_harvest(id)
        await process_frame
        _check(g.can_sow() and not world.is_harvest_phase(g), "%s colhido: deveria poder semear" % g.crop_id)
        _check(not g.get_next_unplanted_cell().is_empty() and not g.has_pending_crop(), "%s não reabriu" % g.crop_id)
        if grid == tomato:
            _check(not corn.can_sow(), "tomate colhido não destrava o milho ainda por colher")
            var t_again := 0
            for cell in g.cells.values():
                if g.plant_cell(String(cell["id"])):
                    t_again += 1
            _check(t_again == g.cells.size(), "tomate: semeou de novo %d de %d com milho pendente" % [t_again, g.cells.size()])
    _check(world.can_sow() and not world.harvest_phase, "tudo colhido: deveria poder semear")
    for grid in [corn, pumpkin]:
        var g := grid as PlantingGrid
        var again := 0
        for cell in g.cells.values():
            if g.plant_cell(String(cell["id"])):
                again += 1
        _check(again == g.cells.size(), "%s: semeou de novo %d de %d" % [g.crop_id, again, g.cells.size()])
    # 4) Segundo ciclo do tomate: colhe de novo por completo e replanta (ciclo repete).
    for cell in tomato.cells.values():
        var id := String(cell["id"])
        tomato.mark_ripe(id, 1)
        tomato.begin_harvest(id)
        tomato.consume_yield(id, 1)
        tomato.finish_harvest(id)
    await process_frame
    var third := 0
    for cell in tomato.cells.values():
        if tomato.plant_cell(String(cell["id"])):
            third += 1
    _check(third == tomato.cells.size(), "tomate 2º ciclo: semeou %d de %d" % [third, tomato.cells.size()])
    world.queue_free()
    await process_frame
    await _test_strict_cycle_all_crops()
    if _failures > 0:
        print("SOW_RULE_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("SOW_RULE_SMOKE_OK")
    quit()
