"""Создаёт «сломанные вещи» для мастерской + ткань и магическую эссенцию.

ЗАЧЕМ. Игровая петля пакета 1 (07.10):
    убил НПЦ -> сломанная вещь -> кузнец/портной -> слитки + ткань + эссенция
    -> рецепт -> новая вещь.
Металл в игре существует ТОЛЬКО как производная от убитых НПЦ.

ЧТО СОЗДАЁТСЯ (125 записей):
    60  сломанная броня    = 20 металлов x 3 качества
    60  сломанное оружие   = 20 металлов x 3 качества
     3  сломанная одежда   = Linen x 3 качества
     1  Fabric             (ткань)
     1  Magic Essence      (магическая эссенция)

КЛЮЧЕВЫЕ ИНВАРИАНТЫ (каждый проверяется тестом craft_items_smoke):

  * `damage_min`/`damage_max`/`to_hit`/`defence`/`absorption`/`magcap` = 0.
    НЕ из эстетики. metal_stats_smoke:145-147 отбрасывает предметы с
    damage_max <= 0 ПЕРЕД проверкой монотонности - если поставить тут
    положительные числа, 123 новых предмета сломают формулу статов.
    Нулевые defence/absorption/magcap - потому что player.get_defense()/
    get_absorption()/_sphere_protection() суммируют их ПО ВСЕМУ инвентарю
    игрока (`_equipped_items()`), и сломанная вещь в рюкзаке начала бы
    менять характеристики героя.

  * `price` = 0. shop_panel._build_sell_list() продаёт весь инвентар за
    `price / sell_price_div`, а `maxi(1, 0)` = 1 золота за штуку. При
    price=1 сломанная вещь стоила бы 1 золота и обходила петлю
    «убил НПЦ -> купил слиток за 1 золото». Цену сломанной вещи задаёт
    рецепт, а не рынок. Продажа их исключается явной фильтрацией.

  * `material` = металл => is_smeltable() == true (вход кузнеца).
    `Linen`/`Fabric`/`Essence` НЕ входят в ItemDB._SMELTABLE, поэтому
    is_smeltable() для них false автоматически, без правок item_db.gd.

  * `material: "Linen"` у сломанной одежды => armor_kind() == "light".
    item_db.gd:161 проверяет `material in ["Linen", "None"]`. Ровно то,
    что нужно: одежда не должна считаться тяжёлой бронёй.

  * `type` не входит ни в один список слотов ItemDB, поэтому slot_of()
    вернёт "" - надеть сломанное нельзя ДВОЙНЫМ заслоном (плюс quality
    в blacklist is_equippable).

  * Сегмент материала в `key` == поле `material` в точном регистре.
    Это контракт tests/item_key_literal_smoke.gd:111. Отсюда порядок
    `Broken [Fine|Rare] {material} {Category}`, а не `Broken {material}`.

  * Русское слово металла обязательно в `name_ru` - контракт
    material_migration_smoke.gd:246 проверяет это для каждого
    металлического предмета.

  * Иконки: свои, в assets/items/broken/. Нельзя указывать на
    assets/loot_icons/ напрямую - item_icons_smoke.gd:120-122 запрещает
    неметаллам указывать в faction/, а validator для металлов принимает
    только faction/, faction_w/, base/, base_w/.

ФОРМАТ ПРАВКИ. item_db.json - плоский массив, каждое поле на своей строке
(indent=1), и ПРОВЕРЕНО замером, что json.dumps(indent=1) round-trip даёт
байт-в-байт совпадение + один завершающий перевод строки. Поэтому здесь
можно пересобирать файл json-модулем, в отличие от баз с многострочными
массивами (см. запись 03.10 про gen_material_migration.py).

Запуск:
    python tests/gen_broken_items.py --dry-run
    python tests/gen_broken_items.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
ICON_DIR = os.path.join(ROOT, "assets", "items", "broken")

# Порядок = ItemDB._SMELTABLE (item_db.gd). Держать синхронно.
METALS = [
    "bronze", "iron", "steel", "gold", "argentum",
    "lutetium", "lanthanum", "terbium", "wolfram", "chromium",
    "cobalt", "titanium", "thorium", "uranium", "plutonium",
    "radium", "gallium", "yttrium", "promethium", "neodymium",
]

# Тот же словарь, что tests/material_migration_smoke.gd:46 RU_WORD, но в
# склонённой форме женского рода («бронзовая броня»). Род меняется через
# agree(). ВАЖНО: проверка в material_migration_smoke ищет в name_ru ОСНОВУ
# из RU_WORD («тербий», «ради», ...), поэтому форма обязана содержать эту
# основу подстрокой. «тербиевая» основу «тербий» НЕ содержит (е != й) -
# отсюда «тербийская». RU_STEM ниже - контракт, он проверяется в тесте.
RU_METAL = {
    "bronze": "бронзовая", "iron": "железная", "steel": "стальная",
    "gold": "золотая", "argentum": "аргентумовая", "lutetium": "лютецевая",
    "lanthanum": "лантановая", "terbium": "тербийская", "wolfram": "вольфрамовая",
    "chromium": "хромовая", "cobalt": "кобальтовая", "titanium": "титановая",
    "thorium": "торийская", "uranium": "урановая", "plutonium": "плутониевая",
    "radium": "радиевая", "gallium": "галлиевая", "yttrium": "иттриевая",
    "promethium": "прометиевая", "neodymium": "неодимовая",
}

# Побайтовая копия RU_WORD из tests/material_migration_smoke.gd:46.
RU_STEM = {
    "bronze": "бронз", "iron": "желез", "steel": "стал", "gold": "золот",
    "argentum": "аргентум", "lutetium": "лютец", "lanthanum": "лантан",
    "terbium": "тербий", "wolfram": "вольфрам", "chromium": "хром",
    "cobalt": "кобальт", "titanium": "титан", "thorium": "торий",
    "uranium": "уран", "plutonium": "плутони", "radium": "ради",
    "gallium": "галли", "yttrium": "иттри", "promethium": "промети",
    "neodymium": "неодим",
}

RU_GARMENT_MATERIAL = "льняная"

# Сломанная вещь: тип -> (подтип ключа, русский сущ, род прилагательного, вес).
# Род обязателен: «Сломанная броня», но «Сломанное оружие». Без него
# получается «Сломанная оружие бронзовая» - имена читаются как ошибка.
CATEGORIES = {
    "Armor":   ("Armor",  "броня",  "f", 8.0),
    "Weapon":  ("Weapon", "оружие", "n", 4.0),
}

# Качество -> (префикс ключа, множитель веса).
# Русские прилагательные собираются по роду из CATEGORIES, поэтому здесь их
# нет: «добротная/добротное» и «редкая/редкое» различаются родом.
QUALITIES = [
    ("Broken",      "",    1.0),
    ("Broken Fine", "Fine", 0.8),
    ("Broken Rare", "Rare", 0.6),
]

RU_ADJ = {
    "f": "ая",   # броня / одежда
    "n": "ое",   # оружие
}
RU_ADJ_FINE = {"f": "добротная", "n": "добротное"}
RU_ADJ_RARE = {"f": "редкая", "n": "редкое"}


def agree(word: str, gender: str) -> str:
    """Согласовать прилагательные (в т.ч. многословные) с нужным родом.

    Все значения словарей ниже записаны в форме женского рода («бронзовая»,
    «Сломанная добротная»), потому что женский род - самая частая категория.
    Средний род получается отбрасыванием окончания «ая» у КАЖДОГО слова и
    присоединением нужного: «Сломанное добротное оружие», «бронзовое
    оружие». Согласование только последнего слова давало «Сломанная
    добротное оружие» - читается как ошибка.
    """
    return " ".join(
        (w[:-2] if w.endswith("ая") else w) + RU_ADJ[gender] for w in word.split(" ")
    )


def ru_adjective(quality: str, gender: str) -> str:
    """«Сломанная» / «Сломанная добротная» / «Сломанное редкое» по роду."""
    if quality == "Broken":
        return agree("Сломанная", gender)
    if quality == "Broken Fine":
        return agree("Сломанная добротная", gender)
    return agree("Сломанная редкая", gender)


def broken_key(material: str, category: str, quality: str) -> str:
    parts = ["Broken"]
    if quality != "Broken":
        parts.append(quality.split(" ", 1)[1])
    parts.append(material)
    parts.append(category)
    return " ".join(parts)


def broken_name_ru(category_ru: str, material_ru: str, adjective: str) -> str:
    return ("%s %s %s" % (adjective, category_ru, material_ru)).strip()


def icon_for(material: str, category: str) -> str:
    slot = "armor" if category == "Armor" else "weapon"
    if material == "Linen":
        return "res://assets/items/broken/linen_garment.png"
    return "res://assets/items/broken/%s_%s.png" % (material, slot)


def make_broken(material: str, category: str, quality: str, ru_cat: str,
                gender: str, base_weight: float, weight_mult: float) -> dict:
    material_ru = agree(RU_METAL.get(material, RU_GARMENT_MATERIAL), gender)
    return {
        "id": 0,
        "key": broken_key(material, category, quality),
        "name_ru": broken_name_ru(ru_cat, material_ru, ru_adjective(quality, gender)),
        "name_en": "%s %s %s" % (quality, material, category),
        "quality": quality,
        "material": material,
        "type": "Broken " + category,
        "price": 0,
        "weight": round(base_weight * weight_mult, 1),
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 0, "absorption": 0, "magcap": 0,
        "level": 1, "effects": [],
        "icon": icon_for(material, category),
    }


def resources() -> list:
    return [
        {
            "id": 0,
            "key": "Fabric",
            "name_ru": "Ткань",
            "name_en": "Fabric",
            "quality": "Fabric",
            "material": "Fabric",
            "type": "Fabric",
            "price": 0,
            "weight": 0.2,
            "damage_min": 0, "damage_max": 0, "to_hit": 0,
            "defence": 0, "absorption": 0, "magcap": 0,
            "level": 1, "effects": [],
            "icon": "res://assets/professions/workshop/fabric.png",
        },
        {
            "id": 0,
            "key": "Magic Essence",
            "name_ru": "Магическая эссенция",
            "name_en": "Magic Essence",
            "quality": "Essence",
            "material": "Essence",
            "type": "Essence",
            "price": 0,
            "weight": 0.1,
            "damage_min": 0, "damage_max": 0, "to_hit": 0,
            "defence": 0, "absorption": 0, "magcap": 0,
            "level": 1, "effects": [],
            "icon": "res://assets/professions/workshop/magic_essence.png",
        },
    ]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        raw = fh.read()
    data = json.loads(raw)

    existing = {str(i.get("key", "")) for i in data}
    next_id = max(int(i.get("id", 0)) for i in data) + 1

    new_items = []
    for material in METALS:
        for category, (_sub, ru_cat, gender, base_weight) in CATEGORIES.items():
            for quality, _prefix, weight_mult in QUALITIES:
                item = make_broken(material, category, quality, ru_cat,
                                   gender, base_weight, weight_mult)
                if item["key"] in existing:
                    continue
                item["id"] = next_id
                next_id += 1
                new_items.append(item)

    for quality, _prefix, weight_mult in QUALITIES:
        item = make_broken("Linen", "Garment", quality, "одежда", "f",
                           2.0, weight_mult)
        if item["key"] in existing:
            continue
        item["id"] = next_id
        next_id += 1
        new_items.append(item)

    for item in resources():
        if item["key"] in existing:
            continue
        item["id"] = next_id
        next_id += 1
        new_items.append(item)

    # --- Инварианты до записи: генератор, который может записать хлам,
    # хуже, чем отсутствие генератора.
    problems = []
    by_key = {}
    for item in new_items:
        by_key[item["key"]] = item
        for field in ("damage_min", "damage_max", "to_hit", "defence",
                      "absorption", "magcap"):
            if item[field] != 0:
                problems.append("%s: %s != 0" % (item["key"], field))
        if item["price"] != 0:
            problems.append("%s: price != 0" % item["key"])
        if item["material"] in METALS and item["material"] not in item["key"]:
            problems.append("%s: сегмент материала != полю material" % item["key"])
        if item["material"] in RU_STEM and RU_STEM[item["material"]] not in item["name_ru"]:
            problems.append("%s: нет основы металла '%s' в name_ru '%s'"
                            % (item["key"], RU_STEM[item["material"]], item["name_ru"]))
    for metal in METALS:
        for category in CATEGORIES:
            for quality, _p, _w in QUALITIES:
                key = broken_key(metal, category, quality)
                if key not in by_key:
                    problems.append("нет записи %s" % key)
    for quality, _p, _w in QUALITIES:
        key = broken_key("Linen", "Garment", quality)
        if key not in by_key:
            problems.append("нет записи %s" % key)

    if problems:
        print("ИНВАРИАНТЫ НАРУШЕНЫ: %d" % len(problems))
        for p in problems[:20]:
            print("   ! %s" % p)
        return 1

    print("Новых записей: %d" % len(new_items))
    print("  сломанная броня:   %d" % sum(
        1 for i in new_items if i["type"] == "Broken Armor"))
    print("  сломанное оружие:  %d" % sum(
        1 for i in new_items if i["type"] == "Broken Weapon"))
    print("  сломанная одежда:  %d" % sum(
        1 for i in new_items if i["type"] == "Broken Garment"))
    print("  ресурсы:           %d" % sum(
        1 for i in new_items if i["type"] in ("Fabric", "Essence")))
    print("Всего предметов: %d -> %d" % (len(data), len(data) + len(new_items)))
    print("Примеры:")
    for item in new_items[:4]:
        print("  %-32s %-34s %s" % (item["key"], item["name_ru"], item["icon"]))

    if args.dry_run:
        print("DRY-RUN: база не изменена")
        return 0

    payload = json.dumps(data + new_items, ensure_ascii=False, indent=1) + "\n"
    # Страховка от молчаливого переформатирования: файл обязан остаться
    # тем же стилем. Если round-trip исходника уже не байт-в-байт, значит
    # формат поменялся и пересборка разъедется по всему файлу.
    if json.dumps(data, ensure_ascii=False, indent=1) + "\n" != raw:
        print("ВНИМАНИЕ: round-trip исходника не байт-в-байт - формат базы изменился")
        print("          пересборка разъедется. Правь вручную.")
        return 2

    with open(DB, "w", encoding="utf-8", newline="") as fh:
        fh.write(payload)
    print("Записано: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())