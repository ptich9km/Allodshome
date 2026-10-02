#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Этап 1 чистки: убрать остатки старой игры, привязать посохи к новому арту.

Что делает:
  1. Удаляет 20 предметов `Quest *` (Crown, Rune, Meta, Treasure, Stone, Map,
     Ingredient, Head, Documents, Banner, Amulet, Ring) - это пережитки
     Аллодов, и в игре нет системы квестов, так что они лежат мёртвым грузом
     на иконках-заглушках. Решение игрока, 01.10.
  2. Удаляет 2 мёртвых зелья `Potion Fighter Bonus` / `Potion Mage Bonus`:
     их effects содержат только временный реген (с "duration"), поэтому
     player.use_potion() их не расходует и не даёт ничего.
  3. Привязывает 6 предметов `Shaman Staff` к новому арту посохов - раньше
     на новый арт попали только обычные `Staff`, а шаманские остались
     на заглушке.

Правка JSON ТЕКСТОВАЯ: блоки вырезаются как есть, без json.dumps
(журнал §12: переформатирование файла ломает diff и ревью).

Запуск:
    python tests/gen_cleanup_quests.py --dry-run
    python tests/gen_cleanup_quests.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

DB = os.path.join("assets", "items", "item_db.json")
STAFF_DIR = os.path.join("assets", "items", "staff")

# Остатки старой игры.
QUEST_PREFIX = "Quest "
DEAD_POTIONS = {"Potion Fighter Bonus", "Potion Mage Bonus"}

# Шаманский посох по качеству: 4 тира арта staff_{cheap,common,good,elite}.
# Для обычного Staff качества Common/Uncommon/Elven -> common, Good -> good,
# Very Rare -> elite; здесь та же логика плюс дешёвый тир для Bad.
SHAMAN_ICON = {
    "Bad": "staff_cheap.png",
    "Common": "staff_common.png",
    "Uncommon": "staff_common.png",
    "Rare": "staff_good.png",
    "Good": "staff_good.png",
    "Very Rare": "staff_elite.png",
    "Elven": "staff_common.png",
}

# Обычный Staff на ветке уже привязан к новому арту, но к пути
# assets/items/placeholder/ - файлы переехали в assets/items/staff/.
# Тот же закон «качество -> тир арта», поэтому таблица общая.


def split_blocks(text: str) -> tuple[str, list[str], str]:
    """(префикс, [тексты блоков], суффикс). Блоки возвращаются КАК ЕСТЬ:
    у части предметов effects записан в несколько строк, и пересборка из
    словаря схлопнула бы его - это переформатирование файла."""
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
    first = text.index(blocks[0])
    prefix = text[:first]
    last = text.rindex(blocks[-1])
    suffix = text[last + len(blocks[-1]) :]
    return prefix, blocks, suffix


def parse_block(block: str) -> dict:
    return json.loads("[" + block.rstrip().rstrip(",") + "]")[0]


def key_of(block: str) -> str:
    m = re.search(r'^\s*"key":\s*"(.*)",\s*$', block, re.M)
    return m.group(1) if m else ""


def should_drop(item: dict) -> bool:
    k = str(item.get("key", ""))
    return k.startswith(QUEST_PREFIX) or k in DEAD_POTIONS


def staff_icon_for(item: dict) -> str | None:
	## Посох любого из двух типов, привязываемый к новому арту:
	## обычный Staff меняет путь (файлы переехали из placeholder/),
	## Shaman Staff меняет ещё и саму картинку.
    if str(item.get("type", "")) not in ("Staff", "Shaman Staff"):
        return None
    quality = str(item.get("quality", ""))
    fname = SHAMAN_ICON.get(quality)
    if fname is None:
        return None
    return "res://assets/items/staff/" + fname


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

    # --- что удаляем ---
    dropped = [str(i.get("key")) for i in items if should_drop(i)]
    print(f"удаляется: {len(dropped)}   остаётся: {len(items) - len(dropped)}")
    quests = [k for k in dropped if k.startswith(QUEST_PREFIX)]
    print(f"  из них Quest-предметов: {len(quests)}")
    print(f"  мёртвых зелий: {len(dropped) - len(quests)}")

    # --- привязка посохов ---
    rewired: list[tuple[str, str]] = []
    new_blocks: list[str] = []
    for b in blocks:
        item = parse_block(b)
        if should_drop(item):
            continue
        icon = staff_icon_for(item)
        if icon is None:
            new_blocks.append(b)
            continue
        real = icon.replace("res://", "").replace("/", os.sep)
        if not os.path.exists(real):
            raise SystemExit(f"FAIL: нет файла арта {real} (сначала перенеси staff_*.png)")
        old_line = re.search(r'^(\s*)"icon":\s*"[^"]*"(,?)\s*$', b, re.M)
        if old_line is None:
            raise SystemExit(f"FAIL: не найдена строка icon в блоке {key_of(b)}")
        # Запятая после поля берётся ИЗ ИСХОДНОЙ строки: у последнего поля
        # блока её нет, и дописывание давало "trailing comma before }".
        newline = '%s"icon": "%s"%s' % (old_line.group(1), icon, old_line.group(2))
        new_blocks.append(b[: old_line.start()] + newline + b[old_line.end() :])
        rewired.append((key_of(b), icon))

    print(f"посохов привязано к новому арту: {len(rewired)}")
    for k, ic in rewired:
        print(f"  {k:36} -> {ic}")

    # --- проверка: ни у кого не осталось заглушки среди посохов ---
    leftovers = [key_of(b) for b in new_blocks
                 if str(parse_block(b).get("type", "")) in ("Staff", "Shaman Staff")
                 and "placeholder" in b]
    print(f"посохов на заглушке после правки (должно быть 0): {len(leftovers)}")
    if leftovers:
        print("   ", leftovers)

    if args.dry_run:
        print(f"RESULT: OK (dry-run, было {len(items)}, станет {len(new_blocks)})")
        return 0

    out = prefix + "\n".join(new_blocks) + suffix
    with open(DB, "w", encoding="utf-8", newline="") as f:
        f.write(out)

    with open(DB, encoding="utf-8") as f:
        check = json.load(f)
    print(f"после записи: {len(check)} предметов, JSON валиден")
    if len(check) != len(new_blocks):
        print(f"FAIL: расхождение {len(check)} != {len(new_blocks)}")
        return 2
    still_quest = [str(i.get("key")) for i in check
                   if str(i.get("key", "")).startswith(QUEST_PREFIX)
                   or str(i.get("key")) in DEAD_POTIONS]
    if still_quest:
        print("FAIL: остались удаляемые:", still_quest)
        return 2
    print(f"RESULT: OK удалено {len(dropped)}, привязано {len(rewired)}, "
          f"осталось {len(check)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())