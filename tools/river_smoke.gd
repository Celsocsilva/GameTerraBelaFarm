extends SceneTree
## ENV-002 — QA headless do rio e das pontes. Sai com 1 em qualquer falha.
##
##   godot --headless --path . -s tools/river_smoke.gd
##
## A: continuidade do curso | B/C: travessia das pontes (ida e volta, física
## real, entrada por teclado) | D: bloqueio pela água fora das pontes |
## E: integração (decoração, plantio, HUD, câmera, joystick, balcão) |
## G: expansão por add_segment sem reconstruir | H: contagens e tempo de setup.

const MAX_SECONDS_PER_LEG := 12.0
const STUCK_SECONDS := 1.5

var failures := 0
var world: FarmWorld
var river: RiverSystem

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error("RIVER_SMOKE_FAIL " + message)

func _run() -> void:
    var started := Time.get_ticks_usec()
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    var setup_ms := (Time.get_ticks_usec() - started) / 1000.0
    world.set_process(false)
    world.harvest_controller.enabled = false
    river = world.river_system
    _check(river != null, "RiverSystem missing from FarmWorld")
    if river == null:
        quit(1)
        return
    _test_structure()
    _test_continuity()
    await _test_bridge("wood")
    await _test_bridge("stone")
    await _test_water_blocks()
    _test_integration()
    _test_expansion()
    _test_performance(setup_ms)
    if failures == 0:
        print("RIVER_SMOKE_OK segments=", river.segments.size(), " bridges=", river.get_bridges().size())
    quit(0 if failures == 0 else 1)

func _test_structure() -> void:
    for child in ["RiverSegments", "RiverBanks", "WaterSurface", "BridgeWood", "BridgeStone", "RiverCollisions"]:
        _check(river.get_node_or_null(child) != null, "RiverSystem child missing: " + child)
    _check(river.get_bridges().size() == 2, "Expected two bridges")

## Teste A — curso contínuo: cada entrada encontra a saída anterior.
func _test_continuity() -> void:
    var max_gap := 0.0
    var max_width_delta := 0.0
    for i in range(1, river.segments.size()):
        var previous: Dictionary = river.segments[i - 1]
        var segment: Dictionary = river.segments[i]
        _check(RiverSystem.OPPOSITE[previous["exit"]] == segment["entry"], "Segment %d entry does not face previous exit" % i)
        var expected: Vector3 = (previous["exit_point"] as Vector3) - (RiverSystem.FLOW[previous["exit"]] as Vector3) * river.junction_overlap
        var gap := expected.distance_to(segment["entry_point"])
        max_gap = maxf(max_gap, gap)
        max_width_delta = maxf(max_width_delta, absf(float(previous["exit_width"]) - float(segment["entry_width"])))
        _check(segment.has("junction_node"), "Junction patch missing at segment %d" % i)
        # A água dos dois tiles se sobrepõe: o ponto da junção é água em ambos.
        _check(river.is_point_in_water(river.to_global(previous["exit_point"] - (RiverSystem.FLOW[previous["exit"]] as Vector3) * 0.3)), "No water before junction %d" % i)
        _check(river.is_point_in_water(river.to_global(segment["entry_point"] + (RiverSystem.FLOW[previous["exit"]] as Vector3) * 0.3)), "No water after junction %d" % i)
    _check(max_gap < 0.001, "Junction gap %.4f m" % max_gap)
    _check(max_width_delta < 0.001, "Junction width mismatch %.4f m" % max_width_delta)
    # Amostragem densa da linha central: toda ela precisa cair na água.
    var samples := 0
    var dry := 0
    for segment in river.segments:
        for point in river.get_segment_centerline(segment, 24):
            samples += 1
            if not river.is_point_in_water(river.to_global(point), 0.25):
                dry += 1
    _check(dry == 0, "Centerline outside water at %d/%d samples" % [dry, samples])
    var first: Dictionary = river.segments[0]
    var last: Dictionary = river.segments[river.segments.size() - 1]
    var edge := world.farm_size * 0.5
    _check(absf(absf((first["entry_point"] as Vector3).x) - edge) < 0.05, "River does not start at the map edge")
    _check(absf(absf((last["exit_point"] as Vector3).x) - edge) < 0.05, "River does not end at the map edge")
    print("RIVER_A_CONTINUITY segments=", river.segments.size(), " junctions=", river.segments.size() - 1,
        " max_gap_m=", snappedf(max_gap, 0.0001), " max_width_delta_m=", snappedf(max_width_delta, 0.0001),
        " centerline_samples=", samples, " dry=", dry)

