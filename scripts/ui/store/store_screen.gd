extends Control
class_name StoreScreen

signal closed
const BACKGROUND := preload("res://assets/store/backgrounds/store_farm_landscape.png")
const CARD_SCRIPT := preload("res://scripts/ui/store/store_card.gd")
const EXIT_NORMAL := preload("res://assets/store/buttons/store_exit_normal.png")
const EXIT_PRESSED := preload("res://assets/store/buttons/store_exit_pressed.png")
const LEFT_NORMAL := preload("res://assets/store/buttons/carousel_left_normal.png")
const LEFT_PRESSED := preload("res://assets/store/buttons/carousel_left_pressed.png")
const RIGHT_NORMAL := preload("res://assets/store/buttons/carousel_right_normal.png")
const RIGHT_PRESSED := preload("res://assets/store/buttons/carousel_right_pressed.png")
var wallet: Wallet
var purchase_service := StorePurchaseService.new()
var entitlements := StoreEntitlements.new()
var _cards: Array[StoreCard] = []
var _selected_index := 0
var _page := 0
var _scroll_tween: Tween
const CARD_GAP := 18.0
## Botão de sair 15% maior (90 → 103,5), mesmo canto superior esquerdo.
const EXIT_SIZE := Vector2(103.5, 103.5)
var _scroll: ScrollContainer
var _row: HBoxContainer
var _title: Label
## FV-SHOP-003: a carteira da loja é o MESMO componente do HUD (HudWalletBar),
## no mesmo retângulo e escala do HUD (FarmHUD chama set_hud_wallet_rect).
var _wallet_bar: HudWalletBar
var _wallet_rect_set := false
var _wallet_pos := Vector2.ZERO
var _wallet_scale := 0.5
var _indicator: Label
var _status: Label
var _close: TextureButton
var _previous: TextureButton
var _next: TextureButton
var _locale_seen := ""
var last_purchase_result: Dictionary = {}
var _carousel_size := Vector2.ZERO

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_STOP; _build(); _locale_seen = TranslationServer.get_locale(); resized.connect(_layout); visible = false
func _process(_delta: float) -> void:
    if _locale_seen != TranslationServer.get_locale(): refresh_language()
func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and _title != null:
        refresh_language()
func refresh_language() -> void:
    _locale_seen = TranslationServer.get_locale()
    _title.text = tr("STORE_V2_TITLE")
    _status.text = tr("STORE_V2_FOOTER")
    _rebuild_cards()
func setup(p_wallet: Wallet) -> void:
    wallet = p_wallet
    if wallet.balance_changed.is_connected(_on_money): wallet.balance_changed.disconnect(_on_money)
    if wallet.gold_changed.is_connected(_on_gold): wallet.gold_changed.disconnect(_on_gold)
    wallet.balance_changed.connect(_on_money); wallet.gold_changed.connect(_on_gold); _refresh_wallet()
func set_purchase_service(service: StorePurchaseService) -> void: purchase_service = service; _rebuild_cards()
func open_shop() -> void: open_store()
func open_store() -> void:
    visible = true; _selected_index = 0; _page = 0; _rebuild_cards(); _layout(); call_deferred("_layout"); call_deferred("_focus_selected")
func close_shop() -> void: close_store()
func close_store() -> void:
    if visible: visible = false; closed.emit()
func is_shop_open() -> bool: return visible
func get_selected_product_id() -> String: return String(StoreCatalog.PRODUCT_IDS[_selected_index])
## FV-SHOP-005: o carrossel anda por PÁGINA (os cards que cabem inteiros na
## tela). Bolinhas = número de páginas (7 cards, 3 por tela = 3 bolinhas; em
## retrato, 1 por tela = 7). Setas, bolinhas e arrasto usam a mesma página.
func select_product(product_id: StringName) -> void:
    var index := StoreCatalog.PRODUCT_IDS.find(product_id)
    if index < 0: return
    _selected_index = index
    # Tocar num card que já está na tela não move o carrossel.
    if index < page_start(_page) or index >= page_start(_page) + visible_count(): _page = page_of(index)
    _focus_selected()
func next() -> void: go_to_page(_page + 1)
func previous() -> void: go_to_page(_page - 1)
func go_to_page(page: int) -> void:
    _page = clampi(page, 0, page_count() - 1); _selected_index = page_start(_page); _focus_selected()
func get_page() -> int: return _page
func visible_count() -> int:
    if _cards.is_empty(): return 1
    var card_w := card_height() * StoreCard.ART_ASPECT
    var sw := _carousel_size.x if _carousel_size.x > 0.0 else _scroll.size.x
    return clampi(int(floor((sw + CARD_GAP) / (card_w + CARD_GAP))), 1, _cards.size())
