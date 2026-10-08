#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка ChatGPTMasters1.png → свитки/чертежи + декор мастерской + ткань.

Атлас 1254x1254 RGB, фон светлая шахматка. Сетка (замер контента 08.10):
  row0: пустой свиток | чертёж брони | чертёж одежды | чертёж меча
  row1: чертёж посоха | наковальня+слитки | печка+слитки
  row2: ткацкий станок+ткань | рулон ткани

Выход:
  assets/items/recipes/scroll_empty.png
  assets/items/recipes/blueprint_armor.png (+ _empty — центр стёрт)
  assets/items/recipes/blueprint_clothes.png (+ _empty)
  assets/items/recipes/blueprint_weapon.png (+ _empty)
  assets/items/recipes/blueprint_staff.png (+ _empty)
  assets/professions/workshop/anvil.png
  assets/professions/workshop/furnace.png
  assets/professions/workshop/loom.png
  assets/professions/workshop/fabric.png   # перезапись

Центр чертежей: тёмный рисунок заливается СРЕДНИМ цветом пергамента
с полей того же листа (цвет тона не меняем — объединяет иконка вещи).

Запуск:
    python tests/extract_chatgpt_masters1.py --report
    python tests/extract_chatgpt_masters1.py
    python tests/extract_chatgpt_masters1.py --sheet
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SOURCE = os.path.join("import", "ChatGPTMasters1.png")
ROOT = Path(r"C:/Work/Allodshome")
SHEET = ROOT / "assets" / "items" / "recipes" / "_contact_sheet_masters1.png"

GAME_SIZE = 80
MIN_AREA = 2500
CLOSE_R = 2
BG_CHROMA = 25.0
BG_VAL = 120.0
PAD = 4

# Оси y для 3 рядов (замер content-mask 08.10: 84-409 / 439-856 / 884-1214)
ROW_Y = (420, 870)

# (row, имя файла относительно assets/) — слева направо
CUTS: list[tuple[int, str]] = [
    (0, "items/recipes/scroll_empty.png"),
    (0, "items/recipes/blueprint_armor.png"),
    (0, "items/recipes/blueprint_clothes.png"),
    (0, "items/recipes/blueprint_weapon.png"),
    (1, "items/recipes/blueprint_staff.png"),
    (1, "professions/workshop/anvil.png"),
    (1, "professions/workshop/furnace.png"),
    (2, "professions/workshop/loom.png"),
    (2, "professions/workshop/fabric.png"),
]

# Чертежи, у которых стирается центр
BLUEPRINTS = [
    "items/recipes/blueprint_armor.png",
    "items/recipes/blueprint_clothes.png",
    "items/recipes/blueprint_weapon.png",
    "items/recipes/blueprint_staff.png",
]

# Центральная зона стирания (доли bbox) — рисунок, не край пергамента
ERASE_INSET = 0.14
# Пиксель «рисунок», если его цвет дальше от среднего пергамента, чем порог
ERASE_DIST = 28.0
# Запасной люм: совсем тёмный контур
ERASE_LUM = 85.0
# Растушёвка краёв заливки (px на полном разрешении)
ERASE_FEATHER = 14.0
# Сила зерна пергамента в залитой зоне (доля std колец)
ERASE_GRAIN = 0.35


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


