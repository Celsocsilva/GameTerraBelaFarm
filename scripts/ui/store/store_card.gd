extends Control
class_name StoreCard
## Card da Store V2 (FV-SHOP-003).
## - O card tem SEMPRE a proporção da arte (1040x1512); título, badges e botão
##   são posicionados em frações medidas na própria arte (caixa do título,
##   caixa creme da descrição e vaga do botão), então ficam alinhados em
##   qualquer tamanho de tela.
## - Nenhum elemento muda de escala ao tocar/clicar: o botão de compra só troca
##   a textura normal/pressionada, desenhada no MESMO retângulo.
## - A descrição virou badges (ícone + quantidade) grandes, com uma linha curta
##   embaixo para o que não é quantidade.

signal selected(product_id: StringName)
signal purchase_pressed(product_id: StringName)

const PURCHASE_NORMAL := preload("res://assets/store/buttons/purchase_normal.png")
const PURCHASE_PRESSED := preload("res://assets/store/buttons/purchase_pressed.png")
const ICON_COIN := preload("res://assets/ui/icons/icon_gold_coins.png")
const ICON_CASH := preload("res://assets/ui/icons/icon_cash_bundle.png")
const ICON_WOOD := preload("res://assets/ui/icon_log.png")
const ICON_HELPER := preload("res://assets/ui/icons/icon_player_portrait.png")
const ICON_BRICKS := preload("res://assets/store/icons/icon_bricks.png")
const ICON_NO_ADS := preload("res://assets/store/icons/icon_no_ads.png")

## Proporção da arte dos cards (largura / altura).
const ART_ASPECT := 1040.0 / 1512.0
const CARD_SIZE := Vector2(328, 328 / ART_ASPECT)
## Regiões da arte em frações do card (medidas nos PNGs de assets/store/cards).
const TITLE_RECT := Rect2(0.165, 0.146, 0.67, 0.056)
const BADGE_RECT := Rect2(0.075, 0.637, 0.85, 0.15)
const BUTTON_RECT := Rect2(0.135, 0.806, 0.73, 0.134)

const TEXT_BROWN := Color("#5a2e0e")
## Título dos packs (pedido de contraste): texto marrom-escuro com borda creme
## clara sobre a caixa creme da arte, em vez de branco com borda alaranjada.
const TITLE_COLOR := Color("#3b1503")
const TITLE_OUTLINE := Color("#fffaf0")
const BADGE_BG := Color(1.0, 1.0, 1.0, 0.92)
const BADGE_BORDER := Color("#e3a43a")

var product: Dictionary
var _price := ""
var _purchase: StorePillButton
var _title: Label
var _price_label: Label
var _badges: HBoxContainer
var _note: Label
var _badge_items: Array = []

func setup(data: Dictionary, price: String, enabled: bool) -> void:
    product = data; _price = price
    mouse_filter = Control.MOUSE_FILTER_STOP
    # Nunca esticar pelo HBox do carrossel: o tamanho vem só de set_card_size.
    size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    tooltip_text = tr(String(product.get("desc_key", "")))
    var art := TextureRect.new(); art.name = "Artwork"; art.texture = StoreCatalog.art_for(product)
    art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_SCALE; art.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(art)
    _title = _label(tr(String(product["title_key"])), 22, TITLE_COLOR, TITLE_OUTLINE, 7); _title.name = "Title"
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; add_child(_title)
    _badge_items = _badge_data(product.get("benefits", {}))
    _badges = HBoxContainer.new(); _badges.name = "Badges"; _badges.alignment = BoxContainer.ALIGNMENT_CENTER; _badges.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_badges)
    for item in _badge_items: _badges.add_child(_make_badge(item))
    var note_key := String(product.get("note_key", ""))
    _note = _label(tr(note_key) if not note_key.is_empty() else "", 15, TEXT_BROWN, Color(0, 0, 0, 0), 0); _note.name = "Description"
    _note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; add_child(_note)
    _purchase = StorePillButton.new(); _purchase.name = "PurchaseButton"; _purchase.texture_normal = PURCHASE_NORMAL; _purchase.texture_pressed = PURCHASE_PRESSED
    _purchase.disabled = false; _purchase.focus_mode = Control.FOCUS_NONE; add_child(_purchase)
    # Assinatura: o valor vem com o período ("/mês", "/mes", "/mo").
    var price_text := price + tr("STORE_V2_PER_MONTH") if not price.is_empty() and bool(product.get("subscription", false)) else price
    _price_label = _label(price_text if not price.is_empty() else tr("STORE_V2_UNAVAILABLE"), 26, Color.WHITE, Color("#2f6b0c"), 7); _price_label.name = "Price"
    _price_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; _purchase.add_child(_price_label)
    _purchase.pressed.connect(func() -> void: purchase_pressed.emit(product["id"]))
    gui_input.connect(func(event: InputEvent) -> void: if event is InputEventMouseButton and event.pressed: selected.emit(product["id"]))
    set_card_size(CARD_SIZE)

