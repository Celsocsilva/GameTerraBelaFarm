extends SceneTree
## FARMER-GAME-001 — fazendeiro 3D integrado ao FarmWorld.
##   godot --headless --path . -s tools/farmer_game_smoke.gd   (sai com 1 se falhar)

var failures: Array[String] = []
var world: FarmWorld


func _initialize() -> void:
    call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
    print(("PASS  " if ok else "FAIL  ") + msg)
    if not ok:
        failures.append(msg)


func _run() -> void:
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.customer_queue.set_process(false)
    var farmer := world.farmer
    _check(farmer.get_node_or_null("Body") == null, "cápsula azul removida do fazendeiro")
    _check(farmer.visual != null and farmer.visual.get_node_or_null("Model/Farmer_Armature/Skeleton3D") != null, "modelo 3D rigado presente")
    _check(farmer.animator != null and farmer.animator.tree != null and farmer.animator.tree.active, "FarmerAnimator com AnimationTree ativo")
    _check(is_equal_approx(farmer.animator.model_scale, farmer.visual.scale.y), "animador usa a escala do modelo (%.2f)" % farmer.animator.model_scale)
    var mesh := farmer.visual.get_node("Model/Farmer_Armature/Skeleton3D/Farmer_Mesh") as MeshInstance3D
    var h := mesh.get_aabb().size.y * farmer.visual.scale.y
    _check(h > 2.0 and h < 3.0, "altura no jogo %.2f m" % h)
    _check(mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "fazendeiro projeta sombra")
    var customer := Customer.create(0)
    _check(customer.get_node_or_null("Body") is MeshInstance3D, "clientes continuam com o corpo-cápsula")
    customer.free()

    # parado -> correndo (joystick cheio = 4 m/s)
    farmer.global_position = world.FARMER_SPAWN + Vector3(-6.0, 0.0, 0.0)
    await _physics(20)
    _check(farmer.animator.loco_state == &"idle", "parado = Idle_Loop (%s)" % farmer.animator.loco_state)
    Input.action_press("ui_left")
    await _physics(45)
    _check(farmer.animator.loco_state == &"run", "joystick cheio = Jog_Fwd_Loop (%s, %.2f m/s)" % [farmer.animator.loco_state, farmer.get_horizontal_speed()])
    var scale := float(farmer.animator.tree.get("parameters/loco_speed/scale"))
    _check(scale > 0.6 and scale < 1.6, "velocidade da corrida acompanha o chão (scale %.2f)" % scale)
    var forward := -farmer.global_transform.basis.z
    _check(forward.x < -0.9, "fazendeiro olha para onde anda (frente %.2f)" % forward.x)
    Input.action_release("ui_left")
    await _physics(40)
    _check(farmer.animator.loco_state == &"idle", "soltou o joystick = Idle_Loop")

    # mochila
    world.harvest_inventory.set_amount(&"tomato", 16)
    await _physics(2)
    _check(farmer.animator.carrying_backpack and farmer.animator.loco_state == &"bp_idle", "mochila com caixas = Backpack_Idle_Loop")
    world.harvest_inventory.set_amount(&"tomato", 0)
    await _physics(2)
    _check(not farmer.animator.carrying_backpack, "mochila vazia = sem pose de alças")

    # semear: evento da grade
    await _wait_idle()
    world.planting_grid.cell_planted.emit(world.planting_grid.cells.keys()[0])
    var sow_action := farmer.animator.last_action
    await process_frame
    await process_frame
    _check(sow_action == &"Interact" and farmer.animator.is_busy(), "semear dispara o gesto de lançar (%s)" % sow_action)
    await _wait_idle()
    world.harvest_controller.harvest_started.emit("x", 1)
    _check(farmer.animator.last_action == &"PickUp_Table", "colher dispara PickUp_Table")
    await _wait_idle()
    world.sales_counter.deposited.emit(8, 8)
    _check(farmer.animator.last_action == &"Interact", "entregar no balcão dispara Interact")

    print("\nFARMER GAME SMOKE: %s" % ("OK" if failures.is_empty() else "FALHOU (%d)" % failures.size()))
    quit(0 if failures.is_empty() else 1)


func _physics(n: int) -> void:
    for i in n:
        await physics_frame


func _wait_idle() -> void:
    var t := 0
    while world.farmer.animator.is_busy() and t < 600:
        await process_frame
        t += 1
    world.farmer.animator.last_action = &""
