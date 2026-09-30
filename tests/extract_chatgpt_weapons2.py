#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTWeapons2.png → assets/items/base_w/.

Вход:  import/ChatGPTWeapons2.png (1536x1024, RGBA, фон прозрачный)
Выход: assets/items/base_w/{type}_{quality}.png

Порядок в атласе (разобран вручную по оригиналу, 58 компонентов):

  row0  y  40..280:  4 кинжала | 4 одн. меча | 4 сабли | 3 двуручных меча
  row1  y 280..480:  4 одн. топора | 5 двуручных топоров | 2 одн. топора (лишние)
  row2  y 480..670:  4 одн. булавы | 4 двуручных булавы | 3 булавы (лишние)
  row3  y 650..840:  4 одн. копья | 5 двуручных копий
  row4  y 830..1024: 4 лука | 4 арбалета | 4 щита

Кроп строго по пикселям своей связной компоненты (не по bbox): соседние
предметы и пыль сглаживания в кроп не попадают. Масштаб: длинная сторона = 80.

Запуск:
    python tests/extract_chatgpt_weapons2.py            # нарезать в base_w
    python tests/extract_chatgpt_weapons2.py --report   # только отчёт
    python tests/extract_chatgpt_weapons2.py --sheet    # + контактный лист
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

SOURCE = os.path.join("import", "ChatGPTWeapons2.png")
OUT_DIR = os.path.join("assets", "items", "base_w")
SHEET = os.path.join(OUT_DIR, "_contact_sheet.png")

GAME_SIZE = 80
KEEP_ALPHA = 200
MIN_AREA = 400

ROW_BANDS = [
    (40, 280),
    (280, 480),
    (480, 670),
    (650, 840),
    (830, 1024),
]

QUALITIES = ["cheap", "common", "good", "elite"]

# (row, a, b, name, ru, quality|None)
CUTS: list[dict] = [
    {"row": 0, "a": 0, "b": 4, "name": "dagger", "ru": "Кинжал"},
    {"row": 0, "a": 4, "b": 8, "name": "one_handed_sword", "ru": "Меч одноручный"},
    {"row": 0, "a": 8, "b": 12, "name": "saber", "ru": "Сабля"},
    # в атласе 3 двуручных: cheap / good(золото) / elite(синий)
    {
        "row": 0, "a": 12, "b": 15, "name": "greatsword", "ru": "Меч двуручный",
        "quality": ["cheap", "good", "elite"],
    },
    {"row": 1, "a": 0, "b": 4, "name": "one_handed_axe", "ru": "Топор одноручный"},
    {"row": 1, "a": 4, "b": 8, "name": "two_handed_axe", "ru": "Топор двуручный"},
    {"row": 1, "a": 8, "b": 11, "name": "_extra_axe", "ru": "Топоры (лишние)"},
    {"row": 2, "a": 0, "b": 4, "name": "one_handed_mace", "ru": "Булава одноручная"},
    {"row": 2, "a": 4, "b": 8, "name": "two_handed_mace", "ru": "Булава двуручная"},
    {"row": 2, "a": 8, "b": 11, "name": "_extra_mace", "ru": "Булавы (лишние)"},
    {"row": 3, "a": 0, "b": 4, "name": "one_handed_spear", "ru": "Копьё одноручное"},
    {"row": 3, "a": 4, "b": 8, "name": "two_handed_spear", "ru": "Копьё двуручное"},
    {"row": 3, "a": 8, "b": 9, "name": "_extra_spear", "ru": "Копьё (лишнее)"},
    {"row": 4, "a": 0, "b": 4, "name": "bow", "ru": "Лук"},
    {"row": 4, "a": 4, "b": 8, "name": "crossbow", "ru": "Арбалет"},
    {"row": 4, "a": 8, "b": 12, "name": "shield", "ru": "Щит"},
]

GAME_TYPES = [
    "dagger",
    "one_handed_sword",
    "saber",
    "greatsword",
    "one_handed_axe",
    "two_handed_axe",
    "one_handed_mace",
    "two_handed_mace",
    "one_handed_spear",
    "two_handed_spear",
    "bow",
    "crossbow",
    "shield",
]


def label_components(mask: np.ndarray) -> tuple[np.ndarray, list[dict]]:
    """Метка компоненты для каждого пикселя (0 = фон) + список компонентов."""
    h, w = mask.shape
    labels = np.zeros((h, w), dtype=np.int32)
    comps: list[dict] = []
    current = 0
    ys, xs = np.where(mask)
    for y0, x0 in zip(ys, xs):
        if labels[y0, x0] != 0:
            continue
        current += 1
        q: deque[tuple[int, int]] = deque([(int(y0), int(x0))])
        labels[y0, x0] = current
        miny = maxy = int(y0)
        minx = maxx = int(x0)
        area = 0
        while q:
            y, x = q.popleft()
            area += 1
            if y < miny:
                miny = y
            if y > maxy:
                maxy = y
            if x < minx:
                minx = x
            if x > maxx:
                maxx = x
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and labels[ny, nx] == 0:
                    labels[ny, nx] = current
                    q.append((ny, nx))
        comps.append(
            {
                "id": current,
                "x0": minx,
                "y0": miny,
                "x1": maxx + 1,
                "y1": maxy + 1,
                "area": area,
            }
        )
    # только крупные, по x
    comps = [c for c in comps if c["area"] >= MIN_AREA]
    comps.sort(key=lambda c: c["x0"])
    return labels, comps


