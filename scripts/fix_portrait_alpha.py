#!/usr/bin/env python3
"""Make near-black background transparent in portrait PNGs."""
from PIL import Image

p = r"D:\Work\UnityProjects\Allodshome_Godot\assets\portraits\goodorc.png"
img = Image.open(p).convert("RGBA")
px = img.load()
w, h = img.size
n = 0
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if r < 12 and g < 12 and b < 12:
            px[x, y] = (0, 0, 0, 0)
            n += 1
img.save(p)
print(f"{n} black pixels -> transparent, mode={img.mode}")
