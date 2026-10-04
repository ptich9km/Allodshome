#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Монета для золотого лута (03.10).

ЗАЧЕМ
-----
Замер: `LootIcons.gold_icon()` возвращал `gold_ingot.png` — золото рисовалось
слитком. Но слиток это ПРЕДМЕТ, а золото — число у игрока в `player.gold`.
Игрок брал мешок, видел слиток, потом не находил его в инвентаре и справедливо
жаловался. Теперь у золота своя картинка — монета.

Размер 32×32 RGBA — как у соседних иконок зелий в `assets/loot_icons/`, чтобы
лут на земле читался одним стилем.

Рисуем процедурно, без новых зависимостей (только PIL, он уже в проекте):
диск с фаской, золотой ободок, тёмная решка, блик сверху-слева и кромка внизу-
справа. Никаких градиентов из внешних картинок — файл самодостаточный и
воспроизводимый.

Запуск:
    python tests/gen_gold_coin.py            # записать assets/loot_icons/gold_coin.png
    python tests/gen_gold_coin.py --report   # только сводка, ничего не писать
"""

from __future__ import annotations

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "loot_icons", "gold_coin.png")

SIZE = 32
CX = CY = 15.5
R_OUT = 14.0      # внешний радиус монеты
R_IN = 11.0       # внутренний диск (решка)

# Палитра: тёмное золото -> светлое. Значения подобраны так, чтобы монета
# читалась и на тёмном, и на светлом грунте, поэтому тёмная кромка обязательна.
RIM_DARK = (128, 84, 24, 255)
RIM_MID = (198, 150, 44, 255)
FACE_HI = (255, 226, 122, 255)
FACE_MID = (232, 186, 62, 255)
FACE_LO = (176, 126, 28, 255)
EDGE_DARK = (86, 54, 12, 255)


def _shade(x: float, y: float) -> tuple[int, int, int, int]:
    """Цвет по положению: блик сверху-слева, тень снизу-справа."""
    # проекция на направление света (-0.6, -0.8)
    t = ((x - CX) * -0.6 + (y - CY) * -0.8) / R_OUT      # -1..1
    t = max(-1.0, min(1.0, t))
    if t > 0.35:
        k = (t - 0.35) / 0.65
        return _mix(FACE_MID, FACE_HI, k)
    if t < -0.3:
        k = (-t - 0.3) / 0.7
        return _mix(FACE_MID, FACE_LO, k)
    return FACE_MID


def _mix(a: tuple, b: tuple, k: float) -> tuple:
    return tuple(int(round(a[i] + (b[i] - a[i]) * k)) for i in range(4))


def make_coin() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()

    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - CX
            dy = y - CY
            d = math.hypot(dx, dy)
            if d > R_OUT + 0.5:
                continue
            # сглаживание края по доле пикселя
            if d > R_OUT - 0.5:
                a = int(round(255 * (R_OUT + 0.5 - d)))
                px[x, y] = (RIM_DARK[0], RIM_DARK[1], RIM_DARK[2], max(0, min(255, a)))
                continue

            if d > R_IN:
                # ободок (фаска): темнее у внешнего края
                t = (d - R_IN) / max(R_OUT - R_IN, 0.001)
                col = _mix(RIM_MID, RIM_DARK, t)
                px[x, y] = col
                continue

            # решка: своя кромка, чтобы монета не выглядела плоским кругом
            if d > R_IN - 1.0:
                px[x, y] = _mix(_shade(x, y), RIM_DARK, 0.45)
                continue
            px[x, y] = _shade(x, y)

    d = ImageDraw.Draw(img)
    # рельеф по центру решки — намёк на оттиск, чтобы монета не была гладкой
    for r, col in ((3.2, (214, 168, 54, 140)), (1.9, (168, 124, 30, 120))):
        d.ellipse(
            [CX - r, CY - r, CX + r, CY + r],
            outline=col,
            width=1,
        )
    # блик-искра сверху-слева
    d.ellipse([CX - 6.5, CY - 7.0, CX - 2.5, CY - 4.5],
        fill=(255, 244, 198, 190))
    # тёмная подрезка снизу-справа, отделяет монету от тёмного грунта
    d.arc([CX - R_IN + 0.5, CY - R_IN + 0.5, CX + R_IN - 0.5, CY + R_IN - 0.5],
        start=10, end=150, fill=EDGE_DARK, width=1)
    return img


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    img = make_coin()
    a = img.load()
    opaque = sum(1 for y in range(SIZE) for x in range(SIZE) if a[x, y][3] > 0)
    opaque_strong = sum(1 for y in range(SIZE) for x in range(SIZE) if a[x, y][3] > 200)
    corners = [a[0, 0][3], a[SIZE - 1, 0][3], a[0, SIZE - 1][3], a[SIZE - 1, SIZE - 1][3]]
    print("размер: %dx%d  режим: %s" % (img.size[0], img.size[1], img.mode))
    print("непрозрачных пикселей: %d (из %d), сильных: %d" % (opaque, SIZE * SIZE, opaque_strong))
    print("альфа в углах (должно быть 0): %s" % corners)

    ok = True
    if corners[0] != 0 or corners[1] != 0 or corners[2] != 0 or corners[3] != 0:
        print("FAIL: углы непрозрачны — монета будет квадратом")
        ok = False
    if opaque < 400:
        print("FAIL: слишком мало непрозрачных пикселей (%d) — похоже на кольцо" % opaque)
        ok = False
    if opaque > 700:
        print("FAIL: слишком много непрозрачных пикселей (%d) — не круг" % opaque)
        ok = False

    if args.report:
        print("RESULT: %s (dry-run, файл не тронут)" % ("OK" if ok else "FAIL"))
        return 0 if ok else 2

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("записано: %s (%d байт)" % (os.path.relpath(OUT, ROOT), os.path.getsize(OUT)))
    print("RESULT: %s" % ("OK" if ok else "FAIL"))
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())