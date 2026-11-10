extends SceneTree
## FLICK-001 — cintilação ao carregar recursos (abóbora, milho, tomate, madeira).
## Uso: Godot --headless --path . -s tools/flicker_smoke.gd
## 1) Caixas da mochila em profundidades diferentes (sem disputar o mesmo plano).
## 2) Tabela de recortes opacos igual ao cálculo real da arte.
## 3) Arte das culturas pré-carregada: trocar de estágio não lê a GPU.

var _failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures += 1
        push_error("FLICKER_SMOKE_FAIL: " + message)

func _run() -> void:
    _test_rect_table()
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.harvest_controller.enabled = false
    for controller in world.crop_harvesters.values():
        (controller as HarvestController).enabled = false
    await _test_backpack_depth(world)
    _test_prewarm(world)
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("FLICKER_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("FLICKER_SMOKE_OK")
    quit()

func _test_rect_table() -> void:
    var checked := 0
    for path in CropPlant.PRECOMPUTED_VISIBLE_RECTS:
        var texture := load(path) as Texture2D
        _check(texture != null and texture.get_size() == CropPlant.PRECOMPUTED_TEXTURE_SIZE, "tamanho da arte mudou: " + path)
        var real := CropPlant._compute_visible_rect(texture.get_image())
        _check(real == CropPlant.PRECOMPUTED_VISIBLE_RECTS[path], "recorte desatualizado %s: %s != %s" % [path, real, CropPlant.PRECOMPUTED_VISIBLE_RECTS[path]])
        checked += 1
    for crop in CropCatalog.CROPS:
        for path in CropCatalog.stage_assets(crop):
            _check(CropPlant.PRECOMPUTED_VISIBLE_RECTS.has(path), "estágio sem recorte pronto: " + path)
    print("FLICKER_RECT_TABLE_OK textures=", checked)

func _test_backpack_depth(world: FarmWorld) -> void:
    var inv := world.harvest_inventory
    var backpack := world.backpack
    var camera := world.camera
    var report := []
    for item in [&"pumpkin", &"corn", &"tomato", &"wood"]:
        for other in [&"pumpkin", &"corn", &"tomato", &"wood"]:
            inv.set_amount(other, 0)
        inv.set_amount(item, inv.get_capacity() - 3)
        await process_frame

        var toward := camera.global_basis.z
        toward.y = 0.0
        toward = toward.normalized()
        var min_gap := INF
        for angle in [0.0, 0.4, 1.2, 2.5, -0.9]:
            world.farmer.rotation.y = angle
            backpack._orient_crates()
            min_gap = minf(min_gap, _min_depth_gap(backpack, toward))
        _check(backpack.get_visible_crate_count() == backpack.max_crates, "%s: 7 caixas visíveis" % item)
        # Cada caixa >= 3 cm mais perto da câmera que a anterior, em qualquer
        # giro do fazendeiro: nada de duas artes no mesmo plano (listras).
        _check(min_gap >= 0.03, "%s: caixas no mesmo plano (menor distância %.4f m)" % [item, min_gap])
        report.append("%s=%.3f" % [item, min_gap])
    print("FLICKER_BACKPACK_DEPTH_OK ", " ".join(report))

func _min_depth_gap(backpack: BackpackCrates, toward: Vector3) -> float:
        var depths: Array[float] = []
        for index in backpack.max_crates:
            var crate := backpack.stack_root.get_node("Crate_%d" % index) as Node3D
            if not crate.visible:
                continue
            var sprite := crate.get_node("CrateSprite") as Sprite3D
            depths.append(sprite.global_position.dot(toward))
        var gap := INF
        for i in range(1, depths.size()):
            gap = minf(gap, depths[i] - depths[i - 1])
        return gap

func _test_prewarm(world: FarmWorld) -> void:
    for crop in CropCatalog.CROPS:
        for path in CropCatalog.stage_assets(crop):
            _check(CropPlant._visible_rect_cache.has(path), "arte não pré-carregada: " + path)
    var grid := world.get_crop_grid(&"pumpkin")
    var cell: Dictionary = grid.cells.values()[0]
    var crop := world.spawn_crop_at_stage(cell["id"], 0)
    var worst := 0
    for stage in CropPlant.STAGES.size():
        var t0 := Time.get_ticks_usec()
        crop._update_stage(stage)
        worst = maxi(worst, Time.get_ticks_usec() - t0)
    _check(worst < 8000, "troca de estágio da abóbora lenta: %d us" % worst)
    print("FLICKER_PREWARM_OK worst_stage_change_us=", worst)
