#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Вписать `loot_family` в наборы Серых в `assets/units/units_db.json`.

Зачем. `assets/config/loot_tables.json` выбирается по семейству вида, но поля
`loot_family` в базе не было ни у одного набора (проверено 22.10: 108 записей,
поле отсутствует). Код на это не полагается — `UnitDB.loot_family_of` выводит
семейство из вида, — но явное поле в базе нужно, чтобы база была самодостаточна
и смена вида в LOOT_BY_SPECIES не меняла лут молча.

Старый `add_loot_family.py` сюда не подходит: он ищет готовые ключи и не
переживает тировых дублей. Поэтому запись ищется по ВИДУ (`monsters/<вид>` и
`monsters/<вид>_t<N>`).

Формат правится ТЕКСТОВОЙ вставкой, а не json.dump всего файла (правило проекта,
см. gen_grey_tiers_db.py): соседние записи и их форматирование не трогаются.
Поле ставится сразу после `"name_ru"` в записи (отступ 2 пробела, как в файле).

Запуск:
    python tests/gen_gray_loot_family.py --check   # сколько записей уже с полем
    python tests/gen_gray_loot_family.py           # записать поле
    python tests/gen_gray_loot_family.py --revert  # убрать поле обратно
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "units", "units_db.json")

# Семейство по виду — один в один UnitDB.LOOT_BY_SPECIES (scripts/unit_db.gd).
FAMILY = {
    "bat": "beast",
    "squirrel": "beast",
    "wolf": "beast",
    "bee": "insect",
    "ghost": "undead",
    "cannibal": "humanoid",
    "troll": "humanoid",
    "dino": "monstrous",
    "dragon": "monstrous",
    "succubus": "monstrous",
}

HEADER = re.compile(r'^[ \t]*"monsters/([a-z_0-9]+?)(?:_t[2-9])?": \{\r?$')
CLOSE = re.compile(r'^[ \t]*\},?[ \t]*\r?$')


FIELD_LINE = '  "loot_family": "%s",'


def line_key(line: str) -> str:
    """` "monsters/wolf_t3": {` -> `monsters/wolf_t3`."""
    return line.strip().lstrip('"').split('"', 1)[0]


def species_of(key: str) -> str:
    """`monsters/wolf_t3` -> `wolf`."""
    short = key.strip().rstrip('":{\r').split("/", 1)[-1]
    return re.sub(r"_t[2-9]$", "", short)


def block_span(lines: list[str], start: int) -> int:
    """Индекс первой строки ПОСЛЕ закрывающейся ` }` блока с заголовком start."""
    i = start + 1
    while i < len(lines):
        if CLOSE.match(lines[i]):
            return i + 1
        i += 1
    raise SystemExit("units_db: не закрыт блок %s" % lines[start].strip())


def field_index(lines: list[str], start: int, end: int) -> int:
    """Индекс строки с `loot_family` внутри блока или -1."""
    for i in range(start, end):
        if lines[i].strip().startswith('"loot_family":'):
            return i
    return -1


def insert_field(lines: list[str], start: int, end: int, family: str) -> None:
    """Вставить поле после `"name_ru"` (или в начало блока, если его нет)."""
    for i in range(start, end):
        if lines[i].startswith('  "name_ru":'):
            lines.insert(i + 1, FIELD_LINE % family)
            return
    lines.insert(start + 1, FIELD_LINE % family)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="только сверить, не писать")
    ap.add_argument("--revert", action="store_true", help="убрать поле обратно")
    args = ap.parse_args()

    with open(DB, encoding="utf-8", newline="") as fh:
        raw = fh.read()
    eol = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.split(eol)
    orig = eol.join(lines)

    found = 0
    with_field = 0
    changed = 0
    others: list[str] = []
    i = 0
    while i < len(lines):
        if not HEADER.match(lines[i]):
            i += 1
            continue
        key = line_key(lines[i])
        family = FAMILY.get(species_of(key), "")
        end = block_span(lines, i)
        found += 1
        at = field_index(lines, i, end)
        if args.revert:
            if at >= 0:
                del lines[at]
                changed += 1
            i = block_span(lines, i)
            continue
        if not family:
            if at >= 0:
                others.append(key)
            i = end
            continue
        if at >= 0:
            with_field += 1
            i = end
            continue
        insert_field(lines, i, end, family)
        changed += 1
        end = block_span(lines, i)
        i = end

    text = eol.join(lines)
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        print("RESULT: FAIL — после правки JSON не разбирается: %s" % exc)
        return 1

    bad: list[str] = []
    for key, rec in parsed.items():
        if not isinstance(rec, dict):
            continue
        if not key.startswith("monsters/"):
            if "loot_family" in rec:
                others.append(key)
            continue
        if rec.get("loot_family", "") != FAMILY.get(species_of(key), ""):
            bad.append(key)
    print("блоков Серых: %d, уже с полем: %d, изменено: %d, лишних: %d"
          % (found, with_field, changed, len(others)))
    for k in others:
        print("  ! поле loot_family не по адресу: %s" % k)
    for k in bad:
        print("  ! семейство не совпало: %s" % k)

    if args.check:
        problems = len(bad) + len(others)
        print("RESULT: %s check (расхождений: %d)"
              % ("OK" if problems == 0 else "WARN", problems))
        return 0
    if text == orig:
        print("RESULT: OK gray_loot_family (без изменений)")
        return 0
    with open(DB, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    recheck = json.load(open(DB, encoding="utf-8"))
    bad = [k for k, rec in recheck.items()
           if k.startswith("monsters/")
           and isinstance(rec, dict)
           and rec.get("loot_family", "") != FAMILY.get(species_of(k), "")]
    ok = not bad and not others
    print("RESULT: %s gray_loot_family (расхождений после записи: %d)"
          % ("OK" if ok else "FAIL", len(bad) + len(others)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
