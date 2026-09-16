#!/usr/bin/env python3
"""Build a labeled montage of sample inventory icons for visual verification."""
import os
from PIL import Image, ImageDraw

icon_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\inventory"
samples = ["0101002", "0102001", "0105002", "0201102", "0501202", "0606208",
           "0712330", "1012028", "1412330", "1506003", "0001002", "0014001", "0014014"]

CELL = 96
cols = 4
rows = (len(samples) + cols - 1) // cols
montage = Image.new("RGB", (cols * CELL, rows * CELL), (30, 30, 30))
draw = ImageDraw.Draw(montage)

for i, sid in enumerate(samples):
    p = os.path.join(icon_dir, sid + "-000.png")
    x, y = (i % cols) * CELL, (i // cols) * CELL
    if os.path.exists(p):
        img = Image.open(p).convert("RGBA")
        # 80x80 иконка -> в клетку 96
        img = img.resize((80, 80), Image.LANCZOS)
        # чёрный фон под прозрачность
        bg = Image.new("RGBA", (CELL, CELL), (20, 20, 20))
        bg.paste(img, (8, 8), img)
        montage.paste(bg.convert("RGB"), (x, y))
    draw.text((x + 4, y + 2), sid, fill=(255, 255, 100))
    draw.rectangle([x, y, x + CELL - 1, y + CELL - 1], outline=(100, 100, 100))

out = r"D:\Work\UnityProjects\Allodshome_Godot\icon_sample.png"
montage.save(out)
print("saved", out, montage.size)