## Ajusta o card para a altura pedida (a largura sai da proporção da arte).
func set_card_size(target: Vector2) -> void:
    var card := Vector2(target.y * ART_ASPECT, target.y)
    custom_minimum_size = card; size = card
    if _title == null: return
    _place(_title, TITLE_RECT, card)
    _fit(_title, roundi(card.y * 0.05), 12)
    _place(_purchase, BUTTON_RECT, card)
    # Valor do botão: ~15% maior que antes (0.049 → 0.058 da altura do card).
    _fit(_price_label, roundi(card.y * 0.058), 14, 0.82)
    _layout_badges(card)
    _purchase.queue_redraw()

func get_badge_count() -> int: return _badge_items.size()

func _place(control: Control, frac: Rect2, card: Vector2) -> void:
    control.position = Vector2(frac.position.x * card.x, frac.position.y * card.y)
    control.size = Vector2(frac.size.x * card.x, frac.size.y * card.y)

func _layout_badges(card: Vector2) -> void:
    var box := Rect2(BADGE_RECT.position * card, BADGE_RECT.size * card)
    var has_note := not _note.text.is_empty()
    var note_h := box.size.y * 0.27 if has_note else 0.0
    var badge_h := (box.size.y - note_h) * (0.90 if has_note else 0.78)
    var count := maxi(1, _badge_items.size())
    var gap := card.x * 0.014
    # Maior tamanho possível: começa grande e reduz até todos caberem na caixa.
    var font_size := roundi(badge_h * 0.58)
    var icon := badge_h * 1.0
    var font := UiStyle.font()
    while font_size > 11:
        var total := gap * (count - 1)
        for item in _badge_items:
            total += _badge_width(item, font, font_size, icon, badge_h)
        if total <= box.size.x: break
        font_size -= 1; icon = maxf(badge_h * 0.8, icon - badge_h * 0.015)
    _badges.add_theme_constant_override("separation", roundi(gap))
    var i := 0
    for badge in _badges.get_children():
        var item: Array = _badge_items[i]; i += 1
        var row := badge.get_node("Row") as HBoxContainer
        row.add_theme_constant_override("separation", roundi(badge_h * 0.04))
        var pic := row.get_node("Icon") as TextureRect
        pic.custom_minimum_size = Vector2(icon, icon * 0.9)
        var value := row.get_node_or_null("Value") as Label
        if value: value.add_theme_font_size_override("font_size", font_size); value.add_theme_constant_override("outline_size", maxi(3, roundi(font_size * 0.2)))
        var style := (badge as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
        style.set_corner_radius_all(roundi(badge_h * 0.5)); style.content_margin_left = badge_h * 0.06; style.content_margin_right = badge_h * 0.2
        style.content_margin_top = 0; style.content_margin_bottom = 0; style.set_border_width_all(maxi(2, roundi(badge_h * 0.05)))
        (badge as Control).custom_minimum_size = Vector2(0, badge_h)
    _badges.position = Vector2(box.position.x, box.position.y + (box.size.y - note_h - badge_h) * 0.5 + (box.size.y * 0.02 if has_note else 0.0))
    _badges.size = Vector2(box.size.x, badge_h)
    _note.position = Vector2(box.position.x, box.end.y - note_h - box.size.y * 0.02)
    _note.size = Vector2(box.size.x, note_h)
    _note.visible = has_note
    if has_note: _fit(_note, maxi(12, roundi(note_h * 0.78)), 12)

func _badge_width(item: Array, font: Font, font_size: int, icon: float, badge_h: float) -> float:
    var w := badge_h * 0.06 + icon + badge_h * 0.2
    if not String(item[1]).is_empty():
        w += badge_h * 0.04 + font.get_string_size(String(item[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size * 0.4
    return w

func _fit(label: Label, max_size: int, min_size: int, height_ratio: float = 0.9) -> void:
    var font := UiStyle.font(); var font_size := maxi(min_size, max_size)
    var width := label.size.x * 0.94
    while font_size > min_size and (font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width or font.get_height(font_size) > label.size.y / height_ratio):
        font_size -= 1
    label.add_theme_font_size_override("font_size", font_size)
    if label.get_theme_constant("outline_size") > 0: label.add_theme_constant_override("outline_size", maxi(3, roundi(font_size * 0.26)))

func _label(text_value: String, font_size: int, color: Color, outline: Color, outline_size: int) -> Label:
    var label := Label.new(); label.text = text_value; label.add_theme_font_override("font", UiStyle.font()); label.add_theme_font_size_override("font_size", maxi(12, font_size))
    label.add_theme_color_override("font_color", color); label.add_theme_color_override("font_outline_color", outline); label.add_theme_constant_override("outline_size", outline_size)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.clip_text = false; return label

## Cada badge: [ícone, valor]. Só quantidades/ativos; o resto vai na linha curta.
func _badge_data(benefits: Dictionary) -> Array:
    var items: Array = []
    if int(benefits.get("coins", 0)) > 0: items.append([ICON_COIN, UiStyle.format_int(int(benefits["coins"]))])
    if int(benefits.get("cash", 0)) > 0: items.append([ICON_CASH, UiStyle.format_int(int(benefits["cash"]))])
    if int(benefits.get("weekly_cash", 0)) > 0: items.append([ICON_CASH, UiStyle.format_int(int(benefits["weekly_cash"])) + tr("STORE_V2_PER_WEEK")])
    if int(benefits.get("bricks", 0)) > 0: items.append([ICON_BRICKS, UiStyle.format_int(int(benefits["bricks"]))])
    if int(benefits.get("wood", 0)) > 0: items.append([ICON_WOOD, UiStyle.format_int(int(benefits["wood"]))])
    if int(benefits.get("helper_count", 0)) > 0: items.append([ICON_HELPER, "×" + str(int(benefits["helper_count"]))])
    # VIP: a duração já está no título ("VIP 7 dias"); o badge mostra só o ícone.
    if bool(benefits.get("ad_free", false)): items.append([ICON_NO_ADS, ""])
    return items

func _make_badge(item: Array) -> PanelContainer:
    var badge := PanelContainer.new(); badge.name = "Badge"; badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new(); style.bg_color = BADGE_BG; style.border_color = BADGE_BORDER; style.anti_aliasing = true
    style.shadow_color = Color(0.45, 0.22, 0.05, 0.25); style.shadow_size = 2; style.shadow_offset = Vector2(0, 2)
    badge.add_theme_stylebox_override("panel", style)
    var row := HBoxContainer.new(); row.name = "Row"; row.alignment = BoxContainer.ALIGNMENT_CENTER; row.mouse_filter = Control.MOUSE_FILTER_IGNORE; badge.add_child(row)
    var pic := TextureRect.new(); pic.name = "Icon"; pic.texture = item[0]; pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER; pic.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(pic)
    if not String(item[1]).is_empty():
        var value := _label(String(item[1]), 20, TEXT_BROWN, Color("#fff6dc"), 4); value.name = "Value"; value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; row.add_child(value)
    return badge
