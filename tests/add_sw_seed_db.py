#!/usr/bin/env python3
"""Добавляет набор heroes/sw_seed в units_db.json текстовой вставкой.

json.dump НЕ используется: база ориентирована на indent=1, и пересборка
разъехалась бы на тысячи строк (та же ошибка, что с spell_db).
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DB = REPO / "assets" / "units" / "units_db.json"

KEY = "seed/sw_seed"

ENTRY = '''"heroes/sw_seed": {
  "desc": "Hero: swordsman, seedream pilot, 8 dirs, idle 8 + move 2 + attack 2",
  "folder": "heroes/sw_seed",
  "frames": 40,
  "prefix": "sprites",
  "dirs": 8,
  "idle_phases": 8,
  "move": 2,
  "move_begin": 0,
  "attack": 2,
  "dying": 0,
  "decay": 0,
  "cast": 0,
  "idle": 0,
  "move_f": [],
  "move_t": [],
  "attack_f": [],
  "attack_t": [],
  "die_f": [],
  "dying_t": [],
  "w": 64,
  "h": 64,
  "cx": 32,
  "cy": 62,
  "tile": null,
  "projectile": -1,
  "palette": 0,
  "blocks": 5,
  "resist": {
   "fire": 10,
   "water": 10,
   "air": 10,
   "earth": 10,
   "astral": 10
  }
 }'''


def main() -> None:
    raw = DB.read_text(encoding="utf-8")
    if KEY in raw:
        print("уже есть, ничего не делаю")
        return
    i = raw.rindex("}")
    head = raw[:i].rstrip()
    if not head.endswith(","):
        head += ","
    out = head + "\n " + ENTRY + "\n}\n"
    DB.write_text(out, encoding="utf-8", newline="")

    db = json.loads(DB.read_text(encoding="utf-8"))
    v = db[KEY]
    print("наборов в базе:", len(db))
    print("проверка:", {k: v[k] for k in
                       ("frames", "dirs", "idle_phases", "move", "attack",
                        "w", "h", "cx", "cy")})
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)