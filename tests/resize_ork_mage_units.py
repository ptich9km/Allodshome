#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ужать кадры ork_mage под стандартный рост юнитов проекта.

Замер (tests/measure_unit_sizes.py):
  heroes/humans/monsters  canvas 32-48 px, content ~33-41 px
  ork_mage                canvas 80 px,   content ~80 px  <- как здание (96 px)
  tile_size=1 -> scale 1.0 -> в игре орк-маг выше стражей в 2+ раза.

Цель: content высотой ~40 px (в диапазоне героев 35-41).
Масштаб 40/80 = 0.5 -> 80x80 -> 40x40, LANCZOS.
После записи обнови units_db (w/h/cx/cy/sel_box) — gen_ork_mage_units.py.
"""
from __future__ import annotations

import os
import sys

from PIL import Image

ROOT = os.path.join("assets", "units", "ork_mage")
NEW = 40
OLD = 80


def main() -> int:
    total = 0
    for t in range(4):
        d = os.path.join(ROOT, f"t{t}")
        if not os.path.isdir(d):
            print("MISSING", d)
            return 1
        for name in sorted(os.listdir(d)):
            if not name.endswith(".png"):
                continue
            path = os.path.join(d, name)
            im = Image.open(path)
            if im.size != (OLD, OLD):
                print(f"skip {path} size={im.size}")
                continue
            out = im.resize((NEW, NEW), Image.Resampling.LANCZOS)
            out.save(path)
            total += 1
    print(f"resized {total} frames to {NEW}x{NEW}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
