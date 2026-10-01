#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTMagic1.png → assets/spells/*.png + точечный патч spells_db.json.

Фон атласа — шахматка (RGB, не альфа). Маска контента:
  content = NOT (low-chroma AND bright)   # шахматка
  obj = dilate(content, 3)                # замыкаем блики внутри иконок
Компоненты obj >= 3000 px → bbox; внутри bbox альфа = closed content.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = os.path.join("import", "ChatGPTMagic1.png")
OUT_DIR = os.path.join("assets", "spells")
DB_PATH = os.path.join("assets", "spells", "spells_db.json")
SHEET = os.path.join(OUT_DIR, "_contact_sheet_magic.png")

GAME_SIZE = 80
MIN_AREA = 2500
CLOSE_R = 2
PAD = 3

SCHOOL_ORDER: list[list[str]] = [
    ["Fire_Arrow", "Fire_Ball", "Wall_of_Fire", "Protection_from_Fire"],
    [
        "Ice_Missile",
        "Poison_Cloud",
        "Blizzard",
        "Protection_from_Water",
        "Acid_Stream",
    ],
    [
        "Lightning",
        "Prismatic_Spray",
        "Invisibility",
        "Protection_from_Air",
        "Darkness",
    ],
    [
        "Stone_Missile",
        "Wall_of_Earth",
        "Stone_Curse",
        "Protection_from_Earth",
        "Diamond_Dust",
    ],
    ["Bless", "Haste", "Heal", "Drain_Life", "Shield", "Summon"],
    [
        "Animate_Dead",
        "Teleport",
        "Curse",
        "Slow",
        "Light",
        "Control_Spirit",
    ],
]

Y_BANDS = [(0, 240), (240, 470), (470, 700), (700, 910), (910, 1080), (1080, 1300)]


def snake(name: str) -> str:
    return name.lower().replace("-", "_")


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    if radius <= 0:
        return mask.copy()
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            shifted = np.zeros_like(mask)
            y0, y1 = max(0, dy), min(h, h + dy)
            x0, x1 = max(0, dx), min(w, w + dx)
            shifted[y0:y1, x0:x1] = mask[y0 - dy : y1 - dy, x0 - dx : x1 - dx]
            out |= shifted
    return out


