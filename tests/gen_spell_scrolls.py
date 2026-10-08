#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Композит свитков заклинаний: свиток стихии + иконка заклинания.

Все Scroll/SuperScroll получают согласованный вид: base scroll_{sphere}.png
+ маленькая иконка заклинания в центре (как у свитков рецептов).
Раньше часть свитков (Wall of Fire, Light) показывала только символ
заклинания — «не по правилам».

Запуск:
    python tests/gen_spell_scrolls.py
    python tests/gen_spell_scrolls.py --report
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
SPELLS_DB = os.path.join(ROOT, "assets", "spells", "spells_db.json")
SCROLL_DIR = os.path.join(ROOT, "assets", "spells")
OUT_DIR = os.path.join(ROOT, "assets", "spells", "scrolls")

SIZE = 80
OVERLAY = 36
PAD = 2

SPHERE_SCROLL = {
    "Fire": "scroll_fire.png",
    "Water": "scroll_water.png",
    "Earth": "scroll_earth.png",
    "Air": "scroll_air.png",
    "Astral": "scroll_astral.png",
}


def bake(base_path: str, icon_path: str) -> Image.Image:
    canvas = Image.open(base_path).convert("RGBA").resize(
        (SIZE, SIZE), Image.Resampling.LANCZOS
    )
    if not os.path.isfile(icon_path):
        return canvas
    icon = Image.open(icon_path).convert("RGBA")
    icon.thumbnail((OVERLAY, OVERLAY), Image.Resampling.LANCZOS)
    # Без тёмной подложки — только лёгкая тень-контур через дубль с альфой
    ix = (SIZE - icon.width) // 2
    iy = (SIZE - icon.height) // 2
    # Мягкая тень: тот же силуэт, сдвинут на 1px, низкая альфа
    shadow = icon.copy()
    sa = shadow.split()[-1].point(lambda a: int(a * 0.35))
    shadow.putalpha(sa)
    canvas.paste(shadow, (ix + 1, iy + 1), shadow)
    canvas.paste(icon, (ix, iy), icon)
    return canvas


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    with open(SPELLS_DB, encoding="utf-8") as f:
        spells = json.load(f)
    with open(DB, encoding="utf-8") as f:
        items = json.load(f)

    os.makedirs(OUT_DIR, exist_ok=True)
    n = 0
    for it in items:
        key = str(it.get("key", ""))
        q = str(it.get("quality", ""))
        if q not in ("Scroll", "SuperScroll"):
            continue
        spell = key.split(" ", 1)[1] if " " in key else ""
        sname = spell.replace(" ", "_").rstrip("-")
        # «Fire Wall» в ключе vs «Wall_of_Fire» в spells_db
        if sname == "Fire_Wall":
            sname = "Wall_of_Fire"
        sphere = str(spells.get(sname, {}).get("sphere", "") or "")
        if not sphere:
            # literal match
            for sn, s in spells.items():
                if sn.replace("_", " ").lower() == spell.lower().rstrip("-"):
                    sphere = str(s.get("sphere", ""))
                    sname = sn
                    break
        scroll_name = SPHERE_SCROLL.get(sphere, "")
        base = os.path.join(SCROLL_DIR, scroll_name)
        if not scroll_name or not os.path.isfile(base):
            print("  MISS sphere for %s (sphere=%s)" % (key, sphere))
            continue
        # Иконка заклинания: assets/spells/{snake}.png — всегда символ, не свиток
        icon_fs = os.path.join(SCROLL_DIR, "%s.png" % sname.lower())
        if not os.path.isfile(icon_fs):
            icon_fs = ""
        out_name = "sc_%s.png" % sname.lower()
        out_path = os.path.join(OUT_DIR, out_name)
        # Перегенерация всегда: композиты могли собраться со свитком-оверлеем
        if not args.report:
            bake(base, icon_fs).save(out_path)
        new_icon = "res://assets/spells/scrolls/%s" % out_name
        if it.get("icon") != new_icon:
            it["icon"] = new_icon
            n += 1
            print("  OK %s -> %s (sphere=%s)" % (key, out_name, sphere))

    print("patched icons: %d" % n)
    if args.report:
        return 0
    with open(DB, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("OK: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.exit(main())
