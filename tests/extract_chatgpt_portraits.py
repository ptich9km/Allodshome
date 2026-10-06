#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTMain*.png → assets/hero_portraits/*.png (расы для героя).

Атласы (замер по снимкам):
  Human1/2  1024x1536  2x2: mage M/F | warrior M/F  (тёмный фон)
  Druid1    1024x1536  2x2: warrior M/F | mage M/F
  Necromant 1536x1024  верхний ряд x4 (фронт), низ = спины — НЕ берём
  Ork1      1536x1024  верхний ряд x4 (фронт), низ = спины — НЕ берём

Фон: тёмный градиент — color-key от углов ячейки + заливка от краёв.
Имена: {race}_{gender}_{class}.png  (war|mage)

Запуск:
  python tests/extract_chatgpt_portraits.py
  python tests/extract_chatgpt_portraits.py --report
  python tests/extract_chatgpt_portraits.py --sheet
  python tests/extract_chatgpt_portraits.py --check
"""
import argparse
import hashlib
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMP = os.path.join(ROOT, "import")
OUT = os.path.join(ROOT, "assets", "hero_portraits")
DB = os.path.join(OUT, "portraits_db.json")
SHEET = os.path.join(OUT, "_contact_sheet.png")

# long side of output portrait
TARGET = 240
# flood-fill tolerance: тёмный градифон, но НЕ глотать тёмную одежду/кожу
BG_TOL = 85
# min component area after keying
MIN_AREA = 400
# pad around bbox
PAD = 8

# (source, layout, [(out_name, row, col), ...])
# layout: "2x2" = full image quadrants; "row1x4" = top row only, 4 columns
JOBS = [
    ("ChatGPTMainHuman1.png", "2x2", [
        ("human_m_mage.png", 0, 0),
        ("human_f_mage.png", 0, 1),
        ("human_m_war.png", 1, 0),
        ("human_f_war.png", 1, 1),
    ]),
    ("ChatGPTMainHuman2.png", "2x2", [
        ("human2_m_mage.png", 0, 0),
        ("human2_f_mage.png", 0, 1),
        ("human2_m_war.png", 1, 0),
        ("human2_f_war.png", 1, 1),
    ]),
    ("ChatGPTMainDruid1.png", "2x2", [
        ("druid_m_war.png", 0, 0),
        ("druid_f_war.png", 0, 1),
        ("druid_m_mage.png", 1, 0),
        ("druid_f_mage.png", 1, 1),
    ]),
    ("ChatGPTMainNecromant1.png", "row1x4", [
        ("necro_m_mage.png", 0, 0),
        ("necro_f_mage.png", 0, 1),
        ("necro_m_war.png", 0, 2),
        ("necro_f_war.png", 0, 3),
    ]),
    ("ChatGPTMainOrk1.png", "row1x4", [
        ("ork_m_war.png", 0, 0),
        ("ork_f_war.png", 0, 1),
        ("ork_m_mage.png", 0, 2),
        ("ork_f_mage.png", 0, 3),
    ]),
]


def _bg_sample(im, box):
    """Только углы ячейки. Семплы с середины краёв попадали на скелет/кость
    и color-key съедал персонажа целиком."""
    x0, y0, x1, y1 = box
    w = x1 - x0
    h = y1 - y0
    pts = []
    for fx, fy in ((0.04, 0.04), (0.96, 0.04), (0.04, 0.96), (0.96, 0.96)):
        px = im.getpixel((int(x0 + fx * w), int(y0 + fy * h)))
        if len(px) >= 3:
            luma = 0.299 * px[0] + 0.587 * px[1] + 0.114 * px[2]
            # отбрасываем светлые «углы» — это фон-персонажа, не фон
            if luma < 70:
                pts.append(px[:3])
    if not pts:
        pts = [(20, 18, 16)]
    return pts


def _is_bg(px, bgs, tol2):
    """Только цветовое расстояние до семплов фона. Глобальный luma-ключ
    съедал тёмные робы/кожу некромантов и орков — отключён."""
    r, g, b = px[0], px[1], px[2]
    for bg in bgs:
        dr = r - bg[0]
        dg = g - bg[1]
        db = b - bg[2]
        if dr * dr + dg * dg + db * db <= tol2:
            return True
    return False


def _cell_box(im, layout, row, col):
    w, h = im.size
    if layout == "2x2":
        cw = w // 2
        ch = h // 2
        return (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
    if layout == "row1x4":
        cw = w // 4
        # top half only (front views)
        return (col * cw, 0, (col + 1) * cw, h // 2)
    raise ValueError(layout)


def _key_and_bbox(im, box, bgs, tol=None):
    x0, y0, x1, y1 = box
    cell = im.crop(box).convert("RGBA")
    px = cell.load()
    cw, ch = cell.size
    t = BG_TOL if tol is None else int(tol)
    tol2 = t * t
    mask = [[False] * cw for _ in range(ch)]
    from collections import deque
    q = deque()
    for x in range(cw):
        for y in (0, ch - 1):
            if _is_bg(px[x, y], bgs, tol2) and not mask[y][x]:
                mask[y][x] = True
                q.append((x, y))
    for y in range(ch):
        for x in (0, cw - 1):
            if _is_bg(px[x, y], bgs, tol2) and not mask[y][x]:
                mask[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < cw and 0 <= ny < ch and not mask[ny][nx]:
                if _is_bg(px[nx, ny], bgs, tol2):
                    mask[ny][nx] = True
                    q.append((nx, ny))
    minx, miny, maxx, maxy = cw, ch, -1, -1
    opaque = 0
    for y in range(ch):
        for x in range(cw):
            # прозрачность только по СВЯЗНОМУ фону (flood), не глобальным
            # color-key: иначе кость скелета/тёмная кожа совпадают с градиентом.
            if mask[y][x]:
                px[x, y] = (0, 0, 0, 0)
            else:
                opaque += 1
                if x < minx:
                    minx = x
                if y < miny:
                    miny = y
                if x > maxx:
                    maxx = x
                if y > maxy:
                    maxy = y
    if opaque < MIN_AREA or maxx < 0:
        return cell, None
    minx = max(0, minx - PAD)
    miny = max(0, miny - PAD)
    maxx = min(cw - 1, maxx + PAD)
    maxy = min(ch - 1, maxy + PAD)
    bbox = (minx, miny, maxx + 1, maxy + 1)
    cut = cell.crop(bbox)
    cw2, ch2 = cut.size
    scale = TARGET / float(max(cw2, ch2))
    nw = max(1, int(round(cw2 * scale)))
    nh = max(1, int(round(ch2 * scale)))
    cut = cut.resize((nw, nh), Image.Resampling.LANCZOS)
    return cut, bbox


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def run(args):
    os.makedirs(OUT, exist_ok=True)
    db = {"source": "tests/extract_chatgpt_portraits.py",
          "target_long_side": TARGET, "bg_tol": BG_TOL, "files": {}}
    ok = True
    for src_name, layout, cells in JOBS:
        src = os.path.join(IMP, src_name)
        if not os.path.exists(src):
            print("FAIL missing", src_name)
            ok = False
            continue
        im = Image.open(src).convert("RGB")
        for out_name, row, col in cells:
            box = _cell_box(im, layout, row, col)
            bgs = _bg_sample(im, box)
            cut, bbox = _key_and_bbox(im, box, bgs)
            if bbox is None:
                # запасной проход: мягче толерантность (тёмный скелет/кожа)
                cut, bbox = _key_and_bbox(im, box, bgs, tol=120)
                if bbox is None:
                    print("FAIL empty", out_name, "from", src_name)
                    ok = False
                    continue
                print("  fallback tol=120 for", out_name)
            path = os.path.join(OUT, out_name)
            if args.check:
                if not os.path.exists(path):
                    print("FAIL no file", out_name)
                    ok = False
                    continue
                # regenerate to temp and compare
                tmp = os.path.join(OUT, "._" + out_name)
                cut.save(tmp, "PNG")
                got, want = sha256(tmp), sha256(path)
                os.remove(tmp)
                mark = "OK  " if got == want else "FAIL"
                if got != want:
                    ok = False
                print("%s %-22s %s  %s" % (mark, out_name, got[:12], want[:12]))
            else:
                cut.save(path, "PNG")
                print("saved %-22s %dx%d bgs=%d bbox=%s" % (
                    out_name, cut.size[0], cut.size[1], len(bgs), bbox))
            db["files"][out_name] = {
                "source": src_name,
                "layout": layout,
                "cell_box": list(box),
                "bgs": [list(b) for b in bgs],
                "bbox_in_cell": list(bbox) if bbox else None,
                "size": list(cut.size),
            }

    if args.sheet or not args.check:
        # contact sheet
        files = sorted(db["files"].keys())
        cols = 5
        cell = 140
        rows = (len(files) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * cell, rows * (cell + 18)), (24, 24, 28, 255))
        d = ImageDraw.Draw(sheet)
        for i, name in enumerate(files):
            p = os.path.join(OUT, name)
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGBA")
            im.thumbnail((cell - 8, cell - 8))
            x = (i % cols) * cell + (cell - im.size[0]) // 2
            y = (i // cols) * (cell + 18) + 4
            sheet.paste(im, (x, y), im)
            d.text(((i % cols) * cell + 4, (i // cols) * (cell + 18) + cell),
                   name.replace(".png", ""), fill=(220, 200, 140, 255))
        sheet.save(SHEET)
        print("sheet", SHEET)

    if not args.check:
        with open(DB, "w", encoding="utf-8") as fh:
            json.dump(db, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("db", DB)
    else:
        print("SHA256:", "all match" if ok else "MISMATCH")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
