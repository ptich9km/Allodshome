#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Фракционные варианты оружия: перекраска base_w в цвет металла.

Вход:  assets/items/base_w/{тип}_{качество}.png  (52 файла = 13 типов x 4)
Палитра: assets/items/faction_palette.json (источник правды)
Выход: assets/items/faction_w/{group}/{metal}_{type}_{tier}.png

Формула дуотона - в faction_tint.py, общая с генератором брони. Копия здесь
означала бы два источника правды, и через месяц неизвестно, какой правильный.

КЛЮЧЕВОЕ: качество = тир металла 1:1 (решение игрока, то же, что у брони).
Поэтому на каждый металл берётся ОДИН файл на тип, а не все четыре: 19
не-base металлов x 13 типов = 247 файлов. Если взять все четыре качества,
выйдет 988 - это четыре копии одного тира с разной детализацией рисунка.
Ровно этот баг один раз случился с бронёй (1368 файлов вместо 342).

Почему дуотон здесь работает лучше, чем на броне: броня - это кожа, ткань и
металл в одном кадре, а оружие почти целиком металл, поэтому подмена тона
меняет цвет и не выедает фактуру.

Запуск:
    python tests/gen_faction_weapon_tint.py --report   # только отчёт
    python tests/gen_faction_weapon_tint.py            # перекрасить всё
    python tests/gen_faction_weapon_tint.py --sheet    # + контактные листы
    python tests/gen_faction_weapon_tint.py --check    # сверить с перегенерацией
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from faction_tint import (  # noqa: E402
    VOLUME_RATIO_MIN,
    alpha_of,
    color_stats,
    duotone,
    load_palette,
    palette_metals,
    sha256_of_img,
    volume_ratio,
)

from PIL import Image, ImageDraw  # noqa: E402

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE_DIR = os.path.join(_ROOT, "assets", "items", "base_w")
OUT_ROOT = os.path.join(_ROOT, "assets", "items", "faction_w")


def scan_base(pal: dict) -> tuple:
    """Разбирает base_w на (типы, качества) и проверяет инварианты.

    Инварианты, без которых скрипт молча сделал бы не то:
      * качество в имени файла должно быть тиром из палитры - иначе ни одно
        задание не совпадёт и выйдет 0 файлов без ошибки;
      * у каждого типа должны быть ВСЕ тиры, иначе металл молча теряет тип.
    """
    tiers = list(pal["tiers"])
    if not os.path.isdir(BASE_DIR):
        return [], tiers, ["НЕТ КАТАЛОГА %s" % BASE_DIR]

    found = {}
    problems = []
    for fn in sorted(os.listdir(BASE_DIR)):
        if not fn.endswith(".png") or fn.startswith("_"):
            continue
        stem = fn[:-4]
        if "_" not in stem:
            problems.append("имя без '_': %s" % fn)
            continue
        wtype, quality = stem.rsplit("_", 1)
        if quality not in tiers:
            problems.append("качество '%s' не тир из палитры: %s" % (quality, fn))
            continue
        found.setdefault(wtype, {})[quality] = os.path.join(BASE_DIR, fn)

    types = sorted(found)
    for wtype in types:
        miss = [t for t in tiers if t not in found[wtype]]
        if miss:
            problems.append("тип '%s' без тиров: %s" % (wtype, ", ".join(miss)))
    return types, tiers, problems


def build(types: list, tiers: list) -> list[dict]:
    """Задания {src, dst, metal, group, tier, wtype, color}. Base-металлы пропускаем."""
    pal = load_palette()
    jobs = []
    for m in palette_metals(pal):
        if m["is_base"]:
            continue  # сталь = сами base-файлы, не дублируем
        for wtype in types:
            src = None
            for tier in tiers:
                cand = os.path.join(BASE_DIR, "%s_%s.png" % (wtype, tier))
                if os.path.exists(cand):
                    src = cand
                    break
            if src is None:
                continue
            # качество = тир: берём файл именно тира металла
            tier = os.path.basename(src)[:-4].rsplit("_", 1)[1]
            dst = os.path.join(OUT_ROOT, m["group"], "%s_%s_%s.png"
                               % (m["metal"], wtype, m["tier"]))
            jobs.append({
                "src": src, "dst": dst, "metal": m["metal"], "group": m["group"],
                "tier": m["tier"], "wtype": wtype, "color": m["color"],
            })
    return jobs


