"""FARM-003: frames limpos das vacas para o jogo + 4 cores novas (7 no total).

Entrada: assets/animals/cows/<cor>/frames/*.png (3 cores originais, 8 frames).
Saída:   assets/animals/cows/game/<cor>/<cor>_NN_<pose>.png (com borda limpa).

Limpeza: as artes originais têm respingos vermelhos semitransparentes em volta
(sobras do recorte). Fica só o maior bloco conectado (a vaca), e pixels de
borda semitransparentes muito vermelhos são descartados.

Cores novas (recoloração em HSV, sem redesenhar):
  cow_red_white     <- dark_brown_white, manchas castanho-avermelhadas
  cow_grey_white    <- black_white, manchas cinza-azuladas
  cow_golden_white  <- light_brown_white, manchas douradas
  cow_jersey        <- light_brown_white, corpo caramelo claro (tipo Jersey)
Uso: python3 tools/art/gen_cow_variants.py   (na raiz do projeto)
"""
import glob
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = "assets/animals/cows"
OUT = os.path.join(ROOT, "game")
BASES = ["cow_black_white", "cow_dark_brown_white", "cow_light_brown_white"]


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1); mn = rgb.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r); gm = m & (mx == g) & ~rm; bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h = h / 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return np.stack([h, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0] * 6.0, hsv[..., 1], hsv[..., 2]
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
    out = np.zeros(hsv.shape)
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[..., 0][m] = a[m]; out[..., 1][m] = b[m]; out[..., 2][m] = c[m]
    return out


def clean(img):
    a = np.array(img.convert("RGBA")).astype(float) / 255.0
    alpha = a[..., 3]
    solid = alpha > 0.35
    labels, n = ndimage.label(solid)
    if n > 1:
        sizes = ndimage.sum(solid, labels, range(1, n + 1))
        keep = labels == (int(np.argmax(sizes)) + 1)
    else:
        keep = solid
    keep = ndimage.binary_fill_holes(keep)
    near = ndimage.binary_dilation(keep, iterations=2)
    rgb = a[..., :3]
    reddish = (rgb[..., 0] > 0.55) & (rgb[..., 1] < 0.35) & (rgb[..., 2] < 0.35)
    alpha = np.where(near, alpha, 0.0)
    alpha = np.where(reddish & (alpha < 0.85) & ~ndimage.binary_erosion(keep, iterations=2), 0.0, alpha)
    a[..., 3] = alpha
    return a


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def recolor(a, mode):
    rgb = a[..., :3]
    hsv = rgb_to_hsv(rgb)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    out = rgb.copy()
    if mode == "red":
        # manchas marrons (matiz 0-50°, saturadas, médias/escuras) -> castanho-avermelhado
        # matiz das manchas 0,04-0,09 (o focinho rosa fica abaixo de 0,035)
        w = smooth(s, 0.22, 0.35) * (1 - smooth(v, 0.58, 0.7)) * smooth(h, 0.03, 0.045) * (1 - smooth(h, 0.1, 0.13))
        nh = hsv.copy(); nh[..., 0] = 0.012; nh[..., 1] = np.clip(s * 1.35 + 0.1, 0, 1); nh[..., 2] = np.clip(v * 1.5, 0, 1)
        out = rgb * (1 - w[..., None]) + hsv_to_rgb(nh) * w[..., None]
    elif mode == "grey":
        # manchas pretas -> cinza-azulado; pupilas (muito escuras) ficam
        w = (1 - smooth(v, 0.38, 0.5)) * smooth(v, 0.06, 0.13) * (1 - smooth(s, 0.55, 0.75))
        grey = np.stack([0.50 + v * 0.55, 0.53 + v * 0.55, 0.60 + v * 0.55], -1)
        out = rgb * (1 - w[..., None]) + np.clip(grey, 0, 1) * w[..., None]
    elif mode == "golden":
        w = smooth(s, 0.22, 0.35) * (1 - smooth(v, 0.88, 0.97)) * smooth(h, 0.03, 0.045) * (1 - smooth(h, 0.1, 0.13))
        nh = hsv.copy(); nh[..., 0] = 0.105; nh[..., 1] = np.clip(s * 1.35, 0, 1); nh[..., 2] = np.clip(v * 1.12, 0, 1)
        out = rgb * (1 - w[..., None]) + hsv_to_rgb(nh) * w[..., None]
    elif mode == "jersey":
        # corpo claro (pouca saturação) -> caramelo claro; manchas -> caramelo escuro
        body = (1 - smooth(s, 0.12, 0.25)) * smooth(v, 0.55, 0.75)
        tan = rgb * np.array([0.96, 0.80, 0.58])
        out = rgb * (1 - body[..., None]) + tan * body[..., None]
        w = smooth(s, 0.22, 0.35) * (1 - smooth(v, 0.88, 0.97)) * smooth(h, 0.03, 0.045) * (1 - smooth(h, 0.1, 0.13))
        nh = rgb_to_hsv(out); nh[..., 0] = 0.07; nh[..., 2] = np.clip(nh[..., 2] * 0.82, 0, 1)
        out = out * (1 - w[..., None]) + hsv_to_rgb(nh) * w[..., None]
    a = a.copy()
    a[..., :3] = np.clip(out, 0, 1)
    return a


VARIANTS = {
    "cow_black_white": ("cow_black_white", None),
    "cow_dark_brown_white": ("cow_dark_brown_white", None),
    "cow_light_brown_white": ("cow_light_brown_white", None),
    "cow_red_white": ("cow_dark_brown_white", "red"),
    "cow_grey_white": ("cow_black_white", "grey"),
    "cow_golden_white": ("cow_light_brown_white", "golden"),
    "cow_jersey": ("cow_light_brown_white", "jersey"),
}


def main():
    for name, (base, mode) in VARIANTS.items():
        dst = os.path.join(OUT, name)
        os.makedirs(dst, exist_ok=True)
        for path in sorted(glob.glob(os.path.join(ROOT, base, "frames", "*.png"))):
            pose = os.path.basename(path)[len(base) + 1:]
            a = clean(Image.open(path))
            if mode:
                a = recolor(a, mode)
            Image.fromarray((a * 255).round().astype(np.uint8), "RGBA").save(os.path.join(dst, f"{name}_{pose}"))
        print("ok", name)


if __name__ == "__main__":
    main()


def make_side_rail():
    """Travessa das laterais do curral: recorte de uma travessa da coop_fence_02
    (x 100-420, y 46-80), girada para correr no eixo Z (vertical no PNG)."""
    src = Image.open("assets/fences/coop_fence_02.png").convert("RGBA")
    rail = src.crop((100, 46, 420, 80)).rotate(90, expand=True)
    rail.save("assets/fences/fence_rail_side.png")
    print("ok fence_rail_side", rail.size)


if __name__ == "__main__":
    make_side_rail()
