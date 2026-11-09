extends SceneTree
## UI-REWARD-001 — capturas do modal de recompensa no jogo real, nos 3 idiomas,
## com os textos normais e com textos longos de estresse. Rodar SEM --headless:
##   godot --path . --resolution 720x1280 -s tools/reward_popup_capture.gd -- <pasta absoluta> [tag]
##   godot --path . --resolution 1280x720 -s tools/reward_popup_capture.gd -- <pasta absoluta> [tag]
## Para cada caso salva a tela inteira e um recorte ampliado do cartão.

## Textos longos (bem maiores que as traduções reais) para provar o ajuste.
const STRESS := {
    "pt_BR": ["Recompensa especial da colheita!", "Missão diária de colheita de tomates concluída com sucesso!", "Coletar recompensa"],
    "es": ["¡Recompensa especial de la cosecha!", "¡Misión diaria de cosecha de tomates completada con éxito!", "Recoger recompensa"],
    "en": ["Special harvest reward unlocked!", "Daily tomato harvest quest successfully completed today!", "Collect reward"],
}

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var out_dir := args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/ui-reward-001")
    var tag := args[1] if args.size() > 1 else "depois"
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
    var hud := world.hud
    var popup := hud.reward_popup
    for locale in ["pt_BR", "es", "en"]:
        TranslationServer.set_locale(locale)
        # 1. Caso real: missão "Colher tomates" concluída pela mochila cheia.
        if locale == "pt_BR":
            world.harvest_inventory.set_amount(&"tomato", 56)
            await create_timer(0.2).timeout
        if not popup.is_open:
            # Mesma chamada do FarmHUD ao concluir uma missão (chaves padrão).
            popup.show_reward(RewardPopup.DEFAULT_TITLE, RewardPopup.DEFAULT_MESSAGE, 10)
        await create_timer(0.6).timeout
        _report(popup, "%s %s normal" % [orientation, locale])
        await _shot(out_dir, "%s-%s-%s-normal" % [tag, orientation, locale], popup)
        # 2. Estresse: textos longos e valor alto.
        var texts: Array = STRESS[locale]
        popup.show_reward(texts[0], texts[1], 9999999, RewardPopup.CASH_ICON, texts[2])
        await create_timer(0.6).timeout
        _report(popup, "%s %s longo" % [orientation, locale])
        await _shot(out_dir, "%s-%s-%s-longo" % [tag, orientation, locale], popup)
        popup.collect()
        await create_timer(0.3).timeout
    TranslationServer.set_locale("pt_BR")
    quit()

func _report(popup: RewardPopup, label: String) -> void:
    var parts: Array[String] = []
    for node in [popup.title_label, popup.message_label, popup.value_label, popup.collect_button.caption]:
        var l := node as Label
        parts.append("%s='%s' font=%d" % [l.name, l.get_text() if l.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else l.tr(l.text), l.get_theme_font_size("font_size")])
    print("CAPTURE_REWARD %s %s" % [label, " | ".join(parts)])

func _shot(out_dir: String, file: String, popup: RewardPopup) -> void:
    for frame in 4:
        await process_frame
    var image := root.get_texture().get_image()
    image.save_png(out_dir.path_join(file + ".png"))
    var scale_px := Vector2(image.get_size()) / root.get_visible_rect().size
    var visual := popup.card.get_global_transform() * Rect2(Vector2.ZERO, popup.card.size)
    var crop := Rect2i(Rect2(visual.position * scale_px, visual.size * scale_px)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
    var detail := image.get_region(crop)
    if detail.get_width() < 577:
        var factor := 577.0 / detail.get_width()
        detail.resize(int(detail.get_width() * factor), int(detail.get_height() * factor), Image.INTERPOLATE_LANCZOS)
    detail.save_png(out_dir.path_join(file + "-zoom.png"))
    print("CAPTURE ", out_dir.path_join(file + ".png"))
