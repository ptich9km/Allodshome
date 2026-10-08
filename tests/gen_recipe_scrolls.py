#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Запечённые свитки рецептов: чертёж-пергамент + иконка вещи в центре.

Иконка = blueprint_*_empty (пустой пергамент из ChatGPTMasters1) + иконка
выхода рецепта поверх. Цвет тона каждого чертежа свой — унификация за счёт
иконки по центру (решение игрока 08.10).

Категория чертежа:
  броня/щит/шлем -> blueprint_armor
  оружие         -> blueprint_weapon
  одежда мага    -> blueprint_clothes
  посохи         -> blueprint_staff

Запуск:
    python tests/gen_recipe_scrolls.py
    python tests/gen_recipe_scrolls.py --report
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
BP_DIR = os.path.join(ROOT, "assets", "items", "recipes")
SMITH_JSON = os.path.join(ROOT, "assets", "professions", "workshop", "smith_recipes.json")
TAILOR_JSON = os.path.join(ROOT, "assets", "professions", "workshop", "tailor_recipes.json")

SCROLL_SIZE = 80
ICON_SIZE = 40
# Центр чертежа: иконка чуть выше геом. центра, как на рукописных схемах
ICON_CX = 0.50
ICON_CY = 0.46

# Цены свитков по металлу/типу (лавка, первая локация — bronze/iron/steel/gold)
SCROLL_PRICE = {
    "bronze_cuirass": 80,
    "iron_cuirass": 120,
    "iron_plate": 180,
    "iron_sword": 100,
    "iron_axe": 110,
    "iron_buckler": 90,
    "steel_cuirass": 250,
    "gold_cuirass": 500,
    "linen_cape": 100,
    "linen_cloak": 140,
    "linen_robe": 200,
    "linen_hat": 120,
}
DEFAULT_PRICE = 150

ARMOR_TYPES = {
    "Cuirass", "Plate Cuirass", "Full Helm", "Buckler", "Shield",
    "Bracers", "Boots", "Heavy Boots", "Amulet",
}
WEAPON_TYPES = {
    "Long Sword", "Short Sword", "Axe", "Great Axe", "Mace", "Sledge",
    "Pike", "Spear", "Halberd", "Bow", "Crossbow", "Club",
}
CLOTH_TYPES = {"Cloak", "Cape", "Robe", "Dress", "Hat", "Low Hat", "Cap"}
STAFF_TYPES = {"Staff"}


def load_recipes(path: str) -> list[dict]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f).get("recipes", [])


def blueprint_for(item: dict) -> str:
    t = str(item.get("type", ""))
    if t in STAFF_TYPES:
        return "blueprint_staff_empty.png"
    if t in WEAPON_TYPES:
        return "blueprint_weapon_empty.png"
    if t in CLOTH_TYPES or str(item.get("material", "")) == "Linen":
        return "blueprint_clothes_empty.png"
    return "blueprint_armor_empty.png"


def bake_scroll(bp_path: str, icon_path: str) -> Image.Image:
    """Пергамент 80×80 + иконка вещи. Без тёмной подложки — чистая композиция."""
    canvas = Image.open(bp_path).convert("RGBA").resize(
        (SCROLL_SIZE, SCROLL_SIZE), Image.Resampling.LANCZOS
    )
    if not os.path.isfile(icon_path):
        return canvas
    icon = Image.open(icon_path).convert("RGBA")
    icon.thumbnail((ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS)
    ix = int(SCROLL_SIZE * ICON_CX) - icon.width // 2
    iy = int(SCROLL_SIZE * ICON_CY) - icon.height // 2
    # Лёгкая тень-силуэт (без плоского rect-фона)
    shadow = icon.copy()
    sa = shadow.split()[-1].point(lambda a: int(a * 0.30))
    shadow.putalpha(sa)
    canvas.paste(shadow, (ix + 1, iy + 1), shadow)
    canvas.paste(icon, (ix, iy), icon)
    return canvas


def recipe_bp(item: dict) -> str:
    """Подкатегория для фильтра в лавке: armor | weapon | clothes."""
    t = str(item.get("type", ""))
    if t in STAFF_TYPES or t in WEAPON_TYPES:
        return "weapon"
    if t in CLOTH_TYPES or str(item.get("material", "")) == "Linen":
        return "clothes"
    return "armor"


def resolve_icon(item: dict) -> str:
    icon = str(item.get("icon", ""))
    if not icon.startswith("res://"):
        return ""
    return os.path.join(ROOT, icon[len("res://"):].replace("/", os.sep))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    smith = load_recipes(SMITH_JSON)
    tailor = load_recipes(TAILOR_JSON)
    with open(DB, encoding="utf-8") as f:
        items = json.load(f)
    by_key = {it["key"]: it for it in items if "key" in it}

    written = 0
    for kind, recipes in (("smith", smith), ("tailor", tailor)):
        for r in recipes:
            rid = str(r.get("id", ""))
            outs = r.get("outputs", [])
            if not outs:
                continue
            base = by_key.get(str(outs[0].get("key", "")), {})
            bp = os.path.join(BP_DIR, blueprint_for(base))
            if not os.path.isfile(bp):
                print("  MISS blueprint for %s: %s" % (rid, bp))
                continue
            icon_src = resolve_icon(base)
            img = bake_scroll(bp, icon_src)
            icon_name = "recipe_%s.png" % rid
            out_path = os.path.join(BP_DIR, icon_name)
            if not args.report:
                img.save(out_path, "PNG")
            price = SCROLL_PRICE.get(rid, DEFAULT_PRICE)
            # Upsert
            scroll_key = "Recipe %s" % rid
            new_item = {
                "key": scroll_key,
                "name_ru": "Свиток: %s" % str(r.get("name_ru", rid)),
                "name_en": "Recipe: %s" % str(base.get("name_en", rid)),
                "quality": "Recipe",
                "type": "Recipe",
                "material": "None",
                "icon": "res://assets/items/recipes/%s" % icon_name,
                "price": price,
                "weight": 0.2,
                "damage_min": 0, "damage_max": 0, "to_hit": 0,
                "defence": 0, "absorption": 0, "magcap": 0,
				"craft": kind,
				"recipe_id": rid,
				"bp": recipe_bp(base),
			}
            if scroll_key in by_key:
                for i, it in enumerate(items):
                    if it.get("key") == scroll_key:
                        # Сохраняем id, обновляем остальное
                        new_item["id"] = it.get("id", 0)
                        items[i] = new_item
                        break
            else:
                new_item["id"] = max(int(it.get("id", 0)) for it in items) + 1
                items.append(new_item)
            written += 1
            print("  OK %s -> %s (price=%d)" % (rid, icon_name, price))

    print("Recipe scrolls baked: %d" % written)
    if args.report:
        print("DRY-RUN")
        return 0
    with open(DB, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("OK: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.exit(main())
