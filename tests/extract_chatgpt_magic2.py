#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTMagic2.png → посохи/книги/свитки/зелья атрибутов.

Атлас 1536x1024 RGB, фон серый. Сетка:
  row0: 4 посоха cheap/common/good/elite
  row1: 5 книг Fire/Water/Earth/Air/Astral
  row2: 5 свитков Fire/Water/Earth/Air/Astral
  row3: 4 банки Body/Reaction/Mind/Spirit (Сила/Ловкость/Разум/Дух)

Выход:
  assets/items/placeholder/staff_{q}.png
  assets/spells/book_{sphere}.png
  assets/spells/scroll_{sphere}.png
  assets/potions/attr_{body|reaction|mind|spirit}.png
Плюс патч item_db.json.

Запуск:
    python tests/extract_chatgpt_magic2.py
    python tests/extract_chatgpt_magic2.py --report
    python tests/extract_chatgpt_magic2.py --sheet
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = os.path.join("import", "ChatGPTMagic2.png")
ROOT = Path(r"C:/Work/Allodshome")
SHEET = ROOT / "assets" / "items" / "placeholder" / "_contact_sheet_magic2.png"

GAME_SIZE = 80
MIN_AREA = 1200
CLOSE_R = 2
BG_CHROMA = 25.0
BG_VAL = 120.0
PAD = 3

# (row, имя файла относительно assets/)
# row0 staffs, row1 books, row2 scrolls, row3 potions
CUTS: list[tuple[int, str]] = [
    # посохи
    (0, "items/placeholder/staff_cheap.png"),
    (0, "items/placeholder/staff_common.png"),
    (0, "items/placeholder/staff_good.png"),
    (0, "items/placeholder/staff_elite.png"),
    # книги
    (1, "spells/book_fire.png"),
    (1, "spells/book_water.png"),
    (1, "spells/book_earth.png"),
    (1, "spells/book_air.png"),
    (1, "spells/book_astral.png"),
    # свитки
    (2, "spells/scroll_fire.png"),
    (2, "spells/scroll_water.png"),
    (2, "spells/scroll_earth.png"),
    (2, "spells/scroll_air.png"),
    (2, "spells/scroll_astral.png"),
    # зелья атрибутов
    (3, "potions/attr_body.png"),
    (3, "potions/attr_reaction.png"),
    (3, "potions/attr_mind.png"),
    (3, "potions/attr_spirit.png"),
]


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


