#!/usr/bin/env python3
"""Внести тиры Серых в `assets/units/units_db.json`.

Что делает:
- в 7 базовых наборов (`monsters/<вид>`) дописывает `name_ru` и `tier: 1`;
- добавляет 28 новых записей `monsters/<вид>_t<2..5>` из `_entry.json`,
  которые уже лежат рядом с кадрами (их пишет `gen_grey_tiers.py`).

ФОРМАТ ПРАВИТСЯ ТЕКСТОВОЙ ВСТАВКОЙ, а не `json.dump` всего файла. Это правило
проекта: `json.dumps(indent=1)` по разобранному файлу переформатировал бы
многострочные блоки (например `effects` у части предметов) и затирал бы
несозданные правки соседних записей. Здесь файл НЕ переписывается целиком:
- новые записи ДОПИСЫВАЮТСЯ в конец перед последней `}`;
- `name_ru`/`tier` в базовые блоки ВСТАВЛЯЮТСЯ после строки `"monsters/<вид>": {`.

Формат совпадает с существующим: отступ 1 пробел (файл записан в
`indent=1`), поэтому один блок печатается `json.dumps(..., indent=1)` со
сдвигом на один пробел.

    python tests/gen_grey_tiers_db.py --check      # ничего не писать
    python tests/gen_grey_tiers_db.py              # записать
    python tests/gen_grey_tiers_db.py --revert     # убрать тиры обратно
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_grey_tiers as G  # noqa: E402

DB = G.REPO / "assets" / "units" / "units_db.json"
BASE_NAMES = sorted(G.SPECIES_RU)


def _block(key: str, entry: dict) -> str:
    """Готовая запись базы в формате файла (отступ 1 пробел)."""
    body = json.dumps(entry, indent=1, ensure_ascii=False)
    body = "\n".join(" " + ln for ln in body.split("\n"))
    return f' "{key}": {body}'


def base_insert(text: str, name: str, name_ru: str) -> str:
    """Вставить `name_ru`/`tier: 1` в базовый блок вида (если их ещё нет)."""
    head = f' "monsters/{name}": {{\n  "desc"'
    # Порядок проверок важен: сначала «уже вставлено», и только потом поиск
    # заголовка. Обратный порядок ронял повторный прогод, потому что после
    # первой вставки блок начинается с `name_ru`, а не с `desc`, и поиск по
    # `desc` даёт 0 совпадений -> SystemExit на втором же запуске.
    if f' "monsters/{name}": {{\n  "name_ru"' in text:
        return text
    if text.count(head) != 1:
        raise SystemExit(f"monsters/{name}: не найден уникальный заголовок блока")
    new = (f' "monsters/{name}": {{\n'
           f'  "name_ru": {json.dumps(name_ru, ensure_ascii=False)},\n'
           f'  "tier": 1,\n'
           f'  "desc"')
    return text.replace(head, new, 1)


def build(apply_changes: bool) -> int:
    raw = DB.read_text(encoding="utf-8")
    orig = raw

    for name in BASE_NAMES:
        # `base_insert` умеет только ДОПИСАТЬ в существующий блок. У нового вида
        # блока в базе ещё нет, и он добавляется целиком ниже.
        if f' "monsters/{name}": {{' in raw:
            raw = base_insert(raw, name, G.tier_name(name, 1))

    # Убрать ранее добавленные тирные записи, чтобы повторный прогон был no-op.
    while True:
        blocks = re.findall(r'\n "monsters/[a-z_0-9]+_t[2-5]": \{.*?\n \}(?=,\n|\n \}\n\})',
                            raw, re.S)
        if not blocks:
            break
        raw = raw.replace(blocks[0], "", 1)

    # Вставить новые записи перед последней закрывающей скобкой объекта.
    add = []
    for name in BASE_NAMES:
        # 17.10: вид может быть НОВЫМ — тогда базовой записи `monsters/<вид>` в
        # базе ещё нет, и её надо добавить целиком (нарезчик пишет только
        # `_entry.json`, базу не трогает). Для старых видов блок уже есть, и
        # `base_insert` выше дописал в него `name_ru`/`tier`.
        base_key = f"monsters/{name}"
        if f' "{base_key}": {{' not in raw:
            base_entry_path = G.SRC_ROOT / name / "_entry.json"
            if not base_entry_path.exists():
                raise SystemExit(
                    f"нет {base_entry_path}: прогони extract_monster_nb.py {name}")
            base_entry = json.loads(base_entry_path.read_text(encoding="utf-8"))
            base_entry = {"name_ru": G.tier_name(name, 1), "tier": 1, **base_entry}
            add.append(_block(base_key, base_entry))
        for tier, *_ in G.TIERS:
            key = f"monsters/{name}_t{tier}"
            entry_path = G.SRC_ROOT / f"{name}_t{tier}" / "_entry.json"
            if not entry_path.exists():
                raise SystemExit(f"нет {entry_path}: сначала прогони gen_grey_tiers.py --build")
            entry = json.loads(entry_path.read_text(encoding="utf-8"))
            add.append(_block(key, entry))
    tail = raw.rstrip()
    if not tail.endswith("}"):
        raise SystemExit("хвост units_db.json не похож на закрывающую скобку")
    body = tail[:-1].rstrip()
    if body.endswith("},"):
        body = body[:-1]
    merged = body + ",\n" + ",\n".join(add) + "\n}\n"

    if apply_changes:
        DB.write_text(merged, encoding="utf-8", newline="")

    # Проверка результата — ИНВАРИАНТ, а не арифметика «сколько добавили».
    # Ожидание вида «len(было) + len(add)» тихо врало: 28 уже существующих
    # тирных записей сначала вычитаются, потом добавляются снова, и в сумме
    # они учитывались дважды. Настоящее требование: у каждого вида ровно
    # 5 наборов (тиры 1..5), и у каждого есть `name_ru` и `tier`.
    data = json.loads(merged)
    want_per_species = 1 + len(G.TIERS)
    problems = []
    for name in BASE_NAMES:
        for tier in range(1, want_per_species + 1):
            key = f"monsters/{name}" if tier == 1 else f"monsters/{name}_t{tier}"
            entry = data.get(key)
            if not isinstance(entry, dict):
                problems.append(f"нет записи {key}")
                continue
            if not str(entry.get("name_ru", "")):
                problems.append(f"{key}: нет name_ru")
            if int(entry.get("tier", 0)) != tier:
                problems.append(f"{key}: tier={entry.get('tier')} (ожидался {tier})")
    print(f"ключей всего: {len(data)}; видов: {len(BASE_NAMES)}; "
          f"наборов на вид: {want_per_species}")
    for pr in problems[:8]:
        print("  ПРОБЛЕМА:", pr)
    if problems:
        return 1
    print("ЗАПИСАНО: ок" if apply_changes else "ПРОВЕРКА: ок")
    return 0


def revert() -> int:
    raw = DB.read_text(encoding="utf-8")
    while True:
        blocks = re.findall(r'\n "monsters/[a-z_0-9]+_t[2-5]": \{.*?\n \}(?=,\n|\n \}\n\})',
                            raw, re.S)
        if not blocks:
            break
        raw = raw.replace(blocks[0], "", 1)
    for name in BASE_NAMES:
        raw = re.sub(r'\n  "name_ru": "[^"]*",\n  "tier": 1,',
                     "", raw, count=1)
    DB.write_text(raw, encoding="utf-8", newline="")
    print(f"откачено, ключей: {len(json.loads(raw))}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="ничего не писать")
    ap.add_argument("--revert", action="store_true")
    args = ap.parse_args()
    if args.revert:
        return revert()
    return build(apply_changes=not args.check)


if __name__ == "__main__":
    sys.exit(main())