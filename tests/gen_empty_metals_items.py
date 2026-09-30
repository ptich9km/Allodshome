"""Заводит предметы для 12 металлов, которым в базе не досталось ни одного.

ПРОБЛЕМА. Арт готов для всех 20 металлов (18 брони + 13 оружия на металл), а
предметы есть только у 8. У каждой фракции наполнен только последний тир, у
Пожинателей два последних - наследие переезда с Аллодов (мифрил->тербий и др.).
Итог: 852 готовые текстуры, на которые нельзя повесить ни один предмет, и 12
металлов, которые не попадают ни в кузню, ни в каталог магазина.

ОБРАЗЕЦ - terbium (43 предмета + слиток): всё оружие _WEAPON_TYPES, броня всех
типов, щиты _SHIELD_TYPES, амулеты и кольца. Набор берём оттуда, поэтому у всех
12 металлов одинаковое покрытие слотов и ни один тип не остаётся без аналога.

ЦЕНЫ - по фактической лестнице проекта, а не придуманной. Множитель металла
считается из цены его слитка относительно слитка terbium: цены предметов в
item_db коррелируют с ценой слитка (проверено: Rare Full Helm terbium 7200 при
слитке 40, titanium 27000 при слитке 160 - ровно та же кратность 3.75).
Цена округляется до 20: в базе цены круглые (800, 1600, 3200, 5440...), и
произвольные хвосты выглядели бы как ошибка.

Запуск:
    python tests/gen_empty_metals_items.py --dry-run
    python tests/gen_empty_metals_items.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
PALETTE = os.path.join(ROOT, "assets", "items", "faction_palette.json")

# Металл -> группа палитры (для проверки, что он существует).
EMPTY_METALS = [
    ("argentum", "light_alliance"),
    ("lutetium", "light_alliance"),
    ("lanthanum", "light_alliance"),
    ("wolfram", "fire_hordes"),
    ("chromium", "fire_hordes"),
    ("cobalt", "fire_hordes"),
    ("thorium", "reapers"),
    ("uranium", "reapers"),
    ("gallium", "druid_circle"),
    ("yttrium", "druid_circle"),
    ("promethium", "druid_circle"),
    ("neodymium", "druid_circle"),
]

# Цена слитка на металл. Взята из фактического поведения item_db, см. ниже.
# Слитки terbium=40, titanium=160, radium=12150, plutonium=1080 - лестница
# экспоненциальная по тиру фракции, и по ней считаются цены предметов.
INGOT_PRICE = {
    "bronze": 2, "iron": 9, "steel": 20, "gold": 80,
    "argentum": 12, "lutetium": 24, "lanthanum": 55, "terbium": 40,
    "wolfram": 18, "chromium": 30, "cobalt": 75, "titanium": 160,
    "thorium": 22, "uranium": 48, "plutonium": 1080, "radium": 12150,
    "gallium": 16, "yttrium": 35, "promethium": 70, "neodymium": 150,
}

# Русские имена: имя предмета собирается как "<Качество> <Металл> <Тип>".
RU_METAL = {
    "argentum": "Аргентум", "lutetium": "Лютеций", "lanthanum": "Лантан",
    "wolfram": "Вольфрам", "chromium": "Хром", "cobalt": "Кобальт",
    "thorium": "Торий", "uranium": "Уран", "gallium": "Галлий",
    "yttrium": "Иттрий", "promethium": "Прометий", "neodymium": "Неодим",
}

# Русские окончания качества в name_ru образца terbium.
RU_QUALITY = {
    "Rare": "Редкий", "Elven": "Эльфийский",
}

# Перевод типа предмета на русский (для name_ru).
RU_TYPE = {
    "Amulet": "Амулет", "Ring": "Кольцо",
    "Helm": "Шлем", "Full Helm": "Полный шлем", "Chain Helm": "Кольчужный шлем",
    "Cuirass": "Кираса", "Plate Cuirass": "Латная кираса",
    "Chain Mail": "Кольчуга", "Scale Mail": "Чешуйчатый доспех",
    "Plate Helm": "Латный шлем", "Plate Bracers": "Латные наручи",
    "Bracers": "Наручи", "Plate Boots": "Латные сапоги",
    "Chain Boots": "Кольчужные сапоги", "Chain Gauntlets": "Кольчужные перчатки",
    "Scale Gauntlets": "Чешуйчатые перчатки",
    "Small Shield": "Малый щит", "Large Shield": "Большой щит",
    "Tower Shield": "Оборонный щит",
    "Dagger": "Кинжал", "Short Sword": "Короткий меч", "Long Sword": "Длинный меч",
    "Bastard Sword": "Полуторный меч", "Two Handed Sword": "Двуручный меч",
    "Axe": "Топор", "Two Handed Axe": "Двуручный топор",
    "Mace": "Булава", "Morning Star": "Утренняя звезда", "War Hammer": "Боевой молот",
    "Pike": "Пика", "Halberd": "Алебарда",
    "Short Bow": "Короткий лук", "Long Bow": "Длинный лук", "Crossbow": "Арбалет",
}

# Русские имена типов без перевода в палитре слагов, где нужен точный вид.
RU_TYPE_FULL = dict(RU_TYPE)
RU_TYPE_FULL["Ingot"] = "Слиток"


def round_price(value: float) -> int:
    """Округление к «человеческому» шагу: кратно 20."""
    return max(20, int(round(value / 20.0)) * 20)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        data = json.load(fh)
    with open(PALETTE, encoding="utf-8") as fh:
        pal = json.load(fh)

    pal_metals = {}
    for g, gd in pal["groups"].items():
        for m in gd["metals"]:
            pal_metals[m["metal"]] = g

    # контроль: каждый металл из списка есть в палитре и в списке слитков
    for metal, group in EMPTY_METALS:
        if pal_metals.get(metal) != group:
            print("! %s в палитре не в группе %s" % (metal, group))
            return 1
        if metal not in INGOT_PRICE:
            print("! нет цены слитка для %s" % metal)
            return 1

    # образец: все предметы terbium без слитка
    template = [i for i in data if str(i.get("material", "")).lower() == "terbium"
                and i.get("type") != "Ingot"]
    if not template:
        print("! нет образца terbium в базе - нечего копировать")
        return 1
    print("ОБРАЗЕЦ: terbium, %d предметов (без слитка)" % len(template))

    # множитель цены от слитка образца
    ref_ingot = INGOT_PRICE["terbium"]

    existing_keys = {i.get("key") for i in data}
    new_items = []
    next_id = max(int(i.get("id", 0)) for i in data) + 1

    for metal, _group in EMPTY_METALS:
        mult = INGOT_PRICE[metal] / float(ref_ingot)
        ru_metal = RU_METAL[metal]
        for src in template:
            base_type = str(src.get("type", ""))
            quality = str(src.get("quality", ""))
            key = "%s %s %s" % (quality, metal.capitalize(), base_type)
            if key in existing_keys:
                continue
            name_en = "%s %s %s" % (quality, metal.capitalize(), base_type)

            ru_q = RU_QUALITY.get(quality, quality)
            ru_t = RU_TYPE_FULL.get(base_type)
            name_ru = ("%s %s %s" % (ru_q, ru_metal, ru_t)) if ru_t else name_en

            item = dict(src)
            item["id"] = next_id
            next_id += 1
            item["key"] = key
            item["name_en"] = name_en
            item["name_ru"] = name_ru
            item["material"] = metal
            item["price"] = round_price(float(src.get("price", 100)) * mult)
            item["icon"] = ""   # проставляется в шаге 3.3 по металлу и типу
            new_items.append(item)

        # слиток
        ingot_key = "%s Ingot" % metal.capitalize()
        if ingot_key not in existing_keys:
            item = {
                "id": next_id, "key": ingot_key,
                "name_ru": "Слиток %s" % RU_METAL[metal].lower(),
                "name_en": "%s Ingot" % metal.capitalize(),
                "quality": "Common", "material": metal, "type": "Ingot",
                "price": INGOT_PRICE[metal], "weight": 1.0,
                "damage_min": 0, "damage_max": 0, "to_hit": 0, "defence": 0,
                "absorption": 0, "magcap": 0, "level": 1, "effects": [],
                "icon": "res://assets/professions/blacksmith/%s_ingot.png" % metal,
            }
            next_id += 1
            new_items.append(item)

    print("СОЗДАНО: %d предметов на 12 металлов" % len(new_items))
    by_metal = {}
    for i in new_items:
        by_metal.setdefault(i["material"], 0)
        by_metal[i["material"]] += 1
    for m in EMPTY_METALS:
        n = by_metal.get(m[0], 0)
        print("  %-11s %-14s %3d предметов, слиток %d"
              % (m[0], m[1], n, INGOT_PRICE[m[0]]))
    print("ПОСЛЕ: %d предметов" % (len(data) + len(new_items)))

    # контроль: дубли ключей
    keys = [i.get("key") for i in data + new_items]
    dups = {k for k in keys if keys.count(k) > 1}
    if dups:
        print("! ДУБЛИ КЛЮЧЕЙ: %s" % sorted(dups)[:5])
        return 1

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
