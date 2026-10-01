#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Чистка материалов в item_db.json: убрать кожу и дерево, вернуть металлические луки.

Что делает:
  1. Удаляет предметы из кожи (Leather / Hard Leather / Dragon Leather) и из
     дерева (Wood / Magic Wood), КРОМЕ посохов — их арт под металлы будет
     нарезан отдельно, до тех пор посох мага должен существовать.
  2. Создаёт для каждого из 20 металлов Long Bow и Short Bow на существующем
     арте `faction_w/{group}/{metal}_bow_{tier}.png` (для стали — `base_w/`),
     чтобы типы луков не остались пустыми.

Правка JSON ТЕКСТОВАЯ: блоки предметов вырезаются и дописываются как есть,
без json.dumps — иначе файл переформатируется целиком (журнал, 27.09).

Цены луков считаются от цены слитка металла: замер по существующим предметам
дал Crossbow = слиток x 1600, поэтому лук берём дешевле арбалета:
Long Bow = слиток x 1200, Short Bow = слиток x 800, округление до 20.
Характеристики лука — доля от среднего по оружию того же металла, чтобы
лук не оказался сильнее меча того же металла.

Запуск:
    python tests/gen_materials_cleanup.py --dry-run
    python tests/gen_materials_cleanup.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

DB = os.path.join("assets", "items", "item_db.json")
PALETTE = os.path.join("assets", "items", "faction_palette.json")

DROP_MATERIALS = {"Leather", "Hard Leather", "Dragon Leather", "Wood", "Magic Wood"}
KEEP_TYPES = {"Staff", "Shaman Staff"}          # посохи переживают чистку

WEAPON_TYPES = {
    "Dagger", "Short Sword", "Long Sword", "Bastard Sword", "Two Handed Sword",
    "Spiked Club", "Club", "Mace", "Morning Star", "Pick Hammer", "War Hammer",
    "Axe", "Two Handed Axe", "Pike", "Lance", "Halberd", "Staff", "Shaman Staff",
    "Short Bow", "Long Bow", "Crossbow",
}

BOWS = [("Long Bow", 1200, 5.0, "Длинный лук", "long_bow"),
        ("Short Bow", 800, 4.0, "Короткий лук", "short_bow")]

QUALITY_RU = {
    "Common": "Обычный", "Uncommon": "Необычный", "Rare": "Редкий",
    "Good": "Хороший", "Very Rare": "Очень редкий", "Elven": "Эльфийский",
    "Bad": "Плохой",
}

METAL_RU = {
    "bronze": "Бронза", "iron": "Железо", "steel": "Сталь", "gold": "Золото",
    "argentum": "Аргентум", "lutetium": "Лютеций", "lanthanum": "Лантан",
    "terbium": "Тербий", "wolfram": "Вольфрам", "chromium": "Хром",
    "cobalt": "Кобальт", "titanium": "Титаний", "thorium": "Торий",
    "uranium": "Уран", "plutonium": "Плутоний", "radium": "Радий",
    "gallium": "Галлий", "yttrium": "Иттрий", "promethium": "Прометий",
    "neodymium": "Неодим",
}


# ───────────────────────── разбор текстовых блоков ─────────────────────────

def split_blocks(text: str) -> tuple[str, list[str], str]:
    """(префикс, [тексты блоков], суффикс) — блоки возвращаются КАК ЕСТЬ.

    Важно: блок не пересобирается из разобранного словаря. У 71 предмета
    массив effects записан в несколько строк, и пересборка схлопнула бы его
    в одну — это переформатирование файла (журнал, 27.09: JSON правится
    текстовой вставкой, json.dumps нельзя).
    """
    lines = text.split("\n")
    blocks: list[str] = []
    start = None
    for i, line in enumerate(lines):
        if start is None and line == " {":
            start = i
            continue
        if start is not None and line in (" }", " },"):
            blocks.append("\n".join(lines[start : i + 1]))
            start = None
    if start is not None:
        raise SystemExit("FAIL: не найден конец блока — структура JSON неожиданная")
    if not blocks:
        raise SystemExit("FAIL: блоки предметов не найдены")
    # префикс — всё до первого блока, суффикс — от последнего блока до конца
    first = text.index(blocks[0])
    prefix = text[:first]
    last = text.rindex(blocks[-1])
    suffix = text[last + len(blocks[-1]):]
    return prefix, blocks, suffix


