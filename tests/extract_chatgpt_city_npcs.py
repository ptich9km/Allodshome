#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка городских NPC: друид-маг, человек-маг, человек-воин, орк-воин.

Атласы 4 ряда (тiers t0..t3) x 8 колонок (направления), фон — та же
шахматка, что у ChatGPTMagic2 (chroma-маска).

НАРЕЗКА ПО КОМПОНЕНТАМ СВЯЗНОСТИ (как magic2), а не по фиксированной
сетке: колонки в атласе неравномерны, фикс-сетка зарезала руки/ноги.

КОСЯК ИИ: колонка 6 (1-й индекс) нарисована как В, а должна быть З.
Лечится зеркальным отражением (flip_h), как у ork_mage_a52.

Порядок колонок в атласе (по визуальному замеру игрока):
  0 Ю | 1 ЮВ | 2 В | 3 СВ | 4 С | 5 СЗ | 6 В->З(flip) | 7 ЮЗ

Порядок файлов игры (unit_anim, dirs=8):
  001 Ю | 002 ЮЗ | 003 З | 004 СЗ | 005 С | 006 СВ | 007 В | 008 ЮВ

Выход: assets/units/<set>/t{0..3}/sprites-00{1..8}.png  (52x64)

Запуск:
    python tests/extract_chatgpt_city_npcs.py --report
    python tests/extract_chatgpt_city_npcs.py
    python tests/extract_chatgpt_city_npcs.py --sheet
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SETS = [
    ("ChatGPTDruidMage1.png", "city_druid_mage"),
    ("ChatGPTDruidWarrior1.png", "city_druid_warrior"),
    ("ChatGPTHumanMage1.png", "city_human_mage"),
    ("ChatGPTHumanWarrior1.png", "city_human_warrior"),
    ("ChatGPTNecrMage1.png", "city_necro_mage"),
    ("ChatGPTNecrWarrior1.png", "city_necro_warrior"),
    ("ChatGPTOrkMage1.png", "city_ork_mage"),
    ("ChatGPTOrkWarrior1.png", "city_ork_warrior"),
]

OUT_W, OUT_H = 52, 64
FEET_PAD = 2

BG_CHROMA = 35.0
BG_VAL = 150.0
# Детектор по фазе сетки (см. background_mask). Замер на 8 атласах: клетка
# шахматки 12x12 px, два уровня ~254 и ~225..236, между клетками 1 px
# мягкого перехода 241..250.
BG_CELL_DEFAULT = 12
BG_LEVEL_TOL = 10
BG_CHROMA_TOL = 14
BG_SOFT_PAD = 2
MIN_AREA = 800
CLOSE_R = 2
PAD = 4

# atlas col -> (game_dir, flip)
ATLAS_TO_GAME = [
    (0, False),  # atlas 0 Ю    -> game 0 Ю
    (7, False),  # atlas 1 ЮВ   -> game 7 ЮВ
    (2, False),  # atlas 2 В    -> game 6 В
    (5, False),  # atlas 3 СВ   -> game 5 СВ
    (4, False),  # atlas 4 С    -> game 4 С
    (3, False),  # atlas 5 СЗ   -> game 3 СЗ
    (6, True),   # atlas 6 Вbug -> game 2 З (flip)
    (1, False),  # atlas 7 ЮЗ   -> game 1 ЮЗ
]

# Центры рядов (замер по content-маске атласов 1374x1145)
ROW_Y = (286, 572, 858)  # границы рядов 0|1, 1|2, 2|3

DB_PATH = os.path.join(ROOT, "assets", "units", "units_db.json")


