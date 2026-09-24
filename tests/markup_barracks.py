#!/usr/bin/env python3
"""Mark up barracks image with zone boundaries."""

from PIL import Image, ImageDraw, ImageFont

SRC = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import/cf5d15fbb82c11f18effeea93894b2af_1.jpeg"
DST = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import/barracks_markup.png"

# Zones: (name, x1, y1, x2, y2, rows, cols, color)
ZONES = [
    ("RECRUIT_PANEL", 26, 136, 219, 889, 7, 2, (255, 50, 50)),
]


def main():
    img = Image.open(SRC).convert("RGBA")
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 12)
    except:
        font = ImageFont.load_default()

    for zone in ZONES:
        name, x1, y1, x2, y2, rows, cols, color = zone

        # Draw zone rectangle
        draw.rectangle([x1, y1, x2, y2], outline=color, width=3)

        # Draw cell grid
        if rows > 0 and cols > 0:
            cell_w = (x2 - x1) / cols
            cell_h = (y2 - y1) / rows

            for r in range(rows + 1):
                y = int(y1 + r * cell_h)
                draw.line([(x1, y), (x2, y)], fill=color, width=2)

            for c in range(cols + 1):
                x = int(x1 + c * cell_w)
                draw.line([(x, y1), (x, y2)], fill=color, width=2)

        # Label
        label = f"{name} {rows}x{cols}"
        bbox = draw.textbbox((0, 0), label, font=font)
        lw = bbox[2] - bbox[0]
        lh = bbox[3] - bbox[1]

        lx, ly = x1 + 2, y1 + 2
        draw.rectangle([lx, ly, lx + lw + 4, ly + lh + 4], fill=(0, 0, 0, 180))
        draw.text((lx + 2, ly + 2), label, fill=color, font=font)

    img.save(DST)
    print(f"Saved: {DST}")
    print("\nZones:")
    for name, x1, y1, x2, y2, rows, cols, color in ZONES:
        cell_w = (x2 - x1) / cols
        cell_h = (y2 - y1) / rows
        print(f"  {name}: ({x1},{y1})-({x2},{y2}) | {rows}x{cols} cells | cell={cell_w:.0f}x{cell_h:.0f}")


if __name__ == "__main__":
    main()
