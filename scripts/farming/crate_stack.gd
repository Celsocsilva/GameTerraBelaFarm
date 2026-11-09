extends RefCounted
class_name CrateStack
## Regras comuns das pilhas de caixas do balcão e da parcela de 10% (FV-STACK-001).
##
## Cada cultura tem UMA única pilha vertical. A pilha tem altura visual limitada
## (visual_max caixas); acima disso as caixas extras ficam só na contagem lógica
## e um contador "x12" aparece acima da pilha. A ordem das culturas segue
## CropSign.CROPS (tomate, milho, abóbora) e cada uma ocupa uma vaga própria em X,
## para que as pilhas nunca se sobreponham.

const CROP_ORDER: Array[StringName] = [&"tomato", &"corn", &"pumpkin"]
const LABEL_FONT_SIZE := 96
const LABEL_PIXEL_SIZE := 0.006
const LABEL_COLOR := Color(1.0, 0.98, 0.9)
const LABEL_OUTLINE := Color(0.36, 0.2, 0.08)

## Deslocamento X da pilha de uma cultura: tomate no meio, milho à esquerda,
## abóbora à direita, separadas por `spacing` (centro a centro).
static func slot_x(crop: StringName, spacing: float) -> float:
    match CROP_ORDER.find(crop):
        1:
            return -spacing
        2:
            return spacing
        _:
            return 0.0

## Índice visual na pilha: as caixas além do limite pousam no topo.
static func visual_index(index: int, visual_max: int) -> int:
    return clampi(index, 0, visual_max - 1)

## Texto do contador: vazio enquanto a pilha mostra todas as caixas.
static func count_text(crates: int, visual_max: int) -> String:
    return "x%d" % crates if crates > visual_max else ""

static func make_count_label() -> Label3D:
    var label := Label3D.new()
    label.name = "StackCount"
    label.font = UiStyle.font()
    label.font_size = LABEL_FONT_SIZE
    label.pixel_size = LABEL_PIXEL_SIZE
    label.modulate = LABEL_COLOR
    label.outline_modulate = LABEL_OUTLINE
    label.outline_size = 24
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true
    label.shaded = false
    label.double_sided = true
    label.render_priority = 10
    label.outline_render_priority = 9
    label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    label.visible = false
    return label
