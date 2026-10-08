"""Добавляет малые зелья лечения/маны в item_db.json (upsert).

Medium = +30 HP/mana за 1000з. Small = +12 за 250з.
Иконки те же (health_medium/mana_medium) — визуально отличаются ценой и эффектом.
"""

from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")

SMALL = [
    {
        "key": "Potion Small Healing",
        "name_ru": "Зелье малого лечения",
        "name_en": "Potion of Minor Healing",
        "quality": "Potion",
        "material": None,
        "type": "Small Healing",
        "price": 250,
        "weight": 1.0,
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 0, "absorption": 0, "magcap": 0,
        "level": 1,
        "effects": ["health=+12"],
        "icon": "res://assets/potions/health_medium.png",
    },
    {
        "key": "Potion Small Mana",
        "name_ru": "Зелье малой маны",
        "name_en": "Potion of Minor Mana",
        "quality": "Potion",
        "material": None,
        "type": "Small Mana",
        "price": 250,
        "weight": 1.0,
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 0, "absorption": 0, "magcap": 0,
        "level": 1,
        "effects": ["mana=+12"],
        "icon": "res://assets/potions/mana_medium.png",
    },
]


def main() -> int:
    with open(DB, encoding="utf-8") as f:
        data = json.load(f)
    by_key = {str(it.get("key", "")): i for i, it in enumerate(data)}
    next_id = max(int(it.get("id", 0)) for it in data) + 1
    n = 0
    for spec in SMALL:
        if spec["key"] in by_key:
            data[by_key[spec["key"]]] = {**data[by_key[spec["key"]]], **spec}
            n += 1
            print("  update", spec["key"])
        else:
            item = dict(spec)
            item["id"] = next_id
            next_id += 1
            data.append(item)
            n += 1
            print("  add", spec["key"])
    with open(DB, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("OK: %d potions" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
