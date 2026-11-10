extends SceneTree
## FARM-003 — solo largo na abóbora, barris 20% menores, cultivos 10% menores,
## fonte do prêmio igual à do progresso, troca de idioma em tempo real, placas,
## casa do fazendeiro, fileiras orgânicas e curral com 7 vacas animadas.
##   godot --headless --path . -s tools/farm003_smoke.gd

var _failures := 0
var world: FarmWorld

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures += 1
        push_error("FARM003_SMOKE_FAIL: " + message)

func _run() -> void:
    TranslationServer.set_locale("pt_BR")
    world = (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    _test_pumpkin_soil()
    _test_sizes()
    _test_signs()
    _test_organic_rows()
    _test_farmhouse()
    await _test_cow_pen()
    await _test_languages()
    _test_csv()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(FarmSettings.PATH))
    world.queue_free()
    await process_frame
    if _failures > 0:
        print("FARM003_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("FARM003_SMOKE_OK")
    quit()

func _test_pumpkin_soil() -> void:
    var entry := world.get_crop_area(&"pumpkin")
    var area := entry["area"] as Node3D
    _check(area.get_child_count() == 2, "abóbora deve ter 2 peças de solo (tem %d)" % area.get_child_count())
    for plot in area.get_children():
        var soil := plot.get_node("PlowedSoil") as MeshInstance3D
        _check((soil.material_override as StandardMaterial3D).albedo_texture == FarmWorld.SOIL_TEXTURE_WIDE, "peça sem o solo largo")
        var quad := soil.mesh as QuadMesh
        var aspect := quad.size.y / quad.size.x
        var art := float(FarmWorld.SOIL_TEXTURE_WIDE.get_height()) / float(FarmWorld.SOIL_TEXTURE_WIDE.get_width())
        _check(absf(aspect - art * FarmWorld.PLANTING_LENGTH_STRETCH) < 0.01, "solo largo distorcido: %.3f" % aspect)
    var tomato := world.get_planting_area_rect().get_area()
    var field := (entry["field"] as Rect2).get_area()
    _check(absf(field / tomato - 1.0) < 0.05, "abóbora com %.0f%% da área do tomate" % (100.0 * field / tomato))
    _check(world.get_crop_grid(&"pumpkin").cells.size() == 2 * 3 * 6, "covas de abóbora")
    print("FARM003_PUMPKIN_OK field=%s" % entry["field"])

func _test_sizes() -> void:
    # Área 10% menor: 1,7 -> 1,53 (lado x sqrt(0,9)).
    _check(is_equal_approx(FarmWorld.PLANTING_AREA_SCALE, 1.53), "escala de área do tomate")
    var corn := (world.get_crop_area(&"corn")["field"] as Rect2).get_area()
    _check(absf(corn / world.get_planting_area_rect().get_area() - 1.0) < 0.01, "milho acompanha o tomate")
    # Barris 20% menores.
    var barrel: Vector2 = CozyEnvironment.PROP_WIDTHS["res://assets/decor/farm_props/barrel_wood.png"]
    _check(barrel.is_equal_approx(Vector2(1.0, 1.15) * CozyEnvironment.PROP_SCALE * 0.8), "faixa de largura do barril: %s" % barrel)
    var count := 0
    for node in world.cozy_environment.get_node("FarmDecorations").get_children():
        if String(node.name).begins_with("barrel"):
            var art := node.get_node("Art") as Sprite3D
            var width := art.pixel_size * art.texture.get_width()
            _check(width <= barrel.y + 0.01 and width >= barrel.x - 0.01, "barril com %.2f m" % width)
            count += 1
    _check(count > 0, "nenhum barril no mapa")
    # Número do prêmio (dinheiro) com a fonte do número de progresso (recursos).
    var panel := world.hud.mission_panel
    var progress_font: int = panel.progress_bar.label_font_size
    _check(panel.reward_label.get_theme_font_size("font_size") <= MissionPanel.REWARD_FONT_SIZE, "fonte do prêmio")
    _check(MissionPanel.REWARD_FONT_SIZE == progress_font, "prêmio deveria usar a fonte do progresso (%d)" % progress_font)
    # Topo direito: dinheiro e ouro com a mesma fonte.
    world.wallet.set_balance(1250)
    world.wallet.set_gold(35)
    var bar := world.hud.wallet_bar
    _check(bar.get_money_label().get_theme_font_size("font_size") == bar.get_gold_label().get_theme_font_size("font_size"), "dinheiro e ouro com fontes diferentes no topo")
    print("FARM003_SIZES_OK barrels=%d barrel_range=%s reward_font=%d progress_font=%d" % [count, barrel, panel.reward_label.get_theme_font_size("font_size"), progress_font])

func _test_signs() -> void:
    for crop in [&"corn", &"pumpkin"]:
        var field: Rect2 = world.get_crop_area(crop)["field"]
        var sign := world.get_crop_sign(crop)
        _check(sign != null and is_equal_approx(sign.position.x, field.position.x + FarmWorld.CROP_SIGN_OFFSET.x), "placa de %s não está à esquerda do canteiro" % crop)
    print("FARM003_SIGNS_OK corn_x=%.2f pumpkin_x=%.2f" % [world.get_crop_sign(&"corn").position.x, world.get_crop_sign(&"pumpkin").position.x])

func _test_organic_rows() -> void:
    var grid := world.planting_grid
    var moved := 0
    var sizes := {}
    for cell in grid.cells.values():
        var offset := grid.get_organic_offset(0, int(cell["row"]), int(cell["column"]))
        # ROWS-002: mais orgânico, mas sempre dentro da cova (|desvio| < 0,3).
        _check(absf(offset.x) <= 0.27 and absf(offset.y) <= 0.2, "desvio orgânico grande demais: %s" % offset)
        sizes[snappedf(float(cell["size_factor"]), 0.01)] = true
    for cell in grid.cells.values():
        var module := world.get_node("PlantingArea/" + String(cell["module_id"])) as Node3D
        var base_x := module.global_position.x + (int(cell["column"]) + 0.5) * float(cell["cell_width"]) - float(cell["cell_width"]) * grid.columns * 0.5
        if absf(Vector3(cell["position"]).x - base_x) > 0.02:
            moved += 1
    _check(moved > grid.cells.size() / 2, "fileiras ainda retas (%d covas deslocadas)" % moved)
    _check(sizes.size() > 5, "plantas sem variação de tamanho")
    print("FARM003_ORGANIC_OK moved=%d/%d sizes=%d" % [moved, grid.cells.size(), sizes.size()])

func _test_farmhouse() -> void:
    var house := world.farmhouse
    _check(house != null and house.has_node("Art") and house.has_node("CollisionShape3D"), "casa sem arte/colisão")
    var rect := world.get_farmhouse_rect()
    var body := world.get_farmhouse_body_rect()
    _check(world.get_map_rect().encloses(rect), "casa fora do mapa")
    _check(rect.get_center().x < 0.0, "casa deveria ficar à esquerda")
    # Fora da água e longe das saídas das pontes.
    # HOUSE-002: o retângulo envolvente da curva do rio é bem maior que a água;
    # confere a água de verdade (com 0,6 m de margem) em pontos do corpo da casa.
    for ix in 9:
        for iz in 7:
            var p := body.position + body.size * Vector2(float(ix) / 8.0, float(iz) / 6.0)
            _check(not world.river_system.is_point_in_water(Vector3(p.x, 0.0, p.y), 0.6), "corpo da casa dentro do rio em %s" % p)
    _check(is_equal_approx(rect.size.x, 7.0 * 1.44), "casa 20%% + 20%% maior: largura %.2f" % rect.size.x)
    # HOUSE-003: no gramado a oeste do rio, entre a ponte de madeira e a de pedra.
    var wood_end: Vector3 = world.river_system.get_bridges()[0].get_endpoints_global()[0]
    var stone_end: Vector3 = world.river_system.get_bridges()[1].get_endpoints_global()[0]
    _check(rect.end.x < minf(wood_end.x, stone_end.x) - 2.0, "casa a oeste do rio: fim x %.2f" % rect.end.x)
    _check(rect.position.y > wood_end.z + 2.0 and rect.get_center().y < stone_end.z + 2.0, "casa entre as pontes: %s" % rect)
    _check(world.get_map_rect().grow(-1.5).encloses(rect), "casa encostada na borda do mapa")
    _check(rect.end.y < world.sales_counter.position.z, "casa antes da cerca do balcão")
    for bridge in world.river_system.get_bridges():
        for end in bridge.get_endpoints_global():
            var p := Vector2(end.x, end.z)
            _check(not rect.grow(1.5).has_point(p), "casa bloqueia a saída da ponte %s" % bridge.name)
    var blocked: Array[Rect2] = [world.get_planting_area_rect(), world.get_extra_plot_rect(), world.get_helper_pad_rect()]
    for entry in world.crop_areas:
        blocked.append(entry["field"]); blocked.append(entry["stock"]); blocked.append(entry["pad_rect"])
    for other in blocked:
        _check(not rect.intersects(other), "casa sobre canteiro/parcela/plataforma %s" % other)
    var counter := Vector2(world.sales_counter.position.x, world.sales_counter.position.z)
    _check(not body.grow(2.0).has_point(counter), "casa sobre o balcão")
    for tree in world.eucalyptus_grove.trees:
        _check(not rect.has_point(Vector2(tree.position.x, tree.position.z)), "árvore dentro da casa")
    print("FARM003_HOUSE_OK rect=%s body=%s" % [rect, body])

func _test_cow_pen() -> void:
    var pen := world.cow_pen
    _check(pen != null and pen.cows.size() >= 7, "curral precisa de 7 vacas")
    if pen == null:
        return
    var colors := {}
    for cow in pen.cows:
        colors[cow.color_id] = true
        _check(ResourceLoader.exists(FarmCow.frame_path(cow.color_id, 0)), "arte da vaca " + cow.color_id)
    _check(colors.size() == pen.cows.size(), "vacas com cores repetidas")
    var map := world.get_map_rect()
    _check(map.encloses(pen.rect), "curral fora do mapa")
    _check(pen.rect.get_center().x < map.get_center().x and pen.rect.get_center().y < map.get_center().y, "curral deveria ficar no topo esquerdo")
    for segment in world.river_system.segments:
        _check(not world.river_system.get_segment_rect(segment).intersects(pen.rect), "curral sobre o rio")
    for entry in world.crop_areas:
        _check(not (entry["field"] as Rect2).intersects(pen.rect), "curral sobre canteiro")
    for tree in world.eucalyptus_grove.trees:
        _check(not pen.rect.grow(0.5).has_point(Vector2(tree.position.x, tree.position.z)), "árvore dentro do curral")
    _check(pen.gate != null and pen.has_node("FenceNorth") and pen.has_node("FenceWest") and pen.has_node("FenceEast"), "cerca/portão incompletos")
    # PEN-002: curral 10% menor e vegetação em volta (fora da cerca e do rio).
    _check(absf(pen.rect.get_area() - 15.5 * 11.0 * 0.9) < 0.05, "curral 10%% menor: %.2f m²" % pen.rect.get_area())
    var pines := pen.get_surroundings_points("pine")
    var bushes := pen.get_surroundings_points("bush")
    _check(pines.size() >= 5 and bushes.size() >= 5, "pinheiros/arbustos perto do curral: %d/%d" % [pines.size(), bushes.size()])
    _check(pen.get_node("Surroundings").get_child_count() == pines.size() + bushes.size(), "vegetação do curral não foi montada")
    for p in pines + bushes:
        var xz := Vector2(p.x, p.z)
        _check(not pen.rect.grow(0.4).has_point(xz), "vegetação dentro do curral %s" % xz)
        _check(CowPen.get_surroundings_rect(pen.rect).grow(0.01).has_point(xz), "vegetação longe do curral %s" % xz)
        _check(map.grow(-0.5).has_point(xz), "vegetação fora do mapa %s" % xz)
        _check(not world.river_system.is_point_in_water(Vector3(p.x, 0.0, p.z), 1.0), "vegetação no rio %s" % xz)
        for entry in world.crop_areas:
            _check(not (entry["field"] as Rect2).grow(0.5).has_point(xz), "vegetação no canteiro %s" % xz)
        _check(not (absf(p.x - pen.gate_x) < 1.5 and p.z > pen.rect.end.y and p.z < pen.rect.end.y + 2.5), "vegetação na frente do portão")
    print("FARM003_PEN_GREEN_OK area=%.1f pines=%d bushes=%d" % [pen.rect.get_area(), pines.size(), bushes.size()])
    # Área: pelo menos ~12 m² por vaca dentro da cerca.
    _check(pen.rect.get_area() / pen.cows.size() >= 12.0, "curral pequeno: %.1f m² por vaca" % (pen.rect.get_area() / pen.cows.size()))
    var frames_seen := {}
    var start := {}
    for cow in pen.cows:
        start[cow] = cow.position
    for step in 300:
        for cow in pen.cows:
            cow._process(1.0 / 30.0)
            frames_seen[cow.get_frame_index()] = true
    var walked := 0
    var states := {}
    var inner := pen.get_inner_rect().grow(0.05)
    for cow in pen.cows:
        if cow.walked_distance > 0.5:
            walked += 1
        for s in cow.states_seen:
            states[s] = true
        _check(inner.has_point(Vector2(cow.position.x, cow.position.z)), "vaca saiu do curral: %s" % cow.position)
    _check(walked >= 4, "poucas vacas andaram: %d" % walked)
    _check(states.has(FarmCow.State.GRAZE) and states.has(FarmCow.State.WALK), "vacas sem pastar/andar")
    _check(frames_seen.size() >= 6, "animação com poucos frames: %d" % frames_seen.size())
    print("FARM003_COWS_OK cows=%d colors=%d walked=%d frames=%d pen=%s" % [pen.cows.size(), colors.size(), walked, frames_seen.size(), pen.rect])
    await process_frame

## Troca de idioma pelas Configurações: tudo no HUD, modais, placas e faixa
## acompanha na hora, sem recarregar.
func _test_languages() -> void:
    var hud := world.hud
    var expected := {
        "pt_BR": {"mission": "Colher tomates", "reward": "Prêmio", "level": "Nível 1", "sign": "Abóbora", "shop": "Loja da Fazenda", "store": "Loja", "banner": "Mochila cheia! Leve as caixas ao Balcão de vendas.", "helper": "Ajudante", "sale": "2 caixas", "money": "Faltam 40 para o ajudante."},
        "es": {"mission": "Cosechar tomates", "reward": "Premio", "level": "Nivel 1", "sign": "Calabaza", "shop": "Tienda de la Granja", "store": "Tienda", "banner": "¡Mochila llena! Lleva las cajas al puesto de ventas.", "helper": "Ayudante", "sale": "2 cajas", "money": "Faltan 40 para el ayudante."},
        "en": {"mission": "Harvest tomatoes", "reward": "Reward", "level": "Level 1", "sign": "Pumpkin", "shop": "Farm Shop", "store": "Shop", "banner": "Backpack full! Take the crates to the sales stall.", "helper": "Helper", "sale": "2 crates", "money": "You need 40 more for the helper."},
    }
    world.harvest_inventory.set_amount(&"tomato", world.harvest_inventory.get_capacity())
    await process_frame
    var popup := hud.show_sale_popup(10, 2)
    popup.lifetime = 30.0
    hud.shop_modal.open_shop()
    for locale in ["en", "es", "pt_BR"]:
        hud.settings_modal.choose_language(locale)
        await process_frame
        await process_frame
        var e: Dictionary = expected[locale]
        _check(hud.mission_panel.get_title() == e["mission"], "%s missão: %s" % [locale, hud.mission_panel.get_title()])
        _check(hud.mission_panel.reward_caption.text == e["reward"], "%s prêmio: %s" % [locale, hud.mission_panel.reward_caption.text])
        _check(hud.level_panel.title_label.text == e["level"], "%s nível: %s" % [locale, hud.level_panel.title_label.text])
        _check(world.get_crop_sign(&"pumpkin")._label.text == e["sign"], "%s placa: %s" % [locale, world.get_crop_sign(&"pumpkin")._label.text])
        _check(hud.shop_modal._title.text == e["shop"], "%s loja: %s" % [locale, hud.shop_modal._title.text])
        _check(hud.store_button.caption.text == e["store"] or tr(hud.store_button.caption.text) == e["store"], "%s botão loja: %s" % [locale, hud.store_button.caption.text])
        _check(hud.get_banner_message() == e["banner"], "%s faixa: %s" % [locale, hud.get_banner_message()])
        _check(world.helper_pad._title.text == e["helper"], "%s ajudante: %s" % [locale, world.helper_pad._title.text])
        _check(is_instance_valid(popup) and popup.detail_label.text == e["sale"], "%s venda: %s" % [locale, popup.detail_label.text if is_instance_valid(popup) else "?"])
        hud.show_banner("HELPER_NO_MONEY", 5.0, [40])
        _check(hud.get_banner_message() == e["money"], "%s aviso: %s" % [locale, hud.get_banner_message()])
        # Volta a mochila cheia para a próxima volta do laço.
        hud._show_banner_key(FarmHUD.FULL_BACKPACK_MESSAGE, [])
        print("FARM003_LOCALE_OK %s mission='%s' banner='%s'" % [locale, hud.mission_panel.get_title(), hud.get_banner_message()])
    # Troca com um aviso com argumento traduzível já na tela.
    hud.settings_modal.choose_language("pt_BR")
    hud.show_banner("HARVEST_SELL_FIRST", 5.0, ["@lower:CROP_CORN"])
    hud.settings_modal.choose_language("en")
    await process_frame
    _check(hud.get_banner_message() == "Backpack busy: sell at the stall before harvesting corn", "aviso com cultura não retraduziu: %s" % hud.get_banner_message())
    hud.shop_modal.close_shop()
    hud.settings_modal.choose_language("pt_BR")
    world.harvest_inventory.set_amount(&"tomato", 0)

## Todas as chaves usadas no código existem no ui.csv com as 3 línguas.
func _test_csv() -> void:
    var file := FileAccess.open("res://localization/ui.csv", FileAccess.READ)
    var header := file.get_csv_line()
    _check(Array(header) == ["keys", "pt_BR", "es", "en"], "cabeçalho do ui.csv")
    var keys := {}
    while not file.eof_reached():
        var line := file.get_csv_line()
        if line.size() < 4 or line[0].is_empty():
            continue
        keys[line[0]] = true
        for column in range(1, 4):
            _check(not line[column].strip_edges().is_empty(), "chave %s sem %s" % [line[0], header[column]])
    var regex := RegEx.create_from_string("\"([A-Z][A-Z0-9_]{3,})\"")
    var missing: Array[String] = []
    for dir in ["res://scripts/ui", "res://scripts/world", "res://scripts/progression", "res://scripts/helpers", "res://scripts/farming"]:
        for path in _gd_files(dir):
            var text := FileAccess.get_file_as_string(path)
            for m in regex.search_all(text):
                var key := m.get_string(1)
                var prefixes := ["HELPER_", "CROP_", "REWARD_", "MESSAGE_", "AREA_", "WOOD_", "SEASON_", "HARVEST_", "SHOP_", "SETTINGS_", "MISSION_", "LEVEL_", "SALE_", "BACKPACK_", "STORE_", "HELP_"]
                var is_key := false
                for prefix in prefixes:
                    if key.begins_with(prefix):
                        is_key = true
                if is_key and not keys.has(key) and not key.ends_with("_") and key != "HELPER_HIRED_%s":
                    missing.append("%s (%s)" % [key, path.get_file()])
    _check(missing.is_empty(), "chaves sem tradução: %s" % [missing])
    print("FARM003_CSV_OK keys=%d" % keys.size())

func _gd_files(dir: String) -> Array[String]:
    var out: Array[String] = []
    for f in DirAccess.get_files_at(dir):
        if f.ends_with(".gd"):
            out.append(dir.path_join(f))
    for d in DirAccess.get_directories_at(dir):
        out.append_array(_gd_files(dir.path_join(d)))
    return out
