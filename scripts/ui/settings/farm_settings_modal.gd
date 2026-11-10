extends Control
class_name FarmSettingsModal
## Modal de configurações (FV-HUD-002): idioma (PT/ES/EN) e som (ligado/desligado
## + volume). Mesmo visual da loja (creme + madeira). Textos em
## localization/ui.csv (SETTINGS_*); os nomes dos idiomas ficam sempre no
## próprio idioma. Fica na camada de modais do HUD, acima de toda a UI, e o
## fundo escurecido bloqueia os toques no jogo enquanto está aberta.

signal closed

const WOOD := Color("#86502b")
const WOOD_DARK := Color("#60371f")
const CREAM := Color("#fff0cd")
const TEXT := Color("#613817")
const GREEN := Color("#74c82e")
const TAB_IDLE := Color("#ead0a1")
const ORANGE := Color("#f4a23a")
const CARD_WIDTH := 460.0
const MIN_MARGIN := 12.0
const LANGUAGE_NAMES := {"pt_BR": "Português", "es": "Español", "en": "English"}

var _dim: ColorRect
var _card: PanelContainer
var _close_button: Button
var _language_buttons: Dictionary = {}
var _sound_button: Button
var _volume_slider: HSlider

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()
    resized.connect(_layout)
    _card.minimum_size_changed.connect(_layout)
    visible = false

func open_settings() -> void:
    _refresh()
    visible = true
    _layout()
    _close_button.grab_focus()

func close_settings() -> void:
    if not visible:
        return
    visible = false
    closed.emit()

func is_open() -> bool:
    return visible

func get_card_rect() -> Rect2:
    return _card.get_global_rect()

## Usado pelos testes: escolhe um idioma como se o botão fosse tocado.
func choose_language(locale: String) -> void:
    FarmSettings.set_locale(locale)
    _refresh()

func toggle_sound() -> void:
    FarmSettings.set_sound_enabled(not FarmSettings.is_sound_enabled())
    _refresh()

func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("ui_cancel"):
        close_settings()
        get_viewport().set_input_as_handled()

func _build_ui() -> void:
    _dim = ColorRect.new()
    _dim.name = "Dim"
    _dim.color = Color(0.07, 0.05, 0.02, 0.73)
    _dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_dim)
    _dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dim.gui_input.connect(func(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.pressed:
            close_settings())

    _card = PanelContainer.new()
    _card.name = "Card"
    _card.mouse_filter = Control.MOUSE_FILTER_STOP
    _card.add_theme_stylebox_override("panel", _style(CREAM, WOOD_DARK, 7, 26))
    add_child(_card)
    var margins := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margins.add_theme_constant_override("margin_" + side, 20)
    _card.add_child(margins)
    var body := VBoxContainer.new()
    body.add_theme_constant_override("separation", 14)
    margins.add_child(body)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 12)
    body.add_child(header)
    var icon := TextureRect.new()
    icon.texture = SettingsButton.ICON
    icon.custom_minimum_size = Vector2(60, 60)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    header.add_child(icon)
    var title := _label("SETTINGS_TITLE", 30)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    _close_button = Button.new()
    _close_button.name = "CloseButton"
    _close_button.custom_minimum_size = Vector2(56, 54)
    _close_button.text = "×"
    _close_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    _close_button.tooltip_text = "SETTINGS_CLOSE"
    _close_button.add_theme_font_size_override("font_size", 28)
    _close_button.add_theme_stylebox_override("normal", _style(Color("#d85545"), WOOD_DARK, 3, 14))
    _close_button.add_theme_stylebox_override("hover", _style(Color("#ef7560"), WOOD_DARK, 3, 14))
    _close_button.add_theme_color_override("font_color", Color.WHITE)
    _close_button.pressed.connect(close_settings)
    header.add_child(_close_button)

    body.add_child(_label("SETTINGS_LANGUAGE", 20))
    var languages := HBoxContainer.new()
    languages.add_theme_constant_override("separation", 8)
    body.add_child(languages)
    for locale in FarmSettings.LOCALES:
        var button := Button.new()
        button.name = "Lang_" + locale
        button.text = LANGUAGE_NAMES[locale]
        button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
        button.custom_minimum_size = Vector2(130, 50)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.add_theme_font_size_override("font_size", 18)
        button.add_theme_color_override("font_color", TEXT)
        button.add_theme_color_override("font_hover_color", TEXT)
        button.add_theme_color_override("font_focus_color", TEXT)
        button.pressed.connect(choose_language.bind(locale))
        languages.add_child(button)
        _language_buttons[locale] = button

    body.add_child(_label("SETTINGS_SOUND", 20))
    var sound_row := HBoxContainer.new()
    sound_row.add_theme_constant_override("separation", 12)
    body.add_child(sound_row)
    _sound_button = Button.new()
    _sound_button.name = "SoundToggle"
    _sound_button.custom_minimum_size = Vector2(150, 50)
    _sound_button.add_theme_font_size_override("font_size", 18)
    _sound_button.add_theme_color_override("font_color", Color.WHITE)
    _sound_button.add_theme_color_override("font_hover_color", Color.WHITE)
    _sound_button.add_theme_color_override("font_focus_color", Color.WHITE)
    _sound_button.pressed.connect(toggle_sound)
    sound_row.add_child(_sound_button)
    _volume_slider = HSlider.new()
    _volume_slider.name = "Volume"
    _volume_slider.min_value = 0.0
    _volume_slider.max_value = 1.0
    _volume_slider.step = 0.05
    _volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _volume_slider.custom_minimum_size = Vector2(160, 40)
    _volume_slider.value_changed.connect(func(value: float) -> void: FarmSettings.set_volume(value))
    sound_row.add_child(_volume_slider)

