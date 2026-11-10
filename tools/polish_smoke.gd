extends SceneTree
## FV-POLISH-001 — caixas iguais (mochila = balcão), pilha 3x3 dos ajudantes,
## sem placeholders sem textura no mapa, props em escala natural, áreas de
## milho/abóbora do tamanho do tomate e pinheiros no leste e nos fundos.
##   godot --headless --path . -s tools/polish_smoke.gd

var _failures := 0

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures += 1
        push_error("POLISH_SMOKE_FAIL: " + message)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    TranslationServer.set_locale("pt_BR")
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    await process_frame
    _test_crates(world)
    _test_placeholders(world)
    _test_props(world)
    _test_areas(world)
    _test_pines(world)
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("POLISH_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("POLISH_SMOKE_OK")
    quit()

func _test_crates(world: FarmWorld) -> void:
    var backpack := world.backpack
    _check(is_equal_approx(backpack.crate_width, SalesCounter.CRATE_WIDTH), "caixa da mochila %.2f m != balcão %.2f m" % [backpack.crate_width, SalesCounter.CRATE_WIDTH])
    world.harvest_inventory.set_amount(&"tomato", 16)
    var sprite := backpack.stack_root.get_child(0).get_node("CrateSprite") as Sprite3D
    var counter_sprite := world.sales_counter.get_node("CounterCrate_00/CrateSprite") as Sprite3D
    _check(sprite.texture == counter_sprite.texture, "arte da caixa cheia diferente do balcão")
    _check(is_equal_approx(sprite.pixel_size * sprite.texture.get_width(), counter_sprite.pixel_size * counter_sprite.texture.get_width()), "largura da caixa diferente do balcão")
    world.harvest_inventory.set_amount(&"corn", 16)
    var corn_stack := world.sales_counter.get_extra_stack(&"corn")
    corn_stack.set_stored_total(16)
    var corn_counter := corn_stack.get_node("PileCrate_00/CrateSprite") as Sprite3D
    sprite = backpack.stack_root.get_child(0).get_node("CrateSprite") as Sprite3D
    _check(sprite.texture == corn_counter.texture and is_equal_approx(sprite.pixel_size, corn_counter.pixel_size), "caixa de milho da mochila diferente do balcão")
    world.harvest_inventory.set_amount(&"corn", 0)
    corn_stack.set_stored_total(0)
    # Clientes levam a mesma arte (sem caixas BoxMesh).
    var customer := Customer.create(0)
    root.add_child(customer)
    customer.carry_crates(2, &"tomato")
    var carried := customer.get_node("CarriedCrates")
    for child in carried.get_children():
        _check(child is Sprite3D and (child as Sprite3D).texture == ItemArt.full_texture(&"tomato"), "cliente leva caixa sem a arte")
    customer.free()
    for pile in [world.tomato_pile, world.get_crop_area(&"corn")["pile"], world.get_crop_area(&"pumpkin")["pile"]]:
        _check((pile as TomatoPile).grid_layout, "pilha de ajudante sem grade 3x3: " + (pile as Node).name)
    print("POLISH_CRATES_OK width=%.2f" % backpack.crate_width)

## Nenhum MeshInstance3D sem textura solto no mapa. Exceções conhecidas
## (personagens e a base de dinheiro), listadas como pendência.
func _test_placeholders(world: FarmWorld) -> void:
    for name in ["Building", "Tree"]:
        _check(world.get_node_or_null(name) == null, "placeholder ainda no mapa: " + name)
    var loose: Array[String] = []
    for node in world.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        if not (mesh.mesh is BoxMesh or mesh.mesh is SphereMesh or mesh.mesh is CylinderMesh):
            continue
        var path := String(world.get_path_to(mesh))
        if path.begins_with("Farmer") or path.begins_with("FarmHelper") or path.begins_with("MoneyStack") or path.begins_with("Ground") or path.begins_with("CustomerQueue"):
            continue
        loose.append(path)
    _check(loose.is_empty(), "primitivas sem textura no mapa: %s" % [loose])
    for body in world.get_children():
        if body.name.begins_with("TerrainBoundary"):
            _check(body.find_children("*", "MeshInstance3D", true, false).is_empty(), "muro da borda ainda visível")
    print("POLISH_PLACEHOLDERS_OK")

func _test_props(world: FarmWorld) -> void:
    var group := world.cozy_environment.get_node("FarmDecorations")
    var count := 0
    for decoration in group.get_children():
        var art := decoration.get_node("Art") as Sprite3D
        var width := art.pixel_size * art.texture.get_width()
        var range_m: Vector2 = CozyEnvironment.PROP_WIDTHS.get(art.texture.resource_path, Vector2.ZERO)
        _check(range_m != Vector2.ZERO and width >= range_m.x - 0.01 and width <= range_m.y + 0.01, "prop fora da escala: %s %.2f m" % [decoration.name, width])
        if art.texture.resource_path.ends_with("lantern_post.png"):
            _check(width * art.texture.get_height() / art.texture.get_width() >= 2.3, "lampião baixo demais")
        count += 1
    _check(count > 0, "sem props de fazenda")
    print("POLISH_PROPS_OK props=%d" % count)

func _test_areas(world: FarmWorld) -> void:
    var tomato := world.get_planting_area_rect()
    var tomato_cells := world.planting_grid.cells.size()
    for entry in world.crop_areas:
        var field: Rect2 = entry["field"]
        _check(absf(field.get_area() / tomato.get_area() - 1.0) < 0.05, "%s com %.0f%% da área do tomate" % [entry["crop"], 100.0 * field.get_area() / tomato.get_area()])
        _check(field.end.y < tomato.position.y - 4.0, "%s deveria ficar nos fundos (norte)" % entry["crop"])
    var corn := world.get_crop_grid(&"corn")
    _check(corn.cells.size() == tomato_cells, "milho com %d covas (tomate %d)" % [corn.cells.size(), tomato_cells])
    print("POLISH_AREAS_OK tomato=%.1f m² cells=%d" % [tomato.get_area(), tomato_cells])

func _test_pines(world: FarmWorld) -> void:
    var grove := world.eucalyptus_grove
    var east := 0
    var north := 0
    var tomato := world.get_planting_area_rect()
    var counter := world.sales_counter.position
    for tree in grove.trees:
        var p := Vector2(tree.position.x, tree.position.z)
        if FarmWorld.PINE_EAST.grow(0.3).has_point(p):
            east += 1
        if p.y < -26.5:
            north += 1
        _check(not tomato.has_point(p), "pinheiro dentro do tomate")
        for entry in world.crop_areas:
            for key in ["field", "stock", "pad_rect"]:
                _check(not (entry[key] as Rect2).has_point(p), "pinheiro dentro de %s/%s" % [entry["crop"], key])
        _check(p.distance_to(Vector2(counter.x, counter.z)) >= 7.0, "pinheiro no balcão")
        for bridge in world.river_system.get_bridges():
            var b := Vector2(bridge.global_position.x, bridge.global_position.z)
            _check(p.distance_to(b + Vector2(3.0, 0.0)) > 1.2, "pinheiro na saída da ponte " + bridge.name)
    _check(east >= 20, "poucos pinheiros no leste: %d" % east)
    _check(north >= east, "o norte deveria ter mais pinheiros que o leste: %d < %d" % [north, east])
    print("POLISH_PINES_OK east=%d north=%d total=%d" % [east, north, grove.get_tree_count()])
