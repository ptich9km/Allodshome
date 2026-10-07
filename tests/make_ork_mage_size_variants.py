#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Лаборатория размеров ork_mage: кандидаты варианта A + контактный лист.

Источник: assets/wip/characters/ork_mage/r{tier}_d{dir}_*.png (80×80, content ~50×80).
Вариант A: content-рост H ∈ {48,52,56,64} на холсте 64×64, feet на y=62.
Методы: NEAREST (основной) и AREA (контроль). LANCZOS не используется.

Кандидаты: assets/units/_size_lab/ork_h{H}_{nearest|area}/t{tier}/sprites-00{1..8}.png
Лист:     assets/units/_size_lab/_contact_sheet_A.png

Запуск:
  python tests/make_ork_mage_size_variants.py
  python tests/make_ork_mage_size_variants.py --check   # замеры content-h, без перезаписи листа
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

WIP_DIR = os.path.join("assets", "wip", "characters", "ork_mage")
LAB_DIR = os.path.join("assets", "units", "_size_lab")
SHEET = os.path.join(LAB_DIR, "_contact_sheet_A.png")
GRASS = os.path.join("assets", "terrain", "tile1-00.bmp")

CANVAS = 64
FOOT_Y = 62          # нижняя строка content (2 px запас)
HEIGHTS = (48, 52, 56, 64)
METHODS = ("nearest", "area")
TIERS = (0, 1, 2, 3)
DIRS = (0, 1, 2, 3, 4, 5, 6, 7)
DIR_RU = ("Ю", "ЮЗ", "З", "СЗ", "С", "СВ", "В", "ЮВ")

# Контрольные колонки листа (реальные файлы, не пережатые)
CONTROLS = [
    ("Allods orc", os.path.join("assets", "units", "monsters", "orc", "sprites-001.png")),
    ("Allods hero", os.path.join("assets", "units", "heroes", "swordsman", "sprites-001.png")),
    ("ork_mage 40", os.path.join("assets", "units", "ork_mage", "t0", "sprites-001.png")),
    ("WIP 80 raw", os.path.join(WIP_DIR, "r0_d0_down.png")),
]

PAD = 8
LABEL_H = 16
ROW_GAP = 10
BAND_GAP = 18


def wip_path(tier: int, d: int) -> str:
    names = ["down", "down_left", "left", "up_left", "up", "up_right", "right", "down_right"]
    return os.path.join(WIP_DIR, "r%d_d%d_%s.png" % (tier, d, names[d]))


def content_bbox(im: Image.Image):
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    return im.getbbox()


def scale_to_height(im: Image.Image, target_h: int, method: str) -> Image.Image:
    """Масштаб по высоте content до target_h, сохраняя пропорции."""
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    bb = content_bbox(im)
    if bb is None:
        return im
    ch = bb[3] - bb[1]
    if ch <= 0:
        return im
    scale = float(target_h) / float(ch)
    nw = max(1, int(round(im.size[0] * scale)))
    nh = max(1, int(round(im.size[1] * scale)))
    resample = Image.Resampling.NEAREST if method == "nearest" else Image.Resampling.BOX
    return im.resize((nw, nh), resample)


