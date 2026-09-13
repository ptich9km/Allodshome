#!/usr/bin/env python3
"""Build montage of terrain file rows for comparison."""
from PIL import Image, ImageDraw
import os

base = r"D:\Games\Rage of Mages II\extracted\graphics\terrain"
out = r"D:\Work\UnityProjects\Allodshome_Godot\tmp_terrain_rows"
os.makedirs(out, exist_ok=True)

order = ["tile1-00.bmp", "tile2-00.bmp", "tile3-00.bmp", "tile4-00.bmp"]
rows_want = [0, 3, 6, 9, 12, 13]

montage = Image.new("RGB", (len(order) * 66, len(rows_want) * 34), (30, 30, 30))
for ci, name in enumerate(order):
    img = Image.open(os.path.join(base, name)).convert("RGB")
    for ri, r in enumerate(rows_want):
        row = img.crop((0, r * 32, 32, r * 32 + 32)).resize((64, 32), Image.NEAREST)
        montage.paste(row, (ci * 66, ri * 34))

d = ImageDraw.Draw(montage)
for ci, name in enumerate(order):
    d.text((ci * 66 + 2, 0), name[:8], fill=(255, 255, 255))
for ri, r in enumerate(rows_want):
    d.text((0, ri * 34 + 2), f"r{r}", fill=(255, 255, 255))
montage.save(os.path.join(out, "montage.png"))
print("saved montage.png", montage.size)