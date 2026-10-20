#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Дроп-иконки основных металлов: программное уменьшение + наклон одобренных иконок.

ЗАЧЕМ: ИИ-генерация дроп-иконок (tests/gen_loot_icons_kodik.py) встала на квоте
Gemini (429, журнал 20.10). Дроп-иконка по замыслу — «та же вещь, лежащая на
земле»: уменьшенный наклонённый силуэт одобренной инвентарной иконки даёт это
программно, без генераций и без расходов. Источник — уже установленные и
одобренные игроком иконки атласа предметов (faction_w/common — оружие,
faction/common — броня); резолв через glob по установленным путям, суффикс
качества (cheap/common/elite) не хардкодится.

ПРАВИЛО ИГРОКА: ничего не ставится в assets/ без личного одобрения. По умолчанию
скрипт пишет 4 ВАРИАНТА трансформации в import/loot_icons_derived/ и собирает
подписанный контакт-лист через skill-скрипт create-game-assets
(scripts/build_preview_sheet.py). Выбор варианта — за игроком; только затем
запускается --install, копирующий выбранный вариант в assets/loot_icons/.

РЕСЕМПЛИНГ: downscale LANCZOS + rotate BICUBIC — сознательное отступление от
«nearest only» из references/raster-pipeline.md: это deliberate preprocessing
pass маленьких иконок (поворот nearest даёт рваную лесенку), как решено ранее
в tests/slice_items_atlas.py.

ПОРЯДОК ПРЕОБРАЗОВАНИЙ: alpha-crop → rotate(expand, BICUBIC) → вертикальный
squash (LANCZOS) → масштаб до fit_px по большей стороне → центровка на холст
32×32. Масштаб ПОСЛЕ поворота гарантирует, что наклонённый силуэт не вылезет за
холст (bbox при повороте растёт).

ВАРИАНТЫ (для выбора игроком):
  v0_flat           — без наклона, только уменьшение
  v1_tilt10         — наклон 10°
  v2_tilt20_squash  — наклон 20° + вертикальный squash 0.80 (рекомендация)
  v3_tilt30_squash  — наклон 30° + вертикальный squash 0.78

Запуск:
    python tests/gen_loot_icons_derived.py                 # варианты + лист
    python tests/gen_loot_icons_derived.py --report        # только отчёт
    python tests/gen_loot_icons_derived.py --variant v2_tilt20_squash --install
    python tests/gen_loot_icons_derived.py --metals bronze,iron --angle 15
