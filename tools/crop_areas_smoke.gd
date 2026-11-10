extends SceneTree
## Testes headless de UI-MESSAGE-001 (modal grande), ENV-FENCE-001 (cerca com a
## arte de madeira) e CROP-AREAS-001 (áreas de milho e abóbora). Código de
## saída 1 em falha. Uso: Godot --headless --path . -s tools/crop_areas_smoke.gd

## Distância mínima (m) entre as bordas de duas áreas de cultura (com estoque e plataforma).
## FV-POLISH-001: com as áreas no tamanho do tomate, o vão mínimo virou
## a passagem livre entre elas (antes 6 m com áreas de 0,75x).
const MIN_AREA_GAP := 2.5

var _failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures += 1
        push_error("CROP_AREAS_SMOKE_FAIL: " + message)

func _run() -> void:
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    _test_fences(world)
    _test_crop_areas(world)
    await _test_locked_pads(world)
    await _test_message_popup(world)
    var area_count := world.crop_areas.size()
    world.queue_free()
    await process_frame
    TranslationServer.set_locale("pt_BR")
    if _failures > 0:
        print("CROP_AREAS_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("CROP_AREAS_SMOKE_OK areas=%d" % area_count)
    quit()

func _test_fences(world: FarmWorld) -> void:
    var fence := world.get_node_or_null("Fence") as StaticBody3D
    _check(fence != null, "cerca provisória sumiu")
    if fence == null:
        return
    var run := fence.get_node_or_null("FenceRun") as FenceRun
    _check(run != null, "cerca sem a arte de madeira (FenceRun)")
    _check(fence.get_node_or_null("CollisionShape3D") != null, "cerca perdeu a colisão")
    if run:
        _check(is_equal_approx(run.length, FarmWorld.FENCE_SIZE.x), "comprimento da cerca mudou")
        _check(run.get_segment_count() >= 1, "cerca sem peças")
        var material := (run.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
        _check(material.albedo_texture == FenceRun.TEXTURE, "cerca sem o PNG de cerca")
        # Postes nas pontas: o primeiro e o último poste caem nas pontas do trecho.
        var first := run.get_child(0) as MeshInstance3D
        var k := run.get_segment_length() / (FenceRun.LAST_POST_PX - FenceRun.FIRST_POST_PX)
        var left_post := first.position.x - (first.mesh as QuadMesh).size.x * 0.5 + FenceRun.FIRST_POST_PX * k
        _check(absf(left_post + run.length * 0.5) < 0.01, "primeiro poste fora da ponta: %.3f" % left_post)
        var last := run.get_child(run.get_child_count() - 1) as MeshInstance3D
        var right_post := last.position.x - (last.mesh as QuadMesh).size.x * 0.5 + FenceRun.LAST_POST_PX * k
        _check(absf(right_post - run.length * 0.5) < 0.01, "último poste fora da ponta: %.3f" % right_post)
        _check(absf(run.get_segment_length() - run.target_segment_length) <= run.target_segment_length * 0.25, "vão esticado demais")
    for side in ["L", "R"]:
        var barrier := world.sales_counter.get_node_or_null("CounterBarrier_" + side) as StaticBody3D
        _check(barrier != null, "cerca do balcão sumiu: " + side)
        if barrier:
            _check(barrier.get_node_or_null("Fence") is FenceRun, "cerca do balcão sem a arte de madeira: " + side)
            var has_collision := false
            for child in barrier.get_children():
                has_collision = has_collision or child is CollisionShape3D
            _check(has_collision, "cerca do balcão perdeu a colisão: " + side)
            _check(barrier.get_node_or_null("Rail") == null, "trilhos antigos de caixa ainda presentes")

func _test_crop_areas(world: FarmWorld) -> void:
    _check(world.crop_areas.size() == FarmWorld.CROP_AREAS.size(), "esperadas %d áreas extras" % FarmWorld.CROP_AREAS.size())
    var footprints: Array[Rect2] = [world.get_planting_area_rect().merge(world.get_extra_plot_rect()).merge(world.get_helper_pad_rect())]
    var map := world.get_map_rect().grow(-0.5)
    for entry in world.crop_areas:
        var crop: StringName = entry["crop"]
        var field: Rect2 = entry["field"]
        var stock: Rect2 = entry["stock"]
        var pad_rect: Rect2 = entry["pad_rect"]
        var whole := field.merge(stock).merge(pad_rect)
        _check(map.encloses(whole), "%s fora do mapa: %s" % [crop, whole])
        # Placa da cultura certa, na frente do canteiro.
        var sign := world.get_crop_sign(crop)
        _check(sign != null, "sem placa de " + crop)
        if sign:
            _check(field.grow(2.0).has_point(Vector2(sign.position.x, sign.position.z)), "placa longe do canteiro de " + crop)
        # Canteiro com a mesma arte do solo; não entra no PlantingGrid (sem arte de crescimento).
        var area := entry["area"] as Node3D
        _check(area.get_meta("crop", "") == String(crop) and area.get_meta("is_crop_group", false), "meta da área de " + crop)
        # FARM-003: a abóbora usa 2 peças do solo largo; as outras, 3 tiras.
        var wide := String(area.get_meta("soil", "")) == "wide"
        _check(area.get_child_count() == (2 if wide else FarmWorld.CROP_AREA_STRIPS), "tiras da área de " + crop)
        _check(wide == (crop == &"pumpkin"), "solo largo só na abóbora: " + crop)
        for plot in area.get_children():
            var soil := plot.get_node("PlowedSoil") as MeshInstance3D
            var expected_soil := FarmWorld.SOIL_TEXTURE_WIDE if wide else FarmWorld.SOIL_TEXTURE
            _check((soil.material_override as StandardMaterial3D).albedo_texture == expected_soil, "solo de " + crop)
        for cell in world.planting_grid.cells.values():
            var p: Vector3 = cell["position"]
            _check(not field.has_point(Vector2(p.x, p.z)), "célula do PlantingGrid dentro da área de " + crop)
        # CROP-CORN-001: culturas plantáveis têm grade própria, com covas dentro do canteiro.
        if FarmWorld.PLANTABLE_CROPS.has(crop):
            var grid := world.get_crop_grid(crop)
            _check(grid != null and not grid.cells.is_empty(), "sem covas de " + crop)
            if grid:
                for cell in grid.cells.values():
                    var p: Vector3 = cell["position"]
                    _check(field.has_point(Vector2(p.x, p.z)) and cell["crop_id"] == String(crop), "cova de %s fora do canteiro" % crop)
        # Estoque de 10% e pilha da cultura.
        var ratio := stock.get_area() / field.get_area()
        _check(absf(ratio - FarmWorld.EXTRA_PLOT_AREA_RATIO) < 0.01, "estoque de %s não é 10%%: %.3f" % [crop, ratio])
        var pile := entry["pile"] as TomatoPile
        _check(pile.item_id == crop and pile.centered, "pilha de " + crop)
        _check(stock.has_point(Vector2(pile.position.x, pile.position.z)), "pilha fora do estoque de " + crop)
        # Plataforma do ajudante no chão, depois do estoque, sem encostar nele.
        var pad := entry["pad"] as HelperPad
        var hiring := entry["hiring"] as HelperHiring
        var requirement := HelperConfig.initial_requirement(crop)
        _check(hiring.requirement_item == requirement.get("item", &"") and hiring.requirement_crates == int(requirement.get("crates", 0)), "requisito do ajudante de " + crop)
        _check(pad.rect.is_equal_approx(pad_rect), "plataforma fora do lugar: " + crop)
        _check(not pad_rect.intersects(stock) and not pad_rect.intersects(field), "plataforma sobre o solo de " + crop)
        # Longe do rio, das pontes, do balcão, da base de dinheiro e das construções.
        for corner in [whole.position, whole.end, Vector2(whole.position.x, whole.end.y), Vector2(whole.end.x, whole.position.y), whole.get_center()]:
            _check(not world.river_system.is_point_in_water(Vector3(corner.x, 0.0, corner.y), 2.0), "%s no rio: %s" % [crop, corner])
        for bridge in world.river_system.get_bridges():
            var b := Vector2(bridge.global_position.x, bridge.global_position.z)
            _check(not whole.grow(1.0).has_point(b + Vector2(3.0, 0.0)), "%s bloqueia a ponte %s" % [crop, bridge.name])
        var counter_half := world.sales_counter.get_half_extents()
        var counter_line := Rect2(-world.farm_size * 0.5, world.sales_counter.position.z - counter_half.y - 4.0, world.farm_size, 8.0)
        _check(not whole.intersects(counter_line), crop + " encosta no balcão/cerca")
        for name in ["Fence"]:
            var node := world.get_node(name) as Node3D
            _check(not whole.grow(1.5).has_point(Vector2(node.position.x, node.position.z)), "%s encosta em %s" % [crop, name])
        var spawn := Vector2(world.farmer.global_position.x, world.farmer.global_position.z)
        _check(not whole.has_point(spawn), "fazendeiro nasce na área de " + crop)
        for other in footprints:
            var gap := _rect_gap(whole, other)
            _check(gap >= MIN_AREA_GAP, "%s perto demais de outra área: %.2f m" % [crop, gap])
        footprints.append(whole)
        print("CROP_AREA %s field=%s stock=%s pad=%s" % [crop, field, stock, pad_rect])

func _rect_gap(a: Rect2, b: Rect2) -> float:
    var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
    var dz := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
    return Vector2(dx, dz).length()

## A plataforma bloqueada (cultura sem plantio) não cobra nem contrata e avisa uma vez por entrada.
func _test_locked_pads(world: FarmWorld) -> void:
    world.wallet.add(500)
    var before := world.wallet.get_balance()
    for entry in world.crop_areas:
        var pad := entry["pad"] as HelperPad
        var hiring := entry["hiring"] as HelperHiring
        # CROP-CORN-001: o milho já planta; sua plataforma fica liberada.
        if FarmWorld.PLANTABLE_CROPS.has(entry["crop"]):
            _check(not pad.locked, "plataforma de %s deveria estar liberada" % entry["crop"])
            continue
        _check(pad.locked, "plataforma de %s deveria estar bloqueada" % entry["crop"])
        var touches := [0]
        pad.locked_touched.connect(func() -> void: touches[0] += 1)
        var center := pad.rect.get_center()
        var on_pad := Vector3(center.x, 0.0, center.y)
        var paid := 0
        for frame in 120:
            paid += pad.process_farmer_position(on_pad, 1.0 / 30.0)
        _check(paid == 0 and hiring.grade == 0 and hiring.paid == 0, "plataforma bloqueada cobrou: " + str(entry["crop"]))
        _check(touches[0] == 1, "aviso da plataforma bloqueada: %d" % touches[0])
        pad.process_farmer_position(Vector3(center.x, 0.0, center.y + 20.0), 0.1)
        pad.process_farmer_position(on_pad, 0.1)
        _check(touches[0] == 2, "aviso deve voltar ao reentrar")
        _check(pad.get_cost_text() == pad.tr("AREA_SOON"), "texto da plataforma bloqueada")
    _check(world.wallet.get_balance() == before, "saldo mudou nas plataformas bloqueadas")
    # A plataforma do tomate continua funcionando.
    _check(not world.helper_pad.locked, "plataforma do tomate bloqueada")
    await process_frame

## Modal grande: abre, ajusta os textos nos 3 idiomas, OK fecha e emite uma vez.
func _test_message_popup(world: FarmWorld) -> void:
    var popup := world.hud.message_popup
    _check(popup != null, "FarmHUD sem MessagePopup")
    if popup == null:
        return
    _check(popup.get_node("Card/Background").texture.resource_path == "res://assets/ui/components/panel_message_large.png", "modal sem a moldura nova")
    _check(world.hud.reward_popup != popup, "modal de recompensa deve continuar separado")
    var closes := [0]
    popup.closed.connect(func() -> void: closes[0] += 1)
    var long_text := "Pare no quadro de madeira com dinheiro para contratar o ajudante. Ele colhe os pés maduros, empilha as caixas na área de estoque e replanta as covas vazias para você."
    for locale in ["pt_BR", "es", "en"]:
        TranslationServer.set_locale(locale)
        for case in [["HELP_HELPER_TITLE", "HELP_HELPER_TEXT"], ["Ajudante da fazenda", long_text]]:
            world.hud.show_message(case[0], case[1])
            await process_frame
            _check(popup.is_open and popup.visible, "modal não abriu")
            _check(popup.title_label.text == popup.tr(case[0]), "título não traduzido (%s)" % locale)
            _check(popup.message_label.text == popup.tr(case[1]), "mensagem não traduzida (%s)" % locale)
            _check(popup.ok_button.caption.text == "OK", "botão OK")
            var font := popup.message_label.get_theme_font("font")
            var title_size := popup.title_label.get_theme_font_size("font_size")
            _check(font.get_string_size(popup.title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x <= MessagePopup.TITLE_RECT.size.x, "título sai da faixa (%s)" % locale)
            var size := popup.message_label.get_theme_font_size("font_size")
            _check(UiStyle.text_fits(font, popup.message_label.text, size, MessagePopup.MESSAGE_RECT.size.x - 4.0, MessagePopup.MESSAGE_RECT.size.y, MessagePopup.MESSAGE_MAX_LINES, 6.0), "mensagem sai do creme (%s, fonte %d)" % [locale, size])
            _check(popup.message_label.position == MessagePopup.MESSAGE_RECT.position and popup.message_label.size == MessagePopup.MESSAGE_RECT.size, "mensagem saiu da área interna")
            popup.close()
            popup.close()
    _check(closes[0] == 6, "closed deve sair uma vez por abertura: %d" % closes[0])
    _check(not popup.is_open, "modal continuou aberto")
