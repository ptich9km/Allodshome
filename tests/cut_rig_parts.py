#!/usr/bin/env python3
"""Нарезка и паддинг частей тела для 2D-рига из сгенерированных PNG.

Контракт (skill 2d-cutout-art):
- Сустав части = ТОЧНЫЙ центр холста (centered=true, offset=0)
- Обе стороны чётные
- Магентный фон снимается порогом по одному каналу

Пивоты (из референса godot-pixel-cutout-rig):
- torso: НИЗ (таз), торс растёт вверх
- head: НИЗ (шея), голова растёт вверх
- arm: ВЕРХ (плечо), рука свисает вниз
- forearm: ВЕРХ (локоть), предплечье свисает вниз
- thigh: ВЕРХ (бедро), нога свисает вниз
- shin: ВЕРХ (колено), голень свисает вниз

Запуск:
    python tests/cut_rig_parts.py
    python tests/cut_rig_parts.py --check
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "import" / "_rig_parts"
OUT = REPO / "assets" / "units" / "rig" / "rig_atlas_v2" / "parts"

# Целевые размеры по высоте
TARGET_H = {
    "head": 14,
    "torso": 24,
    "arm": 14,
    "forearm": 14,
    "thigh": 16,
    "shin": 16,
}

# Пивот: "top" = сустав сверху (конечности), "bottom" = сустав снизу (торс/голова)
PIVOT_Y = {
    "head": "bottom",
    "torso": "bottom",
    "arm": "top",
    "forearm": "top",
    "thigh": "top",
    "shin": "top",
}

# Имя файла -> имя для рига
PART_NAMES = {
    "arm": "upper_arm",
    "forearm": "forearm",
    "head": "head",
    "shin": "shin",
    "thigh": "thigh",
    "torso": "torso",
}

MAG_RG = 45
MAG_BG = 40


def is_magenta(arr: np.ndarray) -> np.ndarray:
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    return ((r - g) > MAG_RG) & ((b - g) > MAG_BG)


def cut_and_pad(src: Path, out: Path, part: str) -> bool:
    img = Image.open(src).convert("RGBA")
    arr = np.array(img)
    mag = is_magenta(arr)
    arr[:, :, 3] = np.where(mag, 0, arr[:, :, 3])

    alpha = arr[:, :, 3]
    content = alpha > 128
    if not content.any():
        print(f"  FAIL {src.name}: нет контента")
        return False
    rows = np.where(content.any(axis=1))[0]
    cols = np.where(content.any(axis=0))[0]
    y0, y1 = int(rows.min()), int(rows.max()) + 1
    x0, x1 = int(cols.min()), int(cols.max()) + 1
    cropped = arr[y0:y1, x0:x1]
    ch, cw = cropped.shape[:2]

    target_h = TARGET_H[part]
    scale = target_h / ch
    new_w = max(2, int(round(cw * scale)))
    new_h = target_h
    resized = Image.fromarray(cropped, "RGBA").resize((new_w, new_h), Image.NEAREST)
    rarr = np.array(resized)
    rh, rw = rarr.shape[:2]

    # Пивот = центр холста (centered=true, offset=0).
    # Сустав должен совпасть с центром, поэтому контент размещается
    # в ПОЛОВИНЕ холста, противоположной суставу:
    # - "top" (конечности): сустав сверху → контент в НИЖНЕЙ половине
    # - "bottom" (торс/голова): сустав снизу → контент в ВЕРХНЕЙ половине
    nh = rh * 2
    nh += nh % 2
    nw = rw + (rw % 2)

    canvas = np.zeros((nh, nw, 4), dtype=np.uint8)
    ox = (nw - rw) // 2
    if PIVOT_Y[part] == "top":
        oy = nh // 2  # контент от центра вниз
    else:
        oy = 0  # контент от верха до центра
    canvas[oy:oy+rh, ox:ox+rw] = rarr

    Image.fromarray(canvas, "RGBA").save(out)
    pivot = (nw // 2, nh // 2)
    print(f"  {part}: {nw}x{nh} pivot={pivot} (joint={PIVOT_Y[part]})")
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)

    if args.check:
        bad = 0
        for f in sorted(OUT.glob("*.png")):
            img = Image.open(f)
            w, h = img.size
            if w % 2 or h % 2:
                print(f"  FAIL {f.name}: нечётный {w}x{h}")
                bad += 1
        print(f"Check: {'OK' if bad == 0 else f'{bad} проблем'}")
        return

    # Лучший вариант по размеру файла
    parts: dict[str, Path] = {}
    for f in sorted(SRC.glob("*.png")):
        base = f.stem.rsplit("_v", 1)[0]
        if base in TARGET_H and (base not in parts or f.stat().st_size > parts[base].stat().st_size):
            parts[base] = f

    for part, src_file in sorted(parts.items()):
        rig_name = PART_NAMES.get(part, part)
        cut_and_pad(src_file, OUT / f"{rig_name}.png", part)

    # Диски
    for name, dia in [("disc_lg", 8), ("disc_sm", 5)]:
        d = dia + (dia % 2)
        disc = Image.new("RGBA", (d, d), (0, 0, 0, 0))
        ImageDraw.Draw(disc).ellipse([0, 0, d-1, d-1], fill=(188, 176, 150, 255))
        disc.save(OUT / f"{name}.png")
        print(f"  {name}: {d}x{d}")

    print(f"\nИтого -> {OUT}")


if __name__ == "__main__":
    main()
