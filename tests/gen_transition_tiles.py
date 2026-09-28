#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генератор переходных тайлов (файлы tile8..15) офлайн-блендингом.

Зачем: файлы tile1..7 (extract_chatgpt_tiles.py) содержат ТОЛЬКО бесшовные
интерьерные плитки - все 14 рядов заполнены базовыми текстурами по циклу.
Кромок в них нет вообще, поэтому границы биомов были жёсткой сеткой 32x32.
Этот скрипт печёт настоящие переходы: текстура биома A с размытой кромкой в
сторону биома B.

Кодировка (см. assets/maps/terrain_tiles_db.json, поле encoding):
    file_n = 8 + dir_index          направление, 8 направлений -> файлы 8..15
    variant = A                     биом-владелец клетки 0..6
    row     = B * 2 + v             сосед B (0..6) и вариация v (0..1) -> 14 рядов
    биты 12-15 тайла = A            террейн-тип для AlmLoader.terrain_type()

Итого 8 направлений x 7 владельцев = 56 файлов по 32x448 (14 рядов).

Детерминизм (procedural-gen): сид плитки = f(A, B, dir, v), глобального
random.* нет, поэтому два прогона дают побайтово одинаковые файлы.

Запуск:  python tests/gen_transition_tiles.py [--check]
  --check  ничего не пишет, только сверяет хеши с уже существующими файлами
