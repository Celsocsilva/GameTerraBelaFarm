extends TextureButton
class_name SettingsButton
## Botão de configurações (engrenagem prateada, assets/ui/icons/icon_settings_gear.png).
## Fica acima do botão da Loja; o FarmHUD posiciona e abre a FarmSettingsModal.
## Desenhado em DESIGN_SIZE e reduzido pelo HUD com `scale`.

const ICON := preload("res://assets/ui/icons/icon_settings_gear.png")
const DESIGN_SIZE := Vector2(220, 220)

func _ready() -> void:
    texture_normal = ICON
    ignore_texture_size = true
    stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
    custom_minimum_size = DESIGN_SIZE
    size = DESIGN_SIZE
    tooltip_text = "SETTINGS_TITLE"
    button_down.connect(func() -> void: modulate = Color(0.85, 0.85, 0.85))
    button_up.connect(func() -> void: modulate = Color.WHITE)
