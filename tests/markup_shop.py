#!/usr/bin/env python3
"""Mark up shop image with precise zone boundaries and cell grids."""

from PIL import Image, ImageDraw, ImageFont

SRC = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import/5dd000fcb81c11f181f8e61391f03ad1_1.jpeg"
DST = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import/shop_markup.png"

# Zones with cell grids: (name, x1, y1, x2, y2, rows, cols, color)
ZONES = [
    ("NPC_SHELF", 26, 231, 217, 835, 7, 2, (255, 50, 50)),
    ("PLAYER_SHELF", 250, 578, 790, 835, 3, 6, (50, 255, 50)),
    ("BOOKS_SHELF", 819, 473, 997, 843, 4, 1, (50, 200, 200)),
    ("POTIONS", 642, 842, 1001, 998, 1, 4, (200, 255, 100)),
    ("PLAYER_TAB", 216, 899, 616, 990, 1, 4, (255, 150, 50)),
    # Icon tabs (no grid)
    ("ARMOR_TAB", 60, 40, 180, 200, 0, 0, (255, 200, 50)),
    ("ROBE_TAB", 850, 40, 980, 200, 0, 0, (200, 50, 255)),
    ("WEAPON_TAB", 30, 850, 180, 990, 0, 0, (255, 100, 50)),
    ("MERCHANT", 350, 180, 700, 550, 0, 0, (50, 100, 255)),
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

        # Draw cell grid if applicable
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
        label = f"{name}"
        if rows > 0:
            label += f" {rows}x{cols}"
        bbox = draw.textbbox((0, 0), label, font=font)
        lw = bbox[2] - bbox[0]
        lh = bbox[3] - bbox[1]

        lx, ly = x1 + 2, y1 + 2
        draw.rectangle([lx, ly, lx + lw + 4, ly + lh + 4], fill=(0, 0, 0, 180))
        draw.text((lx + 2, ly + 2), label, fill=color, font=font)

    img.save(DST)
    print(f"Saved: {DST}")
    print("\nZones with cell grids:")
    for name, x1, y1, x2, y2, rows, cols, color in ZONES:
        if rows > 0:
            cell_w = (x2 - x1) / cols
            cell_h = (y2 - y1) / rows
            print(f"  {name}: ({x1},{y1})-({x2},{y2}) | {rows}x{cols} cells | cell={cell_w:.0f}x{cell_h:.0f}")
        else:
            print(f"  {name}: ({x1},{y1})-({x2},{y2}) | icon/area")


if __name__ == "__main__":
    main()
