#!/usr/bin/env python3
"""Собрать сетку фигур в полосе: сколько рядов и сколько колонок.

Модель за одну сессию отдала три раскладки на одну и ту же просьбу «4 фигуры
в один ряд»: 4x1 (seedream), 4x2 (nano-banana стойка) и 2x2 (nano-banana
бег). Нарезчик раньше умел брать один ряд и резать его на колонки, то есть на
2x2 терял половину фаз. Поэтому сначала смотрим, что приходит на самом деле.

Запуск:
  python tests/strip_layout.py import/Monsters/*.png
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def magenta(a):
    return (a[..., 1] < 110) & (a[..., 0] > 140) & (a[..., 2] > 140) \
        & ((a[..., 0] - a[..., 1]) > 50)


def runs_of(flag, min_count):
    out, start = [], -1
    for i, v in enumerate(flag):
        if v and start < 0:
            start = i
        elif not v and start >= 0:
            out.append((start, i - 1))
            start = -1
    if start >= 0:
        out.append((start, len(flag) - 1))
    return out


def layout(path: Path):
    a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    bg = magenta(a)
    if bg.mean() < 0.2:
        ref = np.median(np.concatenate([
            a[:24, :24].reshape(-1, 3), a[:24, -24:].reshape(-1, 3),
            a[-24:, :24].reshape(-1, 3), a[-24:, -24:].reshape(-1, 3)]), axis=0)
        bg = np.sqrt(((a - ref) ** 2).sum(axis=2)) < 45
    fg = ~bg
    rows = runs_of(fg.sum(axis=1) >= 5, 0)
    cols = runs_of(fg.sum(axis=0) >= 5, 0)
    # сколько колонок в каждом ряду
    per_row = []
    for y0, y1 in rows:
        sub = fg[y0:y1 + 1]
        per_row.append(len(runs_of(sub.sum(axis=0) >= 3, 0)))
    return len(rows), per_row, len(cols), bg.mean()


def main() -> int:
    files = sorted(Path(p) for p in sys.argv[1:])
    print(f"{'файл':<34} {'рядов':>6} {'колонок по рядам':>18} {'фон':>6}")
    for f in files:
        try:
            nrows, per_row, ncols, bgfrac = layout(f)
            print(f"{f.name:<34} {nrows:>6} {str(per_row):>18} {bgfrac * 100:>5.0f}%")
        except Exception as e:  # noqa: BLE001
            print(f"{f.name:<34} ОШИБКА {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())