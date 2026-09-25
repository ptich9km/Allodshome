"""Добавляет предметы-слитки в assets/items/item_db.json.

Слиток — результат переплавки брони/оружия в кузнице: игрок приносит вещь,
кузнец отдаёт слиток её материала. Раньше blacksmith_panel.gd только показывал
иконку слитка в панели и НИЧЕГО не отдавал — предмет просто исчезал.

Набор — 9 переплавляемых металлов (кожа, дерево и ткань кузнец не берут,
решение игрока). Неметаллические псевдо-слитки (Leather->wolfram и подобные)
из blacksmith_panel.gd удалены: переплавка кожи в металл бессмыслична.

id иконок — из assets/loot_icons/README.md (19 материалов по фракциям);
5 из них (lanthanum, thorium, uranium, promethium, neodymium) оставлены в
резерве под будущий контент, поэтому слитков здесь 9, а не 14.

Запуск:
    python tests/gen_ingot_items.py            # добавить/обновить
    python tests/gen_ingot_items.py --dry-run  # только показать
"""
import argparse
import json
import os
import sys

DB = os.path.join(os.path.dirname(__file__), "..", "assets", "items", "item_db.json")
ICON_DIR = "res://assets/professions/blacksmith"

# материал в item_db -> (id иконки, русское название в родительном падеже, вес, доля цены)
METALS = {
    "Bronze":   ("bronze",    "бронзы",    2.0, 0.30),
    "Iron":     ("iron",      "железа",    2.0, 0.30),
    "Steel":    ("steel",     "стали",     2.5, 0.35),
    "Silver":   ("argentum",  "серебра",   1.5, 0.30),
    "Gold":     ("lutetium",  "золота",    1.5, 0.30),
    "Titanium": ("titanium",  "титания",   2.0, 0.30),
    "Terbium":  ("terbium",   "тербия",    1.5, 0.30),
    "Plutonium": ("plutonium", "плутония", 2.5, 0.30),
    "Radium":   ("radium",    "радия",     1.5, 0.30),
}

# Порядок полей — как в существующих записях, иначе diff на весь файл.
FIELDS = ["id", "key", "name_ru", "name_en", "quality", "material", "type",
          "price", "weight", "level", "damage_min", "damage_max", "defence",
          "absorption", "to_hit", "magcap", "effects", "icon"]

# Не экипировать: type, который нельзя надеть. Слиток не броня, хотя
# ItemDB.slot_of() относит всё не-оружие-не-щит к "armor".
NON_EQUIP_TYPE = "Ingot"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    with open(DB, "r", encoding="utf-8") as f:
        data = json.load(f)

    by_key = {it.get("key"): it for it in data}
    max_id = max(int(it.get("id", 0)) for it in data)
    # Цена слитка — от САМОЙ дешёвой вещи из этого металла, а не от средней:
    # средняя смещена самыми дорогими предметами (радиевый амулет 900 000), и
    # слиток вышел бы дороже большинства снаряжения. Инвариант: слиток всегда
    # дешевле любого предмета своего материала — это проверяет blacksmith_smoke.
    min_price = {}
    for it in data:
        m = it.get("material")
        if m in METALS and it.get("price"):
            p = int(it["price"])
            min_price[m] = min(min_price.get(m, p), p)

    added, updated = 0, 0
    for metal, (icon_id, ru_gen, weight, price_share) in METALS.items():
        key = "%s Ingot" % metal
        base = min_price.get(metal, 1000)
        price = int(round(base * price_share / 10.0) * 10) or 10
        # Инвариант строгий: слиток дешевле ЛЮБОЙ вещи из своего материала.
        # Бронза — исключение: самая дешёвая бронзовая вещь стоит 3, поэтому
        # «30% от минимума» давало 10 и слиток оказывался дороже.
        price = max(1, min(price, base - 1))
        entry = {
            "key": key,
            "name_ru": "Слиток %s" % ru_gen,
            "name_en": "%s Ingot" % metal,
            "quality": "Common",
            "material": metal,
            "type": NON_EQUIP_TYPE,
            "price": price,
            "weight": weight,
            "level": 1,
            "damage_min": 0,
            "damage_max": 0,
            "defence": 0,
            "absorption": 0,
            "to_hit": 0,
            "magcap": 0,
            "effects": [],
            "icon": "%s/%s_ingot.png" % (ICON_DIR, icon_id),
        }
        if key in by_key:
            # Обновляем на месте, id не трогаем (иначе ломаются ссылки).
            for field, value in entry.items():
                by_key[key][field] = value
            updated += 1
            print("  %-18s обновлён" % key)
        else:
            max_id += 1
            entry["id"] = max_id
            ordered = {}
            for field in FIELDS:
                ordered[field] = entry[field]
            data.append(ordered)
            by_key[key] = ordered
            added += 1
            print("  %-18s добавлен (id=%d, цена=%d, %s)"
                  % (key, max_id, price, entry["icon"]))

    print("СЛИТКИ: добавлено %d, обновлено %d, всего металлов %d" % (added, updated, len(METALS)))

    if args.dry_run:
        print("DRY-RUN: файл не записан")
        return

    with open(DB, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("ГОТОВО: %s (предметов: %d)" % (DB, len(data)))


if __name__ == "__main__":
    main()
