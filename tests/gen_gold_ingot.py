#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Восстанавливает gold_ingot.png из существующих 19 слитков.

Почему нельзя просто прогнать tests/recolor_ingots.py заново: он читает исходное
ФОТО золотого слитка (import/636d848e-...png), которого в репозитории нет, и
в нём жёсткие Linux-пути `/media/alexey/...`, нерабочие на этой машине. Кроме
того, `gold` в его списке MATERIALS отсутствует - именно поэтому иконки золота
не было, хотя сам исходник как раз золотой.

Почему всё-таки можно. Формула recolor_image() покраски:
    new_c = T_c * 0.7 + (orig_c * v) * 0.3
где T - цвет металла, orig_c - канал исходника, v - его же яркость. Каналы
НЕЗАВИСИМЫ: величины L_r, L_g, L_b - три РАЗНЫХ числа, а не одна яркость.
Из P и известного T каждая из них восстанавливается ТОЧНО:
    L_c = (P_c - T_c * 0.7) / 0.3
и для любого цвета G получаем  P_c = G_c * 0.7 + L_c * 0.3 - это и есть
недостающий золотой слиток.

Инварианты, без которых скрипт сделал бы не то:
  * альфа у всех 19 обязана совпасть байт в байт - иначе это разные исходники,
    а не перекраска одного, и восстановление бессмысленно;
  * восстановленные L из двух РАЗНЫХ металлов должны совпасть. Расхождение
    означало бы, что формула не та, что записана в recolor_ingots.py;
  * пересборка донора в его СОБСТВЕННЫЙ цвет обязана дать исходный файл
    байт в байт - это доказывает обратимость до записи.

Запуск:
    python tests/gen_gold_ingot.py --report   # только проверки, не писать
    python tests/gen_gold_ingot.py            # собрать gold_ingot.png
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST_DIR = os.path.join(_ROOT, "assets", "professions", "blacksmith")
PALETTE = os.path.join(_ROOT, "assets", "items", "faction_palette.json")
OUT_NAME = "gold_ingot.png"

# Формула из tests/recolor_ingots.py. Доли обязаны совпадать с тем файлом.
TARGET_MIX = 0.7
SIZE = (80, 80)
# Порог непрозрачности: recolor_image() красит пиксели с a >= 10.
_OPAQUE_MIN = 128

# Допуск сверки яркости, посчитан из формулы, а не выбран на глаз.
# recolor_image() обрезает результат через int(), то есть ошибка записи P
# лежит в [0, 1). Обращение делит её на (1 - 0.7) = 0.3, то есть усиливает
# в 3.33 раза. Сравнивая ДВА металла, складываем две ошибки: 2 / 0.3 = 6.67.
# Наблюдаемое расхождение 1.45 (макс 2.67) внутри этого предела, то есть
# формула совпадает, а остаток - шум округления.
_ROUND_ERR = 2.0 / (1.0 - TARGET_MIX) + 0.01


def palette_color(metal: str):
    with open(PALETTE, encoding="utf-8") as fh:
        pal = json.load(fh)
    for g in pal["groups"].values():
        for m in g["metals"]:
            if m["metal"] == metal:
                return tuple(m["color"])
    raise KeyError("металл %s не найден в палитре" % metal)


def existing_metals() -> list:
    out = []
    for fn in os.listdir(DST_DIR):
        if fn.endswith("_ingot.png"):
            out.append(fn[: -len("_ingot.png")])
    return sorted(out)