def _flood_from_border(free: np.ndarray) -> np.ndarray:
    """Отметить все True-пиксели, связанные с краем (4-связность)."""
    h, w = free.shape
    seen = np.zeros_like(free)
    dq: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if free[y, x] and not seen[y, x]:
                seen[y, x] = True
                dq.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if free[y, x] and not seen[y, x]:
                seen[y, x] = True
                dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and free[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                dq.append((ny, nx))
    return seen


def _checker_levels(arr: np.ndarray) -> tuple:
    """Период клетки и два уровня яркости шахматки, снятые с чистого угла.

    Шахматка - это РЕГУЛЯРНАЯ СЕТКА. Замер на всех 8 атласах: клетка 12x12 px,
    уровни ~254 и ~225..236, между клетками 1 px мягкого перехода (241..250).
    """
    lum = arr.max(axis=2).astype(np.int32)
    corner = lum[:24, :24]
    vals, counts = np.unique(corner, return_counts=True)
    order = np.argsort(-counts)
    bright = int(vals[order[0]])
    dark = int(vals[order[1]]) if len(vals) > 1 else bright - 20
    if dark > bright:
        bright, dark = dark, bright
    return BG_CELL_DEFAULT, bright, dark


def background_mask(arr: np.ndarray) -> np.ndarray:
    """Маска фона, True = пиксель СЮЖЕТА.

    Фон = ОБЪЕДИНЕНИЕ двух независимых детекторов. Ни один из них поодиночке
    не работает, но у них разные слепые зоны, и объединение закрывает обе:

      1) ЗАЛИВКА от края ("выглядит как фон" И связано с границей картинки).
         Даёт полное покрытие, но пропускает КАРМАНЫ шахматки: между плащом и
         посохом, между ногами, между рукой и торсом они полностью окружены
         фигурой и до края не достаются.

      2) ДЕТЕКТОР ПО ФАЗЕ сетки ("значение совпадает с клеткой шахматки,
         соответствующей моей фазе"). Покрывает карманы, потому что у фона
         есть строгая позиционная структура, которой у серебра нет.
         Замер: серебро он не ест ВООБЩЕ (0 px).

    Раньше карманы снимались по РАЗМЕРУ. Это было неверно: карман между
    ногами неотличим от серебра по размеру, и свип порогов 300/200/150/80
    показал, что ниже 150 серебро режется тем сильнее, чем выше тир
    (t3 минус 1296 светлых пикселей), а выше 300 остаются белые пятна.
    Объединение обходится без порога по размеру вообще.
    """
    lum = arr.max(axis=2).astype(np.int32)
    chroma = lum - arr.min(axis=2).astype(np.int32)

    # 1) заливка от края
    looks_like_bg = (chroma < BG_CHROMA) & (lum > BG_VAL)
    bg = _flood_from_border(looks_like_bg)

    # 2) детектор по фазе сетки + дочистка мягкого перехода между клетками
    cell, bright, dark = _checker_levels(arr)
    h, w = lum.shape
    yy, xx = np.mgrid[0:h, 0:w]
    phase = ((xx // cell) + (yy // cell)) % 2
    expected = np.where(phase == 0, bright, dark).astype(np.int32)
    phase_bg = (np.abs(lum - expected) <= BG_LEVEL_TOL) & (chroma <= BG_CHROMA_TOL)
    # Переход между клетками (1 px, 241..250) не совпадает ни с одним уровнем.
    # Он нейтральный и светлый - ровно как фон, - и лежит вплотную к клеткам,
    # поэтому добираем его морфиологическим расширением.
    soft = (chroma <= BG_CHROMA_TOL) & (lum >= min(bright, dark) - 6)
    phase_bg |= soft & dilate(phase_bg, BG_SOFT_PAD)

    return ~(bg | phase_bg)


def _components(mask: np.ndarray) -> list:
    """Список связных компонент (4-связность) как списки (y, x)."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = []
    ys, xs = np.where(mask)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        stack = [(int(y0), int(x0))]
        seen[y0, x0] = True
        comp = []
        while stack:
            y, x = stack.pop()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        out.append(comp)
    return out


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
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
            shifted[y0:y1, x0:x1] = mask[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
            out |= shifted
    return out


def _erode(mask: np.ndarray, radius: int) -> np.ndarray:
    """Эрозия: оставить пиксели, у которых все соседи в радиусе тоже в маске."""
    if radius <= 0:
        return mask.copy()
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx == 0 and dy == 0:
                continue
            if dx * dx + dy * dy > radius * radius:
                continue
            shifted = np.zeros_like(mask)
            y0, y1 = max(0, dy), min(h, h + dy)
            x0, x1 = max(0, dx), min(w, w + dx)
            shifted[y0:y1, x0:x1] = mask[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
            out &= shifted
    return out


def _drop_small(mask: np.ndarray, min_area: int) -> np.ndarray:
    """Оставить только крупные связные компоненты (тело персонажа)."""
    h, w = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    out = mask.copy()
    ys, xs = np.where(mask)
    for y0, x0 in zip(ys, xs):
        if visited[y0, x0]:
            continue
        stack = [(int(y0), int(x0))]
        visited[y0, x0] = True
        comp = []
        while stack:
            y, x = stack.pop()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1),
                           (1, 1), (-1, -1), (1, -1), (-1, 1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    stack.append((ny, nx))
        if len(comp) < min_area:
            for y, x in comp:
                out[y, x] = False
    return out


def label_comps(mask: np.ndarray, min_area: int) -> list[dict]:
    h, w = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    comps: list[dict] = []
    ys, xs = np.where(mask)
    for y0, x0 in zip(ys, xs):
        if visited[y0, x0]:
            continue
        q: deque[tuple[int, int]] = deque([(int(y0), int(x0))])
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


def fit_game(im: Image.Image, flip: bool) -> Image.Image:
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    w, h = im.size
    max_h = OUT_H - FEET_PAD
    scale = min(OUT_W / w, max_h / h)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))

    # Правильный порядок: premultiply -> усреднение -> unpremultiply.
    #
    # Две ошибки были в старом коде, обе видны игроку на спрайте:
    #
    # 1) NEAREST на альфе. Кроп ~143x252 уходит в 35x62, по X это примерно
    #    4-кратное сжатие, и NEAREST выбрасывал 3 пикселя из 4. Тонкая
    #    светлая деталь (блеск стали, цепь) исчезала целиком — «грудь в дырявую».
    #    BOX усредняет по площади, т.е. это доля покрытия.
    #
    # 2) NEAREST на цвете. У тонкого посоха выходной пиксель брал цвет
    #    СОСЕДНЕГО фонового пикселя, и рядом с посохом и рукой появлялось
    #    белое пятно шахматки (RGB 243,243,243, хрома 1). Поэтому цвет
    #    усредняем ПО МАСКЕ: в premultiply фона вклад = 0, поэтому шахматка
    #    физически не может попасть в смесь (среднее по покрытым пикселям).
    src_a = np.asarray(im.getchannel("A"), dtype=np.float32) / 255.0
    src_rgb = np.asarray(im.convert("RGB"), dtype=np.float32)
    prem = src_rgb * src_a[:, :, None]

    a_small = np.asarray(
        Image.fromarray((src_a * 255).astype(np.uint8), "L").resize(
            (nw, nh), Image.Resampling.BOX), dtype=np.float32) / 255.0
    prem_small = np.asarray(
        Image.fromarray(prem.astype(np.uint8), "RGB").resize(
            (nw, nh), Image.Resampling.BOX), dtype=np.float32)

    # Unpremultiply: где покрытия нет - цвет не имеет значения (альфа 0).
    denom = np.maximum(a_small, 1e-4)[:, :, None]
    rgb_small = np.clip(prem_small / denom, 0, 255)

    # Остаточная дымка от размытой шахматки по краю убирается порогом.
    # 64/255 ~ 25% покрытия: ниже этого пиксель всё равно не различим.
    a_small = np.where(a_small < 0.25, 0.0, np.minimum(1.0, a_small * 1.35))

    out = Image.fromarray(
        np.dstack([rgb_small.round().astype(np.uint8),
                   (a_small * 255).round().astype(np.uint8)]), "RGBA")

    canvas = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
    ox = (OUT_W - nw) // 2
    oy = OUT_H - FEET_PAD - nh
    canvas.paste(out, (ox, max(0, oy)), out)
    return canvas


def patch_units_db(entries: list[dict]) -> int:
    with open(DB_PATH, encoding="utf-8") as f:
        db = json.load(f)
    for e in entries:
        db[e["key"]] = e["data"]
    with open(DB_PATH, "w", encoding="utf-8") as f:
        json.dump(db, f, ensure_ascii=False, indent=1)
        f.write("\n")
    return len(entries)


def make_db_entry(set_name: str, tier: int, desc: str) -> dict:
    return {
        "desc": "%s t%d" % (desc, tier),
        "folder": "%s/t%d" % (set_name, tier),
        "prefix": "sprites",
        "frames": 8,
        "dirs": 8,
        "move": 1,
        "move_begin": 0,
        "attack": 0,
        "dying": 0,
        "decay": 0,
        "cast": 0,
        "idle": 0,
        "idle_phases": 0,
        "move_f": [0],
        "move_t": [2],
        "attack_f": [],
        "attack_t": [],
        "die_f": [],
        "dying_t": [],
        "w": OUT_W,
        "h": OUT_H,
        "cx": OUT_W // 2,
        "cy": OUT_H - FEET_PAD,
        "tile": None,
        "projectile": -1,
        "palette": 0,
        "ids": [],
        "picture": None,
        "blocks": 1,
        "expected_frames": 8,
        "sel_box": [14, 10, 38, OUT_H - FEET_PAD],
        "attack_delay": 4,
        "info_picture": None,
        "sound": [],
        "resist": {"fire": 0, "water": 0, "air": 0, "earth": 0, "astral": 0},
        "tile_size": 1,
        "z": 0,
        "flip": 0,
        "bone": 0,
        "shoot_delay": 8,
        "shoot_offset": [],
    }


DESCS = {
    "city_druid_mage": "Друид-маг города",
    "city_druid_warrior": "Друид-воин города",
    "city_human_mage": "Человек-маг города",
    "city_human_warrior": "Человек-воин города",
    "city_necro_mage": "Пожинатель-маг города",
    "city_necro_warrior": "Пожинатель-воин города",
    "city_ork_mage": "Орк-маг города",
    "city_ork_warrior": "Орк-воин города",
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--no-db", action="store_true")
    # 10.10 этап 1: доводим по одному тиру, начиная с самого дешёвого по металлу
    # (t0). Замер: потери серебра растут с тиром, t0 минус 196 px против
    # t3 минус 1296. Тир задаётся списком, чтобы один прогон трогал только
    # нужные кадры и откат оставался дешёвым.
    ap.add_argument("--tiers", default="0,1,2,3",
                    help="какие тиры нарезать, например --tiers 0")
    args = ap.parse_args()
    tiers = [int(t) for t in args.tiers.split(",") if t.strip() != ""]
    for t in tiers:
        if t not in (0, 1, 2, 3):
            print("FAIL: тир должен быть 0..3, получено %r" % t)
            return 2

    db_entries: list[dict] = []
    written = 0
    missing = []

    for src_name, set_name in SETS:
        src_path = os.path.join(ROOT, "import", src_name)
        if not os.path.isfile(src_path):
            print("FAIL: нет %s" % src_path)
            missing.append(src_name)
            continue
        src = Image.open(src_path).convert("RGB")
        arr = np.array(src)
        content = background_mask(arr)
        obj = dilate(content, CLOSE_R)
        print("%s %dx%d content=%.1f%%" % (src_name, arr.shape[1], arr.shape[0],
                                           content.mean() * 100))

        # Глобальные компоненты: ноги t0 упирались в границу ряда y=286,
        # и фикс-разбивка по ROW_Y срезала их. Ряд — по cy компонента.
        all_comps = label_comps(obj, MIN_AREA)
        print("  total comps: %d" % len(all_comps))
        rows: list[list[dict]] = [[] for _ in range(4)]
        for c in all_comps:
            cy = (c["y0"] + c["y1"]) // 2
            if cy < ROW_Y[0]:
                rows[0].append(c)
            elif cy < ROW_Y[1]:
                rows[1].append(c)
            elif cy < ROW_Y[2]:
                rows[2].append(c)
            else:
                rows[3].append(c)
        for tier in tiers:
            comps = rows[tier]
            comps.sort(key=lambda c: c["x0"])
            print("  t%d: %d comps x0=%s" % (tier, len(comps),
                                            [c["x0"] for c in comps]))
            if len(comps) != 8:
                print("  WARN t%d: ожидалось 8, получено %d" % (tier, len(comps)))
            out_dir = os.path.join(ROOT, "assets", "units", set_name, "t%d" % tier)
            if not args.report:
                os.makedirs(out_dir, exist_ok=True)
            for i, c in enumerate(comps[:8]):
                gdir, flip = ATLAS_TO_GAME[i]
                # Кроп по глобальным координатам без привязки к границе ряда
                gy0 = max(0, c["y0"] - PAD)
                gy1 = min(arr.shape[0], c["y1"] + PAD)
                gx0 = max(0, c["x0"] - PAD)
                gx1 = min(arr.shape[1], c["x1"] + PAD)
                crop = arr[gy0:gy1, gx0:gx1].copy()
                local = content[gy0:gy1, gx0:gx1].copy()
                local = _drop_small(local, 150)
                # Эрозия альфы на 1 px: срезает полутона антиалиаса, которые
                # ловят светлую шахматку и дают белые точки по контуру.
                local = _erode(local, 1)
                # Дополнительно: почти-белые пиксели на краю контента → прозрачные
                # (остатки шахматки, прошедшие chroma-фильтр).
                rgb_f = crop.astype(np.float32)
                near_white = (rgb_f.min(axis=2) > 200) & (rgb_f.max(axis=2) - rgb_f.min(axis=2) < 20)
                # Только граничные (есть прозрачный сосед) — не трогаем белые детали внутри
                padded = np.pad(local, 1, constant_values=False)
                edge = local & ~(padded[1:-1, 1:-1] & padded[:-2, 1:-1] & padded[2:, 1:-1]
                                 & padded[1:-1, :-2] & padded[1:-1, 2:])
                local = local & ~(edge & near_white)
                a = np.where(local, 255, 0).astype(np.uint8)
                rgba = np.dstack([crop, a])
                im = Image.fromarray(rgba, "RGBA")
                out = fit_game(im, flip)
                fn = os.path.join(out_dir, "sprites-%03d.png" % (gdir + 1))
                if not args.report:
                    out.save(fn, "PNG")
                written += 1
            if not args.no_db and not args.report:
                db_entries.append({
                    "key": "%s/t%d" % (set_name, tier),
                    "data": make_db_entry(set_name, tier, DESCS.get(set_name, set_name)),
                })
            print("  %s/t%d OK (%d comps)" % (set_name, tier, min(len(comps), 8)))

    if db_entries and not args.report and not args.no_db:
        n = patch_units_db(db_entries)
        print("units_db.json: +%d записей" % n)

    if args.sheet or not args.report:
        _write_sheet()

    print("\n==== REPORT ====")
    print("written=%d missing=%d" % (written, len(missing)))
    if missing:
        print(missing[:12])
    expected = len(SETS) * len(tiers) * 8
    ok = written == expected and not missing
    print("RESULT: %s (%d/%d)" % ("OK" if ok else "GAPS", written, expected))
    return 0 if ok else 2


def _write_sheet() -> None:
    cell = max(OUT_W, OUT_H) + 8
    sheet = Image.new("RGBA", (8 * cell + 120, len(SETS) * (cell + 8) + 40), (28, 26, 30, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 4), "City NPCs 52x64 — t0..t3 x 8 dirs (game order, col6=flip З)",
              fill=(220, 220, 220, 255))
    y_base = 20
    for si, (src_name, set_name) in enumerate(SETS):
        y_set = y_base + si * (cell + 8)
        draw.text((8, y_set + cell // 2), set_name[:14], fill=(180, 180, 180, 255))
        for gdir in range(8):
            fn = os.path.join(ROOT, "assets", "units", set_name,
                              "t0", "sprites-%03d.png" % (gdir + 1))
            if os.path.isfile(fn):
                ic = Image.open(fn).convert("RGBA")
                sheet.paste(ic, (100 + gdir * cell, y_set), ic)
    sheet_path = os.path.join(ROOT, "assets", "units", "_city_npcs_sheet.png")
    os.makedirs(os.path.dirname(sheet_path), exist_ok=True)
    sheet.save(sheet_path)
    print("SHEET %s" % sheet_path)


if __name__ == "__main__":
    sys.exit(main())
