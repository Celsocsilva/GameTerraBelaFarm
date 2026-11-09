extends SceneTree
## FV-PROPS-001 — banca de feira no balcão de vendas e placas de cultura.
## Uso: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/stall_signs_smoke.gd
## Confere: arte da banca no lugar do tampo antigo, colisão/pegada inalteradas,
## caixas pousando sobre a toalha e na frente do quadro, placa do tomate no
## terreno, troca de placa por cultura (milho/abóbora) e nomes em PT/ES/EN
## cabendo na faixa em branco.

var _failed := false

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failed = true
        push_error("STALL_SIGNS_SMOKE_FAIL " + message)
        print("STALL_SIGNS_SMOKE_FAIL ", message)

func _run() -> void:
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    var counter := world.sales_counter

    # Banca: arte nova, sem o tampo/rebordo marrom antigo.
    var stall := counter.get_node_or_null("CounterBody/StallVisual") as MeshInstance3D
    _check(stall != null, "StallVisual ausente")
    _check(counter.get_node_or_null("CounterBody/CounterTop") == null, "tampo antigo ainda existe")
    _check(counter.get_node_or_null("CounterBody/CounterBack") == null, "rebordo antigo ainda existe")
    var material := stall.material_override as StandardMaterial3D
    _check(material.albedo_texture == SalesCounter.STALL_TEXTURE, "textura da banca")
    _check(SalesCounter.STALL_TEXTURE.resource_path == "res://assets/sales/stall_market_gingham.png", "caminho da arte da banca (plana)")
    # Colisão e pegada inalteradas (11,05 x 2,925 m).
    var shape := (counter.get_node("CounterBody/CounterCollision") as CollisionShape3D).shape as BoxShape3D
    _check(shape.size.is_equal_approx(Vector3(11.05, 1.6, 2.925 + 0.27)), "colisão mudou: %s" % shape.size)
    _check(counter.get_half_extents().is_equal_approx(Vector2(5.525, 1.4625)), "meia pegada mudou")
    _check(counter.get_node_or_null("CounterBarrier_L") != null and counter.get_node_or_null("CounterBarrier_R") != null, "cercas laterais")
    # Quadro inclinado: pé na frente (+Z) no chão, topo na borda de trás (-Z).
    var quad := stall.mesh as QuadMesh
    var bottom := stall.to_global(Vector3(0.0, -quad.size.y * 0.5, 0.0)) - counter.global_position
    var top := stall.to_global(Vector3(0.0, quad.size.y * 0.5, 0.0)) - counter.global_position
    _check(absf(bottom.y) < 0.01 and absf(bottom.z - 1.4625) < 0.01, "pé da banca fora do chão/frente: %s" % bottom)
    _check(absf(top.z + 1.4625) < 0.01 and absf(top.y - SalesCounter.get_stall_rise()) < 0.01, "topo da banca: %s" % top)
    _check(stall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "banca não deve projetar sombra")

    # Caixas: acima do quadro (sempre na frente na tela) e com a mesma pilha.
    world.harvest_inventory.set_amount(&"tomato", 56)
    counter.deposit_from(world.harvest_inventory, world.get_farmer_hands_position())
    _check(counter.get_displayed_crates() == 7, "7 caixas no balcão")
    counter.finish_jumps()
    _check(counter.get_visible_crate_count() == SalesCounter.MAX_VISUAL_CRATES and counter.get_count_text() == "x7", "pilha única após o pulo")
    var rise := SalesCounter.get_stall_rise()
    for index in SalesCounter.MAX_VISUAL_CRATES:
        var slot := counter.get_crate_slot_position(index) - counter.global_position
        # Altura do quadro inclinado nessa profundidade.
        var plane_y := rise * (1.4625 - slot.z) / 2.925
        if slot.y <= plane_y + 0.05:
            _check(false, "caixa %d atrás do quadro da banca (y %.2f <= %.2f)" % [index, slot.y, plane_y])
            break
    # Na tela: base da pilha dentro da toalha desenhada.
    var camera := world.camera
    var focus := counter.global_position
    camera.global_position = focus + Vector3(0.0, world.camera_height, world.camera_distance)
    camera.look_at(focus, Vector3.UP)
    var img_top := camera.unproject_position(stall.to_global(Vector3(0.0, quad.size.y * 0.5, 0.0))).y
    var img_bottom := camera.unproject_position(stall.to_global(Vector3(0.0, -quad.size.y * 0.5, 0.0))).y
    for index in [0]:
        var y := camera.unproject_position(counter.get_crate_slot_position(index)).y
        var frac := (y - img_top) / (img_bottom - img_top)
        print("CRATE_ROW slot=%d fracao_da_arte=%.3f" % [index, frac])
        _check(frac > 0.0 and frac < 0.45, "fileira %d fora da toalha (%.3f)" % [index, frac])
    # Estoque e vendas continuam pelo mesmo caminho.
    _check(counter.take_units(8) == 8 and counter.get_stored_total() == 48, "take_units")

    # Placas de cultura.
    _check(world.crop_signs.size() == 1, "uma placa por terreno (hoje só tomate): %d" % world.crop_signs.size())
    var sign := world.get_crop_sign(&"tomato")
    _check(sign != null, "placa do tomate")
    var field := world.get_planting_area_rect()
    _check(not field.has_point(Vector2(sign.position.x, sign.position.z)), "placa dentro do solo")
    _check(sign.position.distance_to(Vector3(field.position.x, 0.0, field.end.y)) < 2.0, "placa longe do canto do terreno")
    _check(sign.get_texture().resource_path == "res://assets/props/signs/sign_crop_tomato.png", "arte da placa do tomate")
    var expected := {
        &"tomato": {"pt_BR": "Tomate", "es": "Tomate", "en": "Tomato", "art": "sign_crop_tomato.png"},
        &"corn": {"pt_BR": "Milho", "es": "Maíz", "en": "Corn", "art": "sign_crop_corn.png"},
        &"pumpkin": {"pt_BR": "Abóbora", "es": "Calabaza", "en": "Pumpkin", "art": "sign_crop_pumpkin.png"},
    }
    for crop in expected:
        sign.set_crop(crop)
        _check(sign.get_crop_id() == crop, "set_crop %s" % crop)
        _check(sign.get_texture().resource_path.ends_with(expected[crop]["art"]), "arte %s" % crop)
        for locale in ["pt_BR", "es", "en"]:
            TranslationServer.set_locale(locale)
            sign._refresh_text()
            _check(sign.get_text() == expected[crop][locale], "%s/%s: '%s'" % [crop, locale, sign.get_text()])
            _check(sign.get_text_width() <= sign.get_band_width() + 0.001, "texto não cabe na faixa: %s/%s" % [crop, locale])
            print("SIGN %s %s '%s' largura=%.2f faixa=%.2f" % [crop, locale, sign.get_text(), sign.get_text_width(), sign.get_band_width()])
    # Cultura desconhecida mantém a placa atual.
    sign.set_crop(&"pumpkin")
    sign.set_crop(&"banana")
    _check(sign.get_crop_id() == &"pumpkin", "cultura desconhecida trocou a placa")
    TranslationServer.set_locale("pt_BR")

    if _failed:
        print("STALL_SIGNS_SMOKE_FAIL")
        quit(1)
        return
    print("STALL_SIGNS_SMOKE_OK")
    quit()
