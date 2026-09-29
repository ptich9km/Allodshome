#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка атласа одежды/брони ChatGPTArmor1.png в отдельные текстуры.

Источник: import/ChatGPTArmor1.png (1312x1199, RGB) + описание
import/ChatGPTArmor1_atlas_description.md.

Что важно знать про этот атлас (проверено на картинке, не взято из описания):

1. Координаты в .md помечены как «примерные» и они смещены: реальные
   границы колонок и строк отличаются от документированных нарастающим
   образом (например, колонка «Плащ» начинается на x=1180, а не на 1152).
   Поэтому сетка здесь задана явными координатами, измеренными по
   границам ячеек, и проверяется инвариантом 9 колонок x 4 строки x 3 блока.
2. Фон НЕ удалён: это RGB-картинка с запечённой шахматкой, а не альфа-канал
   (в отличие от import/ChatGPTWeapons1.png, который RGBA). Шахматка снимается
   заливкой от границ ячейки по признаку «светлый и нецветной».
3. Каждая ячейка — широкий прямоугольник (129..147 x 66..85 px), и предмет
   нарисован во всю её ширину, то есть все 108 предметов горизонтальные.
   Квадрат 80x80 из .md по центру ячейки их не вмещает: замер показал
   median потери 15% и максимум 44% ширины (magic_shirt_elite 97x60 в
   квадрате 54x54), срезаются бока у 95 предметов из 108. Поэтому по
   решению игрока текстура режется **прямоугольником по содержимому**:
   бокс = содержимое + 1 px прозрачного запаса, масштаб так, чтобы длинная
   сторона стала 80 px, пропорции сохраняются. Обрезки по содержимому нет.

4. Внутренность кольца - замкнутая область: заливка от границ ячейки её не
   достигает, и без clear_enclosed_holes() в текстуре остаётся белое пятно.

Запуск:
    python tests/extract_chatgpt_armor.py            # нарезать в assets/items/base
    python tests/extract_chatgpt_armor.py --report   # только отчёт, без записи
    python tests/extract_chatgpt_armor.py --sheet    # + контактный лист
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import deque

from PIL import Image, ImageDraw

SOURCE = os.path.join("import", "ChatGPTArmor1.png")
OUT_DIR = os.path.join("assets", "items", "base")
SHEET = os.path.join("assets", "items", "base", "_contact_sheet.png")

GAME_SIZE = 80          # длинная сторона готовой текстуры, требование .md раздел 10
CELL_INSET = 3          # отступ от границы ячейки, чтобы не попасть в рамку
BG_MIN_LEVEL = 150      # шахматка светлее этого
BG_MAX_CHROMA = 24      # ... и почти нецветная (max-min каналов)
PAD = 1                 # прозрачный запас вокруг содержимого, вписываемого в кадр
MIN_COMPONENT = 40      # мелкие связные кляксы меньше этого - мусор от рамки ячейки
MIN_HOLE_AREA = 80      # замкнутая фоновая дырка (внутренность кольца) больше этого
MAX_HOLE_CHROMA = 11.0  # ... и её средняя хрома ниже этого (шахматка серая, ткань тёплая)

# Сетка, измеренная по границам ячеек (см. docstring). 10 вертикальных линий
# -> 9 колонок предметов (первая колонка - подписи качества, 1..83).
COL_X = [83, 222, 369, 499, 635, 778, 917, 1049, 1180, 1309]
# Три блока, по 4 строки качества: (y_top, [y для 4 строк])
BLOCKS = [
    ("light", 64, [64, 145, 228, 311, 394]),
    ("heavy", 468, [468, 547, 629, 712, 797]),
    ("magic", 864, [864, 934, 1004, 1070, 1136]),
]
SLOTS = ["head", "chest", "bracers", "gloves", "legs", "ring", "amulet", "shirt", "cloak"]
QUALITIES = ["cheap", "common", "good", "elite"]

EXPECTED_CELLS = len(BLOCKS) * len(QUALITIES) * len(SLOTS)


def is_background(p) -> bool:
    """Шахматка: светлая и почти серая.

    Смотрим только RGB: если взять min/max по RGBA-кортежу, туда попадёт
    alpha=255, и хрома всегда будет 42 - фон не снимется никогда."""
    r, g, b = p[0], p[1], p[2]
    lo = min(r, g, b)
    return lo > BG_MIN_LEVEL and (max(r, g, b) - lo) < BG_MAX_CHROMA


