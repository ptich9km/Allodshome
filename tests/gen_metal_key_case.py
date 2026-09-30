"""Приводит ключи/имена 12 новых металлов к нижнему регистру материала.

ЗАЧЕМ. Перевод металлов в нижний регистр (gen_metal_case_migration.py) прошёл
по ВСЕМ материалам, но новые предметы для 12 пустых металлов
(gen_empty_metals_items.py) были созданы позже и получили ключи вида
"Elven Argentum Amulet" - с заглавного материала. Итог: в базе два стиля
сразу, и литерал "Rare Argentum Cuirass" не совпадает ни с каким-либо
правилом, по которому пишутся остальные ("Rare radium Cuirass").

Это не косметика: ключ предмета - его идентификатор, и любая выборка по нему
(тесты, сохранения, скрипты) обязана иметь одно правило.

Правило: металл в ключе в нижнем регистре (bronze, argentum, radium),
неметаллы без изменений (Leather, Wood, Magic Wood - они по решению игрока
остались с заглавной).

Запуск:
    python tests/gen_metal_key_case.py --dry-run
    python tests/gen_metal_key_case.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")

METALS = [
    "bronze", "iron", "steel", "gold",
    "argentum", "lutetium", "lanthanum", "terbium",
    "wolfram", "chromium", "cobalt", "titanium",
    "thorium", "uranium", "plutonium", "radium",
    "gallium", "yttrium", "promethium", "neodymium",
]

# Материал -> (слово в ключе с заглавной, тоже самое в нижнем).
CAP = {m: m.capitalize() for m in METALS}

# Слова качества, с которых начинается ключ: "Rare Argentum Cuirass".
QUALITIES = [
    "Bad", "Common", "Uncommon", "Good", "Rare", "Very Rare", "Elven",
    "Book", "Scroll", "SuperScroll", "Quest", "Potion", "Herb",
]


def fix_key(key: str, material: str) -> str:
    """Заменяет Слово Материала в ключе на строчное."""
    cap = CAP.get(material)
    if not cap:
        return key
    # слитки: "Argentum Ingot" -> "argentum Ingot"
    if key == "%s Ingot" % cap:
        return "%s Ingot" % material
    # остальные: "<Качество> Argentum <Тип>"
    for q in sorted(QUALITIES, key=len, reverse=True):
        if key.startswith("%s %s " % (q, cap)):
            return "%s %s %s" % (q, material, key[len("%s %s " % (q, cap)):])
    if (" %s " % cap) in key:
        return key.replace(" %s " % cap, " %s " % material)
    return key


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        data = json.load(fh)

    changed = 0
    seen: dict = {}
    for item in data:
        mat = str(item.get("material", ""))
        if mat not in METALS:
            continue
        key = str(item.get("key", ""))
        new_key = fix_key(key, mat)
        if new_key != key:
            item["key"] = new_key
            # name_en повторяет ключ без префикса качества у части предметов;
            # приводим тот же токен материала, если он там есть
            en = str(item.get("name_en", ""))
            cap = CAP[mat]
            if en.startswith("%s " % cap):
                item["name_en"] = "%s %s" % (material, en[len(cap) + 1:])
            changed += 1
        seen[item["key"]] = mat

    print("ИСПРАВЛЕНО КЛЮЧЕЙ: %d" % changed)
    if args.dry_run:
        print("DRY-RUN: файлы не записаны")
        return 0

    # контроль: после правки ключ уникален
    keys = [str(i.get("key", "")) for i in data]
    dups = sorted({k for k in keys if keys.count(k) > 1})
    if dups:
        print("! ДУБЛИ КЛЮЧЕЙ: %s" % dups[:6])
        return 1

    with open(DB, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    print("ГОТОВО: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())