def erase_blueprint_center_rgba(arr_crop: np.ndarray) -> tuple[np.ndarray, dict]:
    """Убрать рисунок GPT diffusion-inpaint'ом: пергамент «втекает» из полей.

    Маска рисунка (цветовое расстояние до тона полей) → дилатация →
    многократный GaussianBlur по маске. Края пятна не читаются как
    прямоугольник: текстура листа продолжается внутрь.
    """
    info = {"ok": False, "lines": 0, "center": (0, 0), "parchment": (0, 0, 0)}
    if arr_crop.ndim != 3 or arr_crop.shape[2] != 4:
        return arr_crop, info
    alpha = arr_crop[:, :, 3]
    solid = alpha > 200
    if solid.sum() < 500:
        return arr_crop, info
    ys, xs = np.where(solid)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    bh, bw = y1 - y0, x1 - x0
    iy0 = y0 + int(bh * ERASE_INSET)
    iy1 = y1 - int(bh * ERASE_INSET)
    ix0 = x0 + int(bw * ERASE_INSET)
    ix1 = x1 - int(bw * ERASE_INSET)
    if iy1 <= iy0 or ix1 <= ix0:
        return arr_crop, info

    ring = np.zeros((bh, bw), dtype=bool)
    ring[:, :] = solid[y0:y1, x0:x1]
    cy0, cy1 = iy0 - y0, iy1 - y0
    cx0, cx1 = ix0 - x0, ix1 - x0
    inner = np.zeros_like(ring)
    inner[cy0:cy1, cx0:cx1] = True
    margin = ring & ~inner
    if margin.sum() < 50:
        margin = ring.copy()
    ring_rgb = arr_crop[y0:y1, x0:x1, 0:3][margin].astype(np.float32)
    parch = ring_rgb.mean(axis=0)

    ch, cw = iy1 - iy0, ix1 - ix0
    # Работаем на всём ббоксе (с полями) — инпейнту нужен контекст краёв
    bbox = arr_crop[y0:y1, x0:x1, 0:3].astype(np.float32).copy()
    bbox_solid = solid[y0:y1, x0:x1]
    rgb_c = bbox[:, :, 0:3]
    lum_c = rgb_c[:, :, 0] * 0.299 + rgb_c[:, :, 1] * 0.587 + rgb_c[:, :, 2] * 0.114
    dist_c = np.sqrt(((rgb_c - parch[None, None, :]) ** 2).sum(axis=2))
    # Рисунок только в центральной зоне (не трогаем рамку орнамента)
    zone = np.zeros((bh, bw), dtype=bool)
    zone[cy0:cy1, cx0:cx1] = True
    drawing = ((dist_c > ERASE_DIST) | (lum_c < ERASE_LUM)) & bbox_solid & zone

    # Дилатация маски рисунка
    draw_m = Image.fromarray((drawing * 255).astype(np.uint8), "L")
    draw_m = draw_m.filter(ImageFilter.MaxFilter(9))
    mask = np.array(draw_m) > 100

    # Diffusion inpaint: пока маска непуста, blur подмешиваем внутрь пятна
    work = bbox.copy()
    # Старт: средний тон, чтобы первые итерации не тянули рисунок
    work[mask] = parch[None, None, :]
    for i in range(24):
        img = Image.fromarray(work.clip(0, 255).astype(np.uint8), "RGB")
        # sigma растёт — сначала точная заливка, потом «размаз» текстуры
        sigma = 2.0 + i * 0.85
        blurred = np.array(img.filter(ImageFilter.GaussianBlur(sigma))).astype(np.float32)
        # Внутри маски — только blur (контекст с полей), маска не «протухает»
        work[mask] = blurred[mask]

    # Мягкая растушёвка краёв пятна: alpha = blur(маски)
    alpha_m = Image.fromarray((mask * 255).astype(np.uint8), "L")
    alpha_m = alpha_m.filter(ImageFilter.GaussianBlur(ERASE_FEATHER))
    alpha_a = np.array(alpha_m).astype(np.float32) / 255.0
    # Не залезаем на орнаментную рамку
    edge = np.ones((bh, bw), dtype=np.float32)
    m = max(4, int(min(bh, bw) * 0.07))
    ramp = np.linspace(0.0, 1.0, m)
    edge[:m, :] *= ramp[:, None]
    edge[-m:, :] *= ramp[::-1, None]
    edge[:, :m] *= ramp[None, :]
    edge[:, -m:] *= ramp[::-1][None, :]
    alpha_a = np.clip(alpha_a * edge, 0.0, 1.0)

    out = arr_crop.copy()
    a3 = alpha_a[:, :, None]
    blended = arr_crop[y0:y1, x0:x1, 0:3].astype(np.float32) * (1.0 - a3) + work * a3
    out[y0:y1, x0:x1, 0:3] = blended.clip(0, 255).astype(np.uint8)

    info = {
        "ok": True,
        "lines": int((alpha_a > 0.4).sum()),
        "center": (cw, ch),
        "parchment": (int(round(float(parch[0]))),
                      int(round(float(parch[1]))),
                      int(round(float(parch[2])))),
    }
    return out, info


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--no-patch", action="store_true", help="не стирать центр чертежей")
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
    # 3 ряда
    rows: list[list[dict]] = [[] for _ in range(3)]
    for c in comps:
        cy = (c["y0"] + c["y1"]) // 2
        if cy < ROW_Y[0]:
            rows[0].append(c)
        elif cy < ROW_Y[1]:
            rows[1].append(c)
        else:
            rows[2].append(c)
    for i, row in enumerate(rows):
        row.sort(key=lambda c: c["x0"])
        print(f"  row{i}: {len(row)} x0={[c['x0'] for c in row]} "
              f"y0={[(c['y0'], c['y1']) for c in row]}")

    rgba_full = np.dstack([arr, np.where(content, 255, 0).astype(np.uint8)])
    a_soft = np.array(
        Image.fromarray(rgba_full[:, :, 3], "L").filter(ImageFilter.GaussianBlur(0.7))
    )
    rgba_full[:, :, 3] = a_soft

    written = 0
    missing = []
    row_idx = {0: 0, 1: 0, 2: 0}
    print("cuts:")
    for ri, rel in CUTS:
        idx = row_idx[ri]
        row_idx[ri] += 1
        row = rows[ri]
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
        local = content[y0:y1, x0:x1]
        crop[:, :, 3] = np.where(local, crop[:, :, 3], 0)
        img = Image.fromarray(crop, "RGBA")
        out80 = fit80(img)
        path = ROOT / "assets" / rel
        if not args.report:
            path.parent.mkdir(parents=True, exist_ok=True)
            out80.save(path)
        written += 1
        print(f"  OK {rel:42} row{ri}[{idx}] crop={crop.shape[1]}x{crop.shape[0]}")

        # Чертежи: пустая копия ДО fit80, на полном разрешении
        if rel in BLUEPRINTS and not args.report and not args.no_patch:
            erased, info = erase_blueprint_center_rgba(crop)
            if info["ok"]:
                empty80 = fit80(Image.fromarray(erased, "RGBA"))
                empty_path = path.with_name(path.stem + "_empty.png")
                empty80.save(empty_path)
                print(f"    empty {empty_path.name}: lines={info['lines']} "
                      f"center={info['center']} parchment={info['parchment']}")
            else:
                print(f"    empty SKIP {rel}")

    # Контактный лист
    if args.sheet or not args.report:
        cell = GAME_SIZE + 12
        n_cols = 5
        n_rows = 3
        sheet = Image.new(
            "RGBA",
            (n_cols * cell + 20, n_rows * (cell + 20) + 40),
            (28, 26, 30, 255),
        )
        draw = ImageDraw.Draw(sheet)
        draw.text((8, 4), "ChatGPTMasters1 — cuts + empty blueprints", fill=(220, 220, 220, 255))

        # Исходник-кроп (уменьшенный)
        if not args.report:
            thumb = src.copy()
            thumb.thumbnail((160, 160), Image.Resampling.LANCZOS)
            sheet.paste(thumb, (8, 20))
            draw.text((8, 185), "source", fill=(160, 160, 160, 255))

        # Нарезки
        y0 = 20
        for gi, (ri, rel) in enumerate(CUTS):
            path = ROOT / "assets" / rel
            col = gi % n_cols
            rowi = gi // n_cols
            x = 180 + col * cell if rowi == 0 else 8 + col * cell
            y = y0 + rowi * (cell + 22)
            label = Path(rel).stem[:12]
            draw.text((x, y + GAME_SIZE + 2), label, fill=(170, 170, 170, 255))
            if path.exists() and not args.report:
                ic = Image.open(path).convert("RGBA")
                sheet.paste(ic, (x, y), ic)

        # Пустые чертежи рядом
        y_empty = y0 + 2 * (cell + 22) + 4
        draw.text((8, y_empty - 14), "empty blueprints:", fill=(210, 190, 120, 255))
        for i, rel in enumerate(BLUEPRINTS):
            path = ROOT / "assets" / rel.replace(".png", "_empty.png")
            x = 8 + i * cell
            if path.exists() and not args.report:
                ic = Image.open(path).convert("RGBA")
                sheet.paste(ic, (x, y_empty), ic)
                draw.text((x, y_empty + GAME_SIZE + 2), Path(rel).stem[:10],
                          fill=(170, 170, 170, 255))

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