def place_on_canvas(im: Image.Image, canvas: int = CANVAS, foot_y: int = FOOT_Y) -> Image.Image:
    """Центр по X, низ content = foot_y."""
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    bb = content_bbox(im)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    if bb is None:
        return out
    ch = bb[3] - bb[1]
    cw = bb[2] - bb[0]
    # сдвигаем так, чтобы bbox content лёг с y = foot_y - ch
    ox = (canvas - im.size[0]) // 2 - bb[0] + (canvas - cw) // 2
    # проще: берём im, центрируем по X с учётом bbox, низ content на foot_y
    x = (canvas - cw) // 2 - bb[0]
    y = foot_y - bb[3] + 1  # bb[3] = y1 включительно -> y1 + y_offset = foot_y
    # bb[3] is exclusive in getbbox? In PIL getbbox: (left, upper, right, lower) exclusive right/lower
    # lower is exclusive, so last content row = bb[3]-1. We want bb[3]-1 + y_off = foot_y
    y = foot_y - (bb[3] - 1) - bb[1] + bb[1]  # = foot_y - bb[3] + 1, then paste at y - bb[1]?
    # paste position for top-left of im:
    paste_y = foot_y - (bb[3] - 1)  # content bottom row lands on foot_y; content top at paste_y+bb[1]
    # Wait: paste at P means content row r goes to P+r. Content bottom row = bb[3]-1.
    # We want P + (bb[3]-1) = foot_y => P = foot_y - (bb[3]-1)
    paste_y = foot_y - (bb[3] - 1)
    paste_x = (canvas - cw) // 2 - bb[0]
    out.paste(im, (paste_x, paste_y), im)
    return out


def make_candidate(tier: int, d: int, height: int, method: str) -> Image.Image:
    src = Image.open(wip_path(tier, d))
    scaled = scale_to_height(src, height, method)
    return place_on_canvas(scaled)


def write_candidates(check_only: bool) -> dict:
    """Возвращает {(height, method): {tier: [Image, ...]}} + пишет PNG если не check."""
    table: dict = {}
    fails = 0
    for h in HEIGHTS:
        for method in METHODS:
            per_tier: dict = {}
            for tier in TIERS:
                frames = []
                for d in DIRS:
                    im = make_candidate(tier, d, h, method)
                    frames.append(im)
                    bb = content_bbox(im)
                    ch = (bb[3] - bb[1]) if bb else 0
                    cw = (bb[2] - bb[0]) if bb else 0
                    if ch < h - 2 or ch > h + 2:
                        print("FAIL content_h=%d expect~%d %s t%d d%d" % (ch, h, method, tier, d))
                        fails += 1
                    if bb and bb[3] - 1 != FOOT_Y:
                        print("FAIL foot y=%d expect %d %s t%d d%d" % (bb[3] - 1, FOOT_Y, method, tier, d))
                        fails += 1
                    if not check_only:
                        out_dir = os.path.join(LAB_DIR, "ork_h%d_%s" % (h, method), "t%d" % tier)
                        os.makedirs(out_dir, exist_ok=True)
                        im.save(os.path.join(out_dir, "sprites-%03d.png" % (d + 1)))
                per_tier[tier] = frames
            table[(h, method)] = per_tier
            if not check_only:
                print("wrote ork_h%d_%s  t0 content~%d" % (
                    h, method,
                    (content_bbox(per_tier[0][0])[3] - content_bbox(per_tier[0][0])[1])
                    if content_bbox(per_tier[0][0]) else 0))
    print("check fails=%d" % fails)
    return table


def load_grass_strip(w: int, h: int) -> Image.Image:
    tile = Image.open(GRASS).convert("RGB")
    # tile1: 32×448 = 14 variants of 32×32
    cell = tile.crop((0, 0, 32, 32))
    strip = Image.new("RGB", (w, h), (80, 120, 28))
    for y in range(0, h, 32):
        for x in range(0, w, 32):
            strip.paste(cell, (x, y))
    return strip


