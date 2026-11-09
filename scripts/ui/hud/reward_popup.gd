extends Control
class_name RewardPopup
## Popup de recompensa (panel_reward_popup.png da v5: cartão completo e isolado,
## 577 x 546 com margem transparente). Título, mensagem, ícone e valor são
## definidos por código e desenhados pela engine, com animação de entrada e
## saída. Recompensas em dinheiro usam o maço oficial
## (assets/currency/cash_bundle_official.png).
##
## Abrir o popup não cria dinheiro: só `collect()` emite `collected`, uma vez.
##
## Textos (UI-REWARD-001): título, mensagem e botão aceitam chaves de
## localization/ui.csv (REWARD_TITLE, REWARD_MISSION_COMPLETE, REWARD_COLLECT) ou
## texto já pronto. Cada texto fica num retângulo interno com margem (dentro da
## faixa vermelha, do creme e da placa) e a fonte é reduzida automaticamente
## (UiStyle.fit_font_box) até caber, com quebra de linha por palavra na mensagem
## e reticências como último recurso. Ao trocar o idioma, tudo é refeito.

signal collected(amount: int)

const CASH_ICON := preload("res://assets/currency/cash_bundle_official.png")
const CARD_SIZE := Vector2(577, 546)
## Retângulos internos (pixels do PNG 577 x 546) com margem de segurança:
## o título fica só na parte reta da faixa vermelha, a mensagem no creme entre as
## pontas da faixa (que descem até y ~320 nas laterais) e acima da placa, o valor
## dentro da placa clara.
const TITLE_RECT := Rect2(132, 224, 313, 54)
const MESSAGE_RECT := Rect2(126, 300, 325, 56)
const PLATE_RECT := Rect2(108, 348, 361, 90)
const VALUE_ICON_RECT := Rect2(132, 358, 100, 70)
const VALUE_RECT := Rect2(238, 364, 206, 62)
const BUTTON_RECT := Rect2(138, 445, 300, 86)
## Tamanhos de fonte (máximo / mínimo) — menores que na v5 original (54/38/56).
const TITLE_FONT := Vector2i(42, 18)
const MESSAGE_FONT := Vector2i(30, 14)
const VALUE_FONT := Vector2i(44, 18)
const BUTTON_CAPTION_RATIO := 0.36
const BUTTON_CAPTION_INSET := 0.3
const MESSAGE_MAX_LINES := 2
## Chaves padrão (localization/ui.csv).
const DEFAULT_TITLE := "REWARD_TITLE"
const DEFAULT_MESSAGE := "REWARD_MISSION_COMPLETE"
const DEFAULT_BUTTON := "REWARD_COLLECT"
const IN_TIME := 0.32
const OUT_TIME := 0.2

@onready var dim: ColorRect = $Dim
@onready var card: Control = $Card
@onready var title_label: Label = $Card/TitleLabel
@onready var message_label: Label = $Card/MessageLabel
@onready var value_plate: TextureRect = $Card/ValuePlate
@onready var value_icon: TextureRect = $Card/ValueIcon
@onready var value_label: Label = $Card/ValueLabel
@onready var collect_button: CtaButton = $Card/CollectButton

var amount := 0
var _title_key := DEFAULT_TITLE
var _message_key := DEFAULT_MESSAGE
var _button_key := DEFAULT_BUTTON
var is_open := false
var _card_scale := 1.0
var _tween: Tween

