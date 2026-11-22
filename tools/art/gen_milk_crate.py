"""DAIRY-001: gera assets/harvest/crate_milk_full.png (caixa vazia + 7 garrafas)
e assets/harvest/milk_bottle.png (garrafa reduzida) a partir de
assets/resources/milk-bottom.png. Uso: python tools/art/gen_milk_crate.py .
"""
from PIL import Image, ImageDraw
import sys
root = sys.argv[1]
crate = Image.open(root + '/assets/harvest/crate_empty.png').convert('RGBA')
bottle = Image.open(root + '/assets/resources/milk-bottom.png').convert('RGBA')
bottle = bottle.crop(bottle.split()[-1].getbbox())
W, H = crate.size
pad_top = 40
canvas = Image.new('RGBA', (W, H + pad_top), (0, 0, 0, 0))
canvas.alpha_composite(crate, (0, pad_top))
def put(cx, bottom, h):
    w = int(bottle.width * h / bottle.height)
    b = bottle.resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(b, (int(cx - w / 2), int(bottom - h + pad_top)))
# Fileira de trás (mais alta na tela) e da frente.
for cx in (150, 235, 320):
    put(cx + 25, 175, 175)
for cx in (120, 205, 290, 375):
    put(cx, 230, 190)
# Frente da caixa por cima: tudo abaixo da borda frontal (polilinha).
mask = Image.new('L', (W, H + pad_top), 0)
d = ImageDraw.Draw(mask)
rim = [(0, 92), (40, 92), (148, 190), (430, 95), (W, 95)]
poly = [(x, y + pad_top) for x, y in rim] + [(W, H + pad_top), (0, H + pad_top)]
d.polygon(poly, fill=255)
front = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
front.alpha_composite(crate, (0, pad_top))
canvas.paste(front, (0, 0), Image.composite(front.split()[-1], Image.new('L', canvas.size, 0), mask))
canvas = canvas.crop(canvas.split()[-1].getbbox())
out = Image.new('RGBA', (canvas.width + 20, canvas.height + 20), (0, 0, 0, 0))
out.alpha_composite(canvas, (10, 10))
out.save(root + "/assets/harvest/crate_milk_full.png")
small = bottle.copy(); small.thumbnail((256, 256), Image.LANCZOS)
o2 = Image.new('RGBA', (small.width + 8, small.height + 8), (0,0,0,0)); o2.alpha_composite(small, (4, 4)); o2.save(root + "/assets/harvest/milk_bottle.png")
print(out.size, o2.size)
