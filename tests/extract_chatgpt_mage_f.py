#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ЮЗ (d1): посох с d2 внахлёст на тело, без «парящего» зазора."""
from __future__ import annotations

import os
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = os.path.join("import", "ChatGPTMage_W1.png")
OUT_DIR = os.path.join("assets", "wip", "characters", "mage_f")
SHEET = os.path.join(OUT_DIR, "_contact_sheet.png")

GAME_SIZE = 80
MIN_AREA = 1500
CLOSE_R = 2
BG_CHROMA = 25.0
BG_VAL = 120.0

ATLAS_RU = ["Ю", "ЮВ", "В", "СВ", "С", "З", "ЮЗ", "ЮВ"]
# game slot -> (atlas col, flip)
# СЗ = зеркало СВ; ЮЗ = зеркало ЮВ (в ЮВ посох есть, в исходном ЮЗ — нет)
GAME_MAP = [
    (0, False),  # 0 Ю
    (1, True),   # 1 ЮЗ = flip(ЮВ)
    (5, False),  # 2 З
    (3, True),   # 3 СЗ = flip(СВ)
    (4, False),  # 4 С
    (3, False),  # 5 СВ
    (2, False),  # 6 В
    (1, False),  # 7 ЮВ
]
GAME_NAMES = ["down", "down_left", "left", "up_left", "up", "up_right", "right", "down_right"]
GAME_RU = ["Ю", "ЮЗ", "З", "СЗ", "С", "СВ", "В", "ЮВ"]
D_YUZ, D_Z = 1, 2


def dilate(mask, radius):
    if radius <= 0:
        return mask.copy()
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            shifted = np.zeros_like(mask)
            y0, y1 = max(0, dy), min(h, h + dy)
            x0, x1 = max(0, dx), min(w, w + dx)
            shifted[y0:y1, x0:x1] = mask[y0 - dy : y1 - dy, x0 - dx : x1 - dx]
            out |= shifted
    return out


