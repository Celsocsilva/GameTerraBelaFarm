"""FARM-005: textura de terra contínua (sem emenda) para os caminhos.

Recorta o miolo de terra de assets/terrain/path_cross.png (arte da lib) e
torna a amostra repetível: cópia deslocada meio quadro misturada com máscara
radial suave (o centro da cópia cobre as emendas da original).
Saída: assets/terrain/path/path_dirt_seamless.png (256 x 256).
"""
from PIL import Image, ImageFilter
import numpy as np

SRC = "assets/terrain/path_cross.png"
OUT = "assets/terrain/path/path_dirt_seamless.png"
SIZE = 256

im = Image.open(SRC).convert("RGB")
w, h = im.size
# Miolo do cruzamento: quadrado de terra sem grama.
cx, cy, half = w // 2, h // 2, 44
crop = im.crop((cx - half, cy - half, cx + half, cy + half)).resize((SIZE, SIZE), Image.LANCZOS)
a = np.asarray(crop).astype(np.float32)
b = np.roll(np.roll(a, SIZE // 2, axis=0), SIZE // 2, axis=1)
y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
# Peso da original: 1 no centro, 0 nas bordas (onde ficam as emendas do roll).
d = np.maximum(np.abs(x - SIZE / 2 + 0.5), np.abs(y - SIZE / 2 + 0.5)) / (SIZE / 2)
wgt = np.clip((1.0 - d) / 0.45, 0.0, 1.0)[..., None]
wgt = wgt * wgt * (3 - 2 * wgt)
out = a * wgt + b * (1 - wgt)
img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH)
img.save(OUT)
print(OUT, img.size)
