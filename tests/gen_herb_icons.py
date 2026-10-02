#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Привязка иконок трав к настоящему арту (этап 1 чистки, продолжение).

Находка игрока: «по ходу удалил растения для професии Алхимия».
Проверка показала: ничего не удалено, все 8 растений на месте
(assets/professions/herbalism/*.png), рецепты и ингредиенты целы.

Настоящая причина: на КАРТЕ растения рисуются настоящим артом
(map_generator.gd HERB_ITEMS -> herb_node.gd), а в ИНВЕНТАРЕ и в панели
алхимии все 8 предметов Herb смотрели на один и тот же
assets/items/placeholder/herb.png. То есть игрок видел серые квадраты там,
где ждал растения.

Маппинг берётся из HERB_ITEMS в map_generator.gd - это источник правды:
что рисуется на карте, то и должно быть в инвентаре.

Правка JSON ТЕКСТОВАЯ (журнал §12: json.dumps переформатирует файл).

Запуск:
    python tests/gen_herb_icons.py --dry-run
    python tests/gen_herb_icons.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

DB = os.path.join("assets", "items", "item_db.json")
HERBALISM = "res://assets/professions/herbalism/"

# Ключ item_db -> файл в assets/professions/herbalism/.
# Порядок и состав совпадают с HERB_ITEMS в scripts/world/map_generator.gd.
HERBS = {
    "Herb Green Leaf": "green_leaf.png",
    "Herb White Flower": "white_flower.png",
    "Herb Red Berry": "red_berry.png",
    "Herb Tall Grass": "tall_grass.png",
    "Herb Lavender": "lavender.png",
    "Herb Mint": "mint.png",
    "Herb Dandelion": "dandelion.png",
    "Herb Broad Leaf": "broad_leaf.png",
}

OLD_PLACEHOLDER = "res://assets/items/placeholder/herb.png"


def split_blocks(text: str) -> tuple[str, list[str], str]:
    """(префикс, [тексты блоков], суффикс). Блоки как есть: у части
    предметов effects записан в несколько строк, пересборка из словаря
    схлопнула бы его."""
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
    prefix = text[: text.index(blocks[0])]
    suffix = text[text.rindex(blocks[-1]) + len(blocks[-1]) :]
    return prefix, blocks, suffix


def parse_block(block: str) -> dict:
    return json.loads("[" + block.rstrip().rstrip(",") + "]")[0]


def key_of(block: str) -> str:
    m = re.search(r'^\s*"key":\s*"(.*)",\s*$', block, re.M)
    return m.group(1) if m else ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    # сперва проверяем, что весь арт на месте - иначе правка сделает битые ссылки
    missing_files = [f for f in HERBS.values()
                     if not os.path.exists(HERBALISM.replace("res://", "") + f)]
    if missing_files:
        print("FAIL: нет файлов арта:", missing_files)
        return 2

    with open(DB, encoding="utf-8", newline="") as f:
        raw = f.read()
    nl = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")

    prefix, blocks, suffix = split_blocks(text)
    changed: list[tuple[str, str]] = []
    out: list[str] = []

    for b in blocks:
        key = key_of(b)
        if key not in HERBS:
            out.append(b)
            continue
        new_icon = HERBALISM + HERBS[key]
        m = re.search(r'^(\s*)"icon":\s*"([^"]*)"(,?)\s*$', b, re.M)
        if m is None:
            raise SystemExit(f"FAIL: не найдена строка icon у {key}")
        if m.group(2) == new_icon:
            out.append(b)
            continue
        # запятая берётся из исходной строки: у последнего поля её нет
        newline = '%s"icon": "%s"%s' % (m.group(1), new_icon, m.group(3))
        out.append(b[: m.start()] + newline + b[m.end():])
        changed.append((key, m.group(2)))

    print(f"трав в базе: {len(HERBS)}")
    print(f"перепривязано: {len(changed)}")
    for k, old in changed:
        print(f"  {k:22} {str(old).split('/')[-1]:20} -> {HERBS[k]}")

    # контроль: после правки ни одна трава не должна смотреть на заглушку
    left = [key_of(b) for b in out if OLD_PLACEHOLDER in b]
    print(f"трав на заглушке после правки (должно быть 0): {len(left)}")

    if args.dry_run:
        print("RESULT: OK (dry-run, файл не тронут)")
        return 0

    result = prefix + "\n".join(out) + suffix
    with open(DB, "w", encoding="utf-8", newline="") as f:
        f.write(result)

    with open(DB, encoding="utf-8") as f:
        check = json.load(f)
    print(f"после записи: {len(check)} предметов, JSON валиден")
    # проверяем, что каждая трава теперь указывает на существующий файл
    bad = []
    for i in check:
        k = str(i.get("key", ""))
        if k in HERBS:
            p = str(i.get("icon", "")).replace("res://", "").replace("/", os.sep)
            if not os.path.exists(p):
                bad.append((k, p))
    print(f"битых ссылок у трав: {len(bad)} {bad if bad else ''}")
    if bad:
        return 2
    print(f"RESULT: OK перепривязано {len(changed)} трав")
    return 0


if __name__ == "__main__":
    sys.exit(main())