func _refresh() -> void:
    var current := FarmSettings.current_locale()
    for locale in _language_buttons:
        var button: Button = _language_buttons[locale]
        var active: bool = locale == current
        var bg := ORANGE if active else TAB_IDLE
        button.add_theme_stylebox_override("normal", _style(bg, WOOD, 2, 12))
        button.add_theme_stylebox_override("hover", _style(Color("#ffe0a5") if not active else ORANGE, WOOD, 2, 12))
        button.add_theme_stylebox_override("pressed", _style(ORANGE, WOOD, 2, 12))
        button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), WOOD_DARK, 2, 12))
    var on := FarmSettings.is_sound_enabled()
    _sound_button.text = "SETTINGS_SOUND_ON" if on else "SETTINGS_SOUND_OFF"
    var color := GREEN if on else Color("#b4aa91")
    _sound_button.add_theme_stylebox_override("normal", _style(color, WOOD, 2, 12))
    _sound_button.add_theme_stylebox_override("hover", _style(color.lightened(0.15), WOOD, 2, 12))
    _sound_button.add_theme_stylebox_override("pressed", _style(color.darkened(0.1), WOOD, 2, 12))
    _volume_slider.set_value_no_signal(FarmSettings.get_volume())
    _volume_slider.editable = on

func _layout() -> void:
    if not is_node_ready():
        return
    var area := size
    var width := minf(CARD_WIDTH, area.x - MIN_MARGIN * 2.0)
    _card.size = Vector2(width, 0.0)
    var card_size := Vector2(width, _card.get_combined_minimum_size().y)
    _card.size = card_size
    _card.position = ((area - card_size) * 0.5).round()

func _label(key: String, font_size: int) -> Label:
    var l := Label.new()
    l.text = key
    l.add_theme_font_override("font", UiStyle.font())
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", TEXT)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return l

func _style(bg: Color, outline: Color, border: int, radius: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.border_color = outline
    box.set_border_width_all(border)
    box.set_corner_radius_all(radius)
    box.content_margin_left = 8
    box.content_margin_right = 8
    box.content_margin_top = 4
    box.content_margin_bottom = 4
    return box
