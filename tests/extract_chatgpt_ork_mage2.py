#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPT_OrkMage2.png -> ork_mage_a52 (контракт A: H=52, canvas 64).

Атлас 1536×1024, RGB, фон серый ~211 (не шахматка), 4 ступени × 8 направлений,
без текста. Порядок колонок LTR как в промте:
  Ю-ЮЗ-З-СЗ-С-СВ-В-ЮВ  (= слоты unit_anim 0..7, flip_h=false).

Сетка по замеру проекций (content share ~0.34, порог minRGB<200):
  строки y: 30..252 | 277..501 | 519..750 | 763..1004
  колонки x: 36..175 | 232..374 | ... | 1375..1514

Итог: content-рост 52 px, холст 64×64, feet y=62, NEAREST (не LANCZOS).

Запуск:
  python tests/extract_chatgpt_ork_mage2.py
  python tests/extract_chatgpt_ork_mage2.py --report
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

SOURCE = os.path.join("import", "ChatGPT_OrkMage2.png")
OUT_ROOT = os.path.join("assets", "units", "ork_mage_a52")
LAB = os.path.join("assets", "units", "_size_lab")
SHEET = os.path.join(LAB, "_contact_sheet_mage2.png")

CANVAS = 64
FOOT_Y = 62
TARGET_H = 52
BG_MAX = 200  # min(RGB) >= 200 -> фон

# замер проекций (см. докстринг); внутри ячейки ещё режем по bbox
ROW_BANDS = [(30, 252), (277, 501), (519, 750), (763, 1004)]
COL_BANDS = [
    (36, 175), (232, 374), (431, 571), (622, 762),
    (811, 951), (1011, 1140), (1219, 1329), (1375, 1514),
]
DIR_RU = ("Ю", "ЮЗ", "З", "СЗ", "С", "СВ", "В", "ЮВ")


def content_bbox(im: Image.Image, bg_max: int = BG_MAX):
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    rgb = im.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if min(r, g, b) < bg_max:
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
                if y < miny:
                    miny = y
                if y > maxy:
                    maxy = y
    if maxx < 0:
        return None
    return (minx, miny, maxx + 1, maxy + 1)


def fit_to_canvas(im: Image.Image, target_h: int = TARGET_H) -> Image.Image:
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    # вырезаем по bbox, убираем фон
    rgb = im.convert("RGB")
    a = Image.new("L", rgb.size, 0)
    rp, ap = rgb.load(), a.load()
    w, h = rgb.size
    for y in range(h):
        for x in range(w):
            r, g, b = rp[x, y]
            if min(r, g, b) < BG_MAX:
                ap[x, y] = 255
    rgba = Image.merge("RGBA", (*rgb.split(), a))
    bb = rgba.getbbox()
    if bb is None:
        return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    fig = rgba.crop(bb)
    ch = fig.size[1]
    scale = float(target_h) / float(ch)
    nw = max(1, int(round(fig.size[0] * scale)))
    nh = max(1, int(round(target_h)))
    fig = fig.resize((nw, nh), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    # низ content = FOOT_Y; bb нижняя строка exclusive -> last = FOOT_Y
    paste_y = FOOT_Y - (nh - 1)
    paste_x = (CANVAS - nw) // 2
    out.paste(fig, (paste_x, paste_y), fig)
    return out


def try_font(size: int):
    for path in (
        r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arial.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def main() -> int:
    report = "--report" in sys.argv
    if not os.path.exists(SOURCE):
        print("MISSING", SOURCE)
        return 1
    src = Image.open(SOURCE).convert("RGB")
    print("SOURCE", SOURCE, src.size)
    os.makedirs(LAB, exist_ok=True)

    tiles = {}  # (tier, dir) -> Image
    problems = 0
    for tier, (y0, y1) in enumerate(ROW_BANDS):
        for d, (x0, x1) in enumerate(COL_BANDS):
            cell = src.crop((x0, y0, x1 + 1, y1 + 1))
            im = fit_to_canvas(cell)
            tiles[(tier, d)] = im
            bb = im.getbbox()
            ch = (bb[3] - bb[1]) if bb else 0
            foot = (bb[3] - 1) if bb else -1
            if ch < TARGET_H - 3 or ch > TARGET_H + 2:
                print("WARN content_h=%d t%d d%d" % (ch, tier, d))
                problems += 1
            if bb and foot != FOOT_Y:
                print("WARN foot=%d t%d d%d" % (foot, tier, d))
                problems += 1
            if not report:
                od = os.path.join(OUT_ROOT, "t%d" % tier)
                os.makedirs(od, exist_ok=True)
                im.save(os.path.join(od, "sprites-%03d.png" % (d + 1)))
        print("tier t%d done" % tier)

    print("problems=%d" % problems)

    # contact sheet: текущий кадр t0 vs новый + ряды новых
    old_path = os.path.join(OUT_ROOT, "t0", "sprites-001.png")
    font = try_font(14)
    cell = CANVAS
    width = 8 * cell + 200
    height = 4 * (cell + 24) + 120
    sheet = Image.new("RGB", (width, height), (30, 30, 34))
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 8), "ChatGPT_OrkMage2 -> ork_mage_a52  H=52 canvas=64 nearest", font=font, fill=(240, 220, 160))
    y = 36
    if os.path.exists(old_path):
        old = Image.open(old_path).convert("RGBA")
        sheet.paste(old, (10, y), old)
        draw.text((10, y + cell + 2), "old t0 d0", font=font, fill=(180, 180, 180))
        new = tiles[(0, 0)]
        sheet.paste(new, (10 + cell + 20, y), new)
        draw.text((10 + cell + 20, y + cell + 2), "new t0 d0", font=font, fill=(180, 220, 180))
    y = 36 + cell + 30
    for tier in range(4):
        draw.text((10, y + 20), "t%d" % tier, font=font, fill=(200, 200, 200))
        for d in range(8):
            im = tiles[(tier, d)]
            sheet.paste(im, (80 + d * cell, y), im)
            draw.text((80 + d * cell + 2, y + cell - 14), DIR_RU[d], font=try_font(11), fill=(220, 220, 220))
        y += cell + 24
    sheet.save(SHEET)
    print("SHEET", SHEET)
    return 0 if problems == 0 else 0  # warns ok


if __name__ == "__main__":
    raise SystemExit(main())