def field(block: str, name: str) -> str:
    m = re.search(r'^\s*"%s":\s*(.*?),?\s*$' % re.escape(name), block, re.M)
    if not m:
        return ""
    return m.group(1).strip().rstrip(",")


def parse_block(block: str) -> dict:
    # блок закрывается " }," — запятая перед "]" даёт невалидный JSON
    return json.loads("[" + block.rstrip().rstrip(",") + "]")[0]


def make_block(item: dict, comma: bool = False) -> str:
    """Текстовый блок предмета. Исходные блоки в файле несут запятую в конце,
    поэтому новые блоки тоже должны её нести — иначе между ними не будет
    разделителя и JSON станет невалидным."""
    lines = [" {"]
    keys = list(item.keys())
    for idx, (k, v) in enumerate(zip(keys, item.values())):
        sep = "," if idx < len(keys) - 1 else ""
        lines.append("  %s: %s%s" % (
            json.dumps(k, ensure_ascii=False),
            json.dumps(v, ensure_ascii=False),
            sep))
    lines.append(" }," if comma else " }")
    return "\n".join(lines)


# ───────────────────────── генерация луков ─────────────────────────

def round_price(value: float) -> int:
    return max(20, int(round(value / 20.0)) * 20)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8", newline="") as f:
        raw = f.read()
    nl = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")

    prefix, blocks, suffix = split_blocks(text)
    items = [parse_block(b) for b in blocks]
    print(f"предметов до: {len(items)}")

    # --- 1. чистка: вырезаем блоки, трогая исходный текст ---
    def is_dropped(btext: str) -> bool:
        material = str(parse_block(btext).get("material"))
        itype = str(parse_block(btext).get("type"))
        return material in DROP_MATERIALS and itype not in KEEP_TYPES

    dropped_keys = []
    kept_blocks: list[str] = []
    for btext in blocks:
        if is_dropped(btext):
            dropped_keys.append(str(parse_block(btext).get("key")))
        else:
            kept_blocks.append(btext)
    print(f"удаляется: {len(dropped_keys)}   остаётся: {len(kept_blocks)}")
    from collections import Counter as _C
    print("  по материалам:", dict(_C(
        str(parse_block(b).get("material")) for b in blocks if is_dropped(b))))
    non_ph = [k for b, k in zip(blocks, [str(parse_block(x).get("key")) for x in blocks])
              if is_dropped(b) and "placeholder" not in b]
    print("  удаляемых с НЕ-заглушкой (должно быть 0):", non_ph)

    # --- 2. луки ---
    with open(PALETTE, encoding="utf-8") as f:
        pal = json.load(f)
    kept_items = [parse_block(b) for b in kept_blocks]
    existing_keys = {str(i.get("key")) for i in kept_items}

    by_metal: dict[str, list[dict]] = defaultdict(list)
    for it in kept_items:
        by_metal[str(it.get("material"))].append(it)

    next_id = max(int(i.get("id", 0)) for i in kept_items) + 1
    new_items: list[dict] = []

    for group_name, group in pal["groups"].items():
        for spec in group["metals"]:
            metal = str(spec["metal"])
            tier = str(spec["tier"])
            is_base = bool(spec.get("is_base", False))
            own = by_metal.get(metal, [])
            if not own:
                print(f"  ПРОПУСК {metal}: нет предметов в базе")
                continue

            ingot = next((i for i in own if str(i.get("type")) == "Ingot"), None)
            if ingot is None:
                print(f"  ПРОПУСК {metal}: нет слитка — не от чего считать цену")
                continue
            ingot_price = int(ingot.get("price", 0))

            weapons = [i for i in own if str(i.get("type")) in WEAPON_TYPES]
            if not weapons:
                print(f"  ПРОПУСК {metal}: нет оружия для выборки характеристик")
                continue
            quality = Counter(str(i.get("quality")) for i in weapons).most_common(1)[0][0]
            avg_dmin = sum(int(i.get("damage_min", 0)) for i in weapons) / len(weapons)
            avg_dmax = sum(int(i.get("damage_max", 0)) for i in weapons) / len(weapons)
            avg_hit = sum(int(i.get("to_hit", 0)) for i in weapons) / len(weapons)
            avg_level = sum(int(i.get("level", 1)) for i in weapons) / len(weapons)

            if is_base:
                icon = "res://assets/items/base_w/bow_%s.png" % tier
            else:
                icon = "res://assets/items/faction_w/%s/%s_bow_%s.png" % (group_name, metal, tier)
            if not os.path.exists(icon.replace("res://", "").replace("/", os.sep)):
                print(f"  ПРОПУСК {metal}: нет арта {icon}")
                continue

            for btype, mult, weight, type_ru, _slug in BOWS:
                key = "%s %s %s" % (quality, metal, btype)
                if key in existing_keys:
                    continue
                item = {
                    "id": next_id,
                    "key": key,
                    "name_ru": "%s %s %s" % (QUALITY_RU.get(quality, quality),
                                             METAL_RU.get(metal, metal), type_ru),
                    "name_en": "%s %s %s" % (quality, metal.capitalize(), btype),
                    "quality": quality,
                    "material": metal,
                    "type": btype,
                    "price": round_price(ingot_price * mult),
                    "weight": weight,
                    "damage_min": max(1, int(round(avg_dmin * 0.6))),
                    "damage_max": max(2, int(round(avg_dmax * 0.6))),
                    "to_hit": max(1, int(round(avg_hit * 0.8))),
                    "defence": 0,
                    "absorption": 0,
                    "magcap": 20,
                    "level": max(1, int(round(avg_level))),
                    "effects": [],
                    "icon": icon,
                }
                next_id += 1
                existing_keys.add(key)
                new_items.append(item)

    print(f"новых луков: {len(new_items)}")

    if args.dry_run:
        print("RESULT: OK (dry-run, файл не тронут)")
        return 0

    # Склейка: между блоками нужна запятая. В исходном файле она есть у всех
    # блоков, КРОМЕ последнего. Два случая:
    #   " }," — последний сохранённый не был последним в файле (исходный хвост
    #            удалён), запятая уже есть, ничего не трогаем;
    #   " }"  — он и есть последний в файле, запятой нет, а следом идут новые
    #            блоки, значит её надо добавить.
    final_count = len(kept_blocks) + len(new_items)
    for idx, item in enumerate(new_items):
        last = idx == len(new_items) - 1
        if idx == 0 and kept_blocks[-1].endswith(" }"):
            # последний сохранённый блок не был последним в файле — у него нет
            # запятой, а следом идут новые блоки
            kept_blocks[-1] += ","
        kept_blocks.append(make_block(item, comma=not last))
    out = prefix + "\n".join(kept_blocks) + suffix
    with open(DB, "w", encoding="utf-8", newline="") as f:
        f.write(out)

    with open(DB, encoding="utf-8") as f:
        check = json.load(f)
    print(f"после записи: {len(check)} предметов, JSON валиден")
    if len(check) != final_count:
        print(f"FAIL: расхождение {len(check)} != {final_count}")
        return 2
    leftover = [str(i.get("key")) for i in check
                if str(i.get("material")) in DROP_MATERIALS
                and str(i.get("type")) not in KEEP_TYPES]
    print("остатки нежелательных материалов (должно быть 0):", len(leftover))
    print(f"RESULT: OK удалено {len(dropped_keys)}, добавлено {len(new_items)}, "
          f"итого {len(check)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
