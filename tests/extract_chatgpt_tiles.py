#!/usr/bin/env python3
"""
Extract 32x32 tiles from ChatGPTImage.png atlas and create BMP strips.
Atlas: 1536x1024px, 7 biomes x 6 variations + header row.
BMP format: 32x448 (14 rows x 32px) to match existing tile1-7.bmp structure.
"""

import struct
import io
import json
import os
import random
from PIL import Image

ATLAS_PATH = "import/ChatGPTImage.png"
OUT_DIR = "assets/terrain"
DB_PATH = "assets/maps/terrain_tiles_db.json"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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


def load_db():
    with io.open(DB_PATH, encoding="utf-8") as f:
        return json.load(f)


def load_base_tiles(db):
    """42 базовые плитки 32x32: base[biome][0..5] -> PIL Image.

    ЕДИНСТВЕННЫЙ кроп атласа на весь проект. От него зависят и интерьеры
    (этот скрипт), и переходы (gen_transition_tiles.py импортирует эту же
    функцию): если резать по-разному, плитки биомов получатся из разных
    границ, и бленд будет бить ровно по шву.

    Границы содержимого - поле atlas.crop в terrain_tiles_db.json. Замерено
    по всем 42 ячейкам: слева разделитель атласа 2-3 px, снизу 1-2 px.
    """
    atlas = Image.open(os.path.join(ROOT, db["atlas"]["source"]))
    if list(atlas.size) != db["atlas"]["size"]:
        raise SystemExit("Размер атласа не совпал с БД: %s != %s"
                         % (list(atlas.size), db["atlas"]["size"]))
    cols = db["atlas"]["columns_x"]
    rows = db["atlas"]["rows_y"]
    crop = db["atlas"]["crop"]
    base = {}
    for biome_s, info in db["biomes"].items():
        col = info["atlas_col"]
        x1 = cols[col]
        tiles = []
        for row in range(6):
            y1 = rows[row]
            box = (x1 + crop["left"], y1 + crop["top"],
                   x1 + crop["right"] + 1, y1 + crop["bottom"] + 1)
            tiles.append(atlas.crop(box).resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS))
        base[int(biome_s)] = tiles
    return base


def main():
    db = load_db()
    base = load_base_tiles(db)
    for col_idx, (file_n, name) in BIOMES.items():
        biome = _biome_of_file(db, file_n)
        tiles = base[biome]

        for variant in range(16):
            # Each variant gets a unique ordering of the 6 base tiles
            rng = random.Random(file_n * 1000 + variant)
            order = list(range(6))
            rng.shuffle(order)

            strip = Image.new('RGB', (TILE_SIZE, TILE_SIZE * ROWS_PER_BMP))
            for row in range(ROWS_PER_BMP):
                strip.paste(tiles[order[row % 6]], (0, row * TILE_SIZE))

            bmp_path = os.path.join(OUT_DIR, f"tile{file_n}-{variant:02d}.bmp")
            save_bmp(strip, bmp_path)

        print(f"tile{file_n} ({name}): 16 BMP strips (16 unique orderings), 32x{ROWS_PER_BMP*32}")

    # Раньше здесь ещё писались PNG в assets/terrain/chatgpt_tiles/ - их удалил
    # 1f67b0ec вместе с биомной системой, и код в проекте их нигде не читает.
    # Не воскрешаем: BMP tile1..15 - единственный источник текстур.
    print(f"\nDone! {len(BIOMES) * 16} BMP strips in {OUT_DIR}")


def _biome_of_file(db, file_n):
    """Ключи biomes в JSON - строки, а base индексируется int."""
    for k, v in db["biomes"].items():
        if int(v["file"]) == file_n:
            return int(k)
    raise SystemExit("Нет биома для файла tile%d" % file_n)


if __name__ == "__main__":
    main()