def strip_background(cell: Image.Image) -> Image.Image:
    """Заливка фона от границ ячейки. Внутренние светлые детали предмета
    (блик серебра) остаются, потому что до них заливка не доходит."""
    w, h = cell.size
    px = cell.load()
    mask = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()

    def push(x: int, y: int) -> None:
        i = y * w + x
        if not mask[i] and is_background(px[x, y]):
            mask[i] = 1
            q.append((x, y))

    for x in range(w):
        push(x, 0)
        push(x, h - 1)
    for y in range(h):
        push(0, y)
        push(w - 1, y)

    while q:
        x, y = q.popleft()
        if x > 0:
            push(x - 1, y)
        if x + 1 < w:
            push(x + 1, y)
        if y > 0:
            push(x, y - 1)
        if y + 1 < h:
            push(x, y + 1)

    out = cell.copy()
    opx = out.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            if mask[row + x]:
                opx[x, y] = (0, 0, 0, 0)
    return out


def clear_enclosed_holes(cell: Image.Image, min_area: int, max_chroma: float) -> tuple[Image.Image, int]:
    """Убирает ЗАМКНУТЫЕ фоновые области - дырки, до которых заливка от границы
    не дошла.

    Главный случай - внутренность кольца: шахматка там окружена ободком кольца,
    flood fill снаружи её не видит, и в текстуре остаётся белое пятно.

    Одной площади мало: у светлых рубашек (heavy/light_shirt) плоские панели
    ткани тоже замкнуты, светлые и проходят тот же тест цвета - и при cleanup
    по площади в рукавах вырезались прямоугольные дыры. Различает СРЕДНЯЯ
    хрома региона: шахматка почти серая, ткань тёплая (кремовая).

    Замер по всем 108 ячейкам, замкнутые зоны >= 80 px:
      кольца/перчатки/нагрудник - mean_chroma 3.8..8.1  (это дырки, чистим)
      шубы/рубашки              - mean_chroma 14.6..19.0 (это ткань, не трогаем)
    Порог 11 стоит в середине пробела.

    Возвращает (картинка, сколько пикселей очищено)."""
    w, h = cell.size
    px = cell.load()
    seen = bytearray(w * h)
    drop = bytearray(w * h)
    removed = 0
    for sx in range(w):
        for sy in range(h):
            i = sy * w + sx
            if seen[i] or not is_background(px[sx, sy]):
                continue
            q = deque([(sx, sy)])
            seen[i] = 1
            comp = []
            chroma = 0
            edge = False
            while q:
                x, y = q.popleft()
                comp.append(y * w + x)
                r, g, b = px[x, y][0], px[x, y][1], px[x, y][2]
                chroma += max(r, g, b) - min(r, g, b)
                if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                    edge = True
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if not seen[j] and is_background(px[nx, ny]):
                            seen[j] = 1
                            q.append((nx, ny))
            if edge or len(comp) < min_area:
                continue
            if chroma / float(len(comp)) > max_chroma:
                continue
            for j in comp:
                drop[j] = 1
            removed += len(comp)
    if not removed:
        return cell, 0
    out = cell.copy()
    opx = out.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            if drop[row + x]:
                opx[x, y] = (0, 0, 0, 0)
    return out, removed


def content_bbox(img: Image.Image):
    """Границы непрозрачного содержимого, либо None."""
    return img.getchannel("A").getbbox()


def drop_specks(cell: Image.Image, min_area: int) -> tuple[Image.Image, int]:
    """Убирает мелкие несвязанные кляксы - остатки мягкого края рамки ячейки.

    Почему нельзя «оставить только крупнейшую компоненту»: у heavy_legs_* вторая
    компонента на 1600-1900 px - это вторая нога, она не касается первой, и такое
    правило разрезало бы поножи пополам. Порог отбора компонент безопасный: мусор
    весит <= 8 px, настоящая вторая часть - больше 1600 px.

    Возвращает (картинка, сколько пикселей выброшено)."""
    w, h = cell.size
    px = cell.load()
    seen = bytearray(w * h)
    drop = bytearray(w * h)
    removed = 0
    for sx in range(w):
        for sy in range(h):
            i = sy * w + sx
            if seen[i] or px[sx, sy][3] == 0:
                continue
            q = deque([(sx, sy)])
            seen[i] = 1
            comp = []
            while q:
                x, y = q.popleft()
                comp.append(y * w + x)
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if not seen[j] and px[nx, ny][3] > 0:
                            seen[j] = 1
                            q.append((nx, ny))
            if len(comp) < min_area:
                for j in comp:
                    drop[j] = 1
                removed += len(comp)
    if not removed:
        return cell, 0
    out = cell.copy()
    opx = out.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            if drop[row + x]:
                opx[x, y] = (0, 0, 0, 0)
    return out, removed