func _bridge(id: String) -> RiverBridge:
    for bridge in river.get_bridges():
        if bridge.bridge_id == id:
            return bridge
    return null

func _press(direction: Vector2) -> void:
    for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
        Input.action_release(action)
    if direction.length() < 0.01:
        return
    if direction.x > 0.0:
        Input.action_press("ui_right", direction.x)
    elif direction.x < 0.0:
        Input.action_press("ui_left", -direction.x)
    if direction.y > 0.0:
        Input.action_press("ui_down", direction.y)
    elif direction.y < 0.0:
        Input.action_press("ui_up", -direction.y)

## Caminha por waypoints com a entrada de teclado do jogo. Retorna estatísticas.
func _walk(points: PackedVector3Array) -> Dictionary:
    var farmer := world.farmer
    var index := 0
    var elapsed := 0.0
    var stuck := 0.0
    var last := farmer.global_position
    var max_y := -INF
    var min_y := INF
    var wet := 0
    var frames := 0
    var max_step := 0.0
    var dt := 1.0 / Engine.physics_ticks_per_second
    while index < points.size() and elapsed < MAX_SECONDS_PER_LEG:
        var target := points[index]
        var pos := farmer.global_position
        var delta := Vector2(target.x - pos.x, target.z - pos.z)
        if delta.length() < 0.3:
            index += 1
            continue
        _press(delta.normalized())
        await physics_frame
        elapsed += dt
        frames += 1
        var now := farmer.global_position
        max_step = maxf(max_step, absf(now.y - pos.y))
        max_y = maxf(max_y, now.y)
        min_y = minf(min_y, now.y)
        # Sobre a água só é permitido estar em cima do tabuleiro (y > 0).
        if river.is_point_in_water(Vector3(now.x, 0.0, now.z)) and now.y < 0.05:
            wet += 1
        if now.distance_to(last) < 0.01:
            stuck += dt
        else:
            stuck = 0.0
        last = now
        if stuck > STUCK_SECONDS:
            break
    _press(Vector2.ZERO)
    for i in 10:
        await physics_frame
    return {"reached": index >= points.size(), "seconds": elapsed, "stuck": stuck > STUCK_SECONDS,
        "max_y": max_y, "min_y": min_y, "wet_frames": wet, "frames": frames, "max_step": max_step,
        "end": farmer.global_position}

## Testes B e C — travessia completa nos dois sentidos.
func _test_bridge(id: String) -> void:
    var bridge := _bridge(id)
    _check(bridge != null, "Bridge missing: " + id)
    if bridge == null:
        return
    var line := bridge.get_centerline_global(24)
    var west := line[0]
    var east := line[line.size() - 1]
    var dir := Vector3(east.x - west.x, 0.0, east.z - west.z).normalized()
    # Entra pelo caminho do acesso oeste, cruza e sai pelo acesso leste.
    var west_path := bridge.get_approach_path_global(false)
    var east_path := bridge.get_approach_path_global(true)
    var path := PackedVector3Array()
    for i in range(west_path.size() - 1, -1, -1):
        path.append(west_path[i])
    path.append_array(line)
    path.append_array(east_path)
    var farmer := world.farmer
    farmer.velocity = Vector3.ZERO
    var start := path[0] + (path[0] - path[1]).normalized() * 1.0
    farmer.global_position = Vector3(start.x, 0.05, start.z)
    for i in 10:
        await physics_frame
    var forward := await _walk(path)
    path.reverse()
    var back := await _walk(path)
    for result in [forward, back]:
        _check(result["reached"], "%s bridge: crossing not completed (stuck=%s, end=%s)" % [id, result["stuck"], result["end"]])
        _check(result["wet_frames"] == 0, "%s bridge: farmer over water below deck in %d frames" % [id, result["wet_frames"]])
        _check(float(result["min_y"]) > -0.05, "%s bridge: farmer sank (min y %.3f)" % [id, result["min_y"]])
        _check(float(result["max_y"]) > bridge.arch_height * 0.6, "%s bridge: did not climb the arch (max y %.3f)" % [id, result["max_y"]])
        _check(float(result["max_y"]) < bridge.arch_height + 0.15, "%s bridge: floated above deck (max y %.3f)" % [id, result["max_y"]])
        _check(float(result["max_step"]) < 0.08, "%s bridge: abrupt height step %.3f" % [id, result["max_step"]])
    var letter := "B" if id == "wood" else "C"
    print("RIVER_%s_%s_BRIDGE forward_s=%.2f back_s=%.2f max_y=%.3f min_y=%.3f max_step=%.3f wet_frames=%d stuck=%s" % [
        letter, id.to_upper(), forward["seconds"], back["seconds"], maxf(forward["max_y"], back["max_y"]),
        minf(forward["min_y"], back["min_y"]), maxf(forward["max_step"], back["max_step"]),
        int(forward["wet_frames"]) + int(back["wet_frames"]), bool(forward["stuck"]) or bool(back["stuck"])])

