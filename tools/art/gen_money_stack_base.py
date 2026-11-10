"""Gera assets/sales/money_stack_base.png: tampo da base de dinheiro (bandeja
de madeira com moldura, tábuas e 15 encaixes rasos). Rodar na raiz do projeto:
    python3 tools/art/gen_money_stack_base.py
Os números repetem as constantes de scripts/economy/money_stack.gd."""
import math, random
from PIL import Image, ImageDraw, ImageFilter

MONEY_SCALE = 1.7
BUNDLE_W = 0.74 * MONEY_SCALE
CELL = (BUNDLE_W, BUNDLE_W * 263.0 / 512.0 / math.sin(math.radians(45)))
COLS, ROWS = 3, 5
MARGIN = 0.12  # deve bater com BASE_MARGIN
W = COLS * CELL[0] + MARGIN * 2
H = ROWS * CELL[1] + MARGIN * 2
PX = 256  # pixels por metro (x2 para antialias)
SS = 2
iw, ih = int(W * PX), int(H * PX)
S = lambda v: int(v * PX * SS)

rnd = random.Random(7)
img = Image.new("RGBA", (iw * SS, ih * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
OUT = (74, 40, 18, 255)
FRAME = (150, 92, 48, 255)
FRAME_HI = (190, 128, 70, 255)
PLANK = [(196, 135, 78, 255), (186, 125, 70, 255), (204, 144, 86, 255)]
GRAIN = (150, 96, 52, 255)

r = S(0.16)
d.rounded_rectangle([0, 0, iw * SS - 1, ih * SS - 1], r, fill=OUT)
b = S(0.035)
d.rounded_rectangle([b, b, iw * SS - 1 - b, ih * SS - 1 - b], r - b, fill=FRAME)
# brilho no topo da moldura
d.line([r, b * 2, iw * SS - r, b * 2], fill=FRAME_HI, width=S(0.02))
# miolo de tábuas
ins = S(MARGIN - 0.05)
x0, y0, x1, y1 = ins, ins, iw * SS - ins, ih * SS - ins
d.rounded_rectangle([x0 - S(0.03), y0 - S(0.03), x1 + S(0.03), y1 + S(0.03)], S(0.08), fill=OUT)
plank_h = (y1 - y0) / 7.0
for i in range(7):
    py0 = int(y0 + i * plank_h)
    py1 = int(y0 + (i + 1) * plank_h)
    d.rectangle([x0, py0, x1, py1], fill=PLANK[i % 3])
    d.line([x0, py0, x1, py0], fill=OUT, width=S(0.018))
    d.line([x0, py0 + S(0.02), x1, py0 + S(0.02)], fill=(222, 166, 104, 255), width=S(0.01))
    for _ in range(2):
        gy = rnd.randint(py0 + S(0.06), py1 - S(0.04))
        gx = rnd.randint(x0, x1 - S(0.8))
        d.line([gx, gy, gx + rnd.randint(S(0.4), S(1.1)), gy], fill=GRAIN, width=S(0.012))
    for nx in (x0 + S(0.12), x1 - S(0.12)):
        cy = (py0 + py1) // 2
        d.ellipse([nx - S(0.03), cy - S(0.03), nx + S(0.03), cy + S(0.03)], fill=(96, 70, 52, 255))
# encaixes rasos (onde os maços ficam)
cx0 = (iw * SS - S(COLS * CELL[0])) // 2
cy0 = (ih * SS - S(ROWS * CELL[1])) // 2
shade = Image.new("RGBA", img.size, (0, 0, 0, 0))
sd = ImageDraw.Draw(shade)
for row in range(ROWS):
    for col in range(COLS):
        ax = cx0 + S(col * CELL[0]) + S(0.06)
        ay = cy0 + S(row * CELL[1]) + S(0.06)
        bx = cx0 + S((col + 1) * CELL[0]) - S(0.06)
        by = cy0 + S((row + 1) * CELL[1]) - S(0.06)
        sd.rounded_rectangle([ax, ay, bx, by], S(0.08), fill=(90, 50, 20, 70), outline=(70, 36, 14, 120), width=S(0.015))
        # cifrão gravado
        mx, my = (ax + bx) // 2, (ay + by) // 2
        rr = S(0.16)
        sd.ellipse([mx - rr, my - rr, mx + rr, my + rr], outline=(70, 36, 14, 90), width=S(0.02))
        sd.line([mx, my - rr + S(0.05), mx, my + rr - S(0.05)], fill=(70, 36, 14, 90), width=S(0.02))
        sd.arc([mx - S(0.07), my - S(0.09), mx + S(0.07), my + S(0.01)], 90, 360, fill=(70, 36, 14, 90), width=S(0.02))
        sd.arc([mx - S(0.07), my - S(0.01), mx + S(0.07), my + S(0.09)], 270, 180, fill=(70, 36, 14, 90), width=S(0.02))
img = Image.alpha_composite(img, shade)
img = img.resize((iw, ih), Image.LANCZOS)
img.save("assets/sales/money_stack_base.png")
print("money_stack_base.png", img.size, "base m", round(W, 3), round(H, 3))