def content_box(cell: Image.Image, bbox, pad: int) -> tuple[int, int, int, int]:
    """Бокс предмета = содержимое + маленький прозрачный запас, вписано в ячейку.
    Обрезки по содержимому нет вообще - это и есть причина, почему предмет
    не влезает в квадрат 80x80 (см. main())."""
    w, h = cell.size
    l, t, r_, b = bbox
    return (max(0, l - pad), max(0, t - pad),
            min(w, r_ + pad), min(h, b + pad))


def fit_resize(img: Image.Image, longest: int) -> Image.Image:
    """Масштаб так, чтобы длинная сторона стала longest, пропорции сохранены."""
    w, h = img.size
    scale = float(longest) / float(max(w, h))
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    return resize_premultiplied(img, (nw, nh))


def resize_premultiplied(img: Image.Image, size) -> Image.Image:
    """Уменьшение с премультипликацией: иначе по краям темный ободок от
    прозрачных (0,0,0) пикселей исходника."""
    r, g, b, a = img.split()
    out = Image.merge("RGBA", (_mul(r, a), _mul(g, a), _mul(b, a), a))
    out = out.resize(size, Image.LANCZOS)
    r, g, b, a = out.split()
    return Image.merge("RGBA", (_div(r, a), _div(g, a), _div(b, a), a))


def _mul(ch: Image.Image, a: Image.Image) -> Image.Image:
    out = Image.new("L", ch.size)
    op, oa = out.load(), a.load()
    p = ch.load()
    for y in range(ch.size[1]):
        for x in range(ch.size[0]):
            av = oa[x, y]
            op[x, y] = (p[x, y] * av + 127) // 255
    return out