def fit_game_size(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    scale = GAME_SIZE / max(w, h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GAME_SIZE, GAME_SIZE), (0, 0, 0, 0))
    canvas.paste(im, ((GAME_SIZE - nw) // 2, (GAME_SIZE - nh) // 2), im)
    return canvas


def label_components(mask: np.ndarray, min_area: int) -> list[dict]:
    h, w = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    comps: list[dict] = []
    ys, xs = np.where(mask)
    for y0, x0 in zip(ys, xs):
        if visited[y0, x0]:
            continue
        q: deque[tuple[int, int]] = deque([(int(y0), int(x0))])
        visited[y0, x0] = True
        miny = maxy = int(y0)
        minx = maxx = int(x0)
        area = 0
        while q:
            y, x = q.popleft()
            area += 1
            miny = min(miny, y)
            maxy = max(maxy, y)
            minx = min(minx, x)
            maxx = max(maxx, x)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    q.append((ny, nx))
        if area >= min_area:
            comps.append(
                {
                    "x0": minx,
                    "y0": miny,
                    "x1": maxx + 1,
                    "y1": maxy + 1,
                    "area": area,
                }
            )
    comps.sort(key=lambda c: (c["y0"] // 80, c["x0"]))
    return comps


def patch_spells_db(written: set[str]) -> int:
    """Патч через json (indent=2, как в файле), без хвостовых запятых."""
    path = Path(DB_PATH)
    db = json.loads(path.read_text(encoding="utf-8"))
    patched = 0
    for school in SCHOOL_ORDER:
        for spell in school:
            fname = f"{snake(spell)}.png"
            if fname not in written or spell not in db:
                continue
            icon = f"res://assets/spells/{fname}"
            entry = db[spell]
            icons = entry.get("icons")
            if not isinstance(icons, dict):
                icons = {}
            if icons.get("scroll") != icon:
                icons["scroll"] = icon
                entry["icons"] = icons
                patched += 1
                print(f"  patched {spell} -> {fname}")
    if patched:
        path.write_text(
            json.dumps(db, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return patched


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--no-patch", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(SOURCE):
        print(f"FAIL: нет {SOURCE}")
        return 1

    src = Image.open(SOURCE).convert("RGB")
    arr = np.array(src)
    af = arr.astype(np.float32)
    mx = af.max(axis=2)
    mn = af.min(axis=2)
    content = ~(((mx - mn) < 22.0) & (mx > 150.0))
    obj = dilate(content, CLOSE_R)
    print(
        f"SOURCE {src.size[0]}x{src.size[1]} "
        f"content={content.mean()*100:.1f}% obj={obj.mean()*100:.1f}%"
    )

    comps = label_components(obj, MIN_AREA)
    print(f"components area>={MIN_AREA}: {len(comps)}")

    by_band: list[list[dict]] = [[] for _ in Y_BANDS]
    for c in comps:
        cy = (c["y0"] + c["y1"]) // 2
        for bi, (ya, yb) in enumerate(Y_BANDS):
            if ya <= cy < yb:
                by_band[bi].append(c)
                break
        else:
            print(f"  WARN вне полос: {c}")

    expected = sum(len(s) for s in SCHOOL_ORDER)
    print(f"expected={expected} bands={[len(b) for b in by_band]}")

    os.makedirs(OUT_DIR, exist_ok=True)
    written: set[str] = set()
    missing: list[str] = []
    h, w = arr.shape[:2]

    for bi, spells in enumerate(SCHOOL_ORDER):
        cells = sorted(by_band[bi], key=lambda c: c["x0"])
        # если компонентов меньше, чем заклинаний — достраиваем bbox по полосе
        if len(cells) < len(spells) and cells:
            xs = [c["x0"] for c in cells] + [cells[-1]["x1"]]
            # оценка ширины ячейки по среднему
            widths = [cells[i]["x1"] - cells[i]["x0"] for i in range(len(cells) - 1)]
            avg_w = int(np.mean(widths)) if widths else 180
            ya = Y_BANDS[bi][0]
            yb = Y_BANDS[bi][1] - 20
            while len(cells) < len(spells):
                x0 = xs[-1] + 8
                x1 = min(src.size[0] - 4, x0 + avg_w)
                if x1 - x0 < 80:
                    break
                cells.append(
                    {"x0": x0, "y0": ya, "x1": x1, "y1": yb, "area": -1, "synthetic": True}
                )
                xs.append(x1)
                print(f"  synth cell band{bi} -> {cells[-1]}")
        print(f"\nBAND {bi} spells={len(spells)} cells={len(cells)}")
        for i, spell in enumerate(spells):
            fname = f"{snake(spell)}.png"
            if i >= len(cells):
                print(f"  MISSING {fname}")
                missing.append(fname)
                continue
            c = cells[i]
            y0 = max(0, c["y0"] - PAD)
            x0 = max(0, c["x0"] - PAD)
            y1 = min(h, c["y1"] + PAD)
            x1 = min(w, c["x1"] + PAD)
            local_content = content[y0:y1, x0:x1]
            local_obj = dilate(local_content, CLOSE_R)
            # убираем чистую шахматку по краям bbox
            local_rgb = af[y0:y1, x0:x1]
            # шахматка: низкая хрома + яркость (та же формула)
            loc_mx = local_rgb.max(axis=2)
            loc_mn = local_rgb.min(axis=2)
            local_bg = ((loc_mx - loc_mn) < 22.0) & (loc_mx > 150.0)
            # альфа: закрытый объект, но не «шахматные» ядра
            alpha_m = local_obj & ~dilate(local_bg, 0)
            # если после вырезки шахматки мало — берём local_obj целиком
            if alpha_m.mean() < 0.15:
                alpha_m = local_obj
            # не даём альфе стать пустой
            if not alpha_m.any():
                alpha_m = local_obj
            a = np.where(alpha_m, 255, 0).astype(np.uint8)
            a = np.array(Image.fromarray(a, "L").filter(ImageFilter.GaussianBlur(0.7)))
            rgba = np.dstack([arr[y0:y1, x0:x1], a])
            crop = Image.fromarray(rgba, "RGBA")
            out_im = fit_game_size(crop)
            if not args.report:
                out_im.save(os.path.join(OUT_DIR, fname))
            written.add(fname)
            print(
                f"  OK {fname:28} {crop.size[0]}x{crop.size[1]} "
                f"area={c['area']} alpha%={float((a>=128).mean()*100):.0f}"
            )

        for j in range(len(spells), len(cells)):
            print(f"  extra cell area={cells[j]['area']} bbox={cells[j]}")

    if not args.no_patch and written and not args.report:
        n = patch_spells_db(written)
        print(f"\nspells_db scroll patched: {n}")

    if args.sheet or not args.report:
        cell = GAME_SIZE + 8
        sheet = Image.new(
            "RGBA", (6 * cell + 16, 6 * (cell + 14) + 8), (32, 32, 36, 255)
        )
        draw = ImageDraw.Draw(sheet)
        for ri, spells in enumerate(SCHOOL_ORDER):
            y = 6 + ri * (cell + 14)
            draw.text(
                (2, y + GAME_SIZE),
                spells[0].split("_")[0],
                fill=(210, 210, 210, 255),
            )
            for ci, spell in enumerate(spells):
                p = os.path.join(OUT_DIR, f"{snake(spell)}.png")
                if os.path.exists(p) and not args.report:
                    ic = Image.open(p).convert("RGBA")
                    sheet.paste(ic, (8 + ci * cell, y), ic)
        if not args.report:
            sheet.save(SHEET)
            print(f"SHEET {SHEET}")

    print("\n==== REPORT ====")
    print(f"written={len(written)} missing={len(missing)}")
    if missing:
        print(missing)
    ok = len(written) == expected and not missing
    print(f"RESULT: {'OK' if ok else 'GAPS'} ({len(written)}/{expected})")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
