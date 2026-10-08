"""Кроп ТОЛЬКО головы human2 (верхние 20%) в 6x - смотрим глазами.

python tests/crop_head_zoom.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = os.path.join(ROOT, "assets", "hero_portraits")
OUT = os.path.join(ROOT, "assets", "hero_portraits", "_diag")


def checker(size, c1=(58, 58, 66, 255), c2=(38, 38, 44, 255), step=12):
    bg = Image.new("RGBA", size, c2)
    d = ImageDraw.Draw(bg)
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            if (x // step + y // step) % 2 == 0:
                d.rectangle([x, y, x + step - 1, y + step - 1], fill=c1)
    return bg


def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for n in sorted(os.listdir(PORT)):
        if not (n.endswith(".png") and n.startswith("human2")):
            continue
        a = np.array(Image.open(os.path.join(PORT, n)).convert("RGBA"))
        h = a.shape[0]
        head = Image.fromarray(a[: int(h * 0.22)], "RGBA")
        z = 6
        head = head.resize((head.width * z, head.height * z), Image.Resampling.NEAREST)
        bg = checker(head.size)
        bg.alpha_composite(head)
        tiles.append((n, bg))
        print("  %-20s голова %dx%d" % (n, head.width, head.height))

    cols = 2
    cw = max(t[1].width for t in tiles)
    ch = max(t[1].height for t in tiles) + 20
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (cw + 10), rows * (ch + 10)), (20, 20, 24, 255))
    d = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(tiles):
        cx = (i % cols) * (cw + 10)
        cy = (i // cols) * (ch + 10)
        d.text((cx + 4, cy + 4), n, fill=(235, 215, 150, 255))
        sheet.alpha_composite(im, (cx, cy + 20))
    p = os.path.join(OUT, "_head_zoom.png")
    sheet.convert("RGB").save(p)
    print("Лист: %s (%dx%d)" % (p, sheet.width, sheet.height))


if __name__ == "__main__":
    main()