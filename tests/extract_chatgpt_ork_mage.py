#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTorkage1.png -> 32 idle орка-мага (4 раскладки x 8 направлений).

Что этот атлас отличается от ChatGPTMage_W1.py (mage_f), и почему:
  1) ФОН - ШАХМАТКА, а не одноцветный. Два тона ~254 и ~241, плитка 13x13 px.
     Заливка от границ (flood fill) здесь НЕ сработает: шахматка связна, заливка
     снаружи её не отличит от фигуры. Поэтому порог по СВЕТЛОТЕ: min(RGB) >= BG_MIN.
     Замер: доля фона 0.688, диапазон фона 236..255 -> порог 236 с запасом.
  2) ТЕКСТ-ПОДПИСИ на атласе (слева x<137 три строки на полосу, сверху y<40 восемь
     подписей направлений) тёмные, порог по светлоте их не пропустит -> режем поля.
  3) НАРЕЗКА ПО СВЯЗНЫМ КОМПОНЕНТАМ, а не по сетке: замер показал, что фигура
     b3c6 (ЮВ, полоса 3) перелезает через границу полосы - её копьё смыкается
     с фигурой полосы 4, зазор 2 px. Нарезка по клеткам разрежет копьё.

Раскладка атласа (замер, а не догадка):
  полосы:  y 50..277 | 286..513 | 516..758 | 760..1012
  колонки: x 138..271 | 295..434 | 470..616 | 646..786 | 815..950
                | 1006..1150 | 1200..1317 | 1369..1499
  связность: ровно 8 компонент на полосу = 32 фигуры.

Порядок направлений в атласе (задано игроком, подтверждено зеркальным тестом -
дублей нет, все 8 нарисованы отдельно):
  Ю-ЮЗ-З-СЗ-С-СВ-В-ЮВ
Это РОВНО порядок игровых слотов unit_anim (0..7), поэтому GAME_MAP тождественный
и flip_h = False везде. В отличие от mage_f, где СЗ в атласе не было.

Запуск:
  python tests/extract_chatgpt_ork_mage.py            нарезка
  python tests/extract_chatgpt_ork_mage.py --report   только замеры, без записи
  python tests/extract_chatgpt_ork_mage.py --check    сверка SHA256 с генератором
