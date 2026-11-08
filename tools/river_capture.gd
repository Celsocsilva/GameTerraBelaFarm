extends SceneTree
## ENV-002 — Capturas reais do rio e das pontes (usar com --write-movie).
##
##   godot --path . --write-movie out.png --fixed-fps 30 -s tools/river_capture.gd -- --view=<vista> [--debug] [--no-river]
##
## Vistas: overview, wide, wood, stone, wood_cross, stone_cross, banks, curve,
## north, focus (--focus=x,z --size=s), game (câmera padrão no fazendeiro),
## wood_walk / stone_walk (travessia completa com a câmera do jogo seguindo o
## fazendeiro, para vídeo) e water (3 s parados para mostrar a animação). --no-river esconde o rio e as
## pontes (captura "antes"); --debug desenha a travessia (verde) e os
## bloqueios da água (vermelho).

var world: FarmWorld
var view := "overview"
var debug := false
var hide_river := false
var _frames := 0
var _walk_line: PackedVector3Array
var _walk_index := 0
var _hold_frames := 0
var _walk_full := false
var _max_frames := 8

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--view="):
            view = arg.trim_prefix("--view=")
        elif arg == "--debug":
            debug = true
        elif arg == "--no-river":
            hide_river = true
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.harvest_controller.enabled = false
    var river := world.river_system
    if hide_river:
        river.visible = false
    if debug:
        _add_debug(river)
    var focus := Vector3(-14.0, 0.0, -4.0)
    var size := 34.0
    var walking := ""
    match view:
        "overview":
            focus = Vector3(-14.0, 0.0, -4.0)
            size = 40.0
        "wide":
            focus = Vector3(-6.0, 0.0, -2.0)
            size = 46.0
        "wood":
            focus = _bridge(river, "wood").global_position
            size = 11.0
        "stone":
            focus = _bridge(river, "stone").global_position
            size = 11.0
        "wood_cross":
            focus = _bridge(river, "wood").global_position
            size = 11.0
            walking = "wood"
        "stone_cross":
            focus = _bridge(river, "stone").global_position
            size = 11.0
            walking = "stone"
        "banks":
            focus = Vector3(-17.0, 0.0, -18.0)
            size = 16.0
        "curve":
            focus = Vector3(-23.0, 0.0, 10.0)
            size = 18.0
        "north":
            focus = Vector3(-24.0, 0.0, -20.0)
            size = 16.0
        "focus":
            # --focus=x,z --size=s : vista livre para inspeção de junções.
            for arg in OS.get_cmdline_user_args():
                if arg.begins_with("--focus="):
                    var parts := arg.trim_prefix("--focus=").split(",")
                    focus = Vector3(float(parts[0]), 0.0, float(parts[1]))
                elif arg.begins_with("--size="):
                    size = float(arg.trim_prefix("--size="))
        "wood_walk", "stone_walk":
            walking = view.trim_suffix("_walk")
            _walk_full = true
            size = world.camera_orthographic_size
        "water":
            focus = Vector3(-14.3, 0.0, -3.4)
            size = 9.0
            _max_frames = 180
        "game":
            world.farmer.global_position = Vector3(-11.0, 0.05, -4.0)
            focus = world.farmer.global_position
            size = world.camera_orthographic_size
        _:
            push_error("Unknown view: " + view)
            quit(1)
            return
    world.set_process(_walk_full)
    world.camera.size = size
    world.camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    world.camera.look_at(focus, Vector3.UP)
    if walking != "":
        var bridge := _bridge(river, walking)
        _walk_line = bridge.get_centerline_global(24)
        if _walk_full:
            var full := PackedVector3Array()
            var west := bridge.get_approach_path_global(false)
            for i in range(west.size() - 1, -1, -1):
                full.append(west[i])
            full.append_array(_walk_line)
            full.append_array(bridge.get_approach_path_global(true))
            _walk_line = full
        var start := _walk_line[0]
        var dir := (_walk_line[1] - _walk_line[0]).normalized()
        world.farmer.global_position = Vector3(start.x, 0.05, start.z) - Vector3(dir.x, 0.0, dir.z) * 1.2
        _walk_index = 1
        if _walk_full:
            world.camera_focus = world.farmer.global_position
            world.camera.global_position = world.camera_focus + Vector3(0.0, world.camera_height, world.camera_distance)
            world.camera.look_at(world.camera_focus, Vector3.UP)
    else:
        world.farmer.set_physics_process(view == "game")
    print("RIVER_CAPTURE view=", view, " debug=", debug, " hide_river=", hide_river)
    physics_frame.connect(_on_physics)

