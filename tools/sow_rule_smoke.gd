extends SceneTree
## FARM-005/006: ciclo da semeadura. Plantando: pode semear o terreno todo.
## Colhendo (começou a colheita em algum cultivo): ninguém semeia (fazendeiro
## nem ajudante). Tudo colhido, em todos os cultivos: reabre e semeia de novo.
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
    # 1) Plantando: pode semear o terreno todo, mesmo com pés já maduros.
    var ripe_id := _first_cell(corn, "EMPTY")
    _check(corn.plant_cell(ripe_id), "semeia o milho")
    corn.mark_ripe(ripe_id, 3)
    _check(world.can_sow(), "plantando: pé maduro não trava a semeadura")
    for grid in [tomato, corn, pumpkin]:
        var g := grid as PlantingGrid
        var planted := 0
        for cell in g.cells.values():
            if cell["state"] == "EMPTY" and g.plant_cell(String(cell["id"])):
                planted += 1
        _check(planted > 0 and g.get_next_unplanted_cell().is_empty(), "plantando: %s não semeou o terreno todo (%d)" % [g.crop_id, planted])
    # 2) Colhendo: começou a colheita, ninguém semeia.
    _check(corn.begin_harvest(ripe_id), "começa a colher")
    _check(world.harvest_phase and not world.can_sow(), "colhendo: deveria travar a semeadura")
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
    # 3) Colhe tudo (todos os cultivos): as covas reabrem e pode semear de novo.
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
        if grid != pumpkin:
            _check(not world.can_sow(), "ainda falta colher a abóbora")
    await process_frame
    _check(world.can_sow() and not world.harvest_phase, "tudo colhido: deveria poder semear")
    for grid in [tomato, corn, pumpkin]:
        var g := grid as PlantingGrid
        _check(not g.get_next_unplanted_cell().is_empty() and not g.has_pending_crop(), "%s não reabriu" % g.crop_id)
        var again := 0
        for cell in g.cells.values():
            if g.plant_cell(String(cell["id"])):
                again += 1
        _check(again == g.cells.size(), "%s: semeou de novo %d de %d" % [g.crop_id, again, g.cells.size()])
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("SOW_RULE_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("SOW_RULE_SMOKE_OK")
    quit()
