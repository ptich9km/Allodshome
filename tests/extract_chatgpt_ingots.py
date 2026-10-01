#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTIngots1.png → assets/professions/blacksmith/{metal}_ingot.png.

Вход:  import/ChatGPTIngots1.png (1536x1024, RGB, тёмный фон ~ (23,24,27))
Сетка: 5 столбцов x 4 строки = 20 слитков.
Выход: 80x80 RGBA. Кроп: color-key фона + дилатация маски (мягкий край).
Без «заливки дырок» — игрок подтвердил эту версию как красивую.

Запуск:
    python tests/extract_chatgpt_ingots.py
    python tests/extract_chatgpt_ingots.py --report
    python tests/extract_chatgpt_ingots.py --sheet
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

SOURCE = os.path.join("import", "ChatGPTIngots1.png")
OUT_DIR = os.path.join("assets", "professions", "blacksmith")
SHEET = os.path.join(OUT_DIR, "_contact_sheet_ingots.png")

GAME_SIZE = 80
COLS = 5
ROWS = 4
BG = (23, 24, 27)
BG_TOL = 32.0
MASK_DILATE = 3

GRID: dict[tuple[int, int], str] = {
    (0, 0): "bronze",
    (0, 1): "iron",
    (0, 2): "steel",
    (0, 3): "argentum",
    (0, 4): "gold",
    (1, 0): "lutetium",
    (1, 1): "titanium",
    (1, 2): "gallium",
    (1, 3): "chromium",
    (1, 4): "wolfram",
    (2, 0): "plutonium",
    (2, 1): "neodymium",
    (2, 2): "lanthanum",
    (2, 3): "thorium",
    (2, 4): "cobalt",
    (3, 0): "radium",
    (3, 1): "promethium",
    (3, 2): "uranium",
    (3, 3): "terbium",
    (3, 4): "yttrium",
}


def fit_game_size(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    scale = GAME_SIZE / max(w, h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GAME_SIZE, GAME_SIZE), (0, 0, 0, 0))
    ox = (GAME_SIZE - nw) // 2
    oy = (GAME_SIZE - nh) // 2
    canvas.paste(im, (ox, oy), im)
    return canvas


def dilate_mask(mask: np.ndarray, radius: int) -> np.ndarray:
    if radius <= 0:
        return mask
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            shifted = np.zeros_like(mask)
            y0 = max(0, dy)
            y1 = min(h, h + dy)
            x0 = max(0, dx)
            x1 = min(w, w + dx)
            shifted[y0:y1, x0:x1] = mask[y0 - dy : y1 - dy, x0 - dx : x1 - dx]
            out |= shifted
    return out


def cut_cell(arr: np.ndarray, x0: int, y0: int, x1: int, y1: int) -> Image.Image:
    """Color-key фона + дилатация. Без заливки внутренних тёмных зон."""
    from PIL import ImageFilter

    cell = arr[y0:y1, x0:x1]
    if cell.ndim == 2:
        cell = np.dstack([cell] * 3)
    rgba = np.dstack(
        [cell[:, :, :3], np.full(cell.shape[:2], 255, dtype=np.uint8)]
    )
    rgb = rgba[:, :, :3].astype(np.float32)
    dist = np.linalg.norm(rgb - np.array(BG, dtype=np.float32), axis=2)
    mask = dist > BG_TOL
    if not mask.any():
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    mask = dilate_mask(mask, MASK_DILATE)
    rgba[:, :, 3] = np.where(mask, rgba[:, :, 3], 0)
    a_soft = Image.fromarray(rgba[:, :, 3], "L").filter(ImageFilter.GaussianBlur(0.7))
    rgba[:, :, 3] = np.array(a_soft)
    ys, xs = np.where(mask)
    return Image.fromarray(
        rgba[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], "RGBA"
    )


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
    print(f"SOURCE {w}x{h}  grid {COLS}x{ROWS}")
    cell_w = w // COLS
    cell_h = h // ROWS

    os.makedirs(OUT_DIR, exist_ok=True)
    written = 0
    for r in range(ROWS):
        for c in range(COLS):
            metal = GRID[(r, c)]
            x0 = c * cell_w
            y0 = r * cell_h
            x1 = (c + 1) * cell_w if c < COLS - 1 else w
            y1 = (r + 1) * cell_h if r < ROWS - 1 else h
            crop = cut_cell(arr, x0, y0, x1, y1)
            out_im = fit_game_size(crop)
            fname = f"{metal}_ingot.png"
            if not args.report:
                out_im.save(os.path.join(OUT_DIR, fname))
            written += 1
            print(f"OK ({r},{c}) {fname:28} crop={crop.size[0]}x{crop.size[1]}")

    if args.sheet or not args.report:
        pad = 8
        label_h = 14
        sheet = Image.new(
            "RGBA",
            (COLS * (GAME_SIZE + pad), ROWS * (GAME_SIZE + pad + label_h)),
            (32, 32, 36, 255),
        )
        draw = ImageDraw.Draw(sheet)
        for r in range(ROWS):
            for c in range(COLS):
                metal = GRID[(r, c)]
                path = os.path.join(OUT_DIR, f"{metal}_ingot.png")
                x = c * (GAME_SIZE + pad)
                y = r * (GAME_SIZE + pad + label_h)
                draw.text((x, y + GAME_SIZE + 2), metal[:12], fill=(220, 220, 220, 255))
                if os.path.exists(path) and not args.report:
                    icon = Image.open(path).convert("RGBA")
                    sheet.paste(icon, (x, y), icon)
        if not args.report:
            sheet.save(SHEET)
            print(f"SHEET {SHEET}")

    print(f"written={written}")
    print(f"RESULT: {'OK' if written == 20 else 'FAIL'}")
    return 0 if written == 20 else 2


if __name__ == "__main__":
    sys.exit(main())