func _bridge(river: RiverSystem, id: String) -> RiverBridge:
    for bridge in river.get_bridges():
        if bridge.bridge_id == id:
            return bridge
    return null

## Conduz o fazendeiro pela linha central até o meio da ponte e para lá.
func _on_physics() -> void:
    _frames += 1
    if not _walk_line.is_empty():
        var target_index := _walk_line.size() - 1 if _walk_full else int(_walk_line.size() * 0.5)
        if _walk_index <= target_index:
            var target := _walk_line[_walk_index]
            var pos := world.farmer.global_position
            var delta := Vector2(target.x - pos.x, target.z - pos.z)
            if delta.length() < 0.35:
                _walk_index += 1
            _press(delta.normalized())
        else:
            _press(Vector2.ZERO)
            _hold_frames += 1
            if _hold_frames > 12:
                _finish()
        if _frames > 900:
            push_error("Walk timeout")
            _finish()
    elif _frames > _max_frames:
        _finish()

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

func _finish() -> void:
    physics_frame.disconnect(_on_physics)
    print("RIVER_CAPTURE_DONE farmer=", world.farmer.global_position)
    quit()

func _add_debug(river: RiverSystem) -> void:
    var green := _debug_material(Color(0.1, 1.0, 0.2, 0.6))
    var red := _debug_material(Color(1.0, 0.1, 0.1, 0.45))
    for bridge in river.get_bridges():
        var polygon := bridge.get_walk_polygon_global()
        for i in polygon.size():
            var a := polygon[i]
            var b := polygon[(i + 1) % polygon.size()]
            _debug_box(Vector3((a.x + b.x) * 0.5, 0.5, (a.y + b.y) * 0.5), Vector3(0.08, 0.08, a.distance_to(b)), atan2(b.x - a.x, b.y - a.y), green)
        for point in bridge.get_centerline_global(12):
            _debug_box(point + Vector3(0, 0.05, 0), Vector3(0.12, 0.12, 0.12), 0.0, green)
        for east in [false, true]:
            for point in bridge.get_approach_path_global(east):
                _debug_box(point + Vector3(0, 0.05, 0), Vector3(0.2, 0.2, 0.2), 0.0, green)
        for node in bridge.find_children("*", "CollisionShape3D", true, false):
            var cylinder := (node as CollisionShape3D).shape as CylinderShape3D
            if cylinder:
                _debug_box((node as CollisionShape3D).global_position, Vector3(cylinder.radius * 2.0, 0.1, cylinder.radius * 2.0), 0.0, red)
    for body in river.get_node("RiverCollisions").get_children():
        for collision in body.get_children():
            var shape := (collision as CollisionShape3D).shape as BoxShape3D
            var marker := MeshInstance3D.new()
            var mesh := BoxMesh.new()
            mesh.size = Vector3(shape.size.x, 0.02, shape.size.z)
            marker.mesh = mesh
            marker.material_override = red
            marker.position = (collision as CollisionShape3D).global_position
            marker.position.y = 0.1
            world.add_child(marker)

func _debug_box(center: Vector3, size: Vector3, yaw: float, material: Material) -> void:
    var marker := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    marker.mesh = mesh
    marker.material_override = material
    marker.position = center
    marker.rotation.y = yaw
    world.add_child(marker)

func _debug_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.no_depth_test = true
    material.render_priority = 100
    return material
