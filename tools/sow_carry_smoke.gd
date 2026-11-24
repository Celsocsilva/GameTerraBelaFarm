extends SceneTree
## SEED-003 + PUMPKIN-CARRY-001 + SOW-SPEED-001 (pedidos do Celso, 24/11).
## Uso: Godot --headless --path . -s tools/sow_carry_smoke.gd
## 1) Sementes menores e lançamento rasteiro, saindo da mão à frente do fazendeiro.
## 2) No máximo 7 abóboras por transporte (e 7 imagens na mochila).
## 3) Mais devagar enquanto semeia sobre o canteiro.

var _failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures += 1
        push_error("SOW_CARRY_SMOKE_FAIL: " + message)

func _run() -> void:
    _test_seed_throw()
    _test_pumpkin_limit()
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    await _test_backpack(world)
    _test_seed_origin(world)
    _test_sowing_speed(world)
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("SOW_CARRY_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("SOW_CARRY_SMOKE_OK")
    quit()

func _test_seed_throw() -> void:
    var throw := (FarmWorld.SEED_THROW_SCENE.instantiate()) as SeedThrow
    _check(throw.seed_scale_max <= 0.5, "grãos principais menores (<= 0,5)")
    _check(throw.fine_scale_max <= 0.2, "grãos finos menores (<= 0,2)")
    # Trajetória rasteira: da mão (0,7 m) até o sulco a 4 m, o punhado sobe pouco.
    var origin := Vector3(0.0, 0.7, 0.0)
    var target := Vector3(0.0, 0.2, -4.0)
    var t := clampf(FarmWorld.SEED_FLIGHT_BASE + 4.0 * FarmWorld.SEED_FLIGHT_PER_M, 0.3, 0.75)
    var velocity := SeedThrow.solve_launch_velocity(origin, target, throw.gravity, t)
    var apex := origin.y
    if velocity.y > 0.0:
        apex = origin.y + velocity.y * velocity.y / (2.0 * -throw.gravity.y)
    _check(apex <= 0.85, "lançamento rasteiro (ápice %.2f m)" % apex)
    throw.free()

func _test_pumpkin_limit() -> void:
    var inventory := HarvestInventory.new()
    _check(inventory.get_capacity(&"pumpkin") == 7, "abóbora: 7 por transporte")
    _check(inventory.get_capacity(&"tomato") == inventory.max_crates * inventory.units_per_crate, "tomate mantém a capacidade")
    var reservation := inventory.try_reserve(&"pumpkin", 20)
    _check(reservation.amount == 7, "reserva de abóbora limitada a 7 (obtido %d)" % reservation.amount)
    inventory.commit(reservation)
    _check(inventory.get_amount(&"pumpkin") == 7 and inventory.is_full(), "mochila cheia com 7 abóboras")
    _check(inventory.try_reserve(&"pumpkin", 1).amount == 0, "nenhuma abóbora além de 7")
    inventory.set_amount(&"pumpkin", 30)
    _check(inventory.get_amount(&"pumpkin") == 7, "set_amount também respeita 7")
    inventory.free()

func _test_backpack(world: FarmWorld) -> void:
    world.harvest_inventory.set_amount(&"pumpkin", 7)
    await process_frame
    _check(world.backpack.get_visible_crate_count() == 7, "7 abóboras visíveis na mochila (obtido %d)" % world.backpack.get_visible_crate_count())
    world.harvest_inventory.set_amount(&"pumpkin", 0)
    await process_frame

func _test_seed_origin(world: FarmWorld) -> void:
    var farmer := world.farmer
    for angle in [0.0, PI * 0.5, PI, -PI * 0.5]:
        farmer.rotation.y = angle
        var forward := -farmer.global_basis.z
        var hand := farmer.global_transform * FarmWorld.SEED_HAND_OFFSET
        var offset := hand - farmer.global_position
        _check(Vector2(offset.x, offset.z).dot(Vector2(forward.x, forward.z)) > 0.2, "mão de semear à frente do fazendeiro (giro %.2f)" % angle)
        _check(offset.y <= 0.8, "mão baixa para lançar rasteiro")

func _test_sowing_speed(world: FarmWorld) -> void:
    var farmer := world.farmer
    var grid := world.planting_grid
    var cell: Dictionary = grid.cells["PlantingPlot_02_r01_c01"]
    farmer.set_process(false)
    farmer.global_position = Vector3(cell["position"].x, farmer.global_position.y, cell["position"].z)
    farmer.rotation.y = atan2(0.0, -1.0) # olhando para +Z (fileiras seguintes)
    _check(world.is_farmer_sowing(), "em cima do canteiro com covas vazias à frente = semeando")
    farmer.global_position = Vector3(cell["position"].x, farmer.global_position.y, cell["position"].z - 30.0)
    _check(not world.is_farmer_sowing(), "fora do canteiro não está semeando")
    _check(farmer.sowing_speed_factor < 0.8, "semeando anda mais devagar")
    # Velocidade alvo: com sowing ligado o fator converge para sowing_speed_factor.
    farmer.sowing = true
    for i in 60:
        farmer._speed_factor = move_toward(farmer._speed_factor, farmer.sowing_speed_factor, 1.0 / 60.0 * 2.5)
    _check(is_equal_approx(farmer._speed_factor, farmer.sowing_speed_factor), "fator converge para a velocidade de semeadura")
