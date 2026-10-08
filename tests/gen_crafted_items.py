"""Создаёт крафтовые вещи трёх уровней: обычная / улучшенная / мастерская.

ЗАЧЕМ. Рецепт в мастерской выдаёт одну из трёх записей одного рецепта.
Инвентарь хранит `Array[String]` ключей (player.gd), поэтому две крафтовые
вещи одного рецепта с РАЗНЫМ уровнем иначе не различить - пришлось бы
переделывать хранение инвентаря на экземпляры. Цена решения: по три записи
на рецепт, но зато НИ ОДНОЙ правки в инвентаре, луте, сейве и торговле.

ОДНА ТЕКСТУРА НА ВСЕ ТРИ УРОВНЯ. Иконка копируется из базовой вещи, как и
просил игрок: различаются только числа и шейдер свечения
(scripts/craft_vfx.gd). Обычный пайплайн наоборот запекает уровень в арт
(assets/items/faction/{metal}_{tier}_*.png по QUALITY_TO_TIER в
gen_item_icons.py), поэтому здесь уровень читается из quality, а не из пути.

МНОЖИТЕЛИ ХАРАКТЕРИСТИК из [craft] tier_improved_mult / tier_master_mult.
Множатся только боевые поля (урон, точность, защита, поглощение, ёмкость
маны). Цена растёт тем же множителем, иначе улучшенная вещь была бы дороже
целой по той же цене - то есть улучшать было бы незачем.

ПОЧЕМУ НУЛИ В damage_max НЕ СТРАШНЫ ЗДЕСЬ. metal_stats_smoke.gd:145-147
отбрасывает предметы с damage_max <= 0 перед проверкой монотонности. У
крафтовой вещи оружия damage_max > 0, поэтому в монотонность она попадёт -
и это правильно: сравнение идёт внутри пары (тип, качество), а уровень
качества здесь и есть измеряемая ось.

Запуск:
    python tests/gen_crafted_items.py --dry-run
    python tests/gen_crafted_items.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
CFG = os.path.join(ROOT, "assets", "config", "game.cfg")

# (recipe_id, ключ базовой вещи). Базовая вещь - образец для текстуры, типа,
# материала и стартовых характеристик.
BASES = [
    ("bronze_cuirass", "Common bronze Cuirass"),
    ("iron_cuirass", "Common iron Cuirass"),
    ("iron_plate", "Common iron Plate Cuirass"),
    ("bronze_sword", "Common bronze Long Sword"),
    ("iron_sword", "Common iron Long Sword"),
    ("iron_axe", "Common iron Axe"),
    ("iron_buckler", "Common iron Buckler"),
    ("steel_cuirass", "Common steel Cuirass"),
    ("gold_cuirass", "Common gold Cuirass"),
    ("linen_cloak", "Common Linen Cloak"),
    ("linen_cape", "Common Linen Cape"),
]

# Базовые вещи, которых в базе НЕТ и которые создаются здесь же.
#
# Иконки assets/items/base/magic_* (24 файла: chest, head, cloak, shirt, ...)
# лежали на диске и не были привязаны НИ К ОДНОМУ предмету - мёртвый арт,
# который в точности и предназначен одежде мага. Нулевая затрата на текстуры.
#
# Числа подобраны рядом с существующей одеждой: у Common Linen Cloak
# defence 2 / magcap 30 / цена 1200. Роба - тело мага (крепче плаща по
# защите, заметно больше маны), колпак - дешёвый аксессуар.
SYNTH_BASES = [
    {
        "recipe": "linen_robe",
        "key": "Common Linen Robe",
        "name_ru": "Роба льняная",
        "name_en": "Linen Robe",
        "material": "Linen",
        "type": "Robe",
        "icon": "res://assets/items/base/magic_chest_common.png",
        "price": 1400, "weight": 3.0,
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 6, "absorption": 0, "magcap": 45,
    },
    {
        "recipe": "mage_hat",
        "key": "Common Linen Hat",
        "name_ru": "Колпак мага",
        "name_en": "Mage Hat",
        "material": "Linen",
        "type": "Hat",
        "icon": "res://assets/items/base/magic_head_common.png",
        "price": 700, "weight": 1.0,
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 3, "absorption": 0, "magcap": 20,
    },
    # Стартовые чертежи первой локации: сталь и золото (08.10, по слову игрока).
    # Статы — между iron Crafted и магазинным Uncommon/Good: крафт слабее
    # лавки того же металла, иначе свиток был бы строго лучше покупки.
    {
        "recipe": "steel_cuirass",
        "key": "Common steel Cuirass",
        "name_ru": "Кираса стальная",
        "name_en": "steel Cuirass",
        "material": "steel",
        "type": "Cuirass",
        "icon": "res://assets/items/base/heavy_chest_good.png",
        "price": 1200, "weight": 90.0,
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 12, "absorption": 1, "magcap": 2,
    },
    {
        "recipe": "gold_cuirass",
        "key": "Common gold Cuirass",
        "name_ru": "Кираса золотая",
        "name_en": "gold Cuirass",
        "material": "gold",
        "type": "Cuirass",
        "icon": "res://assets/items/faction/common/gold_heavy_chest_elite.png",
        "price": 4000, "weight": 100.0,
        "damage_min": 0, "damage_max": 0, "to_hit": 0,
        "defence": 16, "absorption": 2, "magcap": 8,
    },
]

# Уровень -> (quality в базе, множитель характеристик).
# Качество начинается с "Crafted" - на него смотрит CraftVFX.tier_of_item().
TIERS = [
    ("Crafted", "Ordinary"),
    ("Crafted Fine", "Improved"),
    ("Crafted Master", "Master"),
]

RU_TIER = {
    "Crafted": "",
    "Crafted Fine": "улучшенная ",
    "Crafted Master": "мастерская ",
}

MULT_KEY = {
    "Crafted": None,           # 1.0 - обычная вещь не усиливается
    "Crafted Fine": "tier_improved_mult",
    "Crafted Master": "tier_master_mult",
}

COMBAT_FIELDS = ("damage_min", "damage_max", "to_hit", "defence",
                 "absorption", "magcap")

FIELD_ORDER = ["id", "key", "name_ru", "name_en", "quality", "material", "type",
               "price", "weight", "damage_min", "damage_max", "to_hit",
               "defence", "absorption", "magcap", "level", "effects", "icon"]


def load_multipliers() -> dict:
    """Множители из game.cfg, а не из константы: игрок должен крутить одно
    число в конфиге, а не править сотни предметов."""
    cfg = {}
    try:
        import configparser
        # interpolation=None обязателен: строки комментариев в game.cfg
        # содержат "%d" ("шанс ... 80%"), а BasicInterpolation на '%' падает
        # с "'%' must be followed by '%' or '('".
        cp = configparser.ConfigParser(inline_comment_prefixes=(";",), interpolation=None)
        cp.read(CFG, encoding="utf-8")
        for k, v in cp.items("craft"):
            cfg[k] = float(v)
    except Exception as exc:  # noqa: BLE001 - сообщаем и падаем внятно
        print("Не удалось прочитать [craft] из %s: %s" % (CFG, exc))
        return {}
    return cfg


def build(base: dict, quality: str, mult: float) -> dict:
    item = {f: base.get(f) for f in FIELD_ORDER}
    item["quality"] = quality
    item["name_ru"] = RU_TIER[quality] + str(base.get("name_ru", ""))
    item["name_en"] = "%s %s" % (quality, base.get("name_en", ""))
    for field in COMBAT_FIELDS:
        item[field] = int(round(int(base.get(field, 0)) * mult))
    # МИНИМУМ +1. Без него целочисленное округление съедало усиление на
    # предметах с малыми статами: у Common Linen Cloak defence 2, и 2*1.15 =
    # 2.3 -> round = 2, то есть "улучшенная вещь" была бы неотличима от
    # обычной. Игрок заплатил бы ресурсы за воздух.
    if mult > 1.0:
        _ensure_visible_gain(base, item)
    item["price"] = max(1, int(round(int(base.get("price", 1)) * mult / 20.0)) * 20)
    return item


def _ensure_visible_gain(base: dict, item: dict) -> None:
    """Поднять на 1 самое крупное ненулевое боевое поле.

    Работает по СУММЕ б��евых полей: если после умножения сумма не выросла,
    усиление нечитаемо. Поднимается именно самое крупное ненулевое поле, а не
    первое попавшееся - иначе у меча рос бы absorption, которого у него нет.
    """
    before = sum(int(base.get(f, 0)) for f in COMBAT_FIELDS)
    after = sum(int(item.get(f, 0)) for f in COMBAT_FIELDS)
    if after > before:
        return
    best = ""
    best_val = 0
    for field in COMBAT_FIELDS:
        v = int(base.get(field, 0))
        if v > best_val:
            best_val = v
            best = field
    if best != "":
        item[best] = int(item[best]) + 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--refresh-stats", action="store_true",
                    help="пересчитать характеристики уже созданных крафтовых "
                         "вещей по текущим множителям из game.cfg")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        raw = fh.read()
    data = json.loads(raw)
    by_key = {str(i.get("key", "")): i for i in data}

    cfg = load_multipliers()
    if not cfg:
        print("Нет [craft] в конфиге - сначала tests/gen_game_config_defaults.gd")
        return 2

    existing = set(by_key)
    next_id = max(int(i.get("id", 0)) for i in data) + 1
    new_items = []
    made_keys = {}
    refreshed = 0

    # Базовые вещи портного: создаются, только если их ещё нет.
    synth_done = 0
    for spec in SYNTH_BASES:
        if spec["key"] in existing:
            continue
        base = {f: spec.get(f) for f in FIELD_ORDER}
        base["id"] = next_id
        base["level"] = 1
        base["effects"] = []
        # quality обязан быть задан, иначе в базу попадёт null и базовую вещь
        # перестанет находить поиск по Common (ui, тесты, is_equippable).
        base["quality"] = str(spec.get("quality", "Common"))
        if not str(base["key"]).startswith("%s %s " % (base["quality"], base["material"])):
            print("   ! ключ базовой вещи не начинается с «Качество Материал»: %s"
                  % base["key"])
            return 1
        next_id += 1
        existing.add(base["key"])
        by_key[base["key"]] = base
        new_items.append(base)
        synth_done += 1

    all_bases = [(b[0], b[1]) for b in BASES] + \
        [(s["recipe"], s["key"]) for s in SYNTH_BASES]

    for recipe_id, base_key in all_bases:
        base = by_key.get(base_key)
        if base is None:
            print("   ! нет базовой вещи %s (рецепт %s)" % (base_key, recipe_id))
            return 1
        for quality, _tier_name in TIERS:
            mult_key = MULT_KEY[quality]
            # У обычной вещи множителя нет вовсе (1.0) - усиливать нечего.
            # Проверять "> 1" надо только у двух усиленных уровней.
            mult = 1.0 if mult_key is None else float(cfg.get(mult_key, 1.0))
            if mult_key is not None and mult <= 1.0:
                print("   ! множитель %s = %.2f - должен быть > 1" % (mult_key, mult))
                return 1
            # Ключ = "{Качество} {материал} {тип}", как у обычных вещей.
            # Сегмент материала обязан совпасть с полем material - контракт
            # tests/item_key_literal_smoke.gd:111.
            item = build(base, quality, mult)
            item["key"] = "%s %s %s" % (quality, base.get("material", ""),
                                       base.get("type", ""))
            item["id"] = 0
            made_keys[(recipe_id, quality)] = item["key"]
            if item["key"] in existing:
                # --refresh-stats: пересчитать характеристики уже созданной
                # вещи по текущим множителям. Нужно после правки
                # tier_improved_mult/tier_master_mult в game.cfg - без этого
                # игрок крутит одно число, а в базе остаются старые статы.
                if args.refresh_stats:
                    cur = by_key[item["key"]]
                    for f in COMBAT_FIELDS + ("price",):
                        if cur.get(f) != item.get(f):
                            cur[f] = item[f]
                    refreshed += 1
                continue
            item["id"] = next_id
            next_id += 1
            existing.add(item["key"])
            by_key[item["key"]] = item
            new_items.append(item)

    problems = []
    for recipe_id, _base_key in all_bases:
        for quality, _n in TIERS:
            key = made_keys.get((recipe_id, quality))
            if key is None and "%s %s" % (recipe_id, quality) not in existing:
                # запись уже была в базе до этого прогона - это нормально
                base = by_key.get(_base_key)
                if base is None:
                    continue
                want = "%s %s %s" % (quality, base.get("material", ""),
                                     base.get("type", ""))
                if want not in existing:
                    problems.append("нет записи %s" % want)
    for item in new_items:
        if str(item.get("material", "")) not in item["key"]:
            problems.append("%s: сегмент материала != material" % item["key"])
        if not str(item.get("icon", "")).endswith(".png"):
            problems.append("%s: нет иконки" % item["key"])
    if problems:
        print("ИНВАРИАНТЫ НАРУШЕНЫ: %d" % len(problems))
        for p in problems[:20]:
            print("   ! %s" % p)
        return 1

    print("Новых записей: %d (из них базовых вещей: %d)" % (len(new_items), synth_done))
    print("Пересчитано существующих: %d" % refreshed)
    print("Всего предметов: %d -> %d" % (len(data), len(data) + len(new_items)))
    print("Примеры (обычная / улучшенная / мастерская):")
    for recipe_id, base_key in all_bases[:3]:
        base = by_key[base_key]
        for quality, _n in TIERS:
            key = made_keys.get((recipe_id, quality)) or \
                ("%s %s %s" % (quality, base.get("material", ""), base.get("type", "")))
            print("  %-34s icon=%s" % (key, os.path.basename(str(by_key.get(base_key, {}).get("icon", "")))))

    if args.dry_run:
        print("DRY-RUN: база не изменена")
        return 0

    payload = json.dumps(data + new_items, ensure_ascii=False, indent=1) + "\n"
    if json.dumps(data, ensure_ascii=False, indent=1) + "\n" != raw:
        print("ВНИМАНИЕ: round-trip исходника не байт-в-байт")
        return 2
    with open(DB, "w", encoding="utf-8", newline="") as fh:
        fh.write(payload)
    print("Записано: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())