def make_sheet(pal: dict, group: str, types: list) -> None:
    """Лист группы: строки = тиры металла, колонки = типы оружия."""
    metals = [m for m in palette_metals(pal) if m["group"] == group and not m["is_base"]]
    cell = 96
    cols = len(types)
    sheet = Image.new("RGBA", (cols * cell, len(metals) * (cell + 18)), (24, 26, 32, 255))
    d = ImageDraw.Draw(sheet)
    for y in range(0, sheet.size[1], 8):
        for x in range(0, sheet.size[0], 8):
            if ((x // 8) + (y // 8)) % 2 == 0:
                d.rectangle([x, y, x + 7, y + 7], fill=(48, 50, 58, 255))
    for ri, m in enumerate(metals):
        y0 = ri * (cell + 18)
        d.text((4, y0 + cell + 2), "%s %s %s" % (m["metal"], m["tier"], m["color"]),
               fill=(225, 228, 235, 255))
        for li, wtype in enumerate(types):
            p = os.path.join(OUT_ROOT, group, "%s_%s_%s.png" % (m["metal"], wtype, m["tier"]))
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGBA")
            k = (cell - 10) / float(max(im.size))
            im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))),
                           Image.LANCZOS)
            x0 = li * cell
            sheet.alpha_composite(im, (x0 + (cell - im.size[0]) // 2,
                                       y0 + (cell - im.size[1]) // 2))
    sheet.save(os.path.join(OUT_ROOT, group, "_contact_sheet.png"))


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Перекраска base_w в цвета металлов фракций")
    ap.add_argument("--report", action="store_true", help="только отчёт, ничего не писать")
    ap.add_argument("--sheet", action="store_true", help="собрать контактные листы")
    ap.add_argument("--check", action="store_true", help="сверить выход с перегенерацией")
    args = ap.parse_args()

    pal = load_palette()
    types, tiers, problems = scan_base(pal)
    if problems:
        print("ПРОБЛЕМЫ В base_w (%d):" % len(problems))
        for p in problems:
            print("   ! %s" % p)
        return 1
    if not types:
        print("НЕТ ТИПОВ ОРУЖИЯ В %s" % BASE_DIR)
        return 1

    metals = palette_metals(pal)
    n_base = sum(1 for m in metals if m["is_base"])
    print("ТИПОВ ОРУЖИЯ: %d (%s)" % (len(types), ", ".join(types)))
    print("ТИРОВ: %d, МЕТАЛЛОВ: %d (из них base-тиров без перекраски: %d)"
          % (len(tiers), len(metals), n_base))
    print("ПРАВИЛО: качество = тир, значит %d металлов x %d типов = %d (а не %d)"
          % (len(metals) - n_base, len(types), (len(metals) - n_base) * len(types),
             (len(metals) - n_base) * len(types) * len(tiers)))

    jobs = build(types, tiers)
    print("ЗАДАЧ: %d" % len(jobs))
    if not jobs:
        print("НЕТ ЗАДАЧ - проверь пути base_w")
        return 1
    for group in sorted(set(j["group"] for j in jobs)):
        n = sum(1 for j in jobs if j["group"] == group)
        print("  %-14s %3d файлов" % (group, n))

    if args.check:
        bad = [j for j in jobs if not os.path.exists(j["dst"])]
        if bad:
            print("НЕТ ФАЙЛОВ: %d (например %s)" % (len(bad), os.path.basename(bad[0]["dst"])))
            return 1
        mism = []
        for j in jobs:
            got = Image.open(j["dst"]).convert("RGBA")
            want = duotone(Image.open(j["src"]), j["color"])
            if sha256_of_img(got) != sha256_of_img(want):
                mism.append(os.path.basename(j["dst"]))
        if mism:
            print("НЕСОВПАДЕНИЕ: %d файлов, например %s" % (len(mism), ", ".join(mism[:5])))
            return 1
        print("СОВПАДЕНИЕ: все %d файлов идентичны перегенерации" % len(jobs))
        return 0

    if args.report:
        return 0

    for j in jobs:
        j["stats_in"] = color_stats(Image.open(j["src"]).convert("RGBA"))

    for j in jobs:
        img = duotone(Image.open(j["src"]), j["color"])
        os.makedirs(os.path.dirname(j["dst"]), exist_ok=True)
        img.save(j["dst"])
    print("ЗАПИСАНО: %d файлов в %s/" % (len(jobs), OUT_ROOT.replace("\\", "/")))

    for j in jobs:
        j["stats_out"] = color_stats(Image.open(j["dst"]).convert("RGBA"))
    worst = sorted(((volume_ratio(j["stats_in"], j["stats_out"]), j) for j in jobs),
                   key=lambda p: p[0])
    print("ОБЪЁМ (размах светлоты выход/вход, меньше = хуже), худшие 8:")
    for ratio, j in worst[:8]:
        print("   %.3f  %-42s размах %.3f -> %.3f" % (
            ratio, os.path.basename(j["dst"]),
            j["stats_in"]["luma_range"], j["stats_out"]["luma_range"]))
    flat = [j for r, j in worst if r < VOLUME_RATIO_MIN]
    print("ОБЪЁМ ПОТЕРЯН (размах светлоты упал ниже %.2f): %d из %d"
          % (VOLUME_RATIO_MIN, len(flat), len(jobs)))
    for j in flat[:8]:
        print("   ! %s" % os.path.basename(j["dst"]))

    bad_alpha = [j for j in jobs
                 if alpha_of(Image.open(j["src"])) != alpha_of(Image.open(j["dst"]))]
    print("АЛЬФА РАСХОДИТСЯ: %d (должно быть 0)" % len(bad_alpha))
    if bad_alpha:
        return 1

    if args.sheet:
        for group in sorted(set(j["group"] for j in jobs)):
            make_sheet(pal, group, types)
        print("КОНТАКТНЫЕ ЛИСТЫ: assets/items/faction_w/*/_contact_sheet.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
