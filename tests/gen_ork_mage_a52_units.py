#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Вставить 4 набора ork_mage_a52 (вариант A, H=52 nearest) в units_db.json.

Холст 64×64, content ~32×52, feet y=62, tile_size=1 → 1.62 тайла.
Текстовая вставка, без json.dumps всего файла.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_ork_mage_units import fmt, make_set  # noqa: E402

PATH = os.path.join("assets", "units", "units_db.json")
NAMES = [
    ("ork_mage_a52/t0", "Орк-маг A52 (слабый)", 0),
    ("ork_mage_a52/t1", "Орк-маг A52", 1),
    ("ork_mage_a52/t2", "Орк-маг A52 (средний)", 2),
    ("ork_mage_a52/t3", "Орк-маг A52 (сильный)", 3),
]

# content ~32×52 на холсте 64, низ content y=62
SEL = [16, 12, 48, 62]


def make_a52(desc: str, tier: int) -> dict:
    o = make_set(desc, tier)
    o["folder"] = "ork_mage_a52/t%d" % tier
    o["desc"] = desc
    o["w"] = 64
    o["h"] = 64
    o["cx"] = 32
    o["cy"] = 62
    o["sel_box"] = list(SEL)
    o["tile_size"] = 1
    return o


def main() -> int:
    with open(PATH, encoding="utf-8", newline="") as f:
        raw = f.read()
    eol = "\r\n" if "\r\n" in raw else "\n"
    db = json.loads(raw)
    existing = [k for k, _, _ in NAMES if k in db]
    if existing:
        print("already present:", existing)
        return 0

    blocks = []
    for key, desc, tier in NAMES:
        obj = make_a52(desc, tier)
        blocks.append(' "%s": %s' % (key, fmt(obj, 2)))

    insert = ",\n".join(blocks)
    stripped = raw.rstrip()
    if not stripped.endswith("}"):
        print("unexpected file end")
        return 1
    body = stripped[:-1].rstrip()
    if not body.endswith(","):
        body += ","
    new_raw = body + "\n" + insert + "\n}" + eol
    with open(PATH, "w", encoding="utf-8", newline="") as f:
        f.write(new_raw)
    print("inserted 4 sets ork_mage_a52")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
