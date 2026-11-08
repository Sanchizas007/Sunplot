"""Из шести кадров ChatGPT делает «подложки»: фон 1206×2622 без заголовка (текст стёрт полиномом по небу).
Запуск из корня Sunspot: python3 -X utf8 make_plates.py"""
import numpy as np
from PIL import Image
from scipy import ndimage
from pathlib import Path

ROOT = Path.cwd()
SRC = ROOT / "screenshots" / "templates"
DST = SRC / "plates"
W, H = 1206, 2622
NAMES = ["01-today", "02-sky", "03-year", "04-plants", "05-map", "06-compare"]
BAND = 640   # ниже — зона телефона, поверх неё рисуется наш


def features(x, y):
    u, v = x / W, y / BAND
    cols = [np.ones_like(u)]
    for i in range(0, 4):
        for j in range(0, 4 - i):
            if i + j > 0:
                cols.append(u ** i * v ** j)
    return np.stack(cols, axis=-1)


for name in NAMES:
    im = Image.open(SRC / f"{name}.png").convert("RGB").resize((W, H), Image.LANCZOS)
    a = np.asarray(im).astype(float)
    top = a[:BAND]
    mn = top.min(axis=2)
    white = mn >= 222
    yellow = (top[..., 0] > 215) & (top[..., 1] > 150) & (top[..., 2] < 140) & (top[..., 0] - top[..., 2] > 90) & (top[..., 1] < 0.92 * top[..., 0])
    bright = white | yellow
    big = ndimage.binary_dilation(ndimage.binary_opening(bright, structure=np.ones((70, 70), bool)), iterations=10)
    text = ndimage.binary_dilation(bright & ~big, iterations=30)
    gy0, gx0 = np.mgrid[0:BAND, 0:W]
    left_white = ndimage.binary_dilation(white & (gx0 <= 140) & (gy0 > 60), iterations=8)   # первые буквы слева
    text &= (gx0 > 140) | (gy0 > 300)            # листья в левом углу не трогаем
    text |= left_white
    text[:90] = False                            # и блик у верхнего края
    # небо без текста, листьев, облаков и блика: из него считаем гладкую модель
    sky = (top[..., 2] > top[..., 0] + 45) & (top[..., 2] > top[..., 1] + 10) & ~text
    sky = ndimage.binary_erosion(sky, iterations=6)
    ys, xs = np.nonzero(sky[::3, ::3])
    ys, xs = ys * 3, xs * 3
    F = features(xs.astype(float), ys.astype(float))
    fit = np.zeros_like(top)
    gy, gx = np.mgrid[0:BAND, 0:W]
    Fall = features(gx.astype(float), gy.astype(float))
    for c in range(3):
        coef, *_ = np.linalg.lstsq(F, top[ys, xs, c], rcond=None)
        fit[..., c] = Fall @ coef
    resid = np.abs(top - fit).max(axis=2)
    extra = (resid > 12) & (gx0 > 60) & (gx0 < 1100) & (gy0 > 200) & (gy0 < 450)
    text = text | ndimage.binary_dilation(extra, iterations=6)
    text[450:] = False                           # ниже закрывает наш телефон
    alpha = ndimage.gaussian_filter(text.astype(float), 12)
    alpha = np.clip(alpha * 1.6, 0, 1) * (text | (alpha > 0.05))
    rng = np.random.default_rng(11)
    patch = fit + rng.normal(0, 1.4, fit.shape)
    out = a.copy()
    out[:BAND] = top * (1 - alpha[..., None]) + patch * alpha[..., None]
    Image.fromarray(np.clip(out, 0, 255).astype("uint8")).save(DST / f"{name}.png")
    print(name, "стёрто:", int(text.sum()), "образцов неба:", len(xs))
