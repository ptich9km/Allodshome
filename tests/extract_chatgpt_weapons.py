#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка атласа оружия ChatGPTWeapons1.png в отдельные текстуры.

Вход:  import/ChatGPTWeapons1.png (1312x1199, RGBA)
Выход: assets/items/base_w/{type}_{quality}.png   (15 типов x 4 качества = 60)

Чем этот пайплайн отличается от брони (assets/items/base) - и это не деталь:

1. Фон у оружия УЖЕ удалён: файл RGBA, у предметов alpha 240..255. У брони
   был RGB с запечённой шахматкой. Заливки фона здесь не нужно.
2. Предметы режутся НЕ по сетке ячеек, а как связные компоненты внутри
   панели. Причина измерена, а не выбрана: головки топоров физически
   ПЕРЕСЕКАЮТ вертикальные разделители и заходят в соседнюю ячейку
   (в панели топоров содержимое ячейки 0 тянется с x=1 до x=92 при ширине
   ячейки 79). Резать по сетке - значит отрезать кусок головки.
3. Разделители и рамки непрозрачны (alpha 200..250) и прилипают к предметам,
   растягивая bbox до краёв полосы. Отличить их по яркости или по цвету
   НЕЛЬЗЯ: разделитель (20,26,33) и тёмный клинок дешёвого кинжала
   (max 9..16) перекрываются. Отличаются они структурой: разделитель -
   узкий (1..3 px) длинный изолированный столбец, а лезвие меча хоть и
   длинное, но шириной 10..20 px и соседние столбцы заполнены.
4. Рамка панели у левого края (арбалет, щит) шириной 17-18 px - узкой
   она не считается, зато касается и верха и низа полосы, а предметы
   никогда не касаются обеих границ сразу.

Проверка-инвариант: в каждой из 15 панелей должно быть ровно 4 компоненты.
Без неё шаг молча отдаёт 61 или 59 файлов вместо 60.

Запуск:
    python tests/extract_chatgpt_weapons.py            # нарезать в base_w
    python tests/extract_chatgpt_weapons.py --report   # только отчёт
    python tests/extract_chatgpt_weapons.py --sheet    # + контактный лист
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import deque

from PIL import Image, ImageDraw

SOURCE = os.path.join("import", "ChatGPTWeapons1.png")
OUT_DIR = os.path.join("assets", "items", "base_w")
SHEET = os.path.join("assets", "items", "base_w", "_contact_sheet.png")

GAME_SIZE = 80          # длинная сторона готовой текстуры
# Порог непрозрачности. Предмет alpha 240..255, дымка подложки 6..31,
# разделители 113..151.
#
# Порог НЕ 200, хотя сначала был: у арбалета ложе и лук соединены ТОНКОЙ
# тетивой с alpha 24..199, и при 200 она срезалась - предмет распадался на две
# части, правая половина отбрасывалась как «не 4 компоненты», и в игру уходил
# арбалет без тетивы. Порог сверху поставить нельзя: хвост тетивы (24..31)
# перекрывается с дымкой подложки (6..31).
# Граница подобрана замером по инварианту 15x4: 200/128/100 дают ровно 4
# компоненты в каждой из 15 панелей, 64 уже ломает (панель топоров даёт 3).
KEEP_ALPHA = 100
MIN_AREA = 500          # компонент крупнее - «тело» предмета
ATTACH_MIN = 8          # мельче этого - пыль от сглаживания
ATTACH_DIST = 12        # на столько px мелкая часть присоединяется к предмету
LINE_FILL = 0.70        # столбец заполнен на 70%+ высоты полосы = линия
PAD = 1                 # прозрачный запас вокруг содержимого

# 15 типов оружия, слева направо по панелям. Русские названия - как на атласе.
TYPES = [
    [("dagger", "Кинжал"),
     ("sword", "Одноручный меч"),
     ("saber", "Сабля"),
     ("greatsword", "Двуручный меч")],
    [("axe", "Топор одноручный"),
     ("axe_twohand", "Двуручный топор"),
     ("mace", "Булава одноручная"),
     ("mace_twohand", "Двуручная булава")],
    [("sledge", "Толот одноручный"),
     ("hammer", "Молот двуручный"),
     ("spear", "Копьё одноручное"),
     ("spear_twohand", "Двуручное копьё")],
    [("bow", "Лук"),
     ("crossbow", "Арбалет"),
     ("shield", "Щит")],
]
QUALITIES = ["cheap", "common", "good", "elite"]

# Границы панелей по X, измерены по широким тёмным промежуткам между панелями
# (x 323..336, 651..664, 979..994) и краям картинки (0..7, 1307..1311).
PANELS_X = {
    0: [(7, 323), (336, 651), (664, 979), (994, 1307)],
    1: [(7, 323), (336, 651), (664, 979), (994, 1307)],
    2: [(7, 323), (336, 651), (664, 979), (994, 1307)],
    3: [(7, 400), (405, 800), (832, 1307)],
}

