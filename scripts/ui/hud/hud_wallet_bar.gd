extends Control
class_name HudWalletBar
## Bloco do topo direito do HUD (FV-HUD-002): retângulo arredondado preto
## translúcido com SÓ o dinheiro (ícone do maço + valor) e as moedas de ouro
## (ícone da pilha de moedas + valor). Desenhado em tamanho fixo (DESIGN_SIZE);
## o FarmHUD reduz/aumenta com `scale`, como os outros componentes.
##
## Leitura do pedido "preto com transparência de 70%": 70% transparente, ou
## seja, opacidade 0.30 (BG_ALPHA). Para a leitura oposta (70% opaco) troque
## BG_ALPHA para 0.70; nada mais depende desse número.

const BG_ALPHA := 0.30
const BG_COLOR := Color(0.0, 0.0, 0.0, BG_ALPHA)
const CORNER_RADIUS := 34
const DESIGN_SIZE := Vector2(640, 120)
const ICON_SIZE := Vector2(104, 92)
const FONT_SIZE := 52
const MONEY_ICON := preload("res://assets/ui/icons/icon_cash_bundle.png")
const GOLD_ICON := preload("res://assets/ui/icons/icon_gold_coins.png")

signal value_changed(kind: StringName, text: String)

var money_update_count := 0
var gold_update_count := 0
var _panel: Panel
var _money_icon: TextureRect
var _money_label: Label
var _gold_icon: TextureRect
var _gold_label: Label

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    custom_minimum_size = DESIGN_SIZE
    size = DESIGN_SIZE
    _panel = Panel.new()
    _panel.name = "Background"
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = BG_COLOR
    style.set_corner_radius_all(CORNER_RADIUS)
    style.anti_aliasing = true
    _panel.add_theme_stylebox_override("panel", style)
    add_child(_panel)
    _panel.position = Vector2.ZERO
    _panel.size = DESIGN_SIZE
    var half := DESIGN_SIZE.x * 0.5
    _money_icon = _icon("MoneyIcon", MONEY_ICON, Vector2(18, (DESIGN_SIZE.y - ICON_SIZE.y) * 0.5))
    _money_label = _label("MoneyLabel", Rect2(18 + ICON_SIZE.x + 8, 0, half - ICON_SIZE.x - 40, DESIGN_SIZE.y))
    _gold_icon = _icon("GoldIcon", GOLD_ICON, Vector2(half + 6, (DESIGN_SIZE.y - ICON_SIZE.y) * 0.5))
    _gold_label = _label("GoldLabel", Rect2(half + 6 + ICON_SIZE.x + 8, 0, half - ICON_SIZE.x - 36, DESIGN_SIZE.y))
    # Divisória discreta entre os dois valores.
    var divider := ColorRect.new()
    divider.name = "Divider"
    divider.color = Color(1, 1, 1, 0.18)
    divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    divider.position = Vector2(half - 2, 22)
    divider.size = Vector2(3, DESIGN_SIZE.y - 44)
    add_child(divider)
    _money_label.text = "0"
    _gold_label.text = "0"

func _icon(label: String, texture: Texture2D, at: Vector2) -> TextureRect:
    var rect := TextureRect.new()
    rect.name = label
    rect.texture = texture
    rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rect.position = at
    rect.size = ICON_SIZE
    add_child(rect)
    return rect

func _label(label: String, rect: Rect2) -> Label:
    var l := Label.new()
    l.name = label
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    UiStyle.style_label(l, FONT_SIZE, UiStyle.TEXT_CREAM, Color(0, 0, 0, 0.55), 8)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.clip_text = false
    add_child(l)
    UiStyle.place(l, rect)
    return l

func set_money(value: int, animate: bool = true) -> void:
    if _set_label(_money_label, UiStyle.format_int(value), animate):
        money_update_count += 1
        value_changed.emit(&"money", _money_label.text)

func set_gold(value: int, animate: bool = true) -> void:
    if _set_label(_gold_label, UiStyle.format_int(value), animate):
        gold_update_count += 1
        value_changed.emit(&"gold", _gold_label.text)

func get_money_text() -> String:
    return _money_label.text

func get_gold_text() -> String:
    return _gold_label.text

func get_money_label() -> Label:
    return _money_label

func get_gold_label() -> Label:
    return _gold_label

func get_background_color() -> Color:
    return (_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color

func _set_label(label: Label, text: String, animate: bool) -> bool:
    if label.text == text:
        return false
    label.text = text
    UiStyle.fit_font(label, FONT_SIZE)
    if animate:
        UiStyle.pulse(label)
    return true
