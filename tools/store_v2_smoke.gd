extends SceneTree
## STORE-V2-001 + FV-SHOP-003: catálogo, carrossel, preços/regiões, i18n e simulador seguro.
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
    if not value: failures += 1; push_error("STORE_V2_FAIL " + message)
func _run() -> void:
    _catalog(); await _screen(); _purchase(); _finish()
func _catalog() -> void:
    check(StoreCatalog.PRODUCT_IDS.size() == 7, "sete produtos")
    var ids := {}; for product in StoreCatalog.all():
        var id: StringName = product["id"]; check(not ids.has(id), "id duplicado " + id); ids[id] = true
        check(StoreCatalog.art_for(product) != null, "arte ausente " + id)
        check(not StoreCatalog.demo_price(id, "BR").is_empty(), "preço BR " + id)
    StoreLocalization.set_demo_region("BR"); check(StoreLocalization.price_for(&"vip_7d") == "R$ 82,99", "BRL")
    StoreLocalization.set_demo_region("US"); check(StoreLocalization.price_for(&"vip_7d") == "US$ 16.99", "USD")
    TranslationServer.set_locale("es_ES"); StoreLocalization.set_demo_region("US"); check(StoreLocalization.price_for(&"remove_ads") == "US$ 8.99", "idioma não pode alterar região")
    StoreLocalization.set_demo_region("ES_DEMO"); check(StoreLocalization.price_for(&"coins_large") == "US$ 15.99", "ES demo USD")
func _screen() -> void:
    TranslationServer.set_locale("pt_BR"); StoreLocalization.set_demo_region("BR")
    var screen := (load("res://scenes/ui/store/StoreScreen.tscn") as PackedScene).instantiate() as StoreScreen
    root.add_child(screen); screen.size = Vector2(1280, 720); var wallet := Wallet.new(); screen.setup(wallet); screen.open_store(); await process_frame
    check(screen.is_shop_open() and screen._cards.size() == 7, "abertura e sete cards")
    check(screen._scroll.get_h_scroll_bar().modulate.a == 0.0, "sem barra intrusiva")
    check(screen._previous.texture_normal != null and screen._previous.texture_pressed != null and screen._next.texture_normal != null and screen._close.texture_pressed != null, "sprites de botão normal/pressionado")
    check(screen._previous.size.x >= 101 and screen._next.size.x >= 101 and screen._close.size.x >= 90, "botões 10% maiores")
    for card in screen._cards:
        check(card.get_node("Description").get_theme_font_size("font_size") >= 12, "texto mínimo 12pt")
        check(card.get_node("Title").get_theme_color("font_color") == StoreCard.TITLE_COLOR, "título com contraste")
        var price := card.get_node_or_null("PurchaseButton/Price") as Label
        check(price != null and not price.text.is_empty() and card.get_node_or_null("Badges") != null, "preço e badges")
    # FV-SHOP-003: tocar num valor nunca muda tamanho/escala/posição.
    var before := _rects(screen)
    var first_button := screen._cards[0].get_node("PurchaseButton") as BaseButton
    first_button.button_down.emit(); first_button.pressed.emit(); first_button.button_up.emit(); await process_frame; await process_frame
    check(_rects(screen) == before, "clique no valor não altera tamanho dos cards")
    check(screen._status.text == "Skyplan Brasil Ltda marca registrada", "rodapé com a marca: " + screen._status.text)
    for card in screen._cards:
        check(card.scale == Vector2.ONE and (card.get_node("PurchaseButton") as Control).scale == Vector2.ONE, "sem efeito de escala")
        check(card.get_badge_count() >= 1, "badges de itens " + String(card.product["id"]))
        check(absf(card.size.x / card.size.y - StoreCard.ART_ASPECT) < 0.01, "card na proporção da arte")
        check((card.get_node("PurchaseButton/Price") as Label).get_theme_font_size("font_size") >= 22, "valor do botão maior")
    check(screen._previous.scale == Vector2.ONE and screen._close.scale == Vector2.ONE, "setas/fechar sem escala")
    screen.set_hud_wallet_rect(Vector2(944, 45.85), 0.5)
    check(screen.get_wallet_bar().position == Vector2(944, 45.85) and screen.get_wallet_bar().scale == Vector2(0.5, 0.5), "carteira na posição/escala do HUD")
    var ads_price := screen._cards[1].get_node("PurchaseButton/Price") as Label
    check(ads_price.text == "R$ 29,99/mês", "assinatura sem anúncios: " + ads_price.text)
    # FV-SHOP-005: carrossel por página; uma bolinha por página real.
    await process_frame
    check(screen.visible_count() == 3 and screen.page_count() == 3, "1280x720: 3 cards por tela, 3 páginas (%d, %d)" % [screen.visible_count(), screen.page_count()])
    check(screen._indicator.text.count("●") + screen._indicator.text.count("○") == screen.page_count(), "bolinhas = páginas: " + screen._indicator.text)
    check(screen._previous.disabled and not screen._next.disabled, "setas no início")
    screen.next(); check(screen.get_selected_product_id() == "coins_mini" and screen.get_page() == 1, "seta próxima = página 2")
    screen.next(); check(screen.get_selected_product_id() == "coins_medium" and screen.get_page() == 2 and screen._next.disabled, "última página encosta no fim")
    screen.next(); check(screen.get_page() == 2, "não passa da última página")
    check(screen._indicator.text.count("●") == 1 and screen._indicator.text.ends_with("●"), "bolinha da última página")
    screen.select_product(&"helpers_6"); check(screen.get_page() == 2, "tocar card visível não move")
    screen.previous(); screen.previous(); check(screen.get_selected_product_id() == "vip_7d" and screen.get_page() == 0, "seta anterior volta ao início")
    screen.previous(); check(screen.get_page() == 0, "não passa do início")
    check(screen._close.size.x >= 103.0 and screen._close.position == Vector2(20, 16), "sair 15% maior no mesmo canto")
    check(StoreCatalog.demo_price(&"helpers_6", "BR") == "R$ 79,99" and StoreCatalog.demo_price(&"coins_medium", "BR") == "R$ 29,99", "preços BR ajudantes/moedas super")
    check(int(StoreCatalog.find(&"coins_medium")["benefits"]["coins"]) == 600, "Moedas Super = 600")
    for pair in [["pt_BR", "Loja da Fazenda"], ["en_US", "Farm Store"], ["es_ES", "Tienda de la Granja"]]:
        TranslationServer.set_locale(pair[0]); screen.refresh_language(); await process_frame; check(screen._title.text == pair[1], "tradução " + pair[0] + " = " + screen._title.text)
        check(_rects(screen).size() == before.size() and _rects(screen)[0][0].size.is_equal_approx(before[0][0].size), "troca de idioma mantém tamanho %s %s vs %s" % [pair[0], _rects(screen)[0][0].size, before[0][0].size])
        check(screen._status.text == "Skyplan Brasil Ltda marca registrada", "rodapé igual em " + pair[0])
    screen.size = Vector2(1920, 1080); screen._layout(); await process_frame
    check(Rect2(Vector2.ZERO, screen.size).encloses(screen._scroll.get_rect()), "layout 1920")
    var initial_cash := wallet.get_balance(); var initial_gold := wallet.get_gold(); screen.close_store()
    check(not screen.is_shop_open() and wallet.get_balance() == initial_cash and wallet.get_gold() == initial_gold, "fechar preserva jogo")
    screen.queue_free()