def try_font(size: int):
    for path in (
        r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arial.ttf",
        r"C:\Windows\Fonts\calibri.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_sprite_row(draw: ImageDraw.ImageDraw, frames, origin, scale=1, bg=None, bg_box=None):
    """Рисует 8 кадров по горизонтали. origin — левый верхний угол первого кадра."""
    x, y = origin
    cell = CANVAS * scale
    for i, im in enumerate(frames):
        if scale != 1:
            im = im.resize((im.size[0] * scale, im.size[1] * scale), Image.Resampling.NEAREST)
        if bg is not None and bg_box is not None:
            bx, by, bw, bh = bg_box
            tile = bg.crop((bx, by, bx + bw, by + bh)).resize((cell, cell), Image.Resampling.NEAREST)
            draw._image.paste(tile, (x + i * cell, y)) if hasattr(draw, "_image") else None
        # paste с альфой
        base = getattr(draw, "_image", None)
        if base is not None:
            base.paste(im, (x + i * cell, y + (cell - im.size[1]) if scale != 1 else y), im if im.mode == "RGBA" else None)
        else:
            # fallback via separate composite later
            pass
    return x + 8 * cell, y + cell


def build_sheet(table: dict) -> Image.Image:
    font = try_font(14)
    font_sm = try_font(12)
    font_lg = try_font(18)

    cell = CANVAS  # 1×
    row_w = 8 * cell
    left = PAD + 160  # место под подписи
    width = left + row_w + PAD
    # высота: легенда + линейка + 4*H * (4 строки + заголовки) + зум
    legend_h = 70
    ref_h = cell + 36
    band_h = LABEL_H * 2 + ROW_GAP + 4 * (cell + ROW_GAP) + BAND_GAP
    zoom_h = 4 * (2 * CANVAS + ROW_GAP) + 40
    height = legend_h + ref_h + 4 * band_h + zoom_h + PAD * 2

    sheet = Image.new("RGB", (width, height), (28, 28, 32))
    draw = ImageDraw.Draw(sheet)
    grass = load_grass_strip(width, 32 * 4)

    y = PAD
    draw.text((PAD, y), "Вариант A — ork_mage · tile=32 · canvas 64 · content H · feet y=62", font=font_lg, fill=(240, 220, 160))
    y += 24
    draw.text((PAD, y), "Методы: NEAREST (осн.) и AREA (контроль). LANCZOS не используется.", font=font_sm, fill=(180, 180, 180))
    y += 18
    draw.text((PAD, y), "Сравнивай 1× без зума. Потом скажи: «H=52 nearest» или другое.", font=font_sm, fill=(160, 200, 160))
    y = legend_h

    # --- линейка ---
    draw.text((PAD, y), "ЛИНЕЙКА 1×", font=font, fill=(200, 200, 200))
    y += LABEL_H
    # тёмный фон под контролями
    draw.rectangle([0, y, width, y + cell + 8], fill=(40, 40, 48))
    x = left
    labels = []
    for name, path in CONTROLS:
        if not os.path.exists(path):
            draw.text((x, y + 20), "MISSING", font=font_sm, fill=(255, 80, 80))
            labels.append((x, name, 0))
            x += cell + 24
            continue
        im = Image.open(path).convert("RGBA")
        # центрируем по низу в cell
        canvas_im = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        bb = content_bbox(im)
        ch = bb[3] - bb[1] if bb else im.size[1]
        cw = bb[2] - bb[0] if bb else im.size[0]
        px = (cell - cw) // 2 - (bb[0] if bb else 0)
        py = (FOOT_Y - ((bb[3] - 1) if bb else im.size[1] - 1)) if cell >= 64 else cell - ch
        # для контролов с другим размером — прижать низ content к низу cell-полосы
        py = cell - ch - (bb[1] if bb else 0) if not bb else (cell - 1) - (bb[3] - 1)
        px = (cell - cw) // 2 - (bb[0] if bb else 0)
        canvas_im.paste(im, (px, py), im)
        sheet.paste(canvas_im, (x, y), canvas_im)
        draw.text((x, y + cell + 2), name, font=font_sm, fill=(200, 200, 200))
        labels.append((x, name, ch))
        x += cell + 24
    y += cell + 8 + 20
    # трава полоса
    g = grass.crop((0, 0, width, 48))
    sheet.paste(g, (0, y))
    x = left
    for name, path in CONTROLS:
        if not os.path.exists(path):
            x += cell + 24
            continue
        im = Image.open(path).convert("RGBA")
        bb = content_bbox(im)
        ch = bb[3] - bb[1] if bb else im.size[1]
        cw = bb[2] - bb[0] if bb else im.size[0]
        canvas_im = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        px = (cell - cw) // 2 - (bb[0] if bb else 0)
        py = (cell - 1) - (bb[3] - 1) if bb else cell - ch
        canvas_im.paste(im, (px, py), im)
        sheet.paste(canvas_im, (x, y), canvas_im)
        x += cell + 24
    draw.text((PAD, y + 8), "на траве", font=font_sm, fill=(230, 230, 180))
    y += 48 + BAND_GAP

    # --- кандидаты ---
    for h in HEIGHTS:
        draw.text((PAD, y), "H=%d · content %d/64 · %.2f тайла" % (h, h, h / 32.0), font=font, fill=(240, 220, 160))
        y += LABEL_H
        for method in METHODS:
            for tier in (0, 3):
                key = "%s t%d" % (method, tier)
                draw.text((PAD, y + 20), key, font=font_sm, fill=(180, 200, 220))
                frames = table[(h, method)][tier]
                # тёмная подложка
                draw.rectangle([left - 2, y - 2, left + row_w + 2, y + cell + 2], fill=(35, 35, 42))
                for i, im in enumerate(frames):
                    sheet.paste(im, (left + i * cell, y), im)
                # подписи направлений мелко
                for i, dr in enumerate(DIR_RU):
                    draw.text((left + i * cell + 4, y + cell - 14), dr, font=font_sm, fill=(220, 220, 220))
                y += cell + ROW_GAP
            y += 4
        y += BAND_GAP

    # --- зум ×2: 4 строки (H52/H56 × t0/t3), по 4 направления Ю·З·С·ЮВ ---
    draw.text((PAD, y), "ЗУМ ×2 · nearest · Ю · З · С · ЮВ", font=font, fill=(200, 200, 200))
    y += LABEL_H
    zoom_cell = CANVAS * 2
    zoom_row_w = 4 * zoom_cell + 3 * 4
    for h in (52, 56):
        for tier in (0, 3):
            key_l = "H=%d t%d" % (h, tier)
            draw.text((PAD, y + 30), key_l, font=font_sm, fill=(180, 200, 220))
            frames = table[(h, "nearest")][tier]
            picks = [frames[0], frames[2], frames[4], frames[7]]  # Ю З С ЮВ
            draw.rectangle([left - 2, y - 2, left + zoom_row_w + 2, y + zoom_cell + 2], fill=(35, 35, 42))
            xx = left
            for im in picks:
                big = im.resize((zoom_cell, zoom_cell), Image.Resampling.NEAREST)
                sheet.paste(big, (xx, y), big)
                xx += zoom_cell + 4
            y += zoom_cell + ROW_GAP
    draw.text((left, y), "каждая строка: Ю · З · С · ЮВ", font=font_sm, fill=(160, 160, 160))

    return sheet


def main() -> int:
    check_only = "--check" in sys.argv
    if not os.path.isdir(WIP_DIR):
        print("MISSING WIP", WIP_DIR)
        return 1
    os.makedirs(LAB_DIR, exist_ok=True)
    print("WIP:", WIP_DIR)
    table = write_candidates(check_only)
    if check_only:
        return 0
    sheet = build_sheet(table)
    sheet.save(SHEET)
    print("SHEET:", SHEET, sheet.size)
    # краткая сводка content
    print("\ncontent_h (t0 d0) NEAREST:")
    for h in HEIGHTS:
        im = table[(h, "nearest")][0][0]
        bb = content_bbox(im)
        ch = bb[3] - bb[1] if bb else 0
        cw = bb[2] - bb[0] if bb else 0
        print("  H=%d -> content %dx%d  foot_y=%d" % (h, cw, ch, bb[3] - 1 if bb else -1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
