#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Добавить loot_family в units_db.json для наборов monsters/*.

Текстовая точечная правка: вставляем поле после palette, не пересобираем весь JSON.
"""
from __future__ import annotations

import json
import os
import re

PATH = os.path.join("assets", "units", "units_db.json")

FAMILY = {
    "monsters/squirrel": "beast",
    "monsters/wolf": "beast",
    "monsters/bat": "beast",
    "monsters/bee": "insect",
    "monsters/orc": "humanoid",
    "monsters/orc_s": "humanoid",
    "monsters/orc_sh": "humanoid",
    "monsters/orc_good": "humanoid",
    "monsters/goblin": "humanoid",
    "monsters/troll": "humanoid",
    "monsters/troll_good": "humanoid",
    "monsters/ogre": "humanoid",
    "monsters/spider": "insect",
    "monsters/ghost": "undead",
    "monsters/dino": "monstrous",
    "monsters/dragon": "monstrous",
}


def main() -> int:
    with open(PATH, encoding="utf-8", newline="") as f:
        raw = f.read()
    db = json.loads(raw)
    added = 0
    for key, fam in FAMILY.items():
        if key not in db:
            print("MISS", key)
            continue
        if db[key].get("loot_family"):
            print("skip", key, db[key]["loot_family"])
            continue
        # text insert after "palette": N line inside this key block
        # find "key": { ... "palette":
        m = re.search(
            r'("%s"\s*:\s*\{[^}]*?"palette"\s*:\s*(\d+))' % re.escape(key),
            raw,
            re.DOTALL,
        )
        if not m:
            print("NO MATCH", key)
            continue
        insert = m.group(1) + ',\n   "loot_family": "%s"' % fam
        raw = raw[: m.start(1)] + insert + raw[m.end(1) :]
        added += 1
        print("added", key, fam)
    with open(PATH, "w", encoding="utf-8", newline="") as f:
        f.write(raw)
    # verify
    db2 = json.load(open(PATH, encoding="utf-8"))
    ok = sum(1 for k in FAMILY if db2.get(k, {}).get("loot_family"))
    print("verify loot_family count", ok, "added", added)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