def fit80(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    scale = GAME_SIZE / max(w, h)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GAME_SIZE, GAME_SIZE), (0, 0, 0, 0))
    canvas.paste(im, ((GAME_SIZE - nw) // 2, (GAME_SIZE - nh) // 2), im)
    return canvas


def label_comps(mask, min_area):
    h, w = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    comps = []
    ys, xs = np.where(mask)
    for y0, x0 in zip(ys, xs):
        if visited[y0, x0]:
            continue
        q = deque([(int(y0), int(x0))])
        visited[y0, x0] = True
        miny = maxy = int(y0)
        minx = maxx = int(x0)
        area = 0
        while q:
            y, x = q.popleft()
            area += 1
            miny = min(miny, y)
            maxy = max(maxy, y)
            minx = min(minx, x)
            maxx = max(maxx, x)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    q.append((ny, nx))
        if area >= min_area:
            comps.append(
                {"x0": minx, "y0": miny, "x1": maxx + 1, "y1": maxy + 1, "area": area}
            )
    comps.sort(key=lambda c: c["x0"])
    return comps


def cut_rgba(rgba_full, c, pad=3):
    y0 = max(0, c["y0"] - pad)
    x0 = max(0, c["x0"] - pad)
    y1 = min(rgba_full.shape[0], c["y1"] + pad)
    x1 = min(rgba_full.shape[1], c["x1"] + pad)
    return Image.fromarray(rgba_full[y0:y1, x0:x1].copy(), "RGBA")


def extract_staff_held(front_im: Image.Image) -> Image.Image:
    """Посох с фронтальной позы (Ю): правая вертикальная часть, где он в руке."""
    rgba = np.array(front_im.convert("RGBA"))
    op = rgba[:, :, 3] >= 40
    if not op.any():
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    h, w = op.shape
    ys, xs = np.where(op)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    body_w = x1 - x0
    # у фронта посох справа ~ правые 35%
    staff_x0 = x1 - max(14, int(body_w * 0.38))
    mask = np.zeros_like(op)
    mask[:, staff_x0:x1] = op[:, staff_x0:x1]
    # компонента: самая высокая (шапка посоха)
    visited = np.zeros_like(mask, dtype=bool)
    best = None
    ys2, xs2 = np.where(mask)
    for py, px in zip(ys2, xs2):
        if visited[py, px]:
            continue
        q = deque([(int(py), int(px))])
        visited[py, px] = True
        miny = maxy = int(py)
        minx = maxx = int(px)
        area = 0
        pix = []
        while q:
            y, x = q.popleft()
            area += 1
            pix.append((y, x))
            miny = min(miny, y)
            maxy = max(maxy, y)
            minx = min(minx, x)
            maxx = max(maxx, x)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    q.append((ny, nx))
        hh = maxy - miny + 1
        if hh >= int(h * 0.40) and (best is None or hh > best[0]):
            best = (hh, minx, miny, maxx + 1, maxy + 1, pix)
    if best is None:
        crop = rgba[:, staff_x0:x1].copy()
        crop[:, :, 3] = np.where(mask[:, staff_x0:x1], crop[:, :, 3], 0)
        ys3, xs3 = np.where(crop[:, :, 3] >= 40)
        if len(xs3):
            crop = crop[ys3.min() : ys3.max() + 1, xs3.min() : xs3.max() + 1]
        return Image.fromarray(crop, "RGBA")
    hh, bx0, by0, bx1, by1, pix = best
    crop = rgba[by0:by1, bx0:bx1].copy()
    local = np.zeros(crop.shape[:2], dtype=bool)
    for y, x in pix:
        local[y - by0, x - bx0] = True
    crop[:, :, 3] = np.where(local, crop[:, :, 3], 0)
    return Image.fromarray(crop, "RGBA")


def composite_held(yuz_im: Image.Image, staff_im: Image.Image) -> Image.Image:
    """Посох в руке: сильный внахлёст на тело, низ — уровень пояса."""
    base = yuz_im.convert("RGBA")
    staff = staff_im.convert("RGBA")
    if staff.size[0] <= 1:
        return base
    ba = np.array(base)[:, :, 3] >= 40
    if not ba.any():
        return base
    bys, bxs = np.where(ba)
    body_right = int(bxs.max()) + 1
    body_top = int(bys.min())
    body_bot = int(bys.max()) + 1
    body_h = body_bot - body_top

    sw, sh = staff.size
    # посох чуть короче тела — кристалл у макушки, низ у пояса
    target_h = int(body_h * 0.88)
    scale = target_h / sh
    nw = max(8, int(round(sw * scale)))
    staff_r = staff.resize((nw, target_h), Image.Resampling.LANCZOS)

    # внахлёст 45% ширины посоха внутрь тела — не «рядом», а в руке
    overlap = max(10, int(nw * 0.45))
    px = max(0, body_right - overlap)
    # кристалл у уровня головы, низ посоха — пояс (~55-60% тела)
    py = body_top + max(0, int(body_h * 0.05))

    canvas_w = max(base.size[0], px + nw + 1)
    canvas_h = max(base.size[1], py + target_h)
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    canvas.paste(base, (0, 0), base)
    # посох поверх робы (справа), без обрезки низа — пусть уходит за пояс
    canvas.paste(staff_r, (px, py), staff_r)
    # тело поверх нижней части древка, чтобы «хват» читался
    # (верх посоха остаётся виден)
    canvas.paste(base, (0, 0), base)
    # снова посох, но только верхняя часть (кристалл + древко до кисти)
    arr_s = np.array(staff_r).copy()
    hand_cut = int(target_h * 0.55)  # до кисти/пояса
    arr_s[hand_cut:, :, 3] = 0
    staff_top = Image.fromarray(arr_s, "RGBA")
    canvas.paste(staff_top, (px, py), staff_top)

    a = np.array(canvas)[:, :, 3]
    if (a >= 40).any():
        ys, xs = np.where(a >= 40)
        canvas = canvas.crop(
            (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        )
    return canvas


def main() -> int:
    src = Image.open(SOURCE).convert("RGB")
    arr = np.array(src)
    af = arr.astype(np.float32)
    mx, mn = af.max(axis=2), af.min(axis=2)
    content = ~(((mx - mn) < BG_CHROMA) & (mx > BG_VAL))
    obj = dilate(content, CLOSE_R)
    rgba_full = np.dstack([arr, np.where(content, 255, 0).astype(np.uint8)])
    a_soft = np.array(
        Image.fromarray(rgba_full[:, :, 3], "L").filter(ImageFilter.GaussianBlur(0.7))
    )
    rgba_full[:, :, 3] = a_soft

    comps = label_comps(obj, MIN_AREA)
    comps_sorted = sorted(comps, key=lambda c: (c["y0"] + c["y1"]) / 2)
    per = (len(comps_sorted) + 3) // 4
    rows = [comps_sorted[i * per : (i + 1) * per] for i in range(4)]
    for row in rows:
        row.sort(key=lambda c: c["x0"])

    os.makedirs(OUT_DIR, exist_ok=True)
    written = 0
    for ri, row in enumerate(rows):
        for gi, (col, flip) in enumerate(GAME_MAP):
            fname = f"r{ri}_d{gi}_{GAME_NAMES[gi]}.png"
            img = cut_rgba(rgba_full, row[col])
            if flip:
                img = img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            out80 = fit80(img)
            out80.save(os.path.join(OUT_DIR, fname))
            written += 1
            print(f"  OK {fname} col={col}{' FLIP' if flip else ''}")

    # contact sheet
    cell = GAME_SIZE + 6
    sheet = Image.new(
        "RGBA", (8 * cell + 8, 4 * (cell + 16) + 8), (32, 32, 36, 255)
    )
    draw = ImageDraw.Draw(sheet)
    for ri in range(4):
        y = 6 + ri * (cell + 16)
        draw.text((2, y + GAME_SIZE + 2), f"row{ri}", fill=(210, 210, 210, 255))
        for gi, name in enumerate(GAME_NAMES):
            path = os.path.join(OUT_DIR, f"r{ri}_d{gi}_{name}.png")
            x = 4 + gi * cell
            draw.text((x, y + GAME_SIZE + 2), GAME_RU[gi], fill=(160, 160, 160, 255))
            if os.path.exists(path):
                ic = Image.open(path).convert("RGBA")
                sheet.paste(ic, (x, y), ic)
    sheet.save(SHEET)
    print(f"written={written} sheet={SHEET}")
    return 0 if written == 32 else 2


if __name__ == "__main__":
    sys.exit(main())
