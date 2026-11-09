extends Control
class_name MessagePopup
## Modal grande para mensagens (UI-MESSAGE-001): moldura de madeira com laço
## vermelho (assets/ui/components/panel_message_large.png, 1199 x 1312 com
## margem transparente). É o SEGUNDO modal do jogo: o RewardPopup continua só
## para recompensas; este é para avisos e explicações mais longas.
##
## Princípio do Celso: quanto menos texto, mais fácil de usar e entender.
## Prefira um título de 1 a 2 palavras e uma mensagem de 1 a 2 frases curtas.
##
## Textos: título (na faixa vermelha, abaixo do laço), mensagem (no creme, com
## margem) e botão (OK por padrão). Aceitam chaves de localization/ui.csv ou
## texto já pronto. Cada texto tem um retângulo interno e a fonte é reduzida
## automaticamente (UiStyle.fit_font_box) até caber, com quebra por palavra na
## mensagem. Ao trocar o idioma, tudo é refeito.
##
## Uso: hud.show_message("HELP_HELPER_TITLE", "HELP_HELPER_TEXT")
##      popup.closed.connect(...)  # emitido uma vez ao tocar no botão

signal closed()

const CARD_SIZE := Vector2(1199, 1312)
## Retângulos internos (pixels do PNG) com margem de segurança:
## - título: parte reta da faixa vermelha (as pontas do laço descem até y ~260
##   no meio; o texto tem contorno vermelho escuro e fica legível por cima);
## - mensagem: creme interno (x 115..1085, y 410..1075), com ~55 px de margem;
## - botão: rodapé do creme, centralizado.
const TITLE_RECT := Rect2(240, 196, 720, 92)
const MESSAGE_RECT := Rect2(170, 450, 860, 430)
const BUTTON_RECT := Rect2(380, 905, 440, 126)
## Tamanhos de fonte (máximo / mínimo), em pixels do PNG.
const TITLE_FONT := Vector2i(78, 34)
const MESSAGE_FONT := Vector2i(64, 30)
const MESSAGE_MAX_LINES := 5
const BUTTON_CAPTION_RATIO := 0.4
const BUTTON_CAPTION_INSET := 0.3
const DEFAULT_BUTTON := "MESSAGE_OK"
const IN_TIME := 0.32
const OUT_TIME := 0.2

@onready var dim: ColorRect = $Dim
@onready var card: Control = $Card
@onready var title_label: Label = $Card/TitleLabel
@onready var message_label: Label = $Card/MessageLabel
@onready var ok_button: CtaButton = $Card/OkButton

var is_open := false
var _title_key := ""
var _message_key := ""
var _button_key := DEFAULT_BUTTON
var _card_scale := 1.0
var _tween: Tween

func _ready() -> void:
    UiStyle.style_label(title_label, TITLE_FONT.x, Color.WHITE, UiStyle.OUTLINE_RED, 16)
    UiStyle.style_label(message_label, MESSAGE_FONT.x)
    message_label.add_theme_constant_override("line_spacing", 6)
    for label in [title_label, message_label]:
        (label as Label).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    ok_button.caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    ok_button.color = "green"
    ok_button.caption_ratio = BUTTON_CAPTION_RATIO
    ok_button.caption_inset = BUTTON_CAPTION_INSET
    ok_button.pressed.connect(close)
    UiStyle.place(ok_button, BUTTON_RECT)
    card.size = CARD_SIZE
    card.pivot_offset = CARD_SIZE * 0.5
    resized.connect(_layout)
    visible = false
    _apply_texts()
    _layout()

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _apply_texts()

## `title`, `message` e `button_text` podem ser chaves de localization/ui.csv
## ou textos prontos. Título vazio esconde o título.
func show_message(title: String, message: String, button_text: String = DEFAULT_BUTTON) -> void:
    _title_key = title
    _message_key = message
    _button_key = button_text
    _apply_texts()
    ok_button.set_enabled(true)
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

## Botão OK: animação de saída e `closed` (uma única vez por abertura).
func close() -> void:
    if not is_open:
        return
    is_open = false
    ok_button.set_enabled(false)
    _kill_tween()
    _tween = create_tween().set_parallel(true)
    _tween.tween_property(card, "scale", Vector2.ONE * _card_scale * 0.7, OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    _tween.tween_property(card, "modulate:a", 0.0, OUT_TIME)
    _tween.tween_property(dim, "modulate:a", 0.0, OUT_TIME)
    _tween.chain().tween_callback(_hide_after_exit)
    closed.emit()

func get_card_scale() -> float:
    return _card_scale

## Traduz (chave ou texto pronto) e ajusta cada texto à sua área.
func _apply_texts() -> void:
    _place_texts()
    title_label.visible = not _title_key.is_empty()
    title_label.text = tr(_title_key) if not _title_key.is_empty() else ""
    UiStyle.fit_font_box(title_label, TITLE_FONT.x, TITLE_FONT.y, 1)
    message_label.text = tr(_message_key) if not _message_key.is_empty() else ""
    UiStyle.fit_font_box(message_label, MESSAGE_FONT.x, MESSAGE_FONT.y, MESSAGE_MAX_LINES)
    ok_button.text = tr(_button_key)
    # Uma fonte anterior maior pode ter esticado o Label; volta às áreas internas.
    _place_texts()

func _place_texts() -> void:
    UiStyle.place(title_label, TITLE_RECT)
    UiStyle.place(message_label, MESSAGE_RECT)

## Centraliza o cartão e o reduz para caber na tela (retrato ou paisagem).
func _layout() -> void:
    var fit := minf(size.x * 0.9 / CARD_SIZE.x, size.y * 0.82 / CARD_SIZE.y)
    _card_scale = clampf(fit, 0.2, 1.0)
    card.position = (size - CARD_SIZE) * 0.5
    if not (_tween and _tween.is_running()):
        card.scale = Vector2.ONE * _card_scale

func _hide_after_exit() -> void:
    if not is_open:
        visible = false

func _kill_tween() -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
