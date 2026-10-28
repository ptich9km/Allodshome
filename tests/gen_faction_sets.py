"""Пакет C+D переработки ковки: 8 фракционных наборов брони.

КОНЦЕПЦИЯ (решение игрока 28.10). Фракционные наборы делаются из СТАЛИ и
трофейных бирок (пакет B), а не из 16 фракционных металлов (пакет A их удалил).
Наборов восемь: четыре фракции x два комплекта (тяжёлый воину, лёгкий магу).

ЧТО ДЕЛАЕТ ЭТОТ ГЕНЕРАТОР
  1. Текстуры (пакет C): 32 PNG в assets/items/faction_sets/{раса}/{kit}_{slot}.png.
     Источник - assets/items/base/{heavy|light}_*_common.png, перекраска
     дуотоном (tests/faction_tint.py): цвет = сталь, смешанная с цветом фракции.
     Своих ИИ-арт ассетов не требуется, стоимость $0.
  2. Предметы (пакет D): по 3 качества на слот (Crafted / Crafted Fine /
     Crafted Master) с множителями [craft] tier_improved_mult / tier_master_mult
     - тот же контракт, что у остальных крафтовых вещей.
  3. Рецепты: 16 в smith_recipes.json (тяжёлые наборы: сталь + ткань + бирка) и
     16 в tailor_recipes.json (лёгкие: ткань + эссенция + бирка). Портной, а не
     кузнец, потому что лёгкая броня магу должна быть "тканью" по правилу
     класса (`ItemDB.allows_class`).
  4. Свитки-рецепты: 32 предмета `Recipe faction_<раса>_<kit>_<slot>`. Их выдаёт
     ЗАХВАТ форпоста этой фракции (Game.on_outpost_guard_died) - тематическая
     связка пакетов B и D; лавки (пакет F) добавят второй источник.

ФОРМАТ ФАЙЛОВ. item_db.json пишется как в пакете A: indent=1, UTF-8 без
эскейпов, CRLF, хвост CRLF. Рецепты - indent=1, CRLF, БЕЗ хвостового перевода
строки (так они лежат сейчас), чтобы диф был только из добавленных записей.

Запуск:
    python tests/gen_faction_sets.py --check
    python tests/gen_faction_sets.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))

from faction_tint import duotone  # noqa: E402

DB = os.path.join(ROOT, "assets", "items", "item_db.json")
SMITH = os.path.join(ROOT, "assets", "professions", "workshop", "smith_recipes.json")
TAILOR = os.path.join(ROOT, "assets", "professions", "workshop", "tailor_recipes.json")
BASE_DIR = os.path.join(ROOT, "assets", "items", "base")
SETS_DIR = os.path.join(ROOT, "assets", "items", "faction_sets")
SCROLL_DIR = os.path.join(ROOT, "assets", "items", "recipes")
SCROLL_SRC = os.path.join(SCROLL_DIR, "recipe_bronze_cuirass.png")
CFG = os.path.join(ROOT, "assets", "config", "game.cfg")

STEEL = (192, 192, 200)   # цвет стали из faction_palette.json (is_base)
FACTION_MIX = 0.45        # доля цвета фракции в оттенке стали

# Ключи фракций = ось репутации и бирок (ItemDB.TAG_OF_RACE, пакет B).
FACTIONS = {
    "humans": {"name_ru": "Альянса", "key": "Alliance", "color": (86, 140, 214)},
    "ork": {"name_ru": "Орды", "key": "Horde", "color": (198, 92, 52)},
    "necro": {"name_ru": "Пожинателей", "key": "Reaper", "color": (150, 120, 170)},
    "druid": {"name_ru": "Круга", "key": "Circle", "color": (98, 150, 92)},
}
TAG_OF_RACE = {
    "humans": "Alliance Tag",
    "ork": "Horde Tag",
    "necro": "Reaper Tag",
    "druid": "Circle Tag",
}

# Комплекты: (слот, type, имя_ru, поле текстуры base, ресурс, статы).
# Тяжёлый: кузнец, сталь. Лёгкий: портной, лён (маг носит только ткань).
KITS = {
    "heavy": {
        "craft": "smith",
        "material": "steel",
        "source": "heavy",
        "resource": "steel Ingot",
        "slots": [
            # slot, type, name_ru, base_slot, taps: ingots/fabric, def/abs/mag, price, weight
            ("head", "Helm", "Шлем", "head", 6, 7, 2, 2, 1600, 25.0),
            ("body", "Cuirass", "Кираса", "chest", 10, 13, 3, 3, 2600, 90.0),
            ("hands", "Plate Bracers", "Латные наручи", "bracers", 4, 5, 1, 1, 900, 12.0),
            ("feet", "Plate Boots", "Латные сапоги", "legs", 5, 6, 1, 1, 1100, 25.0),
        ],
    },
    "light": {
        "craft": "tailor",
        "material": "Leather",
        "source": "light",
        "resource": "Fabric",
        "slots": [
            ("head", "Cap", "Кожаный капюшон", "head", 5, 3, 0, 20, 900, 1.0),
            ("body", "Scale Mail", "Кожаный доспех", "chest", 10, 8, 1, 18, 1800, 6.0),
            ("hands", "Bracers", "Кожаные наручи", "bracers", 6, 2, 0, 10, 600, 2.0),
            ("feet", "Boots", "Кожаные сапоги", "legs", 5, 3, 0, 8, 700, 2.5),
        ],
    },
    "magic": {
        "craft": "tailor",
        "material": "Linen",
        "source": "magic",
        "resource": "Fabric",
        "slots": [
            ("head", "Hat", "Магический колпак", "head", 5, 3, 0, 30, 1200, 1.0),
            ("body", "Robe", "Магическая мантия", "chest", 10, 7, 0, 55, 2200, 3.0),
            ("hands", "Gloves", "Магические перчатки", "bracers", 6, 2, 0, 16, 800, 2.0),
            ("feet", "Shoes", "Магические туфли", "legs", 5, 3, 0, 12, 900, 2.0),
        ],
    },
}

# ВАЖНО: миграция «роба из льна -> кожаный доспех» (29.10) уже применена в
# данных и закоммичена. Повторять её здесь НЕЛЬЗЯ: у магического набора тело —
# тоже Robe, и глобальная замена ключей превращала его мантию в Scale Mail.
# Если понадобится новая миграция — только точечно, по id рецепта.

TIERS = [
    ("Crafted", "", None),
    ("Crafted Fine", "улучшенная ", "tier_improved_mult"),
    ("Crafted Master", "мастерская ", "tier_master_mult"),
]
COMBAT_FIELDS = ("damage_min", "damage_max", "to_hit", "defence",
                 "absorption", "magcap")
FIELD_ORDER = ["id", "key", "name_ru", "name_en", "quality", "material", "type",
               "price", "weight", "damage_min", "damage_max", "to_hit",
               "defence", "absorption", "magcap", "level", "effects", "icon"]
SCROLL_FIELDS = ["key", "name_ru", "name_en", "quality", "type", "material",
                 "icon", "price", "weight", "damage_min", "damage_max",
                 "to_hit", "defence", "absorption", "magcap", "craft",
                 "recipe_id", "bp"]


def mixed(steel, accent, k=FACTION_MIX):
    return tuple(int(round(a + (b - a) * k)) for a, b in zip(steel, accent))


def build_icon(race: str, kit: str, slot: str, base_slot: str,
               rebuild: bool = False) -> str:
    """Иконка набора. Существующий файл НЕ перезаписываем: с 29.10 там может
    лежать ИИ-арт из extract_faction_art.py, а перекраска его бы затёрла."""
    rel = "res://assets/items/faction_sets/%s/%s_%s.png" % (race, kit, slot)
    if not rebuild and os.path.exists(os.path.join(ROOT, rel.replace("res://", ""))):
        return rel
    src = os.path.join(BASE_DIR, "%s_%s_common.png" % (KITS[kit]["source"], base_slot))
    img = Image.open(src).convert("RGBA")
    out = duotone(img, mixed(STEEL, FACTIONS[race]["color"]))
    path = os.path.join(SETS_DIR, race, "%s_%s.png" % (kit, slot))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)
    return rel


def build_scroll_icon(race: str) -> str:
    src = Image.open(SCROLL_SRC).convert("RGBA")
    out = duotone(src, mixed(STEEL, FACTIONS[race]["color"], 0.65))
    path = os.path.join(SCROLL_DIR, "recipe_faction_%s.png" % race)
    out.save(path)
    return "res://assets/items/recipes/recipe_faction_%s.png" % race


def cfg_mult(key: str | None) -> float:
    if key is None:
        return 1.0
    import configparser
    cp = configparser.ConfigParser(inline_comment_prefixes=(";",), interpolation=None)
    cp.read(CFG, encoding="utf-8")
    return float(cp.get("craft", key))


def build_item(faction_key: str, faction_ru: str, kit: str, slot_spec, tier) -> dict:
    slot, typ, name_ru, _base_slot, _res, defence, absorption, magcap, price, weight = slot_spec
    quality, ru_tier, mult_key = tier
    mult = cfg_mult(mult_key)
    base = {
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": defence, "absorption": absorption, "magcap": magcap,
    }
    stats = {f: int(round(base[f] * mult)) for f in COMBAT_FIELDS}
    if mult > 1.0:
        # Минимум +1 к самому крупному полю, иначе округление съедает
        # улучшение на мелких статах (тот же приём, что в gen_crafted_items).
        before = sum(base.values())
        after = sum(stats.values())
        if after <= before:
            best = max(COMBAT_FIELDS, key=lambda f: base[f])
            stats[best] += 1
    return {
        "key": "%s %s %s" % (quality, faction_key, typ),
        "name_ru": "%s%s %s" % (ru_tier, name_ru, faction_ru),
        "name_en": "%s %s %s" % (quality, faction_key, typ),
        "quality": quality,
        "material": KITS[kit]["material"],
        "type": typ,
        "price": max(1, int(round(price * mult / 20.0)) * 20),
        "weight": weight,
        **stats,
        "level": 1,
        "effects": [],
        "icon": "",
    }


def recipe_id(race: str, kit: str, slot: str) -> str:
    return "faction_%s_%s_%s" % (race, kit, slot)


def build_recipe(race: str, kit: str, slot_spec) -> dict:
    slot, typ, name_ru, _base_slot, taps, *_rest = slot_spec
    faction_ru = FACTIONS[race]["name_ru"]
    ins = [
        {"item": KITS[kit]["resource"], "count": taps},
        {"item": "Fabric" if kit == "heavy" else "Magic Essence", "count": 1},
        {"item": TAG_OF_RACE[race], "count": 1},
    ]
    rid = recipe_id(race, kit, slot)
    return {
        "id": rid,
        "name_ru": "%s %s" % (name_ru, faction_ru),
        "craft": KITS[kit]["craft"],
        "inputs": ins,
        "outputs": [
            {"key": "%s %s %s" % (q, FACTIONS[race]["key"], typ), "weight": w}
            for q, w in (("Crafted", 80.0), ("Crafted Fine", 15.0), ("Crafted Master", 5.0))
        ],
    }


def build_scroll(race: str, kit: str, slot_spec) -> dict:
    slot, typ, name_ru, _b, _t, *_r = slot_spec
    faction_ru = FACTIONS[race]["name_ru"]
    rid = recipe_id(race, kit, slot)
    return {
        "key": "Recipe " + rid,
        "name_ru": "Чертёж: %s %s" % (name_ru, faction_ru),
        "name_en": "Recipe: Crafted %s %s" % (FACTIONS[race]["key"], typ),
        "quality": "Recipe",
        "type": "Recipe",
        "material": "None",
        "icon": "res://assets/items/recipes/recipe_faction_%s.png" % race,
        "price": 80,
        "weight": 0.2,
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 0, "absorption": 0, "magcap": 0,
        "craft": KITS[kit]["craft"],
        "recipe_id": rid,
        # Не "armor"/"weapon"/"clothes": витрины лавки (пакет F) показывают
        # только эти три ярлыка, а чертёж фракционного набора сначала добывают
        # захватом форпоста. Отдельная полка «Фракции» появится в пакете F.
        "bp": "faction",
    }


def load_json(path: str):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def save_items(items: list) -> None:
    text = json.dumps(items, ensure_ascii=False, indent=1)
    with open(DB, "w", encoding="utf-8", newline="") as fh:
        fh.write(text.replace("\n", "\r\n") + "\r\n")


def _j(value) -> str:
    return json.dumps(value, ensure_ascii=False)


## Текстовая вставка нового рецепта в конец массива "recipes".
##
## Почему не перезапись файла целиком: исторический smith_recipes.json уже
## содержит записи с выравниванием на пробел иначе, и json.dumps(indent=1)
## переформатировал бы 94 строки, не изменив ни одного числа. Проект уже
## применял этот приём в gen_grey_tiers_db.py (вставка тиров в units_db.json).
def insert_recipe_text(path: str, rec: dict) -> bool:
    with open(path, "r", encoding="utf-8", newline="") as fh:
        raw = fh.read()
    if ('"id": %s' % _j(rec["id"])) in raw:
        return False
    # Хвост массива находится ПО СМЫСЛУ, а не по числу пробелов: исторически
    # smith_recipes.json закрывает массив с отступом 2, tailor - с 1.
    brace = raw.rfind("}")
    arr = raw.rfind("]", 0, brace)
    if arr < 0:
        raise SystemExit("не найден массив recipes в %s" % path)
    line_start = raw.rfind("\n", 0, arr) + 1
    cut = raw.rfind("\r\n", 0, line_start)
    if cut < 0:
        raise SystemExit("не найден конец последнего рецепта в %s" % path)
    raw = raw[:cut] + ",\r\n" + recipe_text(rec) + raw[cut:]
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(raw)
    return True


def recipe_text(rec: dict) -> str:
    lines = ["  {",
             '   "id": %s,' % _j(rec["id"]),
             '   "name_ru": %s,' % _j(rec["name_ru"]),
             '   "craft": %s,' % _j(rec["craft"]),
             '   "inputs": [']
    lines.append(",\r\n".join(
        '    {"item": %s, "count": %d}' % (_j(x["item"]), int(x["count"]))
        for x in rec["inputs"]))
    lines.append('   ],')
    lines.append('   "outputs": [')
    lines.append(",\r\n".join(
        '    {"key": %s, "weight": %s}' % (_j(x["key"]), _j(float(x["weight"])))
        for x in rec["outputs"]))
    lines.append('   ]')
    lines.append("  }")
    return "\r\n".join(lines)


## Своя запись, а не json.dumps: в рецептах пары {"item": ..., "count": N} и
## {"key": ..., "weight": W} стоят ОДНОЙ строкой, а файл исторически имеет
## разное выравнивание (см. insert_recipe_text). Поэтому новые рецепты
## добавляются текстом, а не перезаписью всего документа.


def apply(rebuild_icons: bool = False) -> int:
    items = load_json(DB)
    by_key = {str(it.get("key", "")): it for it in items}
    next_id = max(int(it.get("id", 0)) for it in items) + 1
    scroll_icons = {race: build_scroll_icon(race) for race in FACTIONS}
    smith_doc = load_json(SMITH)
    tailor_doc = load_json(TAILOR)
    known_recipes = {str(r.get("id", "")) for r in smith_doc["recipes"] + tailor_doc["recipes"]}
    added_items = 0
    added_scrolls = 0
    new_recipes = {"smith": [], "tailor": []}
    for race in FACTIONS:
        for kit_name in KITS:
            for slot_spec in KITS[kit_name]["slots"]:
                icon = build_icon(race, kit_name, str(slot_spec[0]), str(slot_spec[3]),
                                  rebuild_icons)
                for tier in TIERS:
                    item = build_item(FACTIONS[race]["key"], FACTIONS[race]["name_ru"],
                                      kit_name, slot_spec, tier)
                    item["icon"] = icon
                    item["faction"] = race
                    if item["key"] in by_key:
                        # Запись уже есть: генератор — источник правды для чисел
                        # и подписей (миграция «роба -> кожа» меняет материал,
                        # тип и имя), но id и метку времени не трогаем.
                        existing = by_key[item["key"]]
                        for field in ("name_ru", "name_en", "material", "price",
                                      "weight", "damage_min", "damage_max", "to_hit",
                                      "defence", "absorption", "magcap", "icon"):
                            existing[field] = item[field]
                        existing["faction"] = race
                        continue
                    item["id"] = next_id
                    next_id += 1
                    items.append(item)
                    by_key[item["key"]] = item
                    added_items += 1
                rid = recipe_id(race, kit_name, str(slot_spec[0]))
                if rid not in known_recipes:
                    doc = "smith" if KITS[kit_name]["craft"] == "smith" else "tailor"
                    new_recipes[doc].append(build_recipe(race, kit_name, slot_spec))
                    known_recipes.add(rid)
                scroll = build_scroll(race, kit_name, slot_spec)
                scroll["icon"] = scroll_icons[race]
                if scroll["key"] in by_key:
                    # Свиток уже есть: обновляем подписи/полку (миграция кожи),
                    # bp и иконку, но НЕ плодим вторую запись.
                    for field in ("name_ru", "name_en", "icon", "craft", "bp",
                                  "price", "weight"):
                        by_key[scroll["key"]][field] = scroll[field]
                    continue
                scroll["id"] = next_id
                next_id += 1
                items.append(scroll)
                by_key[scroll["key"]] = scroll
                added_scrolls += 1
    save_items(items)
    added_recipes = 0
    for rec in new_recipes["smith"]:
        if insert_recipe_text(SMITH, rec):
            added_recipes += 1
    for rec in new_recipes["tailor"]:
        if insert_recipe_text(TAILOR, rec):
            added_recipes += 1
    print("предметы: +%d, свитки: +%d, рецепты: +%d, всего предметов: %d"
          % (added_items, added_scrolls, added_recipes, len(items)))
    return 0


def check() -> int:
    fails = []
    items = load_json(DB)
    by_key = {str(it.get("key", "")): it for it in items}
    smith = {str(r.get("id", "")): r for r in load_json(SMITH)["recipes"]}
    tailor = {str(r.get("id", "")): r for r in load_json(TAILOR)["recipes"]}
    for race in FACTIONS:
        for kit_name in KITS:
            for slot_spec in KITS[kit_name]["slots"]:
                slot = str(slot_spec[0])
                icon = "res://assets/items/faction_sets/%s/%s_%s.png" % (race, kit_name, slot)
                rel = icon.replace("res://", "").replace("/", os.sep)
                if not os.path.exists(os.path.join(ROOT, rel)):
                    fails.append("нет текстуры %s" % icon)
                for quality, _ru, _m in TIERS:
                    key = "%s %s %s" % (quality, FACTIONS[race]["key"], slot_spec[1])
                    it = by_key.get(key)
                    if it is None:
                        fails.append("нет предмета %s" % key)
                        continue
                    if it.get("icon") != icon:
                        fails.append("%s: иконка не из faction_sets" % key)
                    if str(it.get("faction", "")) != race:
                        fails.append("%s: нет метки фракции %s" % (key, race))
                    if it.get("material") != KITS[kit_name]["material"]:
                        fails.append("%s: материал %s" % (key, it.get("material")))
                rid = recipe_id(race, kit_name, slot)
                doc = smith if KITS[kit_name]["craft"] == "smith" else tailor
                if rid not in doc:
                    fails.append("нет рецепта %s" % rid)
                else:
                    outs = doc[rid].get("outputs", [])
                    if len(outs) != 3:
                        fails.append("%s: выходов %d" % (rid, len(outs)))
                    for out in outs:
                        if str(out.get("key", "")) not in by_key:
                            fails.append("%s: выход %s отсутствует" % (rid, out.get("key")))
                    for ing in doc[rid].get("inputs", []):
                        if str(ing.get("item", "")) not in by_key:
                            fails.append("%s: ингредиент %s отсутствует" % (rid, ing.get("item")))
                scroll_key = "Recipe " + rid
                if scroll_key not in by_key:
                    fails.append("нет свитка %s" % scroll_key)
                else:
                    sicon = str(by_key[scroll_key].get("icon", ""))
                    if not os.path.exists(os.path.join(ROOT, sicon.replace("res://", "").replace("/", os.sep))):
                        fails.append("%s: нет иконки %s" % (scroll_key, sicon))
                    if str(by_key[scroll_key].get("bp", "")) != "faction":
                        fails.append("%s: bp должен быть faction" % scroll_key)
    if fails:
        print("RESULT: FAIL gen_faction_sets --check")
        for f in fails[:30]:
            print("  -", f)
        return 1
    print("RESULT: OK gen_faction_sets (предметов: %d)" % len(items))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--rebuild-icons", action="store_true",
                    help="перерисовать иконки дуотоном (затрёт ИИ-арт!)")
    args = ap.parse_args()
    return check() if args.check else apply(args.rebuild_icons)


if __name__ == "__main__":
    sys.exit(main())
