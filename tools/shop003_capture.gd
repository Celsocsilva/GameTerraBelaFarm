extends SceneTree
## FV-SHOP-003: capturas da loja (HUD antes/depois de abrir, PT/ES/EN, botão pressionado).
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
    var args := OS.get_cmdline_user_args(); var out := args[0] if not args.is_empty() else "res://docs/evidence/fv-shop-003"
    DirAccess.make_dir_recursive_absolute(out)
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world); await create_timer(.8).timeout
    world.wallet.set_balance(12450); world.wallet.set_gold(860)
    await _shot(out, "00-hud-sem-loja.png")
    var hud_wallet: Control = world.hud.wallet_bar
    world.hud.shop_modal.open_store(); await create_timer(.4).timeout
    var store_wallet: Control = world.hud.shop_modal.get_wallet_bar()
    print("SHOP003_WALLET_SAME=", hud_wallet.get_global_rect().is_equal_approx(store_wallet.get_global_rect()), " ", hud_wallet.get_global_rect(), " ", store_wallet.get_global_rect(), " ", store_wallet.get_global_transform().get_scale())
    for locale in ["pt_BR", "es_ES", "en_US"]:
        TranslationServer.set_locale(locale); world.hud.shop_modal.refresh_language(); await create_timer(.3).timeout
        await _shot(out, "loja-%s.png" % locale)
    TranslationServer.set_locale("pt_BR"); world.hud.shop_modal.refresh_language(); await create_timer(.3).timeout
    var card: Control = world.hud.shop_modal._cards[0]
    var btn := card.get_node("PurchaseButton") as Control
    var before := _rects(world.hud.shop_modal)
    var center := btn.get_global_rect().get_center() * root.get_final_transform().get_scale()
    _mouse(center, true); await create_timer(.25).timeout
    await _shot(out, "loja-botao-pressionado.png")
    print("SHOP003_PRESSED_SAME_RECTS=", _rects(world.hud.shop_modal) == before)
    _mouse(center, false); await create_timer(.4).timeout
    await _shot(out, "loja-apos-clique.png")
    print("SHOP003_AFTER_CLICK_SAME_RECTS=", _rects(world.hud.shop_modal) == before, " status=", world.hud.shop_modal._status.text)
    world.hud.shop_modal.next(); await create_timer(.4).timeout
    await _shot(out, "loja-carrossel-pagina-2.png")
    world.hud.shop_modal.next(); await create_timer(.4).timeout
    await _shot(out, "loja-carrossel-pagina-3.png")
    print("SHOP003_PAGES=", world.hud.shop_modal.page_count(), " dots=", world.hud.shop_modal._indicator.text, " next_disabled=", world.hud.shop_modal._next.disabled)
    # Retrato (celular em pé).
    root.content_scale_size = Vector2i(720, 1280); DisplayServer.window_set_size(Vector2i(720, 1280)); await create_timer(.6).timeout
    world.hud.shop_modal.go_to_page(0); await create_timer(.4).timeout
    await _shot(out, "loja-retrato-pt_BR.png")
    print("SHOP003_PORTRAIT_PAGES=", world.hud.shop_modal.page_count(), " dots=", world.hud.shop_modal._indicator.text)
    quit()
func _mouse(at: Vector2, down: bool) -> void:
    var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = down; ev.position = at; ev.global_position = at
    Input.parse_input_event(ev)
func _rects(screen: Control) -> Array:
    var out: Array = []
    for card in screen._cards:
        out.append([card.get_global_rect(), card.scale, (card.get_node("PurchaseButton") as Control).get_global_rect(), (card.get_node("PurchaseButton") as Control).scale])
    out.append([screen.get_wallet_bar().get_global_rect(), screen.get_wallet_bar().scale])
    return out
func _shot(out: String, name: String) -> void:
    for i in 4: await process_frame
    root.get_texture().get_image().save_png(out.path_join(name))