func page_count() -> int: return maxi(1, ceili(float(_cards.size()) / float(visible_count())))
## Primeiro card da página; a última página encosta no fim (sem vazio).
func page_start(page: int) -> int: return clampi(page * visible_count(), 0, maxi(0, _cards.size() - visible_count()))
func page_of(index: int) -> int: return clampi(int(ceil(float(index + 1) / float(visible_count()))) - 1, 0, page_count() - 1)
func _page_scroll(page: int) -> float:
    var step := card_height() * StoreCard.ART_ASPECT + CARD_GAP
    var bar := _scroll.get_h_scroll_bar()
    return clampf(page_start(page) * step, 0.0, maxf(0.0, bar.max_value - bar.page))
## Arrasto (swipe): ao soltar, encaixa na página mais próxima.
func _on_scroll_ended() -> void:
    if _cards.is_empty(): return
    var value := _scroll.get_h_scroll_bar().value; var best := 0; var dist := INF
    for p in page_count():
        var d := absf(_page_scroll(p) - value)
        if d < dist: dist = d; best = p
    go_to_page(best)
func _unhandled_input(event: InputEvent) -> void:
    if not visible: return
    if event.is_action_pressed("ui_cancel"): close_store(); get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_right"): next(); get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_left"): previous(); get_viewport().set_input_as_handled()
func _build() -> void:
    var bg := TextureRect.new(); bg.texture = BACKGROUND; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
    _close = _image_button("BackButton", EXIT_NORMAL, EXIT_PRESSED); _close.position = Vector2(20, 16); _close.size = EXIT_SIZE; _close.pressed.connect(close_store); add_child(_close)
    _title = _label(tr("STORE_V2_TITLE"), 38); _title.name = "StoreTitle"; _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_title)
    _wallet_bar = HudWalletBar.new(); _wallet_bar.name = "WalletBar"; add_child(_wallet_bar)
    _previous = _image_button("Previous", LEFT_NORMAL, LEFT_PRESSED); _previous.pressed.connect(previous); add_child(_previous)
    _next = _image_button("Next", RIGHT_NORMAL, RIGHT_PRESSED); _next.pressed.connect(next); add_child(_next)
    _scroll = ScrollContainer.new(); _scroll.name = "OfferCarousel"; _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO; _scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; _scroll.get_h_scroll_bar().modulate.a = 0.0; add_child(_scroll)
    _row = HBoxContainer.new(); _row.name = "Cards"; _row.add_theme_constant_override("separation", int(CARD_GAP)); _scroll.scroll_ended.connect(_on_scroll_ended); _scroll.add_child(_row)
    _indicator = _label("", 20); _indicator.name = "PageIndicator"; _indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_indicator)
    _status = _label(tr("STORE_V2_FOOTER"), 16); _status.name = "Status"; _status.add_theme_color_override("font_color", Color("#fff3d6")); _status.add_theme_color_override("font_outline_color", Color("#4a250c")); _status.add_theme_constant_override("outline_size", 6); _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_status)
func _rebuild_cards() -> void:
    if _row == null: return
    for child in _row.get_children(): child.queue_free()
    _cards.clear()
    for product in StoreCatalog.all():
        var card := CARD_SCRIPT.new() as StoreCard; var product_id: StringName = product["id"]
        card.setup(product, StoreLocalization.price_for(product_id), purchase_service.can_purchase(product_id)); card.selected.connect(select_product); card.purchase_pressed.connect(_request_purchase); _row.add_child(card); _cards.append(card)
    # Cards novos (troca de idioma) nascem já no tamanho do layout atual.
    _apply_card_sizes()
    _update_indicator()
func _request_purchase(product_id: StringName) -> void:
    # FV-SHOP-003: tocar num valor NÃO recria nem redimensiona os cards (antes
    # o rebuild devolvia os cards ao tamanho-base e tudo encolhia). O rodapé
    # fica fixo com a marca; só a simulação de testes mostra "Processando…".
    var result := purchase_service.begin(product_id)
    last_purchase_result = result
    if bool(result.get("ok", false)): _status.text = tr("STORE_V2_PENDING")
func _focus_selected() -> void:
    if _cards.is_empty() or _scroll == null: return
    _page = clampi(_page, 0, page_count() - 1)
    if _scroll_tween and _scroll_tween.is_valid(): _scroll_tween.kill()
    _scroll_tween = create_tween(); _scroll_tween.tween_property(_scroll.get_h_scroll_bar(), "value", _page_scroll(_page), 0.18); _update_indicator()
func _update_indicator() -> void:
    if _indicator == null: return
    var dots := ""; for i in page_count(): dots += "● " if i == _page else "○ "; _indicator.text = dots.strip_edges()
    # Uma página só: nada para navegar, setas e bolinhas somem.
    var paged := page_count() > 1
    _indicator.visible = paged
    if _previous: _previous.disabled = _page == 0; _previous.visible = paged; _previous.modulate.a = 0.45 if _previous.disabled else 1.0
    if _next: _next.disabled = _page >= page_count() - 1; _next.visible = paged; _next.modulate.a = 0.45 if _next.disabled else 1.0