def fit_game_size(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    scale = GAME_SIZE / max(w, h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GAME_SIZE, GAME_SIZE), (0, 0, 0, 0))
    ox = (GAME_SIZE - nw) // 2
    oy = (GAME_SIZE - nh) // 2
    canvas.paste(im, (ox, oy), im)
    return canvas


def cut_component(
    src_arr: np.ndarray, labels: np.ndarray, comp: dict
) -> Image.Image:
    """Кроп только пикселей данной компоненты + tight bbox."""
    cid = comp["id"]
    sub_lab = labels[comp["y0"] : comp["y1"], comp["x0"] : comp["x1"]]
    sub = src_arr[comp["y0"] : comp["y1"], comp["x0"] : comp["x1"]].copy()
    only = sub_lab == cid
    # всё, что не наша компонента — прозрачное
    sub[~only] = (0, 0, 0, 0)
    # tight bbox по маске
    ys, xs = np.where(only)
    if len(xs) == 0:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    crop = Image.fromarray(sub[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], "RGBA")
    return crop


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(SOURCE):
        print(f"FAIL: нет {SOURCE}")
        return 1

    src = Image.open(SOURCE).convert("RGBA")
    arr = np.array(src)
    mask = arr[:, :, 3] >= KEEP_ALPHA
    print(f"SOURCE {src.size[0]}x{src.size[1]}  alpha>={KEEP_ALPHA}: {mask.mean()*100:.1f}%")

    os.makedirs(OUT_DIR, exist_ok=True)

    # метки на всей картинке, компоненты — по row-полосам
    labels, _all = label_components(mask)
    row_comps: dict[int, list[dict]] = {i: [] for i in range(len(ROW_BANDS))}
    # раскладываем компоненты по полосам по центру bbox
    h, w = mask.shape
    for comp in _all:
        cy = (comp["y0"] + comp["y1"]) // 2
        for ri, (y0, y1) in enumerate(ROW_BANDS):
            if y0 <= cy < y1:
                row_comps[ri].append(comp)
                break
    for ri in range(len(ROW_BANDS)):
        row_comps[ri].sort(key=lambda c: c["x0"])
        print(f"ROW {ri} y={ROW_BANDS[ri][0]}..{ROW_BANDS[ri][1]} components={len(row_comps[ri])}")

    written: list[str] = []
    notes: list[str] = []

    for cut in CUTS:
        ri = cut["row"]
        comps = row_comps[ri]
        a, b = cut["a"], cut["b"]
        chunk = comps[a:b]
        name = cut["name"]
        quals = cut.get("quality") or QUALITIES[: len(chunk)]
        print(f"\n{name} ({cut['ru']}) row{ri}[{a}:{b}] n={len(chunk)}")
        if len(chunk) != len(quals):
            notes.append(f"{name}: компонентов {len(chunk)}, quality {len(quals)}")
        for i, comp in enumerate(chunk):
            if i >= len(quals):
                notes.append(f"{name}: лишний idx={a+i} bbox=({comp['x0']},{comp['y0']})")
                print(f"  EXTRA idx={a+i} area={comp['area']}")
                continue
            q = quals[i]
            if name.startswith("_"):
                print(f"  skip {name} idx={a+i} area={comp['area']}")
                continue
            fname = f"{name}_{q}.png"
            crop = cut_component(arr, labels, comp)
            out_im = fit_game_size(crop)
            path = os.path.join(OUT_DIR, fname)
            if not args.report:
                out_im.save(path)
            written.append(fname)
            print(
                f"  OK {fname:34} crop={crop.size[0]}x{crop.size[1]} "
                f"bbox=({comp['x0']},{comp['y0']})-({comp['x1']},{comp['y1']}) area={comp['area']}"
            )

    if args.sheet or not args.report:
        present = [t for t in GAME_TYPES if any(w.startswith(t + "_") for w in written)]
        row_h = GAME_SIZE + 18
        sheet = Image.new(
            "RGBA",
            (GAME_SIZE * 4 + 24, row_h * len(present) + 8),
            (32, 32, 36, 255),
        )
        draw = ImageDraw.Draw(sheet)
        for idx, tname in enumerate(present):
            y = 4 + idx * row_h
            draw.text((4, y + GAME_SIZE + 2), tname, fill=(220, 220, 220, 255))
            for qi, quality in enumerate(QUALITIES):
                path = os.path.join(OUT_DIR, f"{tname}_{quality}.png")
                if os.path.exists(path):
                    icon = Image.open(path).convert("RGBA")
                    sheet.paste(icon, (8 + qi * (GAME_SIZE + 4), y), icon)
        if not args.report:
            sheet.save(SHEET)
            print(f"\nSHEET {SHEET}")

    print("\n==== REPORT ====")
    print(f"written={len(written)}")
    if notes:
        print("NOTES:")
        for n in notes:
            print(f"  - {n}")
    print("\nGAME TYPES:")
    ok = True
    for t in GAME_TYPES:
        if args.report:
            have = [q for q in QUALITIES if f"{t}_{q}.png" in written]
        else:
            have = [
                q
                for q in QUALITIES
                if os.path.exists(os.path.join(OUT_DIR, f"{t}_{q}.png"))
            ]
        status = "OK" if len(have) == 4 else f"PARTIAL {have}"
        if len(have) != 4:
            ok = False
        print(f"  {t:22} {status}")
    print(f"\nRESULT: {'OK' if ok else 'GAPS'}")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
