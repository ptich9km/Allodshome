"""Ставит поле `boss: 1` боссам и драконам в assets/units/units_db.json.

ЗАЧЕМ. С 07.10 только боссы и драконы роняют ЦЕЛУЮ вещь вместо сломанной
(enemy.gd:_make_loot -> [craft] boss_intact_chance). Признака босса в базе
НЕ БЫЛО: ни level, ни tier, ни elite, ни is_boss. Косвенным признаком мог бы
быть tile_size (дракон 3, тролль 2), но это размер спрайта, а не «босс» -
у humans/catapult1 тоже tile_size 2, и мина выстрелила бы при появлении
крупного обычного моба.

СПИСОК ЗАДАВАН ВРУЧНУЮ, а не выведен из tile_size. Это осознанно: «крупный
= босс» перестаёт работать, как только в игре появится крупный рядовой зверь,
и тогда лут начнёт раздавать целые вещи кому попало.

Правка ТЕКСТОВАЯ, по одному полю на запись: json.dumps пересобрал бы весь
файл (units_db.json — большой, с многострочными массивами resist).

Запуск:
    python tests/add_boss_flag.py --dry-run
    python tests/add_boss_flag.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "units", "units_db.json")

# Кто роняет целую вещь вместо сломанной.
BOSSES = [
    "monsters/dragon",
    "monsters/troll",
    "monsters/ogre",
    "monsters/mainnecro",
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        raw = fh.read()
    data = json.loads(raw)

    missing = [b for b in BOSSES if b not in data]
    if missing:
        print("НЕТ таких наборов в базе:")
        for m in missing:
            print("   ! %s" % m)
        return 1

    already = [b for b in BOSSES if int(data[b].get("boss", 0)) != 0]
    todo = [b for b in BOSSES if b not in already]
    print("Боссов в списке: %d, уже помечены: %d, к пометке: %d"
          % (len(BOSSES), len(already), len(todo)))
    for b in todo:
        print("   + %-24s tile_size=%s  %s"
              % (b, data[b].get("tile_size", 1), data[b].get("desc", "")))

    if args.dry_run:
        print("DRY-RUN: база не изменена")
        return 0
    if not todo:
        print("Помечать нечего - база уже в нужном состоянии")
        return 0

    # Правка ТЕКСТОВАЯ: вставляем поле сразу после открывающей скобки записи.
    # Ключ объекта и есть имя набора (поля "name" в базе нет), а записи
    # содержат многострочные массивы move_f/attack_t/resist - json.dumps
    # пересобрал бы весь файл и развёл его на тысячи строк.
    out = raw
    done = 0
    for name in todo:
        pat = re.compile(r'("%s"\s*:\s*\{\n)' % re.escape(name))
        new, n = pat.subn(r'\1  "boss": 1,\n', out, count=1)
        if n != 1:
            print("   ! не нашёл блок %s" % name)
            return 2
        out = new
        done += 1

    # Проверка: результат обязан оставаться валидным JSON и содержать ровно
    # столько же ключей, сколько было.
    check = json.loads(out)
    if len(check) != len(data):
        print("ВНИМАНИЕ: число наборов изменилось %d -> %d" % (len(data), len(check)))
        return 2
    for b in BOSSES:
        if int(check[b].get("boss", 0)) != 1:
            print("   ! %s не помечен" % b)
            return 2

    with open(DB, "w", encoding="utf-8", newline="") as fh:
        fh.write(out)
    print("Помечено: %d, записано: %s" % (done, DB))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())