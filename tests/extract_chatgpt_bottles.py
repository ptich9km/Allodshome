#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTBottle1.png → assets/potions/*.png.

Вход:  import/ChatGPTBottle1.png (1254x1254, RGB, фон ~ (18,18,19))
Компоненты: 11 связных объектов, найдены авто-детекцией (area > 500 px),
           а не жёсткой сеткой — бутылки разного размера, клетка не равна.
Выход: 64x64 RGBA, пропорции сохранены, бутылка по длинной стороне.

Метод: альфа-градиент по расстоянию до цвета фона, а не бинарный порог.
       У бутылок в атласе мягкая тень (4327 px с dist 12-60). Жёсткая маска
       превращала её в серую плиту — на тёмном фоне магазина читалось как
       чёрный квадрат по краям. Градиент растворяет тень, сохраняя и её, и
       свечения вокруг флаконов.

Запуск:
    python tests/extract_chatgpt_bottles.py
    python tests/extract_chatgpt_bottles.py --report
    python tests/extract_chatgpt_bottles.py --sheet
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = os.path.join("import", "ChatGPTBottle1.png")
OUT_DIR = os.path.join("assets", "potions")
SHEET = os.path.join(OUT_DIR, "_contact_sheet.png")

GAME_SIZE = 64
BG = (18, 18, 19)
ALPHA_LO = 12.0
ALPHA_HI = 110.0
ALPHA_BLUR = 0.8
MIN_AREA = 500

# Имена по порядку компонент: верхний ряд слева направо, потом нижний.
NAMES = [
    "health_small",
    "health_medium",
    "health_large",
    "mana_small",
    "mana_medium",
    "mana_large",
    "nature_leaf",
    "astral_feather",
    "light_star",
    "dark_skull",
    "light_wings",
]


def flood_background(is_bg: np.ndarray) -> np.ndarray:
    """True только для фона, связного с границей изображения (4-связность)."""
    h, w = is_bg.shape
    seen = np.zeros_like(is_bg)
    queue: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and is_bg[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def find_components(obj: np.ndarray) -> list[tuple[int, int, int, int, int]]:
    """Связные компоненты как (area, x0, y0, x1, y1), по чтению сверху вниз."""
    h, w = obj.shape
    labels = np.zeros(obj.shape, dtype=bool)
    comps: list[tuple[int, int, int, int, int]] = []
    ys, xs = np.nonzero(obj)
    for y0, x0 in zip(ys, xs):
        if labels[y0, x0]:
            continue
        queue: deque[tuple[int, int]] = deque([(y0, x0)])
        labels[y0, x0] = True
        minx = maxx = x0
        miny = maxy = y0
        area = 0
        while queue:
            y, x = queue.popleft()
            area += 1
            minx, maxx = min(minx, x), max(maxx, x)
            miny, maxy = min(miny, y), max(maxy, y)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and obj[ny, nx] and not labels[ny, nx]:
                    labels[ny, nx] = True
                    queue.append((ny, nx))
        if area >= MIN_AREA:
            comps.append((area, minx, miny, maxx, maxy))
    # порядок чтения: по верхней границе, затем по левой
    comps.sort(key=lambda c: (round(c[2] / 300), c[1]))
    return comps


def cut_component(arr: np.ndarray, comp: tuple[int, int, int, int, int]) -> Image.Image:
    """Вырезает компоненту; альфа = градиент по расстоянию до цвета фона.

    Бинарный порог здесь не годится: у каждой бутылки в атласе мягкая тень,
    и жёсткая маска превращала её в непрозрачную серую плиту вокруг флакона.
    Градиент растворяет тень, сохраняя и её, и ореолы свечений.
    """
    _, x0, y0, x1, y1 = comp
    cell = arr[y0 : y1 + 1, x0 : x1 + 1]
    dist = np.linalg.norm(
        cell[:, :, :3].astype(np.float32) - np.array(BG, dtype=np.float32), axis=2
    )
    alpha = np.clip((dist - ALPHA_LO) / (ALPHA_HI - ALPHA_LO), 0.0, 1.0) * 255.0
    rgba = np.dstack([cell[:, :, :3], alpha.astype(np.uint8)])
    rgba[:, :, 3] = np.array(
        Image.fromarray(rgba[:, :, 3], "L").filter(ImageFilter.GaussianBlur(ALPHA_BLUR))
    )
    ys, xs = np.where(rgba[:, :, 3] > 16)
    if not len(ys):
        return Image.fromarray(rgba, "RGBA")
    return Image.fromarray(
        rgba[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], "RGBA"
    )


def fit_game_size(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    scale = GAME_SIZE / max(w, h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GAME_SIZE, GAME_SIZE), (0, 0, 0, 0))
    canvas.paste(im, ((GAME_SIZE - nw) // 2, (GAME_SIZE - nh) // 2), im)
    return canvas


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(SOURCE):
        print(f"FAIL: нет {SOURCE}")
        return 1

    src = Image.open(SOURCE).convert("RGB")
    arr = np.array(src)
    h, w = arr.shape[:2]
    print(f"SOURCE {w}x{h}")

    dist = np.linalg.norm(
        arr.astype(np.float32) - np.array(BG, dtype=np.float32), axis=2
    )
    obj = ~flood_background(dist <= ALPHA_LO)
    comps = find_components(obj)
    print(f"components={len(comps)} (ожидается {len(NAMES)})")

    if len(comps) != len(NAMES):
        print("FAIL: число компонент не совпало с NAMES — имена сдвинутся")
        return 2

    os.makedirs(OUT_DIR, exist_ok=True)
    written = 0
    for comp, name in zip(comps, NAMES):
        area, x0, y0, x1, y1 = comp
        crop = cut_component(arr, comp)
        out_im = fit_game_size(crop)
        fname = f"{name}.png"
        if not args.report:
            out_im.save(os.path.join(OUT_DIR, fname))
        written += 1
        print(
            f"OK {name:16} area={area:6} "
            f"bbox=({x0},{y0})-({x1},{y1}) {x1 - x0 + 1}x{y1 - y0 + 1} -> {fname}"
        )

    if args.sheet or not args.report:
        cols = 6
        rows = (len(NAMES) + cols - 1) // cols
        pad = 8
        label_h = 14
        sheet = Image.new(
            "RGBA",
            (cols * (GAME_SIZE + pad), rows * (GAME_SIZE + pad + label_h)),
            (32, 32, 36, 255),
        )
        draw = ImageDraw.Draw(sheet)
        for idx, name in enumerate(NAMES):
            path = os.path.join(OUT_DIR, f"{name}.png")
            x = (idx % cols) * (GAME_SIZE + pad)
            y = (idx // cols) * (GAME_SIZE + pad + label_h)
            draw.text((x, y + GAME_SIZE + 2), name, fill=(220, 220, 220, 255))
            if os.path.exists(path) and not args.report:
                icon = Image.open(path).convert("RGBA")
                sheet.paste(icon, (x, y), icon)
        if not args.report:
            sheet.save(SHEET)
            print(f"SHEET {SHEET}")

    print(f"written={written}")
    print(f"RESULT: {'OK' if written == len(NAMES) else 'FAIL'}")
    return 0 if written == len(NAMES) else 2


if __name__ == "__main__":
    sys.exit(main())