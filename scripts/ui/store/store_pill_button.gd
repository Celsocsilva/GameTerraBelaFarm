extends BaseButton
class_name StorePillButton
## Botão "pílula" da Store V2 (FV-SHOP-003): desenha a textura em 3 fatias
## (ponta esquerda, meio esticado, ponta direita) para ocupar a vaga do botão
## na arte sem deformar as pontas. Ao pressionar só troca para a textura
## pressionada no MESMO retângulo: nada encolhe, cresce ou se desloca.

## Largura da ponta na textura (px) — inclui o brilho do canto esquerdo.
const CAP_PX := 520.0

@export var texture_normal: Texture2D
@export var texture_pressed: Texture2D

func _ready() -> void:
    button_down.connect(queue_redraw); button_up.connect(queue_redraw)
    mouse_exited.connect(queue_redraw)

func _draw() -> void:
    var tex := texture_pressed if (is_pressed() or get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED) and texture_pressed else texture_normal
    if tex == null or size.x <= 0.0 or size.y <= 0.0: return
    var tw := float(tex.get_width()); var th := float(tex.get_height())
    var cap_src := minf(CAP_PX, tw * 0.5 - 1.0)
    var cap_dst := minf(size.y * cap_src / th, size.x * 0.5)
    draw_texture_rect_region(tex, Rect2(0, 0, cap_dst, size.y), Rect2(0, 0, cap_src, th))
    draw_texture_rect_region(tex, Rect2(cap_dst, 0, size.x - cap_dst * 2.0, size.y), Rect2(cap_src, 0, tw - cap_src * 2.0, th))
    draw_texture_rect_region(tex, Rect2(size.x - cap_dst, 0, cap_dst, size.y), Rect2(tw - cap_src, 0, cap_src, th))