def fit80(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    scale = GAME_SIZE / max(w, h)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GAME_SIZE, GAME_SIZE), (0, 0, 0, 0))
    canvas.paste(im, ((GAME_SIZE - nw) // 2, (GAME_SIZE - nh) // 2), im)
    return canvas


def label_comps(mask: np.ndarray, min_area: int) -> list[dict]:
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
                {"x0": minx, "y0": miny, "x1": maxx + 1, "y1": maxy + 1, "area": area}
            )
    comps.sort(key=lambda c: c["x0"])
    return comps


def patch_item_db() -> int:
    path = ROOT / "assets/items/item_db.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    n = 0

    # посохи по quality
    staff_map = {
        "Cheap": "res://assets/items/placeholder/staff_cheap.png",
        "Common": "res://assets/items/placeholder/staff_common.png",
        "Uncommon": "res://assets/items/placeholder/staff_common.png",
        "Good": "res://assets/items/placeholder/staff_good.png",
        "Rare": "res://assets/items/placeholder/staff_good.png",
        "Elite": "res://assets/items/placeholder/staff_elite.png",
        "Very Rare": "res://assets/items/placeholder/staff_elite.png",
        "Bad": "res://assets/items/placeholder/staff_cheap.png",
    }
    # книги сфер
    sphere_book = {
        "Fire": "res://assets/spells/book_fire.png",
        "Water": "res://assets/spells/book_water.png",
        "Earth": "res://assets/spells/book_earth.png",
        "Air": "res://assets/spells/book_air.png",
        "Astral": "res://assets/spells/book_astral.png",
    }
    # свитки по sphere -> иконка
    scroll_by_sphere = {
        "Fire": "res://assets/spells/scroll_fire.png",
        "Water": "res://assets/spells/scroll_water.png",
        "Earth": "res://assets/spells/scroll_earth.png",
        "Air": "res://assets/spells/scroll_air.png",
        "Astral": "res://assets/spells/scroll_astral.png",
    }
    # зелья атрибутов
    attr_potions = {
        "Potion Body": "res://assets/potions/attr_body.png",
        "Potion Reaction": "res://assets/potions/attr_reaction.png",
        "Potion Mind": "res://assets/potions/attr_mind.png",
        "Potion Spirit": "res://assets/potions/attr_spirit.png",
    }

    # сперва строим map spell->sphere из spells_db если есть
    spell_sphere: dict[str, str] = {}
    sp_path = ROOT / "assets/spells/spells_db.json"
    if sp_path.exists():
        sp = json.loads(sp_path.read_text(encoding="utf-8"))
        for name, s in sp.items():
            spell_sphere[name] = str(s.get("sphere") or "")

    for it in data:
        key = str(it.get("key") or "")
        typ = str(it.get("type") or "")
        q = str(it.get("quality") or "")
        icon = ""

        if typ == "Staff":
            icon = staff_map.get(q, "res://assets/items/placeholder/staff_common.png")

        if key.startswith("Book "):
            rest = key[5:]
            for sphere, bpath in sphere_book.items():
                if rest == sphere or rest.startswith(sphere + " "):
                    icon = bpath
                    break

        if key.startswith("Scroll ") or key.startswith("SuperScroll "):
            spell = key.split(" ", 1)[1] if " " in key else ""
            # "Fire Ball" -> Fire_Ball
            sname = spell.replace(" ", "_")
            sphere = spell_sphere.get(sname, "")
            if not sphere:
                # literal match
                for sn, sp2 in spell_sphere.items():
                    if sn.replace("_", " ").lower() == spell.lower():
                        sphere = sp2
                        break
            if sphere in scroll_by_sphere:
                icon = scroll_by_sphere[sphere]

        if key in attr_potions:
            icon = attr_potions[key]

        if icon and it.get("icon") != icon:
            it["icon"] = icon
            n += 1

    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"item_db icons patched: {n}")
    return n


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
    mx, mn = af.max(axis=2), af.min(axis=2)
    content = ~(((mx - mn) < BG_CHROMA) & (mx > BG_VAL))
    obj = dilate(content, CLOSE_R)
    print(f"SOURCE {src.size[0]}x{src.size[1]} content={content.mean()*100:.1f}%")

    comps = label_comps(obj, MIN_AREA)
    print(f"components: {len(comps)}")
    # раскладка по строкам
    rows: list[list[dict]] = [[] for _ in range(4)]
    for c in comps:
        cy = (c["y0"] + c["y1"]) // 2
        if cy < 310:
            rows[0].append(c)
        elif cy < 555:
            rows[1].append(c)
        elif cy < 790:
            rows[2].append(c)
        else:
            rows[3].append(c)
    for i, row in enumerate(rows):
        row.sort(key=lambda c: c["x0"])
        print(f"  row{i}: {len(row)} x0={[c['x0'] for c in row]}")

    rgba_full = np.dstack([arr, np.where(content, 255, 0).astype(np.uint8)])
    a_soft = np.array(
        Image.fromarray(rgba_full[:, :, 3], "L").filter(ImageFilter.GaussianBlur(0.7))
    )
    rgba_full[:, :, 3] = a_soft

    written = 0
    missing = []
    # индексы внутри строки
    row_idx = {0: 0, 1: 0, 2: 0, 3: 0}
    # сначала пройдём CUTS по порядку — внутри строки слева направо
    for ri, rel in CUTS:
        idx = row_idx[ri]
        row_idx[ri] += 1
        row = rows[ri]
        fname = rel.replace("/", os.sep)
        if idx >= len(row):
            print(f"  MISSING {rel} (idx {idx})")
            missing.append(rel)
            continue
        c = row[idx]
        y0 = max(0, c["y0"] - PAD)
        x0 = max(0, c["x0"] - PAD)
        y1 = min(arr.shape[0], c["y1"] + PAD)
        x1 = min(arr.shape[1], c["x1"] + PAD)
        crop = rgba_full[y0:y1, x0:x1].copy()
        # альфа только по контенту в crop
        local = content[y0:y1, x0:x1]
        crop[:, :, 3] = np.where(local, crop[:, :, 3], 0)
        img = Image.fromarray(crop, "RGBA")
        out80 = fit80(img)
        path = ROOT / "assets" / rel
        if not args.report:
            path.parent.mkdir(parents=True, exist_ok=True)
            out80.save(path)
        written += 1
        print(f"  OK {rel:40} row{ri}[{idx}] crop={crop.shape[1]}x{crop.shape[0]}")

    if not args.no_patch and written and not args.report:
        n = patch_item_db()
        print(f"item_db patched: {n}")

    if args.sheet or not args.report:
        # лист по категориям
        groups = [
            ("staffs", [c for c in CUTS if "staff_" in c[1]]),
            ("books", [c for c in CUTS if "book_" in c[1]]),
            ("scrolls", [c for c in CUTS if "scroll_" in c[1]]),
            ("potions", [c for c in CUTS if "attr_" in c[1]]),
        ]
        cell = GAME_SIZE + 10
        sheet = Image.new("RGBA", (5 * cell + 16, 4 * (cell + 16) + 8), (32, 32, 36, 255))
        draw = ImageDraw.Draw(sheet)
        for gi, (gname, items) in enumerate(groups):
            y = 6 + gi * (cell + 16)
            draw.text((2, y + GAME_SIZE + 2), gname, fill=(210, 210, 210, 255))
            for ci, (_, rel) in enumerate(items):
                path = ROOT / "assets" / rel
                x = 8 + ci * cell
                label = Path(rel).stem.replace("staff_", "").replace("book_", "").replace("scroll_", "").replace("attr_", "")
                draw.text((x, y + GAME_SIZE + 2), label[:10], fill=(160, 160, 160, 255))
                if path.exists() and not args.report:
                    ic = Image.open(path).convert("RGBA")
                    sheet.paste(ic, (x, y), ic)
        if not args.report:
            SHEET.parent.mkdir(parents=True, exist_ok=True)
            sheet.save(SHEET)
            print(f"SHEET {SHEET}")

    print("\n==== REPORT ====")
    print(f"written={written} missing={len(missing)}")
    if missing:
        print(missing)
    ok = written == len(CUTS) and not missing
    print(f"RESULT: {'OK' if ok else 'GAPS'} ({written}/{len(CUTS)})")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
