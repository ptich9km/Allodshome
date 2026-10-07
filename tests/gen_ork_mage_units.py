#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Вставить 4 набора ork_mage в units_db.json текстово, без перезаписи файла."""
from __future__ import annotations

import json
import os
import re

PATH = os.path.join("assets", "units", "units_db.json")
NAMES = [
    ("ork_mage/t0", "Орк-маг (слабый)", 0),
    ("ork_mage/t1", "Орк-маг", 1),
    ("ork_mage/t2", "Орк-маг (средний)", 2),
    ("ork_mage/t3", "Орк-маг (сильный)", 3),
]


def make_set(desc: str, tier: int) -> dict:
    return {
        "desc": desc,
        "folder": f"ork_mage/t{tier}",
        "prefix": "sprites",
        "frames": 8,
        "dirs": 8,
        "move": 1,
        "move_begin": 0,
        "attack": 0,
        "dying": 0,
        "decay": 0,
        "cast": 0,
        "idle": 0,
        "idle_phases": 0,
        "move_f": [0],
        "move_t": [2],
        "attack_f": [],
        "attack_t": [],
        "die_f": [],
        "dying_t": [],
        "w": 40,
        "h": 40,
        "cx": 20,
        "cy": 38,
        "tile": None,
        "projectile": -1,
        "palette": 0,
        "ids": [],
        "picture": None,
        "blocks": 1,
        "expected_frames": 8,
        "sel_box": [12, 8, 28, 38],
        "attack_delay": 4,
        "info_picture": None,
        "sound": [],
        "resist": {"fire": 0, "water": 0, "air": 0, "earth": 0, "astral": 0},
        "tile_size": 1,
        "z": 0,
        "flip": 0,
        "bone": 0,
        "shoot_delay": 8,
        "shoot_offset": [],
    }


def fmt(value, indent: int) -> str:
    """Формат как в units_db.json: объект — ключи indent, массив — indent+1, close indent-1."""
    sp = " " * indent
    if isinstance(value, dict):
        if not value:
            return "{}"
        parts = [f'{sp} "{k}": {fmt(v, indent + 1)}' for k, v in value.items()]
        return "{\n" + ",\n".join(parts) + "\n" + (" " * (indent - 1)) + "}"
    if isinstance(value, list):
        if not value:
            return "[]"
        parts = [f"{sp} {fmt(v, indent + 1)}" for v in value]
        return "[\n" + ",\n".join(parts) + "\n" + (" " * (indent - 1)) + "]"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(value)


def main() -> int:
    with open(PATH, encoding="utf-8", newline="") as f:
        raw = f.read()
    # detect EOL
    eol = "\r\n" if "\r\n" in raw else "\n"
    db = json.loads(raw)
    existing = [k for k, _, _ in NAMES if k in db]
    if existing:
        print("already present:", existing)
        return 0

    blocks = []
    for key, desc, tier in NAMES:
        obj = make_set(desc, tier)
        # fmt with indent=2 → keys at 2 spaces, close at 1 space
        blocks.append(f' "{key}": {fmt(obj, 2)}')

    insert = ",\n".join(blocks)
    # insert before final closing brace
    stripped = raw.rstrip()
    if not stripped.endswith("}"):
        print("unexpected file end")
        return 1
    body = stripped[:-1].rstrip()
    # ensure trailing comma on last existing entry
    if not body.endswith(","):
        body += ","
    new_raw = body + "\n" + insert + "\n}" + eol
    with open(PATH, "w", encoding="utf-8", newline="") as f:
        f.write(new_raw)
    print("inserted 4 sets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