# Полосы предметов по Y. Измерены по проекции содержимого, а не взяты из .md:
#   подписи качества кончаются на y=60/361/661/965,
#   сразу под ними горизонтальная линия разделителей (y=70/371/672,
#   307/265/525 ярких пикселей в строке) - её тоже надо пропустить,
#   предметы идут до y≈278/586/889/1179, ниже - нижняя рамка панели.
ITEM_BANDS = {
    0: (72, 284),
    1: (373, 586),
    2: (673, 890),
    3: (975, 1176),
}


def bbox_gap(a, b) -> int:
    """Расстояние между двумя прямоугольниками (0 - пересекаются/касаются)."""
    dx = max(0, max(a[0], b[0]) - min(a[2], b[2]))
    dy = max(0, max(a[1], b[1]) - min(a[3], b[3]))
    return max(dx, dy)


def union(a, b):
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def panel_items(px: Image.Image, x0: int, y0: int, x1: int, y1: int):
    """Возвращает [(area, bbox, mask_cells)] - предметы панели слева направо.

    Шаги: порог по alpha -> вычистка узких длинных столбцов-разделителей ->
    связные компоненты -> отбраковка рамок -> присоединение мелких деталей.

    Про мелкие детали: у арбалета наконечник тетивы - отдельная компонента
    всего в 39 px, и порог MIN_AREA его отбрасывал, из-за чего арбалет
    терял наконечник. Поэтому мелкие компоненты не выкидываются, а
    присоединяются к ближайшему «телу», если расстояние до него <= ATTACH_DIST:
    у соседнего предмета расстояние в 20+ px, а у своего - 0.
    """
    W = x1 - x0 + 1
    H = y1 - y0 + 1
    mask = [[px[x0 + x, y0 + y][3] >= KEEP_ALPHA for x in range(W)] for y in range(H)]

    # разделители: узкие длинные изолированные столбцы
    fill = [sum(1 for y in range(H) if mask[y][x]) for x in range(W)]
    th = LINE_FILL * H
    dead = set()
    for x in range(W):
        if fill[x] < th:
            continue
        if (x - 2 >= 0 and fill[x - 2] >= th) or (x + 2 < W and fill[x + 2] >= th):
            continue  # не изолирован - это часть предмета (лезвие), не линия
        dead.update(range(max(0, x - 1), min(W, x + 2)))
    for x in dead:
        for y in range(H):
            mask[y][x] = False

    seen = bytearray(W * H)
    comps = []
    for sx in range(W):
        for sy in range(H):
            i = sy * W + sx
            if seen[i] or not mask[sy][sx]:
                continue
            q = deque([(sx, sy)])
            seen[i] = 1
            cells = []
            bb = [sx, sy, sx, sy]
            while q:
                x, y = q.popleft()
                cells.append((x, y))
                bb[0] = min(bb[0], x)
                bb[1] = min(bb[1], y)
                bb[2] = max(bb[2], x)
                bb[3] = max(bb[3], y)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H:
                        j = ny * W + nx
                        if not seen[j] and mask[ny][nx]:
                            seen[j] = 1
                            q.append((nx, ny))
            comps.append((len(cells), tuple(bb), cells))

    mains = [[c[0], c[1], c[2]] for c in comps
             if c[0] >= MIN_AREA and not (c[1][1] <= 1 and c[1][3] >= H - 2)]
    small = [c for c in comps if ATTACH_MIN <= c[0] < MIN_AREA]
    if len(mains) != 4:
        return mains, []

    # присоединяем мелкие детали к ближайшему телу
    attached = 0
    for area, bb, cells in small:
        gaps = [bbox_gap(bb, m[1]) for m in mains]
        best = min(range(len(mains)), key=lambda i: gaps[i])
        if gaps[best] > ATTACH_DIST:
            continue
        m = mains[best]
        m[1] = union(m[1], bb)
        m[2] = m[2] + cells
        m[0] += area
        attached += 1
    for i, m in enumerate(mains):
        mains[i] = (m[0], m[1], m[2])
    mains.sort(key=lambda c: c[1][0])
    return mains, small


def cut_item(src: Image.Image, x0: int, y0: int, area: int, bb, cells) -> Image.Image:
    """Вырезает предмет: прозрачность = маска компоненты, цвет = исходный."""
    l, t, r, b = bb
    l = max(0, l - PAD)
    t = max(0, t - PAD)
    r = min(src.size[0], r + 1 + PAD)
    b = min(src.size[1], b + 1 + PAD)
    out = src.crop((x0 + l, y0 + t, x0 + r, y0 + b)).convert("RGBA")
    opx = out.load()
    ow, oh = out.size
    keep = bytearray(ow * oh)
    for (cx, cy) in cells:
        keep[(cy - t) * ow + (cx - l)] = 1
    for yy in range(oh):
        for xx in range(ow):
            if not keep[yy * ow + xx]:
                opx[xx, yy] = (0, 0, 0, 0)
    return out