def _div(ch: Image.Image, a: Image.Image) -> Image.Image:
    out = Image.new("L", ch.size)
    op, oa = out.load(), a.load()
    p = ch.load()
    for y in range(ch.size[1]):
        for x in range(ch.size[0]):
            av = oa[x, y]
            op[x, y] = min(255, (p[x, y] * 255 + av // 2) // av) if av else 0
    return out


def cut_all() -> list[dict]:
    """Режет все ячейки один раз и держит готовые картинки в памяти (108 картинок
    по 80 px - копейки), чтобы не пересчитывать трижды для записи и листа."""
    src = Image.open(SOURCE)
    if src.mode != "RGBA":
        src = src.convert("RGBA")
    records = []

    for set_name, _, rows in BLOCKS:
        for qi in range(4):
            y0 = rows[qi] + CELL_INSET
            y1 = rows[qi + 1] - CELL_INSET
            for ci in range(len(SLOTS)):
                x0 = COL_X[ci] + CELL_INSET
                x1 = COL_X[ci + 1] - CELL_INSET
                cell = strip_background(src.crop((x0, y0, x1, y1)))
                cell, dropped = drop_specks(cell, MIN_COMPONENT)
                cell, holes = clear_enclosed_holes(cell, MIN_HOLE_AREA, MAX_HOLE_CHROMA)
                bbox = content_bbox(cell)
                name = "%s_%s_%s" % (set_name, SLOTS[ci], QUALITIES[qi])
                if bbox is None:
                    records.append({"name": name, "img": None, "empty": True})
                    continue
                box = content_box(cell, bbox, PAD)
                item = fit_resize(cell.crop(box), GAME_SIZE)
                records.append({
                    "name": name,
                    "img": item,
                    "cell": (x0, y0, x1, y1),
                    "box": box,
                    "cell_size": cell.size,
                    "raw": (bbox[2] - bbox[0], bbox[3] - bbox[1]),
                    "size": item.size,
                    "dropped": dropped,
                    "holes": holes,
                    "empty": False,
                })
    return records


def write(records: list[dict]) -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    written = 0
    for rec in records:
        if rec["img"] is None:
            continue
        rec["img"].save(os.path.join(OUT_DIR, rec["name"] + ".png"))
        written += 1
    return written


def make_sheet(records: list[dict], columns: int = 9, cell_size: int = 110) -> None:
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_size, rows * (cell_size + 16)), (24, 26, 32, 255))
    d = ImageDraw.Draw(sheet)
    for y in range(0, sheet.size[1], 8):          # шахматка, видна прозрачность
        for x in range(0, sheet.size[0], 8):
            if ((x // 8) + (y // 8)) % 2 == 0:
                d.rectangle([x, y, x + 7, y + 7], fill=(48, 50, 58, 255))
    for i, rec in enumerate(records):
        px_ = (i % columns) * cell_size
        py_ = (i // columns) * (cell_size + 16)
        d.rectangle([px_, py_, px_ + cell_size - 1, py_ + cell_size - 1],
                    outline=(70, 74, 88, 255))
        if rec["img"] is not None:
            k = (cell_size - 12) / float(max(rec["img"].size))
            shown = rec["img"].resize(
                (max(1, int(rec["img"].size[0] * k)), max(1, int(rec["img"].size[1] * k))),
                Image.LANCZOS)
            sheet.alpha_composite(
                shown, (px_ + (cell_size - shown.size[0]) // 2,
                        py_ + (cell_size - shown.size[1]) // 2))
        d.text((px_ + 3, py_ + cell_size + 2), rec["name"], fill=(225, 228, 235, 255))
    sheet.save(SHEET)


def main() -> int:
    # консоль Windows по умолчанию cp866 и калечит кириллицу
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    ap = argparse.ArgumentParser(description="Нарезка атласа брони ChatGPTArmor1.png")
    ap.add_argument("--report", action="store_true", help="только отчёт, файлы не писать")
    ap.add_argument("--sheet", action="store_true", help="дополнительно собрать contact sheet")
    args = ap.parse_args()

    if not os.path.exists(SOURCE):
        print("НЕТ ИСТОЧНИКА: %s" % SOURCE)
        return 1

    records = cut_all()
    print("АТЛАС: %dx%d" % Image.open(SOURCE).size)
    print("ЯЧЕЕК: %d (ожидалось %d)" % (len(records), EXPECTED_CELLS))
    assert len(records) == EXPECTED_CELLS, "сетка дала неверное число ячеек"

    empty = [r["name"] for r in records if r["empty"]]
    print("ПУСТЫХ (фон съел всё): %d %s" % (len(empty), empty[:8]))
    if empty:
        return 1

    long_side = [r["size"][0] if r["size"][0] >= r["size"][1] else r["size"][1] for r in records]
    print("ДЛИННАЯ СТОРОНА: всегда %d px (макс найдено %d)" % (GAME_SIZE, max(long_side)))
    print("РАЗМЕРЫ: примеры %s" % ", ".join(
        "%dx%d" % r["size"] for r in records[:5]))

    dirty = [(r["name"], r["dropped"]) for r in records if r.get("dropped")]
    dirty.sort(key=lambda p: -p[1])
    print("МУСОР ОТ РАМКИ ВЫЧИЩЕН в %d ячейках, всего %d px; худшие: %s"
          % (len(dirty), sum(p[1] for p in dirty),
             ", ".join("%s=%dpx" % p for p in dirty[:6]) or "нет"))

    holed = [(r["name"], r["holes"]) for r in records if r.get("holes")]
    holed.sort(key=lambda p: -p[1])
    print("ДЫРКИ (внутри колец) ОЧИЩЕНЫ в %d ячейках, всего %d px; худшие: %s"
          % (len(holed), sum(p[1] for p in holed),
             ", ".join("%s=%dpx" % p for p in holed[:6]) or "нет"))

    if args.report:
        return 0

    n = write(records)
    print("ЗАПИСАНО: %d файлов в %s/ (имя {set}_{slot}_{quality}.png)"
          % (n, OUT_DIR.replace("\\", "/")))
    if args.sheet:
        make_sheet(records)
        print("CONTACT SHEET: %s" % SHEET.replace("\\", "/"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
