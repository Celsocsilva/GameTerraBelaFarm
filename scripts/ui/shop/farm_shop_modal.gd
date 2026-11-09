extends Control
class_name FarmShopModal
## Loja de IAP — catálogo navegável SEM cobranças simuladas.
## Todas as ofertas ficam desabilitadas até existir integração nativa + validação
## de recibo/compra no servidor e concessão idempotente dos benefícios.

signal closed

const WOOD := Color("#86502b")
const WOOD_DARK := Color("#60371f")
const CREAM := Color("#fff0cd")
const PALE := Color("#fff9e9")
const TEXT := Color("#613817")
const GREEN := Color("#74c82e")
const ORANGE := Color("#f4a23a")
const TAB_IDLE := Color("#ead0a1")
const MIN_MARGIN := 12.0

var _dim: ColorRect
var _card: PanelContainer
var _title: Label
var _subtitle: Label
var _close_button: Button
var _tab_row: HBoxContainer
var _product_grid: GridContainer
var _details_title: Label
var _details_desc: Label
var _status_label: Label
var _purchase_button: Button
var _tab_buttons: Dictionary = {}
var _category_id := "boosters"
var _selected_id := ""
var _layout_width := 0.0
var _layout_queued := false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build_ui()
    resized.connect(_layout)
    # Rótulos com autowrap podem inflar o cartão por um quadro enquanto ainda
    # não têm largura; o PanelContainer nunca encolhe sozinho, então refazemos
    # o layout sempre que o mínimo do conteúdo muda.
    _card.minimum_size_changed.connect(_queue_layout)
    visible = false
    _translate_and_populate()
    _layout()

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _translate_and_populate()

func open_shop() -> void:
    _category_id = "boosters"
    _selected_id = "speed_growth"
    _translate_and_populate()
    visible = true
    _layout()
    _queue_layout()
    _close_button.grab_focus()

func close_shop() -> void:
    if not visible:
        return
    visible = false
    closed.emit()

func is_shop_open() -> bool:
    return visible

func get_selected_product_id() -> String:
    return _selected_id

func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("ui_cancel"):
        close_shop()
        get_viewport().set_input_as_handled()

func _build_ui() -> void:
    _dim = ColorRect.new()
    _dim.color = Color(0.07, 0.05, 0.02, 0.73)
    _dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_dim)
    _dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _card = PanelContainer.new()
    _card.mouse_filter = Control.MOUSE_FILTER_STOP
    _card.add_theme_stylebox_override("panel", _style(CREAM, WOOD_DARK, 7, 26))
    add_child(_card)

    var margins := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margins.add_theme_constant_override("margin_" + side, 17)
    _card.add_child(margins)

    var body := VBoxContainer.new()
    body.add_theme_constant_override("separation", 10)
    margins.add_child(body)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    body.add_child(header)

    var icon := TextureRect.new()
    icon.texture = preload("res://assets/ui/icons/icon_store_shop.png")
    icon.custom_minimum_size = Vector2(75, 70)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    header.add_child(icon)

    var heading := VBoxContainer.new()
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    heading.add_theme_constant_override("separation", 2)
    header.add_child(heading)
    _title = _label(31, TEXT)
    heading.add_child(_title)
    _subtitle = _label(16, WOOD)
    heading.add_child(_subtitle)

    _close_button = Button.new()
    _close_button.custom_minimum_size = Vector2(56, 54)
    _close_button.text = "×"
    _close_button.add_theme_font_size_override("font_size", 28)
    _close_button.add_theme_stylebox_override("normal", _style(Color("#d85545"), WOOD_DARK, 3, 14))
    _close_button.add_theme_stylebox_override("hover", _style(Color("#ef7560"), WOOD_DARK, 3, 14))
    _close_button.add_theme_color_override("font_color", Color.WHITE)
    _close_button.pressed.connect(close_shop)
    header.add_child(_close_button)

    var tabs_scroll := ScrollContainer.new()
    tabs_scroll.custom_minimum_size.y = 55
    tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    body.add_child(tabs_scroll)

    _tab_row = HBoxContainer.new()
    _tab_row.add_theme_constant_override("separation", 7)
    tabs_scroll.add_child(_tab_row)
    for category in ShopCatalog.CATEGORIES:
        var tab := Button.new()
        tab.custom_minimum_size = Vector2(142, 44)
        tab.add_theme_font_size_override("font_size", 17)
        tab.add_theme_color_override("font_color", TEXT)
        var category_id := String(category["id"])
        tab.pressed.connect(_choose_category.bind(category_id))
        _tab_row.add_child(tab)
        _tab_buttons[category_id] = tab

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    body.add_child(scroll)

    _product_grid = GridContainer.new()
    _product_grid.columns = 3
    _product_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _product_grid.add_theme_constant_override("h_separation", 9)
    _product_grid.add_theme_constant_override("v_separation", 9)
    scroll.add_child(_product_grid)

    var details := PanelContainer.new()
    details.custom_minimum_size.y = 93
    details.add_theme_stylebox_override("panel", _style(PALE, Color("#ddb985"), 2, 14))
    body.add_child(details)
    var details_margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        details_margin.add_theme_constant_override("margin_" + side, 8)
    details.add_child(details_margin)
    var detail_body := VBoxContainer.new()
    detail_body.add_theme_constant_override("separation", 3)
    details_margin.add_child(detail_body)
    _details_title = _label(19, TEXT)
    detail_body.add_child(_details_title)
    _details_desc = _label(15, TEXT)
    _details_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail_body.add_child(_details_desc)

    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 10)
    body.add_child(footer)
    _status_label = _label(14, WOOD)
    _status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    footer.add_child(_status_label)
    _purchase_button = Button.new()
    _purchase_button.custom_minimum_size = Vector2(156, 47)
    _purchase_button.add_theme_font_size_override("font_size", 18)
    _purchase_button.add_theme_stylebox_override("disabled", _style(Color("#b4aa91"), WOOD, 2, 14))
    _purchase_button.add_theme_color_override("font_disabled_color", PALE)
    _purchase_button.disabled = true
    footer.add_child(_purchase_button)