def fit_resize(img: Image.Image, longest: int) -> Image.Image:
    w, h = img.size
    k = float(longest) / float(max(w, h))
    return img.resize((max(1, int(round(w * k))), max(1, int(round(h * k)))), Image.LANCZOS)


def cut_all():
    src = Image.open(SOURCE).convert("RGBA")
    px = src.load()
    records = []
    problems = []
    total_attached = 0
    for row, panels in enumerate(TYPES):
        y0, y1 = ITEM_BANDS[row]
        for p_i, panel in enumerate(panels):
            if p_i >= len(PANELS_X[row]):
                continue
            px0, px1 = PANELS_X[row][p_i]
            items, small = panel_items(px, px0, y0, px1, y1)
            if len(items) != 4:
                problems.append((row, panel[0], len(items)))
                continue
            total_attached += len(small)
            for c, (area, bb, cells) in enumerate(items):
                item = cut_item(src, px0, y0, area, bb, cells)
                item = fit_resize(item, GAME_SIZE)
                records.append({
                    "name": "%s_%s" % (panel[0], QUALITIES[c]),
                    "img": item, "area": area, "size": item.size,
                })
    return records, problems, total_attached


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Нарезка атласа оружия ChatGPTWeapons1.png")
    ap.add_argument("--report", action="store_true", help="только отчёт")
    ap.add_argument("--sheet", action="store_true", help="+ контактный лист")
    args = ap.parse_args()

    if not os.path.exists(SOURCE):
        print("НЕТ ИСТОЧНИКА: %s" % SOURCE)
        return 1

    records, problems, attached = cut_all()
    expected = sum(len(p) for p in TYPES) * 4
    print("АТЛАС: %dx%d" % Image.open(SOURCE).size)
    print("ПРЕДМЕТОВ: %d (ожидалось %d)" % (len(records), expected))
    if problems:
        print("ПАНЕЛИ, ГДЕ КОМПОНЕНТ НЕ 4 (инвариант нарушен):")
        for row, name, n in problems:
            print("   ряд %d %-18s компонент=%d" % (row, name, n))
        return 1

    print("ИНВАРИАНТ 15x4: выполнен")
    print("МЕЛКИХ ДЕТАЛЕЙ ПРИСОЕДИНЕНО К ПРЕДМЕТАМ: %d (наконечники тетивы и т.п.)" % attached)
    small = sorted(records, key=lambda r: r["area"])[:5]
    print("САМЫЕ МЕЛКИЕ ПРЕДМЕТЫ (защита от отрезанных кусков): %s"
          % ", ".join("%s=%dpx" % (r["name"], r["area"]) for r in small))
    print("РАЗМЕРЫ: примеры %s" % ", ".join("%dx%d" % r["size"] for r in records[:6]))

    if args.report:
        return 0

    os.makedirs(OUT_DIR, exist_ok=True)
    for r in records:
        r["img"].save(os.path.join(OUT_DIR, r["name"] + ".png"))
    print("ЗАПИСАНО: %d файлов в %s/ ({type}_{quality}.png, длинная сторона %d)"
          % (len(records), OUT_DIR.replace("\\", "/"), GAME_SIZE))
    if args.sheet:
        make_sheet(records)
        print("CONTACT SHEET: %s" % SHEET.replace("\\", "/"))
    return 0


def make_sheet(records, columns: int = 10, cell_size: int = 112) -> None:
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_size, rows * (cell_size + 16)), (24, 26, 32, 255))
    d = ImageDraw.Draw(sheet)
    for y in range(0, sheet.size[1], 8):
        for x in range(0, sheet.size[0], 8):
            if ((x // 8) + (y // 8)) % 2 == 0:
                d.rectangle([x, y, x + 7, y + 7], fill=(48, 50, 58, 255))
    for i, r in enumerate(records):
        cx = (i % columns) * cell_size
        cy = (i // columns) * (cell_size + 16)
        d.rectangle([cx, cy, cx + cell_size - 1, cy + cell_size - 1], outline=(70, 74, 88, 255))
        im = r["img"]
        k = (cell_size - 12) / float(max(im.size))
        shown = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), Image.LANCZOS)
        sheet.alpha_composite(shown, (cx + (cell_size - shown.size[0]) // 2,
                                      cy + (cell_size - shown.size[1]) // 2))
        d.text((cx + 4, cy + cell_size + 2), r["name"], fill=(225, 228, 235, 255))
    sheet.save(SHEET)


if __name__ == "__main__":
    sys.exit(main())
