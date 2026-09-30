"""Заводит Cloak и Cape из ЛЬНА — тряпки, а не металла.

ПРОБЛЕМА. Удаление 47 предметов с material="None" (gen_drop_none_items.py) унесло
все Cloak (5) и Cape (5) - это была единственная одежда без материала. Слот
"cloak" в EQUIP_SLOTS остался, и на кукле был пустой слот.

ПОЧЕМУ ЛЁН, А НЕ МЕТАЛЛ. Игрок уточнил прямо: плащ и рубашка - это тряпки.
Важны две вещи:
  * кузнец лён не переплавит: is_smeltable() смотрит поле material по списку
    _SMELTABLE, а "Linen" там нет. Металлический плащ был бы ходячим
    противоречием - он и "сталь", и "не варится";
  * armor_kind() относит Cloak/Cape к ткани по ТИПУ, а не по материалу, так
    что лён корректно даёт лёгкий набор анимации.

АРТ. Готовые текстуры лежат в assets/items/base/: light_cloak_* и heavy_cloak_*
по 4 тира. Фракционные faction/*_cloak_* (76 файлов) - это перекраска тех же
текстур в цвета металлов, и для тряпки они не используются: лён не металл.

Запуск:
    python tests/gen_cloak_items.py --dry-run
    python tests/gen_cloak_items.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
BASE = os.path.join(ROOT, "assets", "items", "base")

MATERIAL = "Linen"

# Тип -> (набор в base/, полное имя, короткое имя для ключа)
KINDS = {
    "Cloak": ("light", "Плащ", "Плащ"),
    "Cape":  ("heavy", "Накидка", "Накидка"),
}

QUALITY = {"cheap": "Cheap", "common": "Common", "good": "Good", "elite": "Elite"}
TIERS = ["cheap", "common", "good", "elite"]

# Цены плащей в базе до удаления держались в диапазоне 600-1200; берём верх
# диапазона, потому что лён здесь единственная тканевая броня.
PRICE = {"Cloak": 1200, "Cape": 900}

## Русское имя: качество + ткань. Например "Льняной плащ", "Плащ из льна".
## Форма подобрана так, чтобы читалось по-русски при любом качестве.
RU_QUALITY = {"cheap": "", "common": "Простой", "good": "Крепкий", "elite": "Лучший"}


def ru_name(qual: str, short: str) -> str:
    prefix = RU_QUALITY.get(qual, "")
    return ("%s %s из льна" % (prefix, short)).strip()


def round_price(v: float) -> int:
    return max(20, int(round(v / 20.0)) * 20)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        data = json.load(fh)

    existing = {str(i.get("key", "")) for i in data}
    next_id = max(int(i.get("id", 0)) for i in data) + 1
    new_items = []
    missing = []

    for typ, (aset, ru_full, ru_short) in KINDS.items():
        for tier in TIERS:
            art = os.path.join(BASE, "%s_cloak_%s.png" % (aset, tier))
            if not os.path.exists(art):
                missing.append(art)
                continue
            qual = QUALITY[tier]
            key = "%s %s %s" % (qual, MATERIAL, typ)
            if key in existing:
                continue
            new_items.append({
                "id": next_id,
                "key": key,
                "name_ru": ru_name(qual, ru_short),
                "name_en": "%s Linen %s" % (qual, typ),
                "quality": qual,
                "material": MATERIAL,
                "type": typ,
                "price": round_price(PRICE[typ]),
                "weight": 4.0,
                "damage_min": 0, "damage_max": 0, "to_hit": 0,
                "defence": 2, "absorption": 0, "magcap": 30,
                "level": 1, "effects": [],
                "icon": "",
            })
            next_id += 1

    if missing:
        print("НЕТ АРТА: %d" % len(missing))
        for m in missing:
            print("   ! %s" % os.path.basename(m))
        return 1

    print("СОЗДАНО: %d" % len(new_items))
    for i in new_items:
        print("  %-28s %-14s %6d" % (i["key"], i["name_ru"][:14], i["price"]))
    print("ПОСЛЕ: %d предметов" % (len(data) + len(new_items)))

    if args.dry_run:
        print("DRY-RUN: файлы не записаны")
        return 0

    with open(DB, "w", encoding="utf-8") as fh:
        json.dump(data + new_items, fh, ensure_ascii=False, indent=1)
    print("ГОТОВО: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())