## Teste D — sem ponte, a água bloqueia; o fazendeiro fica na margem de origem.
func _test_water_blocks() -> void:
    var attempts := [
        # [início, direção, descrição]
        [Vector3(-10.6, 0.05, -13.8), Vector2(-1, 0), "vertical leste->oeste z=-13.8"],
        [Vector3(-10.6, 0.05, -4.2), Vector2(-1, 0), "vertical leste->oeste entre as pontes"],
        [Vector3(-10.6, 0.05, -3.45), Vector2(-1, 0), "ao longo da junção reta/reta z=-3.45"],
        [Vector3(-10.6, 0.05, 6.9), Vector2(-1, 0), "ao longo da junção reta/curva z=6.9"],
        [Vector3(-20.66, 0.05, -15.0), Vector2(0, -1), "ao longo da junção braço norte/curva x=-20.66"],
        [Vector3(-18.5, 0.05, -3.6), Vector2(1, 0), "vertical oeste->leste z=-3.6"],
        [Vector3(-26.0, 0.05, -15.0), Vector2(0, -1), "braço norte sul->norte"],
        [Vector3(-26.0, 0.05, -27.0), Vector2(0, 1), "braço norte norte->sul"],
        [Vector3(-25.0, 0.05, 1.0), Vector2(0, 1), "curva sul norte->sul"],
        [Vector3(-23.0, 0.05, 19.0), Vector2(0, -1), "curva sul sul->norte"],
    ]
    var farmer := world.farmer
    var blocked := 0
    for attempt in attempts:
        var start: Vector3 = attempt[0]
        var direction: Vector2 = (attempt[1] as Vector2).normalized()
        _check(not river.is_point_in_water(start, 0.5), "Test D start is in water: " + str(attempt[2]))
        farmer.velocity = Vector3.ZERO
        farmer.global_position = start
        for i in 5:
            await physics_frame
        var wet := 0
        for i in 240:
            _press(direction)
            await physics_frame
            var now := farmer.global_position
            if river.is_point_in_water(Vector3(now.x, 0.0, now.z)) and now.y < 0.05:
                wet += 1
        _press(Vector2.ZERO)
        var end := farmer.global_position
        var moved := Vector2(end.x - start.x, end.z - start.z).dot(direction)
        # 4 s a 4 m/s: sem bloqueio o fazendeiro andaria 16 m; a água tem < 4 m.
        var ok := wet == 0 and moved < 7.0
        _check(ok, "Test D crossed water without bridge: %s (moved %.2f m, wet %d)" % [attempt[2], moved, wet])
        if ok:
            blocked += 1
    print("RIVER_D_WATER_BLOCKS attempts=", attempts.size(), " blocked=", blocked)

