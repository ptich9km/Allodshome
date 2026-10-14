#!/usr/bin/env python3
"""Режет полосу на ряды по горизонтальным полосам контента и сохраняет верхний
ряд отдельно — чтобы замер направления работал, когда модель вернула 2 ряда
вместо одного, и нижний ряд просто отрезался."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
a = np.array(Image.open(src).convert("RGB")).astype(np.int32)
bg = (a[..., 1] < 110) & (a[..., 0] > 140) & (a[..., 2] > 140) & ((a[..., 0] - a[..., 1]) > 50)
if bg.mean() < 0.2:
    # розовый/светлый фон: берём углы как эталон
    ref = np.median(np.concatenate([
        a[:24, :24].reshape(-1, 3), a[:24, -24:].reshape(-1, 3),
        a[-24:, :24].reshape(-1, 3), a[-24:, -24:].reshape(-1, 3)]), axis=0)
    bg = np.sqrt(((a - ref) ** 2).sum(axis=2)) < 45

fg = ~bg
rows = fg.sum(axis=1)
active = rows >= 3
bands, start = [], -1
for y, v in enumerate(active):
    if v and start < 0:
        start = y
    elif not v and start >= 0:
        bands.append((start, y - 1))
        start = -1
if start >= 0:
    bands.append((start, len(active) - 1))

print(f"{src}: рядов контента {len(bands)} -> {bands}")
y0, y1 = bands[0]
# Заливаем мажентой, а не белым: замер направления и preflight определяют фон
# по маженте, и белая заливка была бы принята за контент (ошибка 14.10 —
# проба дала «1 фигуру шириной 2528px» вместо четырёх).
out = np.zeros_like(a)
out[:, :, 0] = 255
out[:, :, 1] = 0
out[:, :, 2] = 255
out[y0:y1 + 1] = a[y0:y1 + 1]
Image.fromarray(out.astype(np.uint8)).save(dst)
print(f"верхний ряд сохранён: {dst} (y {y0}..{y1})")
