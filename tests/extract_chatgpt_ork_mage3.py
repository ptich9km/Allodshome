#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPT_OrkMage3.png -> ork_mage_a52 (контракт A: H=52, canvas 64).

Атлас 1536×1024 RGB, фон серый ~201, 4 ступени × 8 направлений, без текста.
Сетка по замеру проекций (порог minRGB<190):
  строки y: 47..252 | 285..500 | 520..739 | 760..989
  колонки x: 59..197 | 247..380 | ... | 1350..1480
Порядок LTR: Ю-ЮЗ-З-СЗ-С-СВ-В-ЮВ (слоты unit_anim 0..7).

Итог: content-рост 52, холст 64×64, feet y=62, NEAREST.

Запуск:
  python tests/extract_chatgpt_ork_mage3.py
  python tests/extract_chatgpt_ork_mage3.py --report
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps

SOURCE = os.path.join("import", "ChatGPT_OrkMage3.png")
OUT_ROOT = os.path.join("assets", "units", "ork_mage_a52")
LAB = os.path.join("assets", "units", "_size_lab")
SHEET = os.path.join(LAB, "_contact_sheet_mage3.png")
ALLODS_ORC = os.path.join("assets", "units", "monsters", "orc_good", "sprites-001.png")
MAGE2 = os.path.join("import", "ChatGPT_OrkMage2.png")

CANVAS = 64
FOOT_Y = 62
TARGET_H = 52
BG_MAX = 190

# Брак атласа Mage3: колонка В (dir index 6) — тело «на запад», посох как у востока.
# Лечение: В = H-flip корректного западного профиля З (index 2). Проверено игроком 07.10.
DIR_MIRROR_FROM = {6: 2}

ROW_BANDS = [(47, 252), (285, 500), (520, 739), (760, 989)]
COL_BANDS = [
    (59, 197), (247, 380), (433, 568), (617, 752),
    (795, 934), (990, 1117), (1193, 1298), (1350, 1480),
]
DIR_RU = ("Ю", "ЮЗ", "З", "СЗ", "С", "СВ", "В", "ЮВ")


def fit_cell(cell: Image.Image, bg_max: int = BG_MAX) -> Image.Image:
    rgb = cell.convert("RGB")
    w, h = rgb.size
    a = Image.new("L", (w, h), 0)
    rp, ap = rgb.load(), a.load()
    for y in range(h):
        for x in range(w):
            r, g, b = rp[x, y]
            if min(r, g, b) < bg_max:
                ap[x, y] = 255
    rgba = Image.merge("RGBA", (*rgb.split(), a))
    bb = rgba.getbbox()
    if bb is None:
        return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    fig = rgba.crop(bb)
    ch = fig.size[1]
    scale = float(TARGET_H) / float(ch)
    nw = max(1, int(round(fig.size[0] * scale)))
    nh = max(1, int(round(TARGET_H)))
    fig = fig.resize((nw, nh), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    paste_y = FOOT_Y - (nh - 1)
    paste_x = (CANVAS - nw) // 2
    out.paste(fig, (paste_x, paste_y), fig)
    return out


def try_font(size: int):
    for path in (r"C:\Windows\Fonts\segoeui.ttf", r"C:\Windows\Fonts\arial.ttf"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def cut_rows(src: Image.Image, row_bands, col_bands, bg_max: int):
    tiles = {}
    for tier, (y0, y1) in enumerate(row_bands):
        raw = {}
        for d, (x0, x1) in enumerate(col_bands):
            cell = src.crop((x0, y0, x1 + 1, y1 + 1))
            raw[d] = fit_cell(cell, bg_max)
        for d, im in raw.items():
            if d in DIR_MIRROR_FROM:
                src_d = DIR_MIRROR_FROM[d]
                tiles[(tier, d)] = ImageOps.mirror(raw[src_d])
                print("dir %d = flip(%d) tier t%d" % (d, src_d, tier))
            else:
                tiles[(tier, d)] = im
        print("tier t%d done" % tier)
    return tiles


def main() -> int:
    report = "--report" in sys.argv
    if not os.path.exists(SOURCE):
        print("MISSING", SOURCE)
        return 1
    src = Image.open(SOURCE).convert("RGB")
    print("SOURCE", SOURCE, src.size)
    tiles = cut_rows(src, ROW_BANDS, COL_BANDS, BG_MAX)

    problems = 0
    for (tier, d), im in tiles.items():
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
    print("problems=%d" % problems)

    # лист: Allods orc_good | Mage2 t0 | Mage3 t0..t3
    font = try_font(14)
    font_sm = try_font(12)
    cell = CANVAS
    width = 220 + 8 * cell + 40
    height = 80 + 2 * (cell + 40) + 4 * (cell + 28)
    sheet = Image.new("RGB", (width, height), (28, 28, 32))
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 8), "ChatGPT_OrkMage3 -> ork_mage_a52 H=52 vs Allods", font=font, fill=(240, 220, 160))
    y = 36
    # сравнение1
    draw.rectangle([0, y, width, y + cell + 24], fill=(40, 40, 48))
    if os.path.exists(ALLODS_ORC):
        orc = Image.open(ALLODS_ORC).convert("RGBA")
        # прижать низ content к низу канвы cell
        bb = orc.getbbox()
        ch = bb[3] - bb[1] if bb else orc.size[1]
        canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        canvas.paste(orc, ((cell - orc.size[0]) // 2, (cell - 1) - (bb[3] - 1)), orc)
        sheet.paste(canvas, (120, y), canvas)
        draw.text((120, y + cell + 2), "Allods orc_good %dpx" % ch, font=font_sm, fill=(200, 200, 200))
    if os.path.exists(MAGE2):
        # быстрый кадр mage2: первый content-пиксель из ячейки 0 — просто показываем mage3 рядом
        pass
    if tiles:
        t00 = tiles[(0, 0)]
        sheet.paste(t00, (280, y), t00)
        draw.text((280, y + cell + 2), "Mage3 t0 (52)", font=font_sm, fill=(180, 220, 180))
        t30 = tiles[(3, 0)]
        sheet.paste(t30, (400, y), t30)
        draw.text((400, y + cell + 2), "Mage3 t3 (52)", font=font_sm, fill=(200, 180, 220))
    y += cell + 40
    for tier in range(4):
        draw.text((10, y + 22), "t%d" % tier, font=font, fill=(200, 200, 200))
        for d in range(8):
            im = tiles[(tier, d)]
            sheet.paste(im, (80 + d * cell, y), im)
            draw.text((80 + d * cell + 2, y + cell - 14), DIR_RU[d], font=font_sm, fill=(220, 220, 220))
        y += cell + 28
    sheet.save(SHEET)
    print("SHEET", SHEET)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