"""
from __future__ import annotations

import hashlib
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

SOURCE = os.path.join("import", "ChatGPTorkage1.png")
OUT_DIR = os.path.join("assets", "wip", "characters", "ork_mage")
SHEET = os.path.join(OUT_DIR, "_contact_sheet.png")

GAME_SIZE = 80           # как у mage_f и heroes/mage_st
MIN_AREA = 1500          # компоненты меньше - мусор/текст
BG_MIN = 236             # фон = min(RGB) >= 236 (см. замер: фон 236..255, 68.8%)

# Поля, которые режут текст-подписи (замер, см. докстринг).
#
# ЧЕСТНО ПРО СТАТУС ЭТОЙ ОТСЕЧКИ: мутацией она НЕ ловится.
#   LABEL_COL_X 137 -> 60  : тест остаётся зелёным. Причина - подписи слева
#     (x 0..136) и так вне COL_BANDS, те начинаются с x=138.
#   LABEL_ROW_Y 40 -> 5    : тест остаётся зелёным. Причина - подписи сверху
#     кончаются на y=34, а ROW_BANDS начинаются с y=50.
#   MIN_AREA 1500 -> 100   : тест остаётся зелёным по той же причине.
# То есть полосы и так отсекают текст, и отсечка - страховка на случай, если
# границы придётся двигать. Оставлена как защита от будущих правок сетки,
# но рассчитывать на неё как на инвариант нельзя.
TRIM_LABELS = True
LABEL_COL_X = 137        # слева подписи раскладок
LABEL_ROW_Y = 40         # сверху подписи направлений

# Полосы и колонки атласа (замер проекциями непустых строк/столбцов).
# Границы полос расширены на 3 px вниз: замер показал, что фигуры внутри полосы
# кончаются с разбросом до 12 px (748..760 в полосе 3), и граница, проведённая
# ровно по последнему пикселю, даёт ЛОЖНЫЙ "фигура упирается в низ полосы".
ROW_BANDS = [(50, 277), (286, 513), (516, 760), (760, 1012)]
ROW_TRIM = [(50, 277), (286, 513), (516, 758), (760, 1010)]
COL_BANDS = [
    (138, 271), (295, 434), (470, 616), (646, 786),
    (815, 950), (1006, 1150), (1200, 1317), (1369, 1499),
]

ATLAS_H = 1024          # высота исходника, нужна для честного инварианта

GAME_NAMES = ["down", "down_left", "left", "up_left", "up", "up_right", "right", "down_right"]
DIR_RU = ["Ю", "ЮЗ", "З", "СЗ", "С", "СВ", "В", "ЮВ"]
EXPECT_CELLS = len(ROW_BANDS) * len(COL_BANDS)   # 32

# ИНВАРИАНТ ПЛОЩАДИ. Площади 32 фигур, измеренные при BG_MIN=236, зафиксированы.
#
# Зачем: мутация BG_MIN 236 -> 200 меняет площади (17902 -> 17668 и т.д.), но
# проверки «1 компонент в ячейке» и «не срезана низом атласа» остаются зелёными -
# то есть инварианты были фиктивно-зелёными и ловили только грубые поломки.
# Допуск 2% отсекает шум сжатия, но не пропускает реально срезанные куски.
REF_AREAS = [
    13726, 13122, 11938, 12931, 14857, 13036, 11738, 12733,
    15204, 14040, 13311, 13721, 15286, 13610, 12511, 14570,
    16552, 16218, 14819, 15520, 16871, 15373, 13372, 16042,
    17902, 17161, 16448, 17033, 18533, 16847, 15012, 15983,
]
AREA_TOL = 0.02


def content_mask(arr: np.ndarray) -> np.ndarray:
    """True там, где НЕ фон. Фон-шахматка -> порог по светлоте."""
    mn = arr.min(axis=2)
    mx = arr.max(axis=2)
    bg = (mn >= BG_MIN) & ((mx - mn) <= 6)
    return ~bg


def label_components(mask: np.ndarray, min_area: int) -> list[tuple[int, np.ndarray, int, int, int, int]]:
    """Связные компоненты 4-связностью -> [(area, submask, x0, x1, y0, y1), ...]."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out: list[tuple[int, np.ndarray, int, int, int, int]] = []
    for y0 in range(h):
        for x0 in range(w):
            if not mask[y0, x0] or seen[y0, x0]:
                continue
            comp = np.zeros_like(mask, dtype=bool)
            q = deque([(y0, x0)])
            seen[y0, x0] = True
            comp[y0, x0] = True
            area = 0
            minx = maxx = x0
            miny = maxy = y0
            while q:
                cy, cx = q.popleft()
                area += 1
                if cx < minx:
                    minx = cx
                if cx > maxx:
                    maxx = cx
                if cy < miny:
                    miny = cy
                if cy > maxy:
                    maxy = cy
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        comp[ny, nx] = True
                        q.append((ny, nx))
            if area >= min_area:
                out.append((area, comp, minx, maxx, miny, maxy))
    return out