"""

from __future__ import annotations

import argparse
import glob as globmod
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "import", "loot_icons_derived")
LOOT_DIR = os.path.join(ROOT, "assets", "loot_icons")
SKILL_SHEET = os.path.join(
    ROOT, ".agents", "skills", "disciplines", "create-game-assets",
    "scripts", "build_preview_sheet.py",
)
SHEET_PATH = os.path.join(OUT_DIR, "_contact_sheet.png")

# Основные металлы (METALS из tests/gen_items_atlas_kodik.py). Steel исключён:
# его иконки уже есть как base/base_w, а редкие металлы loot_icons не трогаем.
DEFAULT_METALS = ["bronze", "iron", "gold"]

# Вид -> glob по УСТАНОВЛЕННЫМ одобренным иконкам (не import/_sliced: там
# суффиксы _good, а установлены _cheap/_common/_elite).
SOURCE_GLOBS = {
    "weapon": os.path.join(ROOT, "assets", "items", "faction_w", "common",
                           "%(metal)s_one_handed_sword_*.png"),
    "armor": os.path.join(ROOT, "assets", "items", "faction", "common",
                          "%(metal)s_heavy_chest_*.png"),
}

# имя варианта -> (угол поворота в градусах, вертикальный squash)
VARIANTS: dict[str, tuple[float, float]] = {
    "v0_flat": (0.0, 1.0),
    "v1_tilt10": (10.0, 1.0),
    "v2_tilt20_squash": (20.0, 0.80),
    "v3_tilt30_squash": (30.0, 0.78),
}

DEFAULT_FIT = 28  # содержимое не больше 28 px внутри холста 32×32
DEFAULT_CANVAS = 32


def resolve_sources(metals: list[str]) -> tuple[dict[tuple[str, str], str], list[str]]:
    """(metal, kind) -> путь источника; второй возврат — список проблем."""
    srcs: dict[tuple[str, str], str] = {}
    problems: list[str] = []
    for metal in metals:
        for kind, pattern in SOURCE_GLOBS.items():
            hits = sorted(globmod.glob(pattern % {"metal": metal}))
            if not hits:
                problems.append("%s/%s: нет источника по %s"
                                % (metal, kind, pattern % {"metal": metal}))
                continue
            srcs[(metal, kind)] = hits[0]
            if len(hits) > 1:
                print("  ! %s/%s: несколько кандидатов, взят первый: %s"
                      % (metal, kind, ", ".join(os.path.basename(h) for h in hits)))
    return srcs, problems


def derive(src: Image.Image, angle: float, squash: float, fit_px: int,
           canvas_size: int) -> Image.Image:
    """Одобренная иконка -> дроп-иконка: crop, поворот, squash, масштаб, центр."""
    img = src.convert("RGBA")
    alpha = img.split()[-1]
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("источник полностью прозрачен")
    img = img.crop(bbox)
    if angle:
        img = img.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    if squash != 1.0:
        h = max(1, round(img.height * squash))
        img = img.resize((img.width, h), Image.Resampling.LANCZOS)
    scale = min(1.0, fit_px / max(img.width, img.height))
    if scale < 1.0:
        img = img.resize(
            (max(1, round(img.width * scale)), max(1, round(img.height * scale))),
            Image.Resampling.LANCZOS,
        )
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    canvas.alpha_composite(
        img,
        ((canvas_size - img.width) // 2, (canvas_size - img.height) // 2),
    )
    return canvas


def build_sheet(files: list[str]) -> bool:
    """Контакт-лист через skill-скрипт create-game-assets (подписи = имена файлов)."""
    if not os.path.isfile(SKILL_SHEET):
        print("  ! skill-скрипт не найден, лист не построен: %s" % SKILL_SHEET)
        return False
    cmd = [sys.executable, SKILL_SHEET, *files,
           "--out", SHEET_PATH, "--columns", "4", "--cell-size", "160"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("  ! контакт-лист не построился: %s" % (r.stderr.strip() or r.stdout.strip()))
        return False
    print("  OK лист: %s" % os.path.relpath(SHEET_PATH, ROOT))
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--metals", default=",".join(DEFAULT_METALS),
                    help="металлы через запятую (по умолчанию bronze,iron,gold)")
    ap.add_argument("--angle", type=float, default=None,
                    help="угол наклона для варианта custom (градусы)")
    ap.add_argument("--squash", type=float, default=None,
                    help="вертикальный squash для варианта custom (1.0 = нет)")
    ap.add_argument("--fit", type=int, default=DEFAULT_FIT,
                    help="максимальная сторона содержимого, px (по умолчанию 28)")
    ap.add_argument("--size", type=int, default=DEFAULT_CANVAS,
                    help="сторона выходного холста, px (по умолчанию 32)")
    ap.add_argument("--variant", default=None,
                    help="один вариант из списка (для точечной установки)")
    ap.add_argument("--install", action="store_true",
                    help="скопировать выбранный вариант в assets/loot_icons/")
    ap.add_argument("--report", action="store_true",
                    help="только отчёт по источникам, файлы не писать")
    ap.add_argument("--no-sheet", action="store_true",
                    help="не строить контакт-лист")
    args = ap.parse_args()

    metals = [m.strip().lower() for m in args.metals.split(",") if m.strip()]
    if args.angle is not None or args.squash is not None:
        todo = {"custom": (args.angle or 0.0, args.squash if args.squash is not None else 1.0)}
    elif args.variant:
        if args.variant not in VARIANTS:
            print("RESULT: FAIL — нет варианта %s (есть: %s)"
                  % (args.variant, ", ".join(VARIANTS)))
            return 1
        todo = {args.variant: VARIANTS[args.variant]}
    else:
        todo = dict(VARIANTS)

    srcs, problems = resolve_sources(metals)
    if problems:
        for p in problems:
            print("  ! %s" % p)
        print("RESULT: FAIL — не найдены источники (%d)" % len(problems))
        return 1

    print("-- источники (одобрены игроком 20.10) --")
    for (metal, kind), path in sorted(srcs.items()):
        with Image.open(path) as im:
            size = "%dx%d" % (im.width, im.height)
        print("  %s/%s: %s (%s)" % (metal, kind, os.path.relpath(path, ROOT), size))
    if args.report:
        print("DRY-RUN: вариантов %d, металлов %d" % (len(todo), len(metals)))
        print("RESULT: OK report")
        return 0

    os.makedirs(OUT_DIR, exist_ok=True)
    written: list[str] = []
    print("-- деривация: crop -> rotate -> squash -> fit %d -> canvas %d --"
          % (args.fit, args.size))
    for (metal, kind), src_path in sorted(srcs.items()):
        with Image.open(src_path) as src:
            for vname, (angle, squash) in sorted(todo.items()):
                img = derive(src, angle, squash, args.fit, args.size)
                name = "%s_%s_%s.png" % (metal, kind, vname)
                out_path = os.path.join(OUT_DIR, name)
                img.save(out_path, "PNG")
                written.append(out_path)
                print("  OK %s (угол %.0f, squash %.2f)" % (name, angle, squash))

    if todo and not args.no_sheet:
        build_sheet(written)

    if args.install:
        if len(todo) != 1:
            print("RESULT: FAIL — --install требует ровно один вариант (--variant или --angle/--squash)")
            return 1
        vname = next(iter(todo))
        copied = 0
        for (metal, kind), _src in sorted(srcs.items()):
            src_png = os.path.join(OUT_DIR, "%s_%s_%s.png" % (metal, kind, vname))
            dst = os.path.join(LOOT_DIR, "%s_%s.png" % (metal, kind))
            shutil.copyfile(src_png, dst)
            copied += 1
            print("  OK install %s -> %s" % (os.path.basename(src_png), os.path.relpath(dst, ROOT)))
        print("Установлено: %d (вариант %s)" % (copied, vname))

    print("Итого файлов: %d" % len(written))
    print("RESULT: OK loot_icons_derived (%d металлов, %d вариантов)" % (len(metals), len(todo)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
