extends SceneTree
## FARM-005 (10/11): caminhos de terra, construções da biblioteca e folga da
## vegetação em volta das áreas de cultivo.
##   godot --headless --path . -s tools/farm005_smoke.gd

var _failures := 0
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures += 1
        push_error("FARM005_FAIL: " + message)

func _run() -> void:
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    var fields := world.get_crop_field_rects()
    var stocks: Array[Rect2] = [world.get_extra_plot_rect()]
    for entry in world.crop_areas:
        stocks.append(entry["stock"] as Rect2)
    var map := world.get_map_rect()
    var bridges: Array[Vector2] = []
    for bridge in world.river_system.get_bridges():
        bridges.append(Vector2(bridge.global_position.x, bridge.global_position.z))
    # Caminhos: dentro do mapa, fora dos canteiros, das pilhas, da água (só
    # atravessam o rio pelas pontes) e das construções.
    var paths := world.farm_paths
    _check(paths != null and paths.samples.size() == FarmWorld.PATH_ROUTES.size(), "caminhos não foram montados")
    var total := 0.0
    for index in paths.samples.size():
        var line := paths.samples[index]
        var label := String(paths.routes[index]["name"])
        for i in line.size():
            var p := line[i]
            if i > 0:
                total += line[i - 1].distance_to(p)
            _check(map.has_point(p), "caminho %s fora do mapa: %s" % [label, p])
            for field in fields:
                _check(not field.has_point(p), "caminho %s em cima de canteiro: %s" % [label, p])
            for stock in stocks:
                _check(not stock.has_point(p), "caminho %s em cima da pilha: %s" % [label, p])
            var on_bridge := false
            for b in bridges:
                on_bridge = on_bridge or b.distance_to(p) < 6.5
            _check(on_bridge or not world.river_system.is_point_in_water(Vector3(p.x, 0.0, p.y), 0.3), "caminho %s no rio: %s" % [label, p])
            # O caminho chega até a frente da construção (base), não passa por baixo dela.
            for spec in FarmWorld.BUILDINGS:
                var art := FarmBuildings.get_art_rect(spec[2], float(spec[3]))
                var base: Vector2 = spec[2]
                _check(not art.has_point(p) or p.distance_to(base) < 1.6, "caminho %s por baixo de %s: %s" % [label, spec[0], p])
    _check(total > 250.0, "caminhos curtos demais: %.0f m" % total)
    # Construções: 5 artes da biblioteca, longe dos canteiros, rio, curral e casa.
    var b := world.farm_buildings
    _check(b.buildings.size() == 5, "construções: %d" % b.buildings.size())
    var arts := b.get_art_rects()
    for i in arts.size():
        var art := arts[i]
        var name := String(FarmWorld.BUILDINGS[i][0])
        _check(ResourceLoader.exists(String(FarmWorld.BUILDINGS[i][1])), "%s sem arte" % name)
        _check(map.grow(-1.0).encloses(art), "%s fora do mapa" % name)
        for field in fields:
            _check(not field.grow(3.0).intersects(art), "%s perto demais de um canteiro" % name)
        _check(not CowPen.get_surroundings_rect(world.COW_PEN_RECT).intersects(art), "%s no curral" % name)
        _check(not world.get_farmhouse_rect().intersects(art), "%s em cima da casa" % name)
        for j in arts.size():
            _check(i == j or not art.intersects(arts[j]), "%s em cima de outra construção" % name)
        for x in range(int(art.position.x), int(art.end.x) + 1):
            for z in range(int(art.position.y), int(art.end.y) + 1):
                _check(not world.river_system.is_point_in_water(Vector3(x, 0.0, z), 0.5), "%s no rio" % name)
        for bridge in bridges:
            _check(not art.grow(4.0).has_point(bridge), "%s colada numa ponte" % name)
    # Vegetação: nada dentro da folga dos canteiros nem em cima dos caminhos.
    var points: Array[Vector2] = []
    for tree in world.eucalyptus_grove.trees:
        points.append(Vector2(tree.position.x, tree.position.z))
    for p in world.border_forest.points:
        points.append(Vector2(p.x, p.z))
    for entry in world.cozy_environment.placements:
        var pos: Vector3 = entry["position"]
        points.append(Vector2(pos.x, pos.z))
    for kind in ["pine", "bush"]:
        for p in world.cow_pen.get_surroundings_points(kind):
            points.append(Vector2(p.x, p.z))
    var clear := FarmWorld.CROP_CLEARANCE
    for p in points:
        for field in fields:
            _check(not field.grow_individual(clear.x, clear.y, clear.x, FarmWorld.CROP_CLEARANCE_FRONT).has_point(p), "vegetação colada num canteiro: %s" % p)
        for stock in stocks:
            _check(not stock.grow(FarmWorld.CROP_STOCK_CLEARANCE).has_point(p), "vegetação colada na pilha: %s" % p)
        _check(not paths.is_near(p, 0.2), "vegetação em cima de caminho: %s" % p)
        for art in arts:
            _check(not art.has_point(p), "vegetação dentro de construção: %s" % p)
    print("FARM005_OK paths=%d length=%.0fm buildings=%d decor=%d" % [paths.samples.size(), total, b.buildings.size(), points.size()])
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("FARM005_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("FARM005_SMOKE_OK")
    quit()