func _label(font_size: int, color: Color) -> Label:
    var l := Label.new()
    l.add_theme_font_override("font", UiStyle.font())
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    return l

func _style(bg: Color, outline: Color, border: int, radius: int) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = outline
    s.set_border_width_all(border)
    s.set_corner_radius_all(radius)
    return s

func _choose_category(category_id: String) -> void:
    _category_id = category_id
    var products := ShopCatalog.products_for_category(category_id)
    _selected_id = String(products[0]["id"]) if not products.is_empty() else ""
    _translate_and_populate()

func _select_product(product_id: String) -> void:
    _selected_id = product_id
    _update_details()

func _translate_and_populate() -> void:
    if _title == null:
        return
    _title.text = tr("SHOP_TITLE")
    _subtitle.text = tr("SHOP_SUBTITLE")
    _close_button.tooltip_text = tr("SHOP_CLOSE")
    _purchase_button.text = tr("SHOP_UNAVAILABLE")
    _status_label.text = tr("SHOP_PAYMENT_PENDING")
    for category in ShopCatalog.CATEGORIES:
        var key := String(category["id"])
        var btn := _tab_buttons[key] as Button
        btn.text = tr(String(category["title_key"]))
        var active := key == _category_id
        var bg := ORANGE if active else TAB_IDLE
        btn.add_theme_stylebox_override("normal", _style(bg, WOOD, 2, 12))
        btn.add_theme_stylebox_override("hover", _style(Color("#ffe0a5"), WOOD, 2, 12))
    _populate_cards()
    _update_details()
    _queue_layout()

func _queue_layout() -> void:
    if _layout_queued:
        return
    _layout_queued = true
    call_deferred("_layout")

func _populate_cards() -> void:
    for child in _product_grid.get_children():
        _product_grid.remove_child(child)
        child.queue_free()
    for product in ShopCatalog.products_for_category(_category_id):
        _product_grid.add_child(_make_card(product))
    _layout_cards()

func _make_card(product: Dictionary) -> PanelContainer:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", _style(PALE, Color("#d9aa70"), 2, 15))
    card.custom_minimum_size = Vector2(275, 157)
    var box_margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        box_margin.add_theme_constant_override("margin_" + side, 8)
    card.add_child(box_margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    box_margin.add_child(column)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    column.add_child(row)
    var picture := TextureRect.new()
    picture.texture = ShopCatalog.ICONS.get(String(product["icon"]), null)
    picture.custom_minimum_size = Vector2(62, 65)
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    row.add_child(picture)
    var texts := VBoxContainer.new()
    texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(texts)
    var name_label := _label(18, TEXT)
    name_label.text = tr(String(product["title_key"]))
    name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    texts.add_child(name_label)
    var unavailable := _label(13, WOOD)
    unavailable.text = tr("SHOP_UNAVAILABLE")
    texts.add_child(unavailable)
    var detail_button := Button.new()
    detail_button.custom_minimum_size.y = 36
    detail_button.text = tr("SHOP_DETAILS")
    detail_button.add_theme_font_size_override("font_size", 16)
    detail_button.add_theme_color_override("font_color", TEXT)
    detail_button.add_theme_stylebox_override("normal", _style(Color("#c9e69b"), GREEN, 2, 10))
    detail_button.add_theme_stylebox_override("hover", _style(Color("#e5f6c0"), GREEN, 2, 10))
    detail_button.pressed.connect(_select_product.bind(String(product["id"])))
    column.add_child(detail_button)
    return card

func _update_details() -> void:
    if _details_title == null:
        return
    var product := ShopCatalog.find_product(_selected_id)
    if product.is_empty():
        _details_title.text = tr("SHOP_NO_PRODUCTS")
        _details_desc.text = ""
    else:
        _details_title.text = tr(String(product["title_key"]))
        _details_desc.text = tr(String(product["description_key"]))
    # Sem preço fictício, compra em teste ou crédito de saldo.
    _purchase_button.disabled = true

func _layout() -> void:
    _layout_queued = false
    if _card == null:
        return
    var width := maxf(260.0, minf(size.x - MIN_MARGIN * 2.0, 1080.0))
    var height := maxf(340.0, minf(size.y - MIN_MARGIN * 2.0, 650.0))
    # Zera antes para o cartão voltar ao tamanho pedido mesmo que tenha crescido.
    _card.size = Vector2.ZERO
    _card.size = Vector2(width, height)
    _card.position = (size - _card.size) * 0.5
    _layout_width = width
    _layout_cards()

func _layout_cards() -> void:
    if _product_grid == null:
        return
    var columns := 3 if _layout_width >= 920.0 else (2 if _layout_width >= 650.0 else 1)
    _product_grid.columns = columns
    var content_width := maxf(245.0, _layout_width - 75.0)
    var cell_width := (content_width - (columns - 1) * 9.0) / columns
    for child in _product_grid.get_children():
        (child as Control).custom_minimum_size = Vector2(cell_width, 157)
