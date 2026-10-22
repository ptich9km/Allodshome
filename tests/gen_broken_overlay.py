#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Иконка «сломано»: трещина поверх УЖЕ ОДОБРЕННОЙ иконки вещи.

ЗАЧЕМ: сломанные вещи (quality Broken/Broken Fine/Broken Rare) рисовались
заглушками tests/gen_broken_icons.py (удалён 22.10) — прямоугольник с
эллипсами «броня» и
треугольник «оружие», ОДНИ И ТЕ ЖЕ для всех 20 металлов. Игрок забраковал их
(22.10): «вместо того чтобы взять иконку имеющейся брони/оружия и написать
сломано». ИИ-генерация для этой задачи не нужна: сломанная вещь — это ТА ЖЕ
вещь, поэтому берётся её готовая иконка и на неё накладывается трещина.

ОТКУДА ИСТОЧНИК
    броня тела  — {group}/{metal}_heavy_chest_{tier}.png (+ base/heavy_chest_{tier});
    оружие      — {group}/{metal}_one_handed_sword_{tier}.png (+ base_w/...);
    одежда      — assets/professions/workshop/fabric.png (настоящей иконки
                  льняной одежды в базе нет).
    Путь резолвится glob-ом по УСТАНОВЛЕННЫМ файлам в assets/items/faction/
    и faction_w/, и ТИР качества НЕ хардкодится: один и тот же металл
    принадлежит своему тиру палитры (terbium — elite, steel — base/good), и
    привязка «metal -> tier» не переписывается, если палитра поменяется.
    Берётся общий для всех металлов индекс картинки — она одна и та же во всех
    четырёх качествах (отличается только раскраска).

ТРЕЩИНА РИСУЕТСЯ ПРОГРАММНО (PIL) и строится ОТ СИЛУЭТА:
    1. силуэт источника = alpha-маска;
    2. трещина идёт от кромки силуэта вглубь с ломанным сдвигом;
    3. точки трещины обязаны лежать НА непрозрачных пикселях — иначе линия
       уходила бы в пустоту и на 32×32 её не было бы видно вовсе;
    4. линия рисуется в увеличенном масштабе и уменьшается LANCZOS (тот же
       deliberate preprocessing pass, что в tests/gen_loot_icons_derived.py:
       линия шириной 1 px цифрами «в лоб» даёт рваную лесенку);
    5. тёмный контур по обеим сторонам + светлый блик ВНУТРИ: трещина должна
       читаться и на тёмном кобальте, и на светлой стали.

СОСТОЯНИЕ (22.10):
    - первый заход — тонкая трещина от кромки; игрок в игре не прочитал;
    - второй заход — жирные трещины/сколы (v0…v5) — тоже забракованы;
    - итог игрока: «просто рисуй красную пересекающую линию не сильно жирную,
      но заметную», одной линией. Поэтому трещина/сколы ВЫКЛЮЧЕНЫ
      (`crack=False`), а рисуется `draw_cross()`: одна красная линия по
      диагонали bbox силуэта с тёмной обводкой. Формы трещины на 32 px не
      разобрать, знак «перечёркнуто» — стандартный для сломанного предмета и
      читается сразу.

ЧТО РИСУЕТСЯ (`VARIANTS`):
    v7_red_line — одна красная линия по диагонали, length 1.00, width 3.0 px.

Скрипт по умолчанию НИЧЕГО не пишет в assets/: вариант и подписанный
контакт-лист кладутся в import/broken_overlay/. Плюс `_compare.png` —
ПОПАРНО «целая | сломанная» для шести вещей (тёмный кобальт, сталь,
серебро × броня/оружие), и `_compare_small.png` — то же, уменьшенное до 32 px
(размер дроп-иконки на земле и в складе), чтобы видеть, ЧИТАЕТСЯ ли линия
в мелком масштабе. Установка — только --install после одобрения игрока.

Запуск:
    python tests/gen_broken_overlay.py                     # вариант + листы
    python tests/gen_broken_overlay.py --report            # только отчёт
    python tests/gen_broken_overlay.py --variant v7_red_line --install
    python tests/gen_broken_overlay.py --check             # сверка установленного
