#!/usr/bin/env python3
"""Замер направления взгляда и длины ног по СЫРОЙ полосе.

Направление: в полосе персонажа берём голову (верхние 22% высоты фигуры) и
ищем кожу/волосы. Смещение центра лица относительно центра фигуры читается как
направление: у правого профиля центр головы смещён вправо от центра тела.

Длина ног: точка бёдер — нижняя граница полосы «платья/туники» (olive), ноги
считаются от неё до низа сапог.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("import/Player/hero_stand_nb5.png")
a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
h, w, _ = a.shape

# фон — мажента
bg = (a[..., 1] < 110) & (a[..., 0] > 140) & (a[..., 2] > 140) & ((a[..., 0] - a[..., 1]) > 50)
fg = ~bg
cols = fg.sum(axis=0)
runs, start = [], -1
for x, v in enumerate(cols >= 3):
    if v and start < 0:
        start = x
    elif not v and start >= 0:
        runs.append((start, x - 1))
        start = -1
if start >= 0:
    runs.append((start, w - 1))

# Модель дважды вернула 8 фигур в два ряда, и у полосы смерти фигуры упираются
# в левый и правый край кадра — колоночные прогоны тогда сливаются в один
# (замер 14.10: «1 фигура шириной 2528px»). Запасной путь: если прогонов один,
# режем полосу на 4 равные доли — раскладка всё равно равномерная.
if len(runs) <= 1 and len(sys.argv) > 2 and sys.argv[2] == "--split4":
    runs = []
    for k in range(4):
        runs.append((k * w // 4, (k + 1) * w // 4 - 1))
    print("  (колоночные прогоны слиплись — режу на 4 равные доли)")

print(f"{path}  фигур: {len(runs)}")
for i, (x0, x1) in enumerate(runs):
    sub = fg[:, x0:x1 + 1]
    ys, xs = np.where(sub)
    if ys.size == 0:
        continue
    y0, y1 = int(ys.min()), int(ys.max())
    ch = y1 - y0 + 1
    body_cx = (x0 + xs.min() + x0 + xs.max()) / 2.0

    # голова: верхние 22% фигуры. НО это band включает наплечники, поэтому
    # bbox всего band смещён асимметричными плечами и ничего не говорит о
    # взгляде (замер 14.10: -11px при ширине band 426px = 2.6%, шум).
    # Направление читается по ЦЕНТРУ КОЖИ ЛИЦА: у профиля вправо лицо
    # смещено вправо от центра тела, у профиля влево — влево.
    head_y1 = y0 + max(1, int(ch * 0.22))
    head = fg[y0:head_y1, x0:x1 + 1]
    crop_head = a[y0:head_y1, x0:x1 + 1]
    skin = (crop_head[..., 0] > 165) & (crop_head[..., 1] > 105) & \
        (crop_head[..., 1] < 205) & (crop_head[..., 2] > 80) & \
        (crop_head[..., 2] < 185) & ((crop_head[..., 0] - crop_head[..., 2]) > 30)
    hys, hxs = np.where(head)
    sys_, sxs = np.where(skin)
    if hxs.size and sxs.size > 50:
        # body_cx — от bbox ВСЕЙ фигуры (ys/xs), head_cx — от bbox полосы головы
        # (hys/hxs). Раньше обе считались от hxs, то есть признаки совпадали
        # тождественно и второй ничего не проверял (ошибка 14.10).
        body_cx = x0 + float(xs.min() + xs.max()) / 2.0
        body_w = int(xs.max() - xs.min() + 1)
        face_cx = x0 + float(sxs.mean())
        off = face_cx - body_cx
        # Второй, независимый от конечностей признак: смещение кожи лица
        # относительно СОБСТВЕННОГО bbox головы. Нужен потому, что вытянутая
        # вперёд рука в панели удара раздвигает bbox тела вправо и ломает
        # первый признак (замер 14.10: панели 3 и 4 дали -13% при вправо
        # нарисованном ударе, панель 2 той же полосы дала +21%).
        head_cx = x0 + (hxs.min() + hxs.max()) / 2.0
        head_w = int(hxs.max() - hxs.min() + 1)
        off2 = face_cx - head_cx
        agree = "согласны" if (off > 0) == (off2 > 0) else "РАСХОДЯТСЯ"
        print(f"  фигура {i+1}: высота={ch} ширина тела={body_w} "
              f"кожи лица={len(sxs)}px | от центра тела {off:+.1f}px "
              f"({off / body_w * 100:+.1f}%) | от центра головы {off2:+.1f}px "
              f"({off2 / head_w * 100:+.1f}%) [{agree}] -> "
              f"{'ВПРАВО' if off2 > 0 else 'ВЛЕВО'}")
    elif hxs.size:
        print(f"  фигура {i+1}: высота={ch}, кожи лица не нашли — "
              f"направление замером НЕ ОПРЕДЕЛЯЕТСЯ")

    # ноги: где кончается оливковая туника (низ платья) и сколько остаётся
    crop = a[y0:y1 + 1, x0:x1 + 1]
    olive = (crop[..., 0] > 90) & (crop[..., 0] < 190) & (crop[..., 1] > 90) \
        & (crop[..., 1] < 180) & (crop[..., 2] < 120) & ((crop[..., 1] - crop[..., 2]) > 30)
    rows_olive = olive.sum(axis=1)
    tunic_rows = [y for y, v in enumerate(rows_olive) if v > 3]
    if tunic_rows:
        hem = max(tunic_rows)
        legs = ch - hem
        print(f"      низ туники на {hem}/{ch}, ноги = {legs}px "
              f"({legs / ch * 100:.0f}% высоты)")
