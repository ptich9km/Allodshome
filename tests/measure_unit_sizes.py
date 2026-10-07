#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Замер размеров спрайтов ork_mage vs других юнитов."""
from __future__ import annotations

import json
import os
import glob

from PIL import Image

ROOT = r"C:\Work\Allodshome\assets"
DB = os.path.join(ROOT, "units", "units_db.json")


def content_bbox(path: str):
    im = Image.open(path)
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    bbox = im.getbbox()
    return im.size, bbox


def main() -> int:
    with open(DB, encoding="utf-8") as f:
        db = json.load(f)

    samples = [
        "ork_mage/t0",
        "ork_mage/t1",
        "ork_mage/t2",
        "ork_mage/t3",
        "humans/unarmed",
        "humans/swordsman",
        "humans/mage_st",
        "humans/clubman",
        "monsters/orc",
        "monsters/wolf",
        "heroes/swordsman",
        "heroes/mage_st",
        "heroes/unarmed",
    ]
    print(f"{'set':25} {'tile':4} {'frames':6} {'canvas':12} {'content':20} folder")
    for key in samples:
        o = db.get(key)
        if not o:
            print(f"{key:25} MISSING")
            continue
        folder = o.get("folder", key)
        prefix = o.get("prefix", "sprites")
        path = os.path.join(ROOT, "units", folder, f"{prefix}-001.png")
        if not os.path.exists(path):
            print(f"{key:25} NO FILE {path}")
            continue
        size, bbox = content_bbox(path)
        ch = ""
        if bbox:
            ch = f"{bbox[2]-bbox[0]}x{bbox[3]-bbox[1]}"
        print(
            f"{key:25} {o.get('tile_size')}    {o.get('frames'):6} "
            f"{size[0]}x{size[1]:<6} {ch:20} {folder}"
        )

    # wip source
    wip = os.path.join(ROOT, "wip", "characters", "ork_mage", "r0_d0_down.png")
    if os.path.exists(wip):
        size, bbox = content_bbox(wip)
        print(f"\nwip r0_d0_down canvas={size} content={bbox}")

    # buildings for comparison
    for rel in [
        "structures/shop3/house-001.png",
        "structures/inn4/house-001.png",
    ]:
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            size, bbox = content_bbox(p)
            print(f"building {rel}: canvas={size} content={bbox}")

    # how many pixels tall are ork vs human content
    print("\n--- content height comparison ---")
    for key in ["ork_mage/t0", "humans/unarmed", "humans/swordsman", "heroes/swordsman", "monsters/orc"]:
        o = db.get(key, {})
        folder = o.get("folder", key)
        prefix = o.get("prefix", "sprites")
        path = os.path.join(ROOT, "units", folder, f"{prefix}-001.png")
        if not os.path.exists(path):
            continue
        size, bbox = content_bbox(path)
        h = bbox[3] - bbox[1] if bbox else 0
        print(f"{key:25} content_h={h:3} canvas={size[0]}x{size[1]} tile_size={o.get('tile_size')} visual_h≈{h * max(1, int(o.get('tile_size',1)))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
