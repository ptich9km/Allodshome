#!/usr/bin/env python3
"""Контактный лист нарезанных иконок С ПОДПИСЯМИ имён (проверка соответствия).

Игрок и агент сверяют: подпись должна соответствовать нарисованному.
Выход: import/items_atlas/_sliced/_contact_labeled.png
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent / "import" / "items_atlas" / "_sliced"
OUT = ROOT / "_contact_labeled.png"

CELL = 84
LABEL_H = 26
COLS = 6


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    files = []
    for metal in ("bronze", "iron", "gold"):
        for sub in ("weapons", "armor"):
            files += sorted((ROOT / metal / sub).glob("*.png"))
    try:
        font = ImageFont.truetype("consola.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    rows = (len(files) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * CELL, rows * (CELL + LABEL_H)), (40, 40, 46))
    draw = ImageDraw.Draw(sheet)
    for i, p in enumerate(files):
        im = Image.open(p).convert("RGBA")
        cx, cy = (i % COLS) * CELL, (i // COLS) * (CELL + LABEL_H)
        sheet.paste(im, (cx + 6, cy + 2), im)
        # подпись: имя без суффикса тира (он и так виден по цвету)
        name = p.stem.rsplit("_", 1)[0]
        draw.text((cx + 4, cy + CELL - LABEL_H + 8), name[:13],
                  fill=(255, 220, 120), font=font)
    sheet.save(OUT)
    print("ЛИСТ С ПОДПИСЯМИ: %s (%d иконок)" % (OUT, len(files)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
