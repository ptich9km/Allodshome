#!/usr/bin/env python3
"""Split herb sheet into 8 individual 32x32 icons for herbalism profession."""

from PIL import Image
import os

SRC = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import/95462815-02f6-4e89-b114-7c109fe5e75c.png"
DST = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/assets/professions/herbalism"

# 8 herb names (4 columns × 2 rows)
HERBS = [
    "green_leaf",      # row 0, col 0 - young green plant
    "white_flower",    # row 0, col 1 - white daisy
    "red_berry",       # row 0, col 2 - red berries
    "tall_grass",      # row 0, col 3 - tall grass
    "lavender",        # row 1, col 0 - purple lavender
    "mint",            # row 1, col 1 - mint leaves
    "dandelion",       # row 1, col 2 - yellow dandelion
    "broad_leaf",      # row 1, col 3 - broad leaves
]

def main():
    img = Image.open(SRC)
    w, h = img.size
    print(f"Source: {w}×{h}")

    os.makedirs(DST, exist_ok=True)

    # Grid: 4 columns × 2 rows
    cols, rows = 4, 2
    cell_w = w // cols
    cell_h = h // rows

    for idx, name in enumerate(HERBS):
        row = idx // cols
        col = idx % cols

        # Crop cell
        left = col * cell_w
        top = row * cell_h
        right = left + cell_w
        bottom = top + cell_h
        cell = img.crop((left, top, right, bottom))

        # Resize to 32x32
        cell_resized = cell.resize((32, 32), Image.LANCZOS)

        # Save
        path = f"{DST}/{name}.png"
        cell_resized.save(path)
        print(f"  {name}.png (row={row}, col={col})")

    print(f"\nDone! {len(HERBS)} herb icons saved to {DST}")

if __name__ == "__main__":
    main()
