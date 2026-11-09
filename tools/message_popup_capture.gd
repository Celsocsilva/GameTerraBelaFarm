extends SceneTree
## UI-MESSAGE-001 — capturas do modal grande (moldura com laço vermelho) no jogo
## real, nos 3 idiomas, com o texto real curto e com um texto longo de estresse.
## Rodar SEM --headless:
##   godot --path . --resolution 720x1280 -s tools/message_popup_capture.gd -- <pasta absoluta> [tag]
##   godot --path . --resolution 1280x720 -s tools/message_popup_capture.gd -- <pasta absoluta> [tag]

## Texto longo (bem maior que o recomendado) para provar o ajuste da fonte.
const STRESS := {
    "pt_BR": ["Ajudante da fazenda", "Pare no quadro de madeira com dinheiro para contratar o ajudante. Ele colhe os pés maduros, empilha as caixas na área de estoque e replanta as covas vazias para você."],
    "es": ["Ayudante de la granja", "Párate en el cuadro de madera con dinero para contratar al ayudante. Cosecha las plantas maduras, apila las cajas en el área de almacén y vuelve a plantar por ti."],
    "en": ["Farm helper", "Stand on the wooden board with money to hire the helper. They harvest ripe plants, stack the crates in the storage area and replant the empty holes for you."],
}

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/ui-message-001")
    var tag := args[1] if args.size() > 1 else "modal"
    DirAccess.make_dir_recursive_absolute(out_dir)
    var window_size := DisplayServer.window_get_size()
    var orientation := "retrato" if window_size.y > window_size.x else "paisagem"
    if window_size.y > window_size.x:
        root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    await create_timer(0.6).timeout
    var popup := world.hud.message_popup
    for locale in ["pt_BR", "es", "en"]:
        TranslationServer.set_locale(locale)
        world.hud.show_message("HELP_HELPER_TITLE", "HELP_HELPER_TEXT")
        await create_timer(0.6).timeout
        _report(popup, "%s %s normal" % [orientation, locale])
        await _shot(out_dir, "%s-%s-%s-normal" % [tag, orientation, locale], popup)
        var texts: Array = STRESS[locale]
        popup.show_message(texts[0], texts[1])
        await create_timer(0.6).timeout
        _report(popup, "%s %s longo" % [orientation, locale])
        await _shot(out_dir, "%s-%s-%s-longo" % [tag, orientation, locale], popup)
        popup.close()
        await create_timer(0.3).timeout
    TranslationServer.set_locale("pt_BR")
    quit()

func _report(popup: MessagePopup, label: String) -> void:
    var parts: Array[String] = []
    for node in [popup.title_label, popup.message_label, popup.ok_button.caption]:
        var l := node as Label
        parts.append("%s='%s' font=%d" % [l.name, l.text, l.get_theme_font_size("font_size")])
    print("CAPTURE_MESSAGE %s scale=%.2f %s" % [label, popup.get_card_scale(), " | ".join(parts)])

func _shot(out_dir: String, file: String, popup: MessagePopup) -> void:
    for frame in 4:
        await process_frame
    var image := root.get_texture().get_image()
    image.save_png(out_dir.path_join(file + ".png"))
    var scale_px := Vector2(image.get_size()) / root.get_visible_rect().size
    var visual := popup.card.get_global_transform() * Rect2(Vector2.ZERO, popup.card.size)
    var crop := Rect2i(Rect2(visual.position * scale_px, visual.size * scale_px)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
    image.get_region(crop).save_png(out_dir.path_join(file + "-zoom.png"))
    print("CAPTURE ", out_dir.path_join(file + ".png"))