"""

from __future__ import annotations

import argparse
import glob as globmod
import hashlib
import json
import math
import os
import random
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "import", "broken_overlay")
BROKEN_DIR = os.path.join(ROOT, "assets", "items", "broken")
LOOT_DIR = os.path.join(ROOT, "assets", "loot_icons")
PALETTE = os.path.join(ROOT, "assets", "items", "faction_palette.json")
FABRIC = os.path.join(ROOT, "assets", "professions", "workshop", "fabric.png")
WEAPON_LOOT = "one_handed_sword"
SHEET = os.path.join(
    ROOT, ".agents", "skills", "disciplines", "create-game-assets",
    "scripts", "build_preview_sheet.py",
)
SHEET_PATH = os.path.join(OUT_DIR, "_contact_sheet.png")

# Порядок = ItemDB._SMELTABLE (scripts/item_db.gd). Держать синхронно.
METALS = [
    "bronze", "iron", "steel", "gold", "argentum",
    "lutetium", "lanthanum", "terbium", "wolfram", "chromium",
    "cobalt", "titanium", "thorium", "uranium", "plutonium",
    "radium", "gallium", "yttrium", "promethium", "neodymium",
]

# Тир качества у картинки ОДИН на металл (bronze — cheap, iron — common,
# steel — good/base, terbium — elite): берётся первый найденный внутри группы
# металла из палитры. Сталь (is_base) лежит в базовых каталогах без префикса
# металла, у неё картинка одна и та же по всем качествам.
FACTION_GLOB = {
    "armor": "assets/items/{sub}/*/%(metal)s_heavy_chest_*.png",
    "weapon": "assets/items/{sub}/*/%(metal)s_" + WEAPON_LOOT + "_*.png",
}
BASE_GLOB = {
    "armor": "assets/items/base/heavy_chest_*.png",
    "weapon": "assets/items/base_w/" + WEAPON_LOOT + "_*.png",
}

## Красная перечёркивающая линия — стандартный знак «не годится» (как в
## инвентарях RPG). Игрок выбрал ОДНУ линию (22.10): из верхнего левого угла
## в нижний правый, чуть длиннее диагонали силуэта, чтобы край был виден.
## Толщина — в пикселях ИСТОЧНИКА (иконки 60-80 px), `width` 3.0 даёт на
## 32 px тёмную читаемую линию без «закрашенного» силуэта.
VARIANTS: dict[str, dict] = {
    "v7_red_line": {"lines": [1.00], "width": 3.0},
}

CROSS_COLOR = (214, 32, 28, 255)
LINE_REACH = 1.06         # линия длиннее диагонали силуэта — выходит за кромку
LINE_INSET = 0.06         # отступ начала от угла bbox, доля диагонали
LINE_SPREAD = 0.0         # наклон линии от угла bbox к углу (0 = точно по диагонали)
LINE_SHADE = 0.55          # затемнение иконки под линией (обводка под красным)

## Пары для сравнения в import/broken_overlay/_compare.png: (металл, вид) —
## три уровня «света» (тёмный кобальт, средняя сталь, светлое серебро) × броня и оружие.
COMPARE: list[tuple[str, str]] = [
    ("cobalt", "armor"), ("steel", "armor"), ("argentum", "armor"),
    ("cobalt", "weapon"), ("steel", "weapon"), ("argentum", "weapon"),
]
COMPARE_PATH = os.path.join(OUT_DIR, "_compare.png")
COMPARE_SMALL_PATH = os.path.join(OUT_DIR, "_compare_small.png")
SMALL_PX = 32            # размер дроп-иконки на земле и в ячейке склада

SUPERSAMPLE = 8          # линия рисуется в 8x и уменьшается LANCZOS
CRACK_DARK = (8, 6, 6, 245)
CRACK_LIGHT = (255, 252, 244, 250)
SEED = 2210              # детерминизм: одна и та же трещина при каждом прогоне


def faction_groups() -> dict[str, str]:
    """металл -> каталог в assets/items/faction[_w]/ по faction_palette.json."""
    with open(PALETTE, encoding="utf-8") as fh:
        data = json.load(fh)
    groups: dict[str, str] = {}
    for group_name, rec in (data.get("groups") or {}).items():
        for metal_rec in rec.get("metals", []):
            metal = str(metal_rec.get("metal", ""))
            if metal:
                groups[metal] = str(group_name)
    return groups


def is_base_metal(metal: str) -> bool:
    """Сталь в палитре помечена is_base: её иконки лежат в base/, а не во фракции."""
    with open(PALETTE, encoding="utf-8") as fh:
        data = json.load(fh)
    for rec in (data.get("groups") or {}).values():
        for metal_rec in rec.get("metals", []):
            if str(metal_rec.get("metal", "")) == metal:
                return bool(metal_rec.get("is_base"))
    return False


def resolve_source(metal: str, kind: str) -> tuple[str, list[str]]:
    """(путь иконки металла нужного вида, проблемы)."""
    problems: list[str] = []
    if is_base_metal(metal):
        hits = sorted(globmod.glob(os.path.join(ROOT, BASE_GLOB[kind])))
        if not hits:
            problems.append("%s/%s: нет источника (%s)" % (metal, kind, BASE_GLOB[kind]))
            return "", problems
        return hits[0], problems
    groups = faction_groups()
    want = groups.get(metal, "")
    for sub in ("faction_w",) if kind == "weapon" else ("faction",):
        pattern = FACTION_GLOB[kind].format(sub=sub)
        cands = sorted(globmod.glob(os.path.join(ROOT, pattern % {"metal": metal})))
        if want:
            cands = [c for c in cands if os.sep + want + os.sep in c]
        if cands:
            return cands[0], problems
    problems.append("%s/%s: нет источника (%s)"
                    % (metal, kind, FACTION_GLOB[kind].format(sub="faction")
                       % {"metal": metal}))
    return "", problems


def silhouette(img: Image.Image) -> Image.Image:
    return img.convert("RGBA").getchannel("A").point(lambda v: 255 if v > 96 else 0)


def crack_path(mask: Image.Image, rng: random.Random, side: int = 0) -> list[tuple[float, float]]:
    """Ломаная трещины, лежащая ЦЕЛИКОМ на непрозрачных пикселях силуэта.

    Идём от кромки силуэта вглубь: шаг «вниз + поперёк», угол скачет
    (трещина не прямая). Точка принимается, только если она на силуэте, —
    иначе линия ушла бы в прозрачный фон и на 32 px её не было бы видно.
    """
    w, h = mask.size
    rows = [y for y in range(h) if any(mask.getpixel((x, y)) for x in range(w))]
    if not rows:
        return []
    top, bottom = rows[0], rows[-1]
    height = max(1, bottom - top)
    y0 = top + int(height * (0.10 + 0.22 * side))
    xs = [x for x in range(w) if mask.getpixel((x, y0))]
    if not xs:
        return []
    x0 = xs[-1] if side == 0 else xs[0]
    inward = -1.0 if side == 0 else 1.0
    length = max(6, int(height * 0.55))
    widen = max(1.0, float(w) / 80.0)
    pts = [(float(x0), float(y0))]
    x, y = float(x0) - inward, float(y0)
    angle = inward
    for _i in range(1, length):
        angle = max(-1.6, min(1.6, angle + rng.uniform(-0.7, 0.7)))
        x += angle * widen
        y += 1.0
        if not (1 <= int(x) < w - 1 and 1 <= int(y) < h - 1):
            break
        if not mask.getpixel((int(x), int(y))):
            if mask.getpixel((int(x), int(y) - 1)):
                y -= 1.0
            else:
                break
        pts.append((x, y))
    return pts


def cross_lines(canvas: Image.Image, variant: dict) -> list[tuple[tuple[float, float],
                                                                 tuple[float, float]]]:
    """Линия перечёркивания по диагонали bbox иконки.

    Начинается около верхнего левого угла bbox и идёт к нижнему правому;
    конец выходит за силуэт на LINE_REACH — прямая линия видна сразу, в
    отличие от трещины, форму которой на 32 px не разобрать.
    """
    sig = silhouette(canvas)
    bbox = sig.getbbox()
    if not bbox:
        return []
    x0, y0, x1, y1 = bbox
    diag = math.hypot(x1 - x0, y1 - y0)
    ax, ay = x0 + diag * LINE_INSET, y0 + diag * LINE_INSET
    ux, uy = (x1 - x0) / diag, (y1 - y0) / diag
    out: list[tuple[tuple[float, float], tuple[float, float]]] = []
    spreads = [LINE_SPREAD * i for i in range(len(variant["lines"]))]
    for length, spread in zip(variant["lines"], spreads):
        sx, sy = ax - uy * diag * spread, ay + ux * diag * spread
        ex, ey = ax + ux * diag * LINE_REACH * length, ay + uy * diag * LINE_REACH * length
        out.append(((sx, sy), (ex, ey)))
    return out


def draw_cross(canvas: Image.Image, scale: float, variant: dict) -> None:
    """Красная перечёркивающая линия с тёмной обводкой под ней.

    Обводка нужна, чтобы линия читалась и на светлом серебре: чистый красный
    на кремовом теряется. Ширина считается в пикселях источника и рисуется в
    SUPERSAMPLE с уменьшением LANCZOS — иначе на 32 px край рваный.
    """
    k = SUPERSAMPLE
    big = Image.new("RGBA", (canvas.width * k, canvas.height * k), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    width = max(2, round(float(variant.get("width", 3.0)) * scale * k))
    shade_w = max(width + 2, round(width * (1.0 + LINE_SHADE)))
    for (sx, sy), (ex, ey) in cross_lines(canvas, variant):
        draw.line([(sx * k, sy * k), (ex * k, ey * k)],
                  fill=(0, 0, 0, 110), width=shade_w)
    for (sx, sy), (ex, ey) in cross_lines(canvas, variant):
        draw.line([(sx * k, sy * k), (ex * k, ey * k)], fill=CROSS_COLOR, width=width)
    canvas.alpha_composite(big.resize(canvas.size, Image.Resampling.LANCZOS))


def draw_crack(canvas: Image.Image, pts: list[tuple[float, float]], scale: float,
               variant: dict) -> None:
    """Тёмный разрыв с бликом внутри и (по варианту) затемнение под ним.

    Трещина обязана читаться на 32 px и на любом металле: тёмный кобальт
    скрывает тонкую линию, светлая сталь — тёмную без блика. Ширина
    считается в пикселях ИСТОЧНИКА (иконки 60-80 px), поэтому итоговая
    линия на холсте разного размера выглядит одинаково.
    """
    k = SUPERSAMPLE
    big = Image.new("RGBA", (canvas.width * k, canvas.height * k), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    line = [(x * k, y * k) for x, y in pts]
    dark_w = max(2, round(float(variant.get("dark", 2.2)) * scale * k))
    light_w = max(0, round(float(variant.get("light", 1.0)) * scale * k))
    shade_w = max(0, round(float(variant.get("shade", 0)) / 100.0 * scale * k))
    if shade_w > 0:
        draw.line(line, fill=(0, 0, 0, round(255 * float(variant.get("shade", 0)) / 100.0)),
                  width=max(dark_w, shade_w * 2), joint="curve")
    draw.line(line, fill=CRACK_DARK, width=dark_w, joint="curve")
    if light_w > 0:
        draw.line(line, fill=CRACK_LIGHT, width=light_w, joint="curve")
    canvas.alpha_composite(big.resize(canvas.size, Image.Resampling.LANCZOS))


def chipped(img: Image.Image, rng: random.Random) -> Image.Image:
    """Скол: угол силуэта стёрт грубым многоугольником с кромки."""
    mask = silhouette(img)
    w, h = mask.size
    rows = [y for y in range(h) if any(mask.getpixel((x, y)) for x in range(w))]
    if not rows:
        return img
    top, bottom = rows[0], rows[-1]
    corner_y = bottom - int((bottom - top) * 0.22)
    xs = [x for x in range(w) if mask.getpixel((x, corner_y))]
    if not xs:
        return img
    edge = xs[-1]
    size = max(3, int((bottom - top) * 0.26))
    poly = [
        (edge - size, corner_y),
        (w, corner_y - rng.randint(0, 2)),
        (w, h),
        (edge - rng.randint(0, 3), h),
    ]
    k = SUPERSAMPLE
    big = Image.new("L", (w * k, h * k), 0)
    ImageDraw.Draw(big).polygon([(x * k, y * k) for x, y in poly], fill=255)
    hole = big.resize(mask.size, Image.Resampling.LANCZOS).point(lambda v: 255 if v > 96 else 0)
    out = img.copy()
    px = out.load()
    hp = hole.load()
    for y in range(h):
        for x in range(w):
            if hp[x, y]:
                px[x, y] = (0, 0, 0, 0)
    return out


def derive(src: Image.Image, variant: dict, seed: int) -> Image.Image:
    """Иконка вещи + красное перечёркивание. Размер источника сохраняется."""
    img = src.convert("RGBA").copy()
    rng = random.Random(seed)
    mask = silhouette(img)
    scale = max(1.0, float(mask.width) / 80.0)
    if variant.get("crack"):
        if variant.get("notch"):
            img = chipped(img, rng)
        mask = silhouette(img)
        for side in range(int(variant.get("cracks", 1))):
            pts = crack_path(mask, rng, side=side)
            if len(pts) < 3:
                continue
            draw_crack(img, pts, scale, variant)
    draw_cross(img, scale, variant)
    return img


def targets() -> list[tuple[str, str, str, str]]:
    """(metal, kind, source_path, dest_path) для всех сломанных вещей базы.

    Использование по FIGURE: 20 металлов × {броня, оружие} плюс одежда, то есть
    ровно те 41 файл, на которые ссылаются 125 записей Broken в item_db.json.
    """
    out: list[tuple[str, str, str, str]] = []
    for metal in METALS:
        for kind in ("armor", "weapon"):
            out.append((metal, kind, "", os.path.join(BROKEN_DIR, "%s_%s.png" % (metal, kind))))
    out.append(("Linen", "garment", FABRIC, os.path.join(BROKEN_DIR, "linen_garment.png")))
    return out


def out_name(dest: str, variant: str) -> str:
    """import/broken_overlay/iron_armor_v7_red_line.png: имя dest + вариант."""
    stem = os.path.basename(dest)[:-4]
    return "%s_%s.png" % (stem, variant)


def sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()



def build_sheet(files: list[str], sheet_path: str | None = None,
                columns: int = 6, cell_size: int = 128) -> bool:
    """Подписанный контакт-лист skill-скриптом create-game-assets."""
    path = sheet_path or SHEET_PATH
    if not os.path.isfile(SHEET):
        print("  ! skill-скрипт не найден, лист не построен: %s" % SHEET)
        return False
    cmd = [sys.executable, SHEET, *files,
           "--out", path, "--columns", str(columns), "--cell-size", str(cell_size)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("  ! контакт-лист не построился: %s" % (r.stderr.strip() or r.stdout.strip()))
        return False
    print("  OK лист: %s" % os.path.relpath(path, ROOT))
    return True


def build_compare_sources() -> dict[tuple[str, str], str]:
    """Сохранить ЦЕЛЫЕ иконки шести сравниваемых вещей в import/broken_overlay/.

    Обычный источник брони — heavy_chest, оружия — one_handed_sword: подписи
    листа получают понятные имена `whole_<металл>_<вид>.png`.
    """
    os.makedirs(OUT_DIR, exist_ok=True)
    srcs: dict[tuple[str, str], str] = {}
    for metal, kind in COMPARE:
        path, _p = resolve_source(metal, kind)
        if not path:
            continue
        out = os.path.join(OUT_DIR, "_src_%s_%s.png" % (metal, kind))
        with Image.open(path) as im:
            im.convert("RGBA").save(out)
        srcs[(metal, kind)] = out
    return srcs


def build_compare(srcs: dict[tuple[str, str], str]) -> list[str]:
    """Пара «целая | сломанная» на каждую вещь и вариант плюс её 32 px-вид.

    Файл `_cmp_<металл>_<вид>_<вариант>.png`, поэтому подписанный контакт-лист
    сам показывает и вещь, и вариант.
    """
    files: list[str] = []
    for (metal, kind), src_path in srcs.items():
        with Image.open(src_path) as im:
            whole = im.convert("RGBA")
        for vname, variant in sorted(VARIANTS.items()):
            with Image.open(src_path) as im:
                broken = derive(im, variant, SEED)
            w, h = whole.size
            pair = Image.new("RGBA", (w * 2 + 6, h), (26, 26, 30, 255))
            pair.alpha_composite(whole, (0, 0))
            pair.alpha_composite(broken, (w + 6, 0))
            small_w = round(pair.width * SMALL_PX / float(h))
            small = pair.resize((max(1, small_w), SMALL_PX), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (pair.width, pair.height + small.height + 4),
                               (26, 26, 30, 255))
            canvas.alpha_composite(pair, (0, 0))
            canvas.alpha_composite(small, (max(0, (pair.width - small.width) // 2),
                                           pair.height + 4))
            out = os.path.join(OUT_DIR, "_cmp_%s_%s_%s.png" % (metal, kind, vname))
            canvas.save(out, "PNG")
            files.append(out)
    return files


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default=None, help="один вариант из списка")
    ap.add_argument("--install", action="store_true",
                    help="записать выбранный вариант в assets/items/broken/")
    ap.add_argument("--report", action="store_true", help="только отчёт об источниках")
    ap.add_argument("--check", action="store_true",
                    help="сверить, что установленные файлы совпадают с вариантом")
    ap.add_argument("--no-sheet", action="store_true", help="не строить контакт-лист")
    args = ap.parse_args()

    if args.variant and args.variant not in VARIANTS:
        print("RESULT: FAIL — нет варианта %s (есть: %s)"
              % (args.variant, ", ".join(VARIANTS)))
        return 1
    todo = {args.variant: VARIANTS[args.variant]} if args.variant else dict(VARIANTS)

    srcs: dict[tuple[str, str], str] = {}
    problems: list[str] = []
    print("-- источники --")
    for metal, kind, path, _dest in targets():
        if path == "":
            path, p = resolve_source(metal, kind)
            problems.extend(p)
        if path == "":
            continue
        srcs[(metal, kind)] = path
        with Image.open(path) as im:
            print("  %s/%s: %s (%dx%d)"
                  % (metal, kind, os.path.relpath(path, ROOT), im.width, im.height))
    for p in problems:
        print("  ! %s" % p)
    if args.report:
        print("DRY-RUN: источников %d, вариантов %d, металлов %d"
              % (len(srcs), len(todo), len(METALS)))
        print("RESULT: OK report" if not problems else "RESULT: WARN report (%d)" % len(problems))
        return 0
    if any(not os.path.isfile(p) for p in srcs.values()):
        print("RESULT: FAIL — не найдены источники")
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    compare_srcs = build_compare_sources()
    written: list[str] = []
    hashes: dict[str, str] = {}
    print("-- деривация: силуэт -> трещина (8x, LANCZOS) --")
    for vname, variant in sorted(todo.items()):
        for metal, kind, path, dest in targets():
            src_path = path if path != "" else srcs[(metal, kind)]
            with Image.open(src_path) as src:
                img = derive(src, variant, SEED)
            out_path = os.path.join(OUT_DIR, out_name(dest, vname))
            img.save(out_path, "PNG")
            written.append(out_path)
            hashes[os.path.relpath(dest, ROOT)] = sha256(out_path)
        print("  OK вариант %s: %d файлов" % (vname, len(srcs)))

    if not args.no_sheet:
        build_sheet(written)
        compare_files = build_compare(compare_srcs)
        build_sheet(compare_files, sheet_path=COMPARE_PATH, columns=1)
        build_sheet(compare_files, sheet_path=COMPARE_SMALL_PATH, columns=3, cell_size=48)

    if args.check:
        bad = [rel for rel in hashes if not os.path.isfile(os.path.join(ROOT, rel))
               or sha256(os.path.join(ROOT, rel)) != hashes[rel]]
        print("Проверено установленных: %d, расхождений: %d" % (len(hashes), len(bad)))
        for b in bad[:10]:
            print("   ! %s" % b)
        print("RESULT: %s check" % ("OK" if not bad else "FAIL"))
        return 0 if not bad else 1

    if args.install:
        if len(todo) != 1:
            print("RESULT: FAIL — --install требует ровно один вариант (--variant)")
            return 1
        vname = next(iter(todo))
        copied = 0
        for metal, kind, path, dest in targets():
            src_png = os.path.join(OUT_DIR, out_name(dest, vname))
            if not os.path.isfile(src_png):
                print("  ! нет %s" % src_png)
                continue
            shutil.copyfile(src_png, dest)
            copied += 1
        print("Установлено: %d (вариант %s)" % (copied, vname))
        if copied != len(srcs):
            print("RESULT: FAIL broken_overlay (установлено %d из %d)" % (copied, len(srcs)))
            return 1

    print("Итого файлов: %d" % len(written))
    print("RESULT: OK broken_overlay (вариантов %d, металлов %d, файлов %d)"
          % (len(todo), len(METALS), len(srcs)))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