func _ready() -> void:
    UiStyle.style_label(title_label, TITLE_FONT.x, Color.WHITE, UiStyle.OUTLINE_RED, 10)
    UiStyle.place(title_label, TITLE_RECT)
    UiStyle.style_label(message_label, MESSAGE_FONT.x)
    UiStyle.place(message_label, MESSAGE_RECT)
    UiStyle.place(value_plate, PLATE_RECT)
    UiStyle.place(value_icon, VALUE_ICON_RECT)
    UiStyle.style_label(value_label, VALUE_FONT.x)
    UiStyle.place(value_label, VALUE_RECT)
    UiStyle.place(collect_button, BUTTON_RECT)
    # O texto exibido já vem traduzido por tr(); assim o ajuste mede o texto real.
    for label in [title_label, message_label, value_label]:
        (label as Label).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    collect_button.caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    collect_button.color = "green"
    collect_button.caption_ratio = BUTTON_CAPTION_RATIO
    collect_button.caption_inset = BUTTON_CAPTION_INSET
    collect_button.pressed.connect(collect)
    card.size = CARD_SIZE
    card.pivot_offset = CARD_SIZE * 0.5
    resized.connect(_layout)
    visible = false
    _apply_texts()
    _layout()

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _apply_texts()

## Traduz (chave ou texto pronto) e ajusta cada texto à sua área.
func _apply_texts() -> void:
    _place_texts()
    title_label.text = tr(_title_key)
    UiStyle.fit_font_box(title_label, TITLE_FONT.x, TITLE_FONT.y, 1)
    message_label.text = tr(_message_key)
    UiStyle.fit_font_box(message_label, MESSAGE_FONT.x, MESSAGE_FONT.y, MESSAGE_MAX_LINES)
    value_label.text = UiStyle.format_int(amount)
    UiStyle.fit_font_box(value_label, VALUE_FONT.x, VALUE_FONT.y, 1)
    collect_button.text = tr(_button_key)
    # Uma fonte anterior maior pode ter esticado o Label; volta às áreas internas.
    _place_texts()

func _place_texts() -> void:
    UiStyle.place(title_label, TITLE_RECT)
    UiStyle.place(message_label, MESSAGE_RECT)
    UiStyle.place(value_label, VALUE_RECT)

## Centraliza o cartão e o reduz para caber na tela (retrato ou paisagem).
func _layout() -> void:
    var fit := minf(size.x * 0.9 / CARD_SIZE.x, size.y * 0.75 / CARD_SIZE.y)
    _card_scale = clampf(fit, 0.4, 1.35 if size.y > size.x else 1.0)
    card.position = (size - CARD_SIZE) * 0.5
    if not (_tween and _tween.is_running()):
        card.scale = Vector2.ONE * _card_scale

func get_card_scale() -> float:
    return _card_scale

## `title`, `message` e `button_text` podem ser chaves de localization/ui.csv
## (padrão) ou textos prontos.
func show_reward(title: String = DEFAULT_TITLE, message: String = DEFAULT_MESSAGE, value: int = 0, icon: Texture2D = CASH_ICON, button_text: String = DEFAULT_BUTTON) -> void:
    amount = value
    _title_key = title
    _message_key = message
    _button_key = button_text
    value_icon.texture = icon
    _apply_texts()
    collect_button.set_enabled(true)
    is_open = true
    visible = true
    _kill_tween()
    _layout()
    card.scale = Vector2.ONE * _card_scale * 0.55
    card.modulate.a = 0.0
    dim.modulate.a = 0.0
    _tween = create_tween().set_parallel(true)
    _tween.tween_property(card, "scale", Vector2.ONE * _card_scale, IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _tween.tween_property(card, "modulate:a", 1.0, IN_TIME * 0.6)
    _tween.tween_property(dim, "modulate:a", 1.0, IN_TIME)

## Botão "Coletar" (REWARD_COLLECT): animação de saída e depois emite `collected` (uma única vez).
func collect() -> void:
    if not is_open:
        return
    is_open = false
    collect_button.set_enabled(false)
    var value := amount
    _kill_tween()
    _tween = create_tween().set_parallel(true)
    _tween.tween_property(card, "scale", Vector2.ONE * _card_scale * 0.7, OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    _tween.tween_property(card, "modulate:a", 0.0, OUT_TIME)
    _tween.tween_property(dim, "modulate:a", 0.0, OUT_TIME)
    _tween.chain().tween_callback(_hide_after_exit)
    collected.emit(value)

func _hide_after_exit() -> void:
    if not is_open:
        visible = false

func _kill_tween() -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
