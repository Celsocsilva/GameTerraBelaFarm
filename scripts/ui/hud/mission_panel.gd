extends Control
class_name MissionPanel
## Painel de missão (mission_panel_bg.png). Título, ícone, barra de progresso e
## prêmio são definidos por código: set_mission() e set_progress().
## A barra pintada no PNG fica coberta pela HudProgressBar (o progresso real).

const CASH_ICON := preload("res://assets/currency/cash_bundle_official.png")
const ICON_RECT := Rect2(62, 62, 130, 130)
const TITLE_RECT := Rect2(254, 52, 440, 60)
const BAR_RECT := Rect2(242, 131, 462, 57)
const REWARD_CAPTION_RECT := Rect2(234, 224, 170, 110)
const REWARD_ICON_RECT := Rect2(404, 236, 124, 84)
const REWARD_VALUE_RECT := Rect2(534, 224, 150, 110)
## FARM-003: o número do prêmio (dinheiro) usa o MESMO tamanho de fonte do
## número de progresso (recursos, ex.: "0/336") da barra; antes era 50.
const REWARD_FONT_SIZE := 36

@onready var icon_rect: TextureRect = $Icon
@onready var title_label: Label = $TitleLabel
@onready var progress_bar: HudProgressBar = $ProgressBar
@onready var reward_caption: Label = $RewardCaption
@onready var reward_icon: TextureRect = $RewardIcon
@onready var reward_label: Label = $RewardLabel

func _ready() -> void:
    UiStyle.place(icon_rect, ICON_RECT)
    UiStyle.style_label(title_label, 40)
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    UiStyle.place(title_label, TITLE_RECT)
    UiStyle.place(progress_bar, BAR_RECT)
    UiStyle.style_label(reward_caption, 36)
    for label in [title_label, reward_caption, reward_label]:
        (label as Label).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    reward_caption.text = tr("MISSION_REWARD")
    UiStyle.place(reward_caption, REWARD_CAPTION_RECT)
    reward_icon.texture = CASH_ICON
    UiStyle.place(reward_icon, REWARD_ICON_RECT)
    UiStyle.style_label(reward_label, REWARD_FONT_SIZE)
    reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    UiStyle.place(reward_label, REWARD_VALUE_RECT)

## Chave (ou texto) do título atual: retraduzido quando o idioma muda.
var _title_key := ""

## `title` pode ser uma chave de localization/ui.csv (ex.: MISSION_HARVEST_TOMATOES).
func set_mission(title: String, icon: Texture2D, target: int, reward: int) -> void:
    _title_key = title
    title_label.text = tr(title)
    icon_rect.texture = icon
    reward_label.text = UiStyle.format_int(reward)
    UiStyle.fit_font(reward_label, REWARD_FONT_SIZE)
    progress_bar.set_progress(0, target)

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        reward_caption.text = tr("MISSION_REWARD")
        if not _title_key.is_empty():
            title_label.text = tr(_title_key)

func set_progress(value: int, target: int) -> void:
    progress_bar.set_progress(value, target)

## Título + progresso de uma vez (API pedida no prompt UI v5).
func set_mission_progress(title: String, current: int, target: int) -> void:
    _title_key = title
    title_label.text = tr(title)
    progress_bar.set_progress(current, target)

func get_title() -> String:
    return title_label.text

func get_progress_text() -> String:
    return progress_bar.get_label_text()
