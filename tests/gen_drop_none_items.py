"""Удаляет 47 экипируемых предметов с material="None" (пережиток Аллодов).

ЧТО УДАЛЯЕТСЯ. Одежда без материала: Dress 7, Cap 6, Cloak 5, Cape 5, Gloves 5,
Hat 5, Low Hat 5, Shoes 5, Robe 4. Всё это одежда Аллодов, которой не из чего
красить: материала нет, значит нет и фракционной иконки (их цвет задаётся
металлом, см. gen_item_icons.py). Удерживать их нечем.

ЧТО НЕ ТРОГАЕТСЯ. 104 неэкипируемых предмета с material="None" - это свитки,
книги, квесты, зелья и травы. Их игрок прямо просил сохранить, и они никуда не
годились для переплавки (is_smeltable режет по списку металлов), так что
удаление было бы потерей без причины.

ПОЧЕМУ НЕ ЧЕРЕЗ СПИСОК ТИПОВ. Список "удалить эти 9 типов" выглядит надёжнее,
но он же и опаснее: тип "Cap" или "Hat" существует ещё и в других материалах,
и такое удаление вырезало бы живые вещи. Здесь отбор по признаку
(экипируемый + material == "None"), и инварианты проверяют, что под нож не
попал ни один предмет вне девяти ожидаемых типов.

Запуск:
    python tests/gen_drop_none_items.py --dry-run
    python tests/gen_drop_none_items.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")

# Типы, которые обязаны исчезнуть. Если появится новый тип с material=None и
# экипируемый - скрипт остановится и потребует решения, а не удалит молча.
EXPECTED_TYPES = {
    "Dress": 7, "Cap": 6, "Cloak": 5, "Cape": 5, "Gloves": 5,
    "Hat": 5, "Low Hat": 5, "Shoes": 5, "Robe": 4,
}
EXPECTED_TOTAL = 47

# Качество, по которому предмет носить нельзя. В коде это
# ItemDB.is_equippable(), здесь - тот же список.
NON_EQUIPPABLE_QUALITY = {"Book", "Potion", "Scroll", "SuperScroll", "Quest", "Herb"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        data = json.load(fh)

    before = len(data)
    doomed = []
    for i in data:
        d = i
        mat = str(d.get("material", ""))
        typ = str(d.get("type", ""))
        qual = str(d.get("quality", ""))
        if mat not in ("None", "<null>"):
            continue
        if typ == "Ingot" or qual in NON_EQUIPPABLE_QUALITY:
            continue  # слитки и расходники остаются
        doomed.append(d)

    got_types: dict = {}
    for d in doomed:
        got_types[str(d.get("type", ""))] = got_types.get(str(d.get("type", "")), 0) + 1

    print("БЫЛО: %d предметов" % before)
    print("К УДАЛЕНИЮ: %d" % len(doomed))
    for t, n in sorted(got_types.items(), key=lambda kv: -kv[1]):
        print("  %-12s %3d" % (t, n))

    # инварианты
    if len(doomed) != EXPECTED_TOTAL:
        print("! ожидалось %d предметов, найдено %d - состав изменился"
              % (EXPECTED_TOTAL, len(doomed)))
        return 1
    if got_types != EXPECTED_TYPES:
        print("! набор типов не совпал с ожидаемым")
        print("   лишние: %s" % sorted(set(got_types) - set(EXPECTED_TYPES)))
        print("   не хватает: %s" % sorted(set(EXPECTED_TYPES) - set(got_types)))
        return 1

    keys = [str(d.get("key", "")) for d in doomed]
    dups = sorted({k for k in keys if keys.count(k) > 1})
    if dups:
        print("! дубли ключей среди удаляемых: %s" % dups)
        return 1

    # после удаления ключи остальных предметов не должны потерять уникальность
    dropped = set(keys)
    rest = [str(i.get("key", "")) for i in data if i not in doomed]
    if len(rest) != len(set(rest)):
        print("! в оставшихся предметах есть дубли ключей")
        return 1

    if args.dry_run:
        print("ПОСЛЕ: %d предметов (минус %d)" % (before - len(doomed), len(doomed)))
        print("DRY-RUN: файлы не записаны")
        return 0

    keep = [i for i in data if i not in doomed]
    print("ПОСЛЕ: %d предметов" % len(keep))
    with open(DB, "w", encoding="utf-8") as fh:
        json.dump(keep, fh, ensure_ascii=False, indent=1)
    print("ГОТОВО: %s" % DB)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())