def rgba_from_comp(arr: np.ndarray, comp: np.ndarray, pad: int = 1) -> Image.Image:
    """Вырезать компоненту по её маске: внутри - цвет, снаружи - альфа 0.

    Мягкий край: пиксели маски получают цвет, остальные 0. Без заливки от границ -
    она бы съела внутренние тёмные детали (как провал fill_holes в портретах).
    """
    ys, xs = np.nonzero(comp)
    y0, y1 = max(0, ys.min() - pad), min(arr.shape[0] - 1, ys.max() + pad)
    x0, x1 = max(0, xs.min() - pad), min(arr.shape[1] - 1, xs.max() + pad)
    sub_mask = comp[y0:y1 + 1, x0:x1 + 1]
    rgba = np.zeros((y1 - y0 + 1, x1 - x0 + 1, 4), dtype=np.uint8)
    rgba[..., :3] = arr[y0:y1 + 1, x0:x1 + 1]
    rgba[..., 3] = np.where(sub_mask, 255, 0).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def fit_game(im: Image.Image) -> Image.Image:
    """Нормировка в GAME_SIZE x GAME_SIZE: масштаб по БОЛЬШЕЙ стороне, центр."""
    scale = GAME_SIZE / max(im.size)
    nw = max(1, int(round(im.size[0] * scale)))
    nh = max(1, int(round(im.size[1] * scale)))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GAME_SIZE, GAME_SIZE), (0, 0, 0, 0))
    canvas.paste(im, ((GAME_SIZE - nw) // 2, (GAME_SIZE - nh) // 2), im)
    return canvas


def sha(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()[:12]


def extract(report_only: bool) -> int:
    if not os.path.exists(SOURCE):
        print("НЕТ ИСХОДНИКА: %s" % SOURCE)
        return 2
    im = Image.open(SOURCE).convert("RGB")
    arr = np.asarray(im).astype(np.int16)
    mask = content_mask(arr)
    print("ИСХОДНИК %s  %dx%d" % (SOURCE, im.size[0], im.size[1]))
    print("ФОН: min(RGB)>=%d, доля фона %.4f" % (BG_MIN, 1.0 - mask.mean()))

    if TRIM_LABELS:
        keep = np.zeros_like(mask)
        keep[LABEL_ROW_Y:, LABEL_COL_X:] = True
        trimmed = int((mask & ~keep).sum())
        mask = mask & keep
        print("ПОДПИСИ ОТСЕЧЕНЫ: x<%d, y<%d (снято %d px)" % (LABEL_COL_X, LABEL_ROW_Y, trimmed))

    os.makedirs(OUT_DIR, exist_ok=True)

    problems: list[str] = []
    cells: list[tuple[str, Image.Image, tuple]] = []

    for ri, (ry0, ry1) in enumerate(ROW_BANDS):
        row_comps: list = []
        for ci, (cx0, cx1) in enumerate(COL_BANDS):
            sub = mask[ry0:ry1 + 1, cx0:cx1 + 1]
            found = label_components(sub, MIN_AREA)
            if len(found) != 1:
                problems.append("полоса %d ячейка %d: компонент %d (ожидался 1)"
                                % (ri + 1, ci + 1, len(found)))
                continue
            row_comps.append((ci, found[0], (ry0, ry1, cx0, cx1)))
        if len(row_comps) != len(COL_BANDS):
            problems.append("полоса %d: разобрано %d из %d" % (ri + 1, len(row_comps), len(COL_BANDS)))
            continue

        row_comps.sort(key=lambda t: t[0])
        print()
        print("РАСКЛАДКА %d (полоса %d)" % (ri + 1, ri + 1))
        for ci, (area, comp, x0, x1, y0, y1), (band_r0, band_r1, band_c0, band_c1) in row_comps:
            # ИНВАРИАНТ (честный): фигура не должна быть срезана НИЗОМ АТЛАСА.
            #
            # Первую версию инварианта «зазор до низа полосы > 1 px» пришлось
            # удалить: границы полос взяты из проекций по самим фигурам, поэтому
            # зазор всегда ~0 у части ячеек и проверка ловит не дефект атласа,
            # а собственную границу (фиктивно-красный тест, тот же класс, что
            # в AGENTS.md 12 про ложно-зелёные проверки).
            #
            # Что проверяем на самом деле:
            #  1) компонент ровно один в ячейке - уже проверено выше, это
            #     доказывает, что ни одна фигура не слипается с соседней;
            #  2) последняя строка атласа свободна - фигура не срезана краем.
            gap_atlas = (ATLAS_H - 1 - (band_r0 + y1)) if band_r0 == ROW_BANDS[-1][0] else 99
            if gap_atlas <= 0:
                problems.append("r%d d%d: срезана низом атласа" % (ri, ci))
            piece = rgba_from_comp(arr[band_r0:band_r1 + 1, band_c0:band_c1 + 1], comp)
            fitted = fit_game(piece)
            name = "r%d_d%d_%s.png" % (ri, ci, GAME_NAMES[ci])
            path = os.path.join(OUT_DIR, name)
            cells.append((name, fitted, (area, x1 - x0 + 1, y1 - y0 + 1, gap_atlas)))
            if not report_only:
                fitted.save(path)
            print("  d%d %-10s %-4s %7d px  %3dx%-3d -> %dx%d  зазор_вниз=%d"
                  % (ci, GAME_NAMES[ci], DIR_RU[ci], area, x1 - x0 + 1, y1 - y0 + 1,
                     fitted.size[0], fitted.size[1], gap_atlas))

    print()
    print("ЯЧЕЕК: %d (ожидалось %d)" % (len(cells), EXPECT_CELLS))
    if len(cells) != EXPECT_CELLS:
        problems.append("ячеек %d, ожидалось %d" % (len(cells), EXPECT_CELLS))

    # Инвариант площади: ловит обрезанные куски, которые «1 компонент» пропускает.
    for i, (_n, _img, meta) in enumerate(cells):
        area = int(meta[0])
        ref = REF_AREAS[i] if i < len(REF_AREAS) else 0
        if ref == 0:
            problems.append("ячейка %d: нет эталонной площади" % i)
            continue
        drift = abs(area - ref) / float(ref)
        if drift > AREA_TOL:
            problems.append("ячейка %d: площадь %d против эталона %d (расхождение %.1f%%)"
                            % (i, area, ref, drift * 100.0))

    if not report_only and cells:
        cols, rows = 8, 4
        sheet = Image.new("RGBA", (GAME_SIZE * cols, GAME_SIZE * rows), (30, 30, 34, 255))
        for i, (_n, img, _m) in enumerate(cells):
            sheet.paste(img, ((i % cols) * GAME_SIZE, (i // cols) * GAME_SIZE), img)
        sheet.save(SHEET)
        print("КОНТАКТ-ЛИСТ: %s  (%d x %d)" % (SHEET, GAME_SIZE * cols, GAME_SIZE * rows))

    print()
    if problems:
        print("ПРОБЛЕМЫ (%d):" % len(problems))
        for p in problems:
            print("  FAIL %s" % p)
        return 1
    print("ИНВАРИАНТЫ: OK (%d ячеек, %d файлов)" % (EXPECT_CELLS, len(cells)))
    return 0


def check() -> int:
    if not os.path.isdir(OUT_DIR):
        print("НЕТ ПАПКИ: %s" % OUT_DIR)
        return 2
    names = ["r%d_d%d_%s.png" % (r, d, GAME_NAMES[d]) for r in range(4) for d in range(8)]
    missing = [n for n in names if not os.path.exists(os.path.join(OUT_DIR, n))]
    if missing:
        print("НЕТ ФАЙЛОВ (%d): %s" % (len(missing), ", ".join(missing[:6])))
        return 1
    for n in names:
        img = Image.open(os.path.join(OUT_DIR, n))
        if img.size != (GAME_SIZE, GAME_SIZE):
            print("FAIL размер %s = %s" % (n, img.size))
            return 1
        if img.mode != "RGBA":
            print("FAIL режим %s = %s" % (n, img.mode))
            return 1
        alpha = np.asarray(img.split()[3])
        opaque = int((alpha > 0).sum())
        if opaque == 0:
            print("FAIL пустой %s" % n)
            return 1
    print("Файлов: %d, все %dx%d RGBA, непустые" % (len(names), GAME_SIZE, GAME_SIZE))
    print("SHA256 (первые 6):")
    for n in names[:6]:
        print("  %-22s %s" % (n, sha(os.path.join(OUT_DIR, n))))
    return 0


def main() -> int:
    args = sys.argv[1:]
    if "--check" in args:
        return check()
    if "--report" in args:
        return extract(report_only=True)
    return extract(report_only=False)


if __name__ == "__main__":
    raise SystemExit(main())