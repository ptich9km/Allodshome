#!/usr/bin/env python3
"""Slice a terrain BMP into rows to understand sub-tile structure."""
from PIL import Image
import os

base = r"D:\Games\Rage of Mages II\extracted\graphics\terrain"
out = r"D:\Work\UnityProjects\Allodshome_Godot\tmp_terrain_rows"
os.makedirs(out, exist_ok=True)

for name in ["tile1-00.bmp", "tile1-01.bmp", "tile1-02.bmp", "tile1-03.bmp"]:
    img = Image.open(os.path.join(base, name)).convert("RGB")
    w, h = img.size
    print(f"{name}: {w}x{h}")
    rows = h // 32
    print(f"  rows: {rows}")
    for r in range(min(rows, 14)):
        row = img.crop((0, r*32, w, r*32+32))
        # resize 32->64 for viewing
        row = row.resize((64, 32), Image.NEAREST)
        row.save(os.path.join(out, f"{name.replace('.bmp','')}_row{r:02d}.png"))
    print(f"  saved rows to {out}")

# Also check dirt.bmp
img = Image.open(os.path.join(base, "dirt.bmp")).convert("RGB")
print(f"dirt.bmp: {img.size}x, rows={img.size[1]//32}")