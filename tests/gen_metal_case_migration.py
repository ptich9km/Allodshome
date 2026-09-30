"""Миграция материалов item_db.json: Metal -> metal, удаление silver.

ЗАЧЕМ НИЖНИЙ РЕГИСТР. Материал - это ключ, по которому предмет ищет иконку
(`assets/items/faction/{group}/{metal}_*`), иконку слитка
(`assets/professions/blacksmith/{material}_ingot.png`) и категорию каталога.
Все эти имена на диске в нижнем регистре, а в базе было "Bronze" - то есть
связь держалась на ручном маппинге, который однажды и отвалился бы при
добавлении металла. Регистр приводится к тому, что на диске.

НЕ ТРОГАЕМ неметаллы: "None", "Wood", "Leather", "Hard Leather",
"Dragon Leather", "Magic Wood" остаются с заглавной. Причина измерена, а не
предположена: кузница отбирает предметы через is_smeltable(), а та проверяет
material in _SMELTABLE, где только металлы. Дерево и кожа в кузницу не попадают
никогда, поэтому единообразие им ничего не даёт, а смена регистра затронула бы
armor_kind() в item_db.gd.

SILVER УДАЛЯЕТСЯ: это пережиток Аллодов, заменён argentum. 7 предметов.

Запуск:
    python tests/gen_metal_case_migration.py --dry-run
    python tests/gen_metal_case_migration.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")

# 20 металлов палитры в том регистре, в каком они на диске.
PALETTE_METALS = [
    "bronze", "iron", "steel", "gold",
    "argentum", "lutetium", "lanthanum", "terbium",
    "wolfram", "chromium", "cobalt", "titanium",
    "thorium", "uranium", "plutonium", "radium",
    "gallium", "yttrium", "promethium", "neodymium",
]

# Материал, который уходит совсем (пережиток Аллодов, заменён argentum).
DROP_MATERIALS = {"Silver"}

EXPECTED_SILVER = 7

# Русские имена металлов для name_ru. Нужны, потому что материал вшит в ЧЕТЫРЕ
# поля, и оставить "Серебряный" в name_ru при удалении серебра нельзя.
RU = {
    "bronze": "бронза", "iron": "железо", "steel": "сталь", "gold": "золото",
    "argentum": "аргентум", "lutetium": "лютеций", "lanthanum": "лантан",
    "terbium": "тербий", "wolfram": "вольфрам", "chromium": "хром",
    "cobalt": "кобальт", "titanium": "титаний", "thorium": "торий",
    "uranium": "уран", "plutonium": "плутоний", "radium": "радий",
    "gallium": "галлий", "yttrium": "иттрий", "promethium": "прометий",
    "neodymium": "неодим",
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        data = json.load(fh)

    before = len(data)

    # 1. выкинуть серебро
    dropped = [i for i in data if str(i.get("material", "")) in DROP_MATERIALS]
    data = [i for i in data if str(i.get("material", "")) not in DROP_MATERIALS]

    # 2. металлы в нижний регистр, во всех четырёх полях
    changed = {}
    ingot_keys = {}
    for item in data:
        m = str(item.get("material", ""))
        low = m.lower()
        if low not in PALETTE_METALS or m == low:
            continue
        # key и name_en: английский токен материала
        for f in ("key", "name_en"):
            if f in item:
                item[f] = item[f].replace(m, low)
        # Слитки новых 12 металлов родились с ключом "Argentum Ingot" (с заглавной),
        # а старые 8 - "Bronze Ingot". Оба варианта надо привести к одному виду,
        # иначе ingot_key() найдёт только половину слитков.
        if item.get("type") == "Ingot":
            ingot_keys[item["key"]] = low
        # name_ru: по СЛОВУ, иначе "золото" внутри "золотой" - да, поэтому
        # заменяем только словоформу с заглавной, стоящую отдельным словом.
        if "name_ru" in item and m in RU:
            import re
            item["name_ru"] = re.sub(r"\b%s\b" % re.escape(m), RU[low].capitalize(),
                                     item["name_ru"])
        item["material"] = low
        changed[m] = changed.get(m, 0) + 1

    # 2a. единый вид ключа слитка: "%metal% Ingot" (материал в нижнем регистре)
    for item in data:
        if item.get("type") != "Ingot":
            continue
        mat = str(item.get("material", "")).lower()
        want = "%s Ingot" % mat
        if item["key"] != want:
            item["key"] = want
        en = "%s Ingot" % mat.capitalize()
        if item.get("name_en") != en:
            item["name_en"] = en
        ru_word = RU.get(mat, mat)
        ru = "Слиток %s" % ru_word.lower()
        if item.get("name_ru") != ru:
            item["name_ru"] = ru

    print("УДАЛЕНО silver-предметов: %d (ожидалось %d)" % (len(dropped), EXPECTED_SILVER))
    if len(dropped) != EXPECTED_SILVER:
        print("! число серебряных предметов изменилось - перечитай миграцию")
        return 1
    for m in sorted(changed):
        print("  %-12s -> %-12s %3d предметов" % (m, m.lower(), changed[m]))
    print("ПЕРЕИМЕНОВАНО: %d предметов" % sum(changed.values()))
    print("БЫЛО %d, СТАЛО %d" % (before, len(data)))

    # 3. контроль: металлы в нижнем регистре, серебра нет
    bad_case = {}
    for i in data:
        m = str(i.get("material", ""))
        if m in PALETTE_METALS and m != m.lower():
            bad_case[m] = bad_case.get(m, 0) + 1
    if bad_case:
        print("! ОСТАЛСЯ ЗАГЛАВНЫЙ РЕГИСТР: %s" % bad_case)
        return 1
    if any(str(i.get("material", "")) in DROP_MATERIALS for i in data):
        print("! серебро осталось в базе")
        return 1
    # 4. контроль: ключи слитков строятся из материала с заглавной
    ingots = [i for i in data if i.get("type") == "Ingot"]
    print("СЛИТКОВ: %d -> %s" % (len(ingots), ", ".join(sorted(i["key"] for i in ingots))))
    # единый вид ключа: материал в нижнем регистре, иначе ingot_key() найдёт
    # только часть слитков (старые 8 были с заглавной, новые 12 тоже)
    for i in ingots:
        want = "%s Ingot" % str(i.get("material", "")).lower()
        if i["key"] != want:
            print("! КЛЮЧ СЛИТКА В РАЗНЫХ РЕГИСТРАХ: %s (хотим %s)" % (i["key"], want))
            return 1
    missing = [m for m in PALETTE_METALS
               if not any(i.get("type") == "Ingot" and i.get("material") == m for i in data)]
    if missing:
        print("! НЕТ СЛИТКА ДЛЯ: %s" % ", ".join(missing))
        return 1

    if args.dry_run:
        print("DRY-RUN: файлы не записаны")
        return 0

    # Отступ 1 пробел, без хвостового перевода строки - как в исходном файле,
    # иначе diff на весь файл (см. gen_material_migration.py).
    with open(DB, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    print("ГОТОВО: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
