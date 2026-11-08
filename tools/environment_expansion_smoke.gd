extends SceneTree
## Simula a distribuição numa fazenda 128 × 128 sem modificar o mapa jogável.

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var env := CozyEnvironment.new()
    var ground := MeshInstance3D.new()
    var started := Time.get_ticks_msec()
    env.setup(ground, 128.0, 8.0, 2.3, 20.5, Vector3(0.0, 0.0, 60.5))
    var elapsed := Time.get_ticks_msec() - started
    var valid := env.placements.size() > 500
    for entry in env.placements:
        if not env.is_allowed_position(entry["position"], entry["clearance"]):
            valid = false
            break
    print("ENV_EXPANSION size=128 placements=", env.placements.size(), " setup_ms=", elapsed, " valid=", valid)
    env.free()
    ground.free()
    quit(0 if valid else 1)
