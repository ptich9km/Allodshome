#!/usr/bin/env python3
"""
Extract 32x32 tiles from ChatGPTImage.png atlas and create BMP strips.
Atlas: 1536x1024px, 7 biomes x 6 variations + header row.
BMP format: 32x448 (14 rows x 32px) to match existing tile1-7.bmp structure.
"""

import struct
import os
from PIL import Image

ATLAS_PATH = "import/ChatGPTImage.png"
OUT_DIR = "assets/terrain"

# Atlas layout from ChatGPTImage.md
COL_X = [8, 226, 445, 664, 884, 1104, 1324]
COL_W = 204
ROW_Y = [52, 213, 370, 526, 683, 839]
ROW_H = 150

# column index -> (file_n, name)
BIOMES = {
    0: (6, "sand"),
    1: (2, "mountain"),
    2: (7, "mud"),
    3: (3, "water"),
    4: (5, "soil"),
    5: (1, "grass"),
    6: (4, "road"),
}

TILE_SIZE = 32
ROWS_PER_BMP = 14


def save_bmp(img, path):
    img = img.convert("RGB")
    w, h = img.size
    row_size = w * 3
    pad = (4 - (row_size % 4)) % 4
    data_size = (row_size + pad) * h
    file_size = 54 + data_size

    buf = bytearray(file_size)
    buf[0:2] = b'BM'
    struct.pack_into('<I', buf, 2, file_size)
    struct.pack_into('<I', buf, 10, 54)
    struct.pack_into('<I', buf, 14, 40)
    struct.pack_into('<i', buf, 18, w)
    struct.pack_into('<i', buf, 22, h)
    struct.pack_into('<H', buf, 26, 1)
    struct.pack_into('<H', buf, 28, 24)
    struct.pack_into('<I', buf, 34, data_size)

    o = 54
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b = img.getpixel((x, y))
            buf[o] = b
            buf[o + 1] = g
            buf[o + 2] = r
            o += 3
        for _ in range(pad):
            buf[o] = 0
            o += 1

    with open(path, 'wb') as f:
        f.write(buf)


def main():
    atlas = Image.open(ATLAS_PATH)
    print(f"Atlas: {atlas.size[0]}x{atlas.size[1]}")

    for col_idx, (file_n, name) in BIOMES.items():
        tiles = []
        for row_idx in range(6):
            x1 = COL_X[col_idx]
            y1 = ROW_Y[row_idx]
            tile = atlas.crop((x1, y1, x1 + COL_W, y1 + ROW_H))
            tile = tile.resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS)
            tiles.append(tile)

        strip = Image.new('RGB', (TILE_SIZE, TILE_SIZE * ROWS_PER_BMP))
        for row in range(ROWS_PER_BMP):
            strip.paste(tiles[row % len(tiles)], (0, row * TILE_SIZE))

        for variant in range(16):
            bmp_path = os.path.join(OUT_DIR, f"tile{file_n}-{variant:02d}.bmp")
            save_bmp(strip, bmp_path)

        print(f"tile{file_n} ({name}): 16 BMP strips, 32x{ROWS_PER_BMP*32}")

    png_dir = os.path.join(OUT_DIR, "chatgpt_tiles")
    os.makedirs(png_dir, exist_ok=True)
    for col_idx, (file_n, name) in BIOMES.items():
        for row_idx in range(6):
            x1 = COL_X[col_idx]
            y1 = ROW_Y[row_idx]
            tile = atlas.crop((x1, y1, x1 + COL_W, y1 + ROW_H))
            tile = tile.resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS)
            tile.save(os.path.join(png_dir, f"{name}_{row_idx+1:02d}.png"))

    print(f"\nDone! PNGs saved to {png_dir}/")


if __name__ == "__main__":
    main()