## Teste E — integração com o que já existia.
func _test_integration() -> void:
    _check(world.camera != null and world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Camera changed")
    _check(world.get_node_or_null("HUD/VirtualJoystick") != null, "Joystick missing")
    _check(world.hud != null and world.sales_counter != null and world.customer_queue != null, "HUD/sales missing")
    var expected := FarmWorld.PLANTING_PLOT_COUNT * world.planting_grid.columns * world.planting_grid.rows_per_module
    _check(world.planting_grid.cells.size() == expected, "Planting cell count changed")
    var bad_cells := 0
    for cell in world.planting_grid.cells.values():
        var position: Vector3 = cell["position"]
        if river.is_point_in_water(position, 1.0) or not river.is_planting_allowed(position):
            bad_cells += 1
    _check(bad_cells == 0, "Planting cells inside river area: %d" % bad_cells)
    var water_points := 0
    var rejected := 0
    for segment in river.segments:
        for point in river.get_segment_centerline(segment, 8):
            water_points += 1
            if not river.is_planting_allowed(river.to_global(point)):
                rejected += 1
    _check(rejected == water_points, "River accepts planting at %d points" % (water_points - rejected))
    var in_reserved := 0
    for entry in world.cozy_environment.placements:
        if river.blocks_decoration(entry["position"], entry["clearance"]):
            in_reserved += 1
    _check(in_reserved == 0, "Decorations inside river/bridges: %d" % in_reserved)
    _check(world.cozy_environment.reserved_areas.has(river), "CozyEnvironment does not know the river")
    print("RIVER_E_INTEGRATION planting_cells=", world.planting_grid.cells.size(), " cells_in_river=", bad_cells,
        " river_points_rejected=", rejected, "/", water_points, " decorations=", world.cozy_environment.placements.size(),
        " decorations_on_river=", in_reserved)

## Teste G — um novo segmento entra sem recriar os anteriores.
func _test_expansion() -> void:
    var system := RiverSystem.new()
    system.anchor_position = Vector3(0, 0, 0)
    system.anchor_width = 2.5
    system.course = [{"tile": "river_straight_vertical", "entry": "top"}, {"tile": "river_corner_right_down"}]
    root.add_child(system)
    var before_nodes: Array = []
    for child in system.get_node("RiverSegments").get_children():
        before_nodes.append(child.get_instance_id())
    var before_bodies := system.get_node("RiverCollisions").get_child_count()
    var started := Time.get_ticks_usec()
    system.add_segment({"tile": "river_straight_horizontal"})
    system.add_segment({"tile": "river_corner_left_down"})
    system.add_segment({"tile": "river_straight_vertical"})
    var add_ms := (Time.get_ticks_usec() - started) / 1000.0
    var kept := 0
    for child in system.get_node("RiverSegments").get_children():
        if before_nodes.has(child.get_instance_id()):
            kept += 1
    _check(kept == before_nodes.size(), "Existing segment nodes were rebuilt")
    _check(system.segments.size() == 5, "Expansion segments not added")
    _check(system.get_node("RiverCollisions").get_child_count() == before_bodies + 6, "Expansion collisions not added")
    var gap := 0.0
    for i in range(1, system.segments.size()):
        var a: Dictionary = system.segments[i - 1]
        var b: Dictionary = system.segments[i]
        gap = maxf(gap, ((a["exit_point"] as Vector3) - (RiverSystem.FLOW[a["exit"]] as Vector3) * system.junction_overlap).distance_to(b["entry_point"]))
    _check(gap < 0.001, "Expansion junction gap")
    # Ponta do rio fechada por um lago (peça terminal).
    var pond := RiverSystem.new()
    pond.anchor_position = Vector3(40, 0, 0)
    pond.anchor_width = 2.5
    pond.course = [{"tile": "river_straight_vertical", "entry": "top"}]
    root.add_child(pond)
    pond.add_segment({"tile": "river_pond_endcap_top"})
    _check(pond.segments.size() == 2 and pond.segments[1]["exit"] == "", "Pond endcap failed")
    print("RIVER_G_EXPANSION added=3 kept_nodes=", kept, "/", before_nodes.size(), " add_ms=", snappedf(add_ms, 0.01),
        " max_gap_m=", snappedf(gap, 0.0001), " pond_endcap=ok")
    system.queue_free()
    pond.queue_free()

## Teste H — custo do rio (contagens; FPS real só em aparelho).
func _test_performance(setup_ms: float) -> void:
    var meshes := 0
    for node in river.find_children("*", "MeshInstance3D", true, false):
        meshes += 1
    var shapes := 0
    for node in river.find_children("*", "CollisionShape3D", true, false):
        shapes += 1
    _check(meshes < 80, "Too many river meshes: %d" % meshes)
    _check(shapes < 400, "Too many river collision shapes: %d" % shapes)
    print("RIVER_H_PERFORMANCE world_setup_ms=", snappedf(setup_ms, 0.1), " river_meshes=", meshes,
        " collision_shapes=", shapes, " blocker_boxes=", river.get_total_blocker_boxes())
