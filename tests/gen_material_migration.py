"""Миграция материалов: фэнтезийные -> придуманные (assets/items/item_db.json).

Проект переходит с материалов оригинальной Allods II на собственный набор из
assets/loot_icons/README.md (19 материалов, разбитых по фракциям). Уходят:
адамантий, мифрил, метеорит, кристалл. Их иконки слитков уже покрашены под
элементные id (titanium/terbium/plutonium/radium) — blacksmith_panel.gd маппил
фэнтезийные названия в эти id, то есть визуально ничего не меняется, меняется
только название материала.

Материал вшит в ЧЕТЫРЕ поля (material, key, name_en, name_ru), поэтому замена
делается по значению поля material КАЖДОГО предмета, а не глобальным поиском:
иначе «Crystal» зацепил бы чужие названия.

Запуск:
    python tests/gen_material_migration.py            # применить
    python tests/gen_material_migration.py --dry-run  # только показать
"""
import argparse
import json
import os
import re
import sys

DB = os.path.join(os.path.dirname(__file__), "..", "assets", "items", "item_db.json")
CATALOG = os.path.join(os.path.dirname(__file__), "..", "assets", "maps", "inventory_catalog.json")

# Короткое имя в редакторном каталоге (inventory_catalog.gd) -> длинное.
SHORT_TO_LONG = {
    "adamant": "titanium",
    "mithril": "terbium",
    "meteor":  "plutonium",
    "crystal": "radium",
}

# старое имя материала -> (новое имя, русское слово, новое русское слово)
# Русские формы проверены по item_db.json: у каждого материала ровно одна
# словоформа, отдельным токеном, с маленькой буквы ("Эльфийский адамантий Амулет").
RENAMES = {
    "Adamantium": ("Titanium", "адамантий", "титаний"),
    "Mithrill":   ("Terbium",   "мифрил",   "тербий"),
    "Meteoric":   ("Plutonium", "метеорит", "плутоний"),
    "Crystal":    ("Radium",    "кристалл", "радий"),
}

EXPECTED_TOTAL = 152  # 61 + 43 + 32 + 16


def migrate_catalog(dry_run=False):
    """Переименовать категории в assets/maps/inventory_catalog.json.

    Файл — редакторный каталог иконок: "иконка.png" -> {cat, quality}, где cat
    вида "weapon_adamant". Без миграции эти записи указывали бы на несуществующие
    категории после правки inventory_catalog.gd.
    """
    with open(CATALOG, "r", encoding="utf-8") as f:
        catalog = json.load(f)
    changed = 0
    for entry in catalog.values():
        cat = entry.get("cat", "")
        for short, long in SHORT_TO_LONG.items():
            if cat.endswith("_" + short):
                entry["cat"] = cat[: -len(short)] + long
                cat = entry["cat"]
                changed += 1
                break
    if dry_run:
        print("КАТАЛОГ: изменено категорий %d (dry-run)" % changed)
        return changed
    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, separators=(",", ":"))
    print("КАТАЛОГ: изменено категорий %d" % changed)
    return changed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    with open(DB, "r", encoding="utf-8") as f:
        data = json.load(f)

    touched = {}
    for item in data:
        old = item.get("material")
        if old not in RENAMES:
            continue
        new, ru_old, ru_new = RENAMES[old]
        item["material"] = new
        # key и name_en: английский токен материала ("Elven Adamantium Amulet")
        if "key" in item:
            item["key"] = item["key"].replace(old, new)
        if "name_en" in item:
            item["name_en"] = item["name_en"].replace(old, new)
        # name_ru: только целое слово, иначе «кристалл» заденет «кристальный»
        if "name_ru" in item:
            item["name_ru"] = re.sub(
                r"\b%s\b" % re.escape(ru_old), ru_new, item["name_ru"])
        touched[old] = touched.get(old, 0) + 1

    # Контроль: старых имён не осталось нигде в выгрузке.
    dump = json.dumps(data, ensure_ascii=False)
    leftovers = {}
    for old, (new, ru_old, ru_new) in RENAMES.items():
        hits = dump.count(old) + dump.count(ru_old)
        if hits:
            leftovers[old] = hits

    total = sum(touched.values())
    for old in sorted(RENAMES):
        print("  %-10s -> %-10s %3d предметов" % (old, RENAMES[old][0], touched.get(old, 0)))
    print("МИГРАЦИЯ: изменено %d из %d (ожидалось %d)" % (total, len(data), EXPECTED_TOTAL))
    if leftovers:
        print("ОСТАЛИСЬ СТАРЫЕ ИМЕНА: %s" % leftovers)
        sys.exit(1)
    # 0 — файл уже мигрирован (повторный прогон не должен быть ошибкой),
    # иначе ровно EXPECTED_TOTAL. Любое другое число — расхождение с данными.
    if total not in (0, EXPECTED_TOTAL):
        print("ВНИМАНИЕ: ожидалось %d предметов, изменено %d" % (EXPECTED_TOTAL, total))
        sys.exit(1)
    if total == 0:
        print("МИГРАЦИЯ: item_db.json уже мигрирован")

    if args.dry_run:
        migrate_catalog(True)
        print("DRY-RUN: файлы не записаны")
        return

    # Отступ 1 пробел и БЕЗ хвостового перевода строки — как в исходном файле,
    # иначе diff на весь файл.
    with open(DB, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("ГОТОВО: %s" % DB)
    migrate_catalog()

if __name__ == "__main__":
    main()