"""

import hashlib
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# Writer BMP и ЕДИНСТВЕННЫЙ кроп атласа берём из существующего скрипта, а не
# дублируем: формат 24-bit bottom-up в Godot 4 нечем сохранить (Image.save_bmp
# отсутствует), и ошибка в размере заголовка даёт valid=false на импорте.
# Кроп обязательно общий: плитки интерьеров и переходов должны резаться по
# одним и тем же границам, иначе бленд бьёт ровно по шву.
from extract_chatgpt_tiles import save_bmp, load_db, load_base_tiles  # noqa: E402

DB_PATH = os.path.join(ROOT, "assets", "maps", "terrain_tiles_db.json")
OUT_DIR = os.path.join(ROOT, "assets", "terrain")

DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
# Какие края плитки затрагивает направление (для min() по расстояниям).
EDGE_SETS = {
    "N":  ("top",),
    "NE": ("top", "right"),
    "E":  ("right",),
    "SE": ("bottom", "right"),
    "S":  ("bottom",),
    "SW": ("bottom", "left"),
    "W":  ("left",),
    "NW": ("top", "left"),
}

TILE = 32
ROWS = 14
VARIATIONS = 2
BAND_PX = 13.0      # глубина полосы смешивания
NOISE_AMP = 0.35    # амплитуда шума маски (в долях полосы)
DITHER = 1.0 / 16.0 # Bayer 4x4, амплитуда квантования

# Упорядоченная матрица Байера 4x4: даёт упорядоченный дизеринг, поэтому стык
# выглядит сеткой разной плотности, а не гладким градиентом. На 32x32 это
# читается как пиксель-арт, на гладком градиенте - как «размытая картинка».
BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def hash01(*parts):
    """Детерминированное число 0..1 из любых целых (замена random)."""
    h = hashlib.sha256("|".join(str(p) for p in parts).encode("utf-8")).digest()
    return int.from_bytes(h[:4], "big") / 0xFFFFFFFF


def value_noise(seed_parts, fx, fy, octaves=2):
    """2-октавный value-noise на сетке 8x8 внутри плитки.

    Низкочастотная октава даёт крупные языки, высокочастотная - рваный край.
    Обе гладкие: билинейная интерполяция решётки, поэтому полоса не превращается
    в кашу из пикселей.
    """
    total = 0.0
    amp = 1.0
    norm = 0.0
    freq = 4.0
    for o in range(octaves):
        total += amp * _octave(seed_parts, o, fx * freq, fy * freq)
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm


def _octave(seed_parts, octave, u, v):
    x0 = int(u // 1)
    y0 = int(v // 1)
    tx = u - x0
    ty = v - y0
    # smoothstep по координате - сетка не должна быть видна ступеньками
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)
    n00 = hash01(*seed_parts, octave, x0, y0)
    n10 = hash01(*seed_parts, octave, x0 + 1, y0)
    n01 = hash01(*seed_parts, octave, x0, y0 + 1)
    n11 = hash01(*seed_parts, octave, x0 + 1, y0 + 1)
    a = n00 + (n10 - n00) * sx
    b = n01 + (n11 - n01) * sx
    return a + (b - a) * sy


def edge_distance(edges, x, y):
    """Расстояние (в px) от ближайшего из заданных краёв плитки."""
    best = 999.0
    for e in edges:
        if e == "top":
            best = min(best, float(y))
        elif e == "bottom":
            best = min(best, float(TILE - 1 - y))
        elif e == "left":
            best = min(best, float(x))
        elif e == "right":
            best = min(best, float(TILE - 1 - x))
    return best


def make_tile(a_img, b_img, edges, seed_parts):
    """Плитка A с кромкой, уходящей в B по краям edges.

    Маска: 1 у самого края, 0 на расстоянии BAND_PX. Расстояние возмущается
    шумом - кромка получается рваной, а не прямой линией. Дальше smoothstep и
    квантование по Байеру, чтобы переход был дизерингом.
    """
    out = Image.new("RGB", (TILE, TILE))
    ap = a_img.load()
    bp = b_img.load()
    op = out.load()
    for y in range(TILE):
        for x in range(TILE):
            d = edge_distance(edges, x, y)
            base = 1.0 - (d / BAND_PX)
            if base < 0.0:
                base = 0.0
            elif base > 1.0:
                base = 1.0
            n = value_noise(seed_parts, x / float(TILE), y / float(TILE))
            m = base + (n - 0.5) * NOISE_AMP
            dth = (BAYER4[y & 3][x & 3] + 0.5) / 16.0 - 0.5
            m += dth * DITHER * 2.0
            if m <= 0.0:
                op[x, y] = ap[x, y]
                continue
            if m >= 1.0:
                op[x, y] = bp[x, y]
                continue
            m = m * m * (3.0 - 2.0 * m)
            ca = ap[x, y]
            cb = bp[x, y]
            op[x, y] = (
                int(ca[0] + (cb[0] - ca[0]) * m),
                int(ca[1] + (cb[1] - ca[1]) * m),
                int(ca[2] + (cb[2] - ca[2]) * m),
            )
    return out


def main():
    check_only = "--check" in sys.argv
    db = load_db()
    base = load_base_tiles(db)
    tf = db["transition_files"]
    file_base = tf["file_base"]
    seed_base = tf["blend"]["seed_base"]

    if list(dirs_order(db)) != DIRS:
        raise SystemExit("Порядок направлений в БД не совпал с константой скрипта")

    written = 0
    mismatched = []
    for dir_index, direction in enumerate(DIRS):
        file_n = file_base + dir_index
        edges = EDGE_SETS[direction]
        for a in range(7):
            strip = Image.new("RGB", (TILE, TILE * ROWS))
            for b in range(7):
                for v in range(VARIATIONS):
                    row = b * VARIATIONS + v
                    if row >= ROWS:
                        raise SystemExit("row %d вне диапазона" % row)
                    seed_parts = (seed_base, a, b, dir_index, v)
                    # Базовые плитки разводим по индексу, чтобы A и B не были
                    # одной и той же картинкой и вариации отличались.
                    a_tile = base[a][(a + v * 2) % 6]
                    b_tile = base[b][(b * 2 + v + 1) % 6]
                    t = make_tile(a_tile, b_tile, edges, seed_parts)
                    strip.paste(t, (0, row * TILE))
            path = os.path.join(OUT_DIR, "tile%d-%02d.bmp" % (file_n, a))
            # Хеш считаем по BMP-байтам, а не по сырому RGB: на диске лежит
            # полный файл, и сравнивать надо с ним же.
            bmp_bytes = bmp_bytes_of(strip)
            digest = hashlib.sha256(bmp_bytes).hexdigest()
            if check_only:
                if not os.path.exists(path):
                    mismatched.append(os.path.basename(path) + " (нет файла)")
                else:
                    with open(path, "rb") as f:
                        if hashlib.sha256(f.read()).hexdigest() != digest:
                            mismatched.append(os.path.basename(path) + " (хеш разошёлся)")
            else:
                with open(path, "wb") as f:
                    f.write(bmp_bytes)
                written += 1
        print("tile%d (%s): 7 файлов, A=0..6, B=0..6" % (file_n, direction))

    if check_only:
        if mismatched:
            print("FAIL: %d файлов разошлись с генератором" % len(mismatched))
            for m in mismatched[:10]:
                print("  " + m)
            return 1
        print("OK: 56 файлов совпадают с генератором (детерминизм)")
        return 0
    print("Записано файлов: %d в %s" % (written, OUT_DIR))
    return 0


def dirs_order(db):
    return db["directions"]["order"]


def bmp_bytes_of(img):
    """BMP того же формата, что пишет save_bmp, но в памяти.

    save_bmp() пишет сразу в файл; для --check нужен ещё и байтовый вид,
    поэтому пишем во временный файл рядом и читаем обратно. Формат BMP в
    Godot 4 нечем сохранить иначе (Image.save_bmp отсутствует).
    """
    tmp = os.path.join(OUT_DIR, "_tmp_check.bmp")
    save_bmp(img, tmp)
    with open(tmp, "rb") as f:
        data = f.read()
    os.remove(tmp)
    return data


if __name__ == "__main__":
    sys.exit(main())