func _layout() -> void:
    if _title == null: return
    var w := size.x; var h := size.y
    _title.position = Vector2(w * .30, 48); _title.size = Vector2(w * .40, 58)
    _layout_wallet()
    # Retrato: a carteira fica onde o HUD a põe; se ela cruzar o título, o
    # título (e o carrossel) descem, nunca a carteira.
    var wallet_rect := Rect2(_wallet_bar.position, HudWalletBar.DESIGN_SIZE * _wallet_scale)
    if wallet_rect.intersects(_title.get_rect()): _title.position.y = wallet_rect.end.y + 8.0
    # Opções 20% mais abaixo e maiores que a primeira composição da V2.
    var top := _title.position.y + 74.0
    _carousel_size = Vector2(w - 184, h - top - 88)
    _scroll.position = Vector2(92, top); _scroll.size = _carousel_size; _indicator.position = Vector2(0, h - 68); _indicator.size = Vector2(w, 28); _status.position = Vector2(0, h - 38); _status.size = Vector2(w, 24)
    _apply_card_sizes()
    # A janela do carrossel tem a largura exata dos cards de uma página e fica
    # centrada: sem pedaços de cards vizinhos aparecendo nas bordas.
    if not _cards.is_empty():
        var vc := visible_count(); var view_w := vc * card_height() * StoreCard.ART_ASPECT + (vc - 1) * CARD_GAP
        _scroll.size.x = view_w; _scroll.position.x = (w - view_w) * 0.5
    # Paisagem/retrato mudam quantos cards cabem: a página é recalculada.
    if not _cards.is_empty():
        _page = page_of(_selected_index); _update_indicator()
        if visible: call_deferred("_focus_selected")
    if _previous: _previous.position = Vector2(8, _scroll.position.y + _scroll.size.y * .42); _previous.size = Vector2(102, 102)
    if _next: _next.position = Vector2(w - 110, _scroll.position.y + _scroll.size.y * .42); _next.size = Vector2(102, 102)
## Altura dos cards: cabe na área do carrossel, mostra 3 cards em paisagem e 1
## em retrato, sempre na proporção da arte.
func card_height() -> float:
    if _scroll == null: return StoreCard.CARD_SIZE.y
    # Usa a área pedida no layout, não o tamanho atual do ScrollContainer: ele
    # cresce com o mínimo dos cards (+ barra oculta) e realimentaria o tamanho.
    var sw := _carousel_size.x if _carousel_size.x > 0.0 else _scroll.size.x
    var sh := (_carousel_size.y if _carousel_size.y > 0.0 else _scroll.size.y) - 16.0
    var max_w := (sw - 36.0) / 3.0 if sw >= 900.0 else sw * 0.86
    return maxf(240.0, minf(sh, max_w / StoreCard.ART_ASPECT))
func _apply_card_sizes() -> void:
    var h := card_height()
    for card in _cards: card.set_card_size(Vector2(h * StoreCard.ART_ASPECT, h))
## Recebe do FarmHUD a posição/escala exatas da carteira do HUD.
func set_hud_wallet_rect(pos: Vector2, wallet_scale: float) -> void:
    _wallet_rect_set = true; _wallet_pos = pos; _wallet_scale = wallet_scale; _layout_wallet()
func get_wallet_bar() -> HudWalletBar: return _wallet_bar
func _layout_wallet() -> void:
    if _wallet_bar == null: return
    if not _wallet_rect_set:
        _wallet_scale = minf(0.5, (size.x * 0.4) / HudWalletBar.DESIGN_SIZE.x)
        _wallet_pos = Vector2(size.x - 16.0 - HudWalletBar.DESIGN_SIZE.x * _wallet_scale, 16.0)
    _wallet_bar.scale = Vector2.ONE * _wallet_scale; _wallet_bar.position = _wallet_pos
func _refresh_wallet() -> void:
    if wallet and _wallet_bar and _wallet_bar.is_node_ready(): _wallet_bar.set_money(wallet.get_balance(), false); _wallet_bar.set_gold(wallet.get_gold(), false)
func _on_money(_balance: int, _delta: int) -> void: _refresh_wallet()
func _on_gold(_gold: int, _delta: int) -> void: _refresh_wallet()
func _label(key: String, font_size: int) -> Label:
    var label := Label.new(); label.text = key; label.add_theme_font_override("font", UiStyle.font()); label.add_theme_font_size_override("font_size", font_size); label.add_theme_color_override("font_color", Color("#60371f")); label.add_theme_color_override("font_outline_color", Color("#fff6dc")); label.add_theme_constant_override("outline_size", 4); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.mouse_filter = Control.MOUSE_FILTER_IGNORE; return label
func _image_button(node_name: String, normal: Texture2D, pressed: Texture2D) -> TextureButton:
    var button := TextureButton.new(); button.name = node_name; button.texture_normal = normal; button.texture_pressed = pressed; button.ignore_texture_size = true; button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED; return button