def recover_luma(img: Image.Image, target):
    """Восстанавливает три плоскости (orig_c * v) по формуле покраски.

    Возвращает (luma, alpha), luma[y][x] = (L_r, L_g, L_b).

    ВАЖНО: считаем ТОЛЬКО непрозрачные пиксели. В recolor_image() пиксели с
    alpha < 10 не перекрашивались вовсе (`continue`), там остался исходник, и
    применение к ним формулы даёт мусор - из-за этого восстановленная яркость
    на прозрачных пикселях расходилась между металлами на сотни единиц.
    """
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    mix, inv = TARGET_MIX, 1.0 - TARGET_MIX
    luma = [[(0.0, 0.0, 0.0)] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= _OPAQUE_MIN:
                luma[y][x] = (
                    (r - target[0] * mix) / inv,
                    (g - target[1] * mix) / inv,
                    (b - target[2] * mix) / inv,
                )
    return luma, img.getchannel("A")


def paint(luma, target, alpha: Image.Image, donor: Image.Image) -> Image.Image:
    """Собирает слиток заданного цвета из восстановленной яркости.

    Пиксели с alpha < _OPAQUE_MIN в формулу не входили (исходник их не красил),
    поэтому они копируются из донора без изменений.
    """
    w, h = alpha.size
    mix, inv = TARGET_MIX, 1.0 - TARGET_MIX
    out = Image.new("RGBA", (w, h))
    dst = out.load()
    src_a = alpha.load()
    src_d = donor.load()
    for y in range(h):
        for x in range(w):
            a = src_a[x, y]
            if a < _OPAQUE_MIN:
                dst[x, y] = src_d[x, y]
                continue
            L = luma[y][x]
            dst[x, y] = (
                max(0, min(255, int(target[0] * mix + L[0] * inv))),
                max(0, min(255, int(target[1] * mix + L[1] * inv))),
                max(0, min(255, int(target[2] * mix + L[2] * inv))),
                a,
            )
    return out


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Сборка gold_ingot.png из существующих слитков")
    ap.add_argument("--report", action="store_true", help="только проверки, не писать файл")
    args = ap.parse_args()

    metals = [m for m in existing_metals() if m != "gold"]
    if not metals:
        print("НЕТ ИСХОДНЫХ СЛИТКОВ в %s" % DST_DIR)
        return 1
    print("СЛИТКОВ НА ДИСКЕ: %d, gold_ingot.png уже есть: %s"
          % (len(metals), os.path.exists(os.path.join(DST_DIR, OUT_NAME))))

    # 1. альфа у всех обязана совпадать байт в байт
    images = {m: Image.open(os.path.join(DST_DIR, "%s_ingot.png" % m)).convert("RGBA")
              for m in metals}
    ref = images[metals[0]].getchannel("A").tobytes()
    bad = [m for m in metals if images[m].getchannel("A").tobytes() != ref]
    print("АЛЬФА СОВПАДАЕТ У ВСЕХ: %s%s"
          % (not bad, (", расходятся: " + ", ".join(bad)) if bad else ""))
    if bad:
        print("! это разные исходники, а не перекраска одного - восстановление невозможно")
        return 1

    colors = {m: palette_color(m) for m in metals}
    # 2. без клампинга берём металлы с target <= 200
    safe = [m for m in metals if max(colors[m]) <= 200]
    print("БЕЗ КЛАМПИНГА (target <= 200): %d из %d" % (len(safe), len(metals)))
    if not safe:
        print("! нет ни одного безопасного металла")
        return 1

    luma = {}
    for m in safe:
        luma[m], alpha = recover_luma(images[m], colors[m])

    # 3. сверка: яркость из ДВУХ разных металлов должна совпасть
    a, b = safe[0], safe[1]
    diffs = []
    for y in range(alpha.size[1]):
        for x in range(alpha.size[0]):
            if alpha.getpixel((x, y)) < _OPAQUE_MIN:
                continue
            for c in range(3):
                diffs.append(abs(luma[a][y][x][c] - luma[b][y][x][c]))
    mean_diff = sum(diffs) / len(diffs)
    print("СВЕРКА ЯРКОСТИ %s vs %s: пикселей %d, среднее расхождение %.4f, максимум %.2f (допуск %.2f)"
          % (a, b, len(diffs), mean_diff, max(diffs), _ROUND_ERR))
    if max(diffs) > _ROUND_ERR:
        print("! формула в recolor_ingots.py не совпадает с фактической - стоп")
        return 1

    gold = palette_color("gold")
    donor = safe[0]
    print("ЦЕЛЕВОЙ ЦВЕТ gold: %s, донор яркости: %s" % (gold, donor))

    # 4. доказательство обратимости: пересобрать донора в его собственный цвет
    check = paint(luma[donor], colors[donor], alpha, images[donor])
    same = check.tobytes() == images[donor].tobytes()
    print("САМОПРОВЕРКА (пересборка %s в его цвет): %s" % (donor, "байт в байт" if same else "НЕ СОВПАЛО"))
    if not same:
        print("! формула не обратима - файл не пишем")
        return 1

    img = paint(luma[donor], gold, alpha, images[donor])
    if args.report:
        print("REPORT: всё сходится, файл не записан (--report)")
        return 0

    dst = os.path.join(DST_DIR, OUT_NAME)
    if img.size != SIZE:
        img = img.resize(SIZE, Image.LANCZOS)
    img.save(dst)
    opaque = sum(1 for v in alpha.getdata() if v > 128)
    print("ЗАПИСАНО: %s (%dx%d, непрозрачных %d)" % (dst, img.size[0], img.size[1], opaque))
    return 0


if __name__ == "__main__":
    sys.exit(main())
