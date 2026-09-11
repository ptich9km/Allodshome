#!/usr/bin/env python3
"""Slice 24 spell icons (2 rows x 12) from spellbook.bmp."""
from PIL import Image

img = Image.open(r"D:\Work\UnityProjects\Allodshome_Godot\assets\interface\spellbook.bmp")
out_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\spells"

CELL = 36
SEP = 2
X0 = 5
ROWS = [5, 43]

count = 0
for row_i, y0 in enumerate(ROWS):
    for col_i in range(12):
        x0 = X0 + col_i * (CELL + SEP)
        box = (x0, y0, x0 + CELL, y0 + CELL)
        icon = img.crop(box)
        idx = row_i * 12 + col_i
        out = rf"{out_dir}\spell_{idx:02d}.png"
        icon.save(out)
        count += 1
        print(f"spell_{idx:02d}.png <- crop{box}")

print(f"\nDone: {count} icons {CELL}x{CELL}")