func _rects(screen: StoreScreen) -> Array:
    var out: Array = []
    for card in screen._cards: out.append([Rect2(card.position, card.size), card.scale, (card.get_node("PurchaseButton") as Control).get_rect()])
    return out
func _purchase() -> void:
    var wallet := Wallet.new(); var service := StorePurchaseService.new(); var entitlements := StoreEntitlements.new()
    check(not service.begin(&"vip_7d").get("ok", false), "produção indisponível")
    service.mode = StorePurchaseService.Mode.SIMULATED
    StoreLocalization.set_demo_region("BR")
    check(service.begin(&"vip_7d").get("ok", false), "simulação inicia")
    check(not service.begin(&"vip_7d").get("ok", false) and service.request_count == 1, "bloqueio duplicado pendente")
    var result := service.complete_simulated("editor:vip:001", entitlements, wallet)
    check(result.get("ok", false) and wallet.get_gold() == 700 and wallet.get_balance() == 2000, "benefícios simulados")
    check(not entitlements.grant_simulated("editor:vip:001", StoreCatalog.find(&"vip_7d"), wallet), "idempotência")
    check(wallet.get_gold() == 700 and wallet.get_balance() == 2000, "sem duplicar saldo")
    service.online = false; check(not service.begin(&"coins_mini").get("ok", false), "offline bloqueia")
func _finish() -> void:
    if failures > 0: print("STORE_V2_FAILED ", failures); quit(1)
    else: print("STORE_V2_OK"); quit()
