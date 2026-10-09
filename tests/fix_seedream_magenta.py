"""Почистить остаточную магенту в уже нарезанных seedream-ассетах.

Исходников (import/_stage*) в репозитории нет, поэтому генераторы запустить
нельзя. Применяем к готовым PNG то же правило, что теперь в скриптах:
мадженты в арте не бывает, значит её можно резать по цвету, без связности.

Меряем потерю силуэта по каждому файлу и печатаем отчёт: правило «съедено
хорошее» тут невозможно проверить иначе.
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

PATTERNS = [
    "assets/structures/**/house-*.png",
    "assets/map-objects/**/*.png",
]


def dilate(mask, r):
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r:
                continue
            s = np.zeros_like(mask)
            y0, y1 = max(0, dy), min(h, h + dy)
            x0, x1 = max(0, dx), min(w, w + dx)
            s[y0:y1, x0:x1] = mask[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
            out |= s
    return out


def clean(rgba, report):
    a = rgba[:, :, 3].astype(np.int16)
    r = rgba[:, :, 0].astype(np.int16)
    g = rgba[:, :, 1].astype(np.int16)
    b = rgba[:, :, 2].astype(np.int16)
    before = int((a > 0).sum())

    # 1) Ядро магенты — чистый фон, попавший внутрь силуэта.
    #    Порог тот же, что в генераторах (g<90, r-g>90, b-g>70).
    core = (g < 90) & ((r - g) > 90) & ((b - g) > 70) & (a > 0)
    a[core] = 0

    # 2) Остаточная кайма — смесь магенты с артом на границе фона. Отличает
    #    ОТТЕНОК, а не яркость: у магенты r-g И b-g высокие одновременно,
    #    у арта (листва, дерево, черепица) — только один из двух, либо
    #    b-g отрицательный. Замер в 4 файлах:
    #      магента: r-g = 73..81, b-g = 51..76
    #      арт:     r-g =  3..24, b-g = -17..8
    #    Первый вариант теста был по хромам и яркости (g<150, r-g>35) и сжёг
    #    9097 px, включая файлы, где ядра магенты было 10 px при потере 604 px,
    #    то есть ел честные тёплые тона.
    hue = (a > 0) & ((r - g) > 45) & ((b - g) > 40)
    a[hue] = 0

    after = int((a > 0).sum())
    out = rgba.copy()
    out[:, :, 3] = a.astype(np.uint8)
    if report is not None:
        report["before"] = before
        report["after"] = after
        report["core"] = int(core.sum())
        report["hue"] = int(hue.sum())
    return out


def main():
    files = []
    for p in PATTERNS:
        files.extend(glob.glob(p, recursive=True))
    files = [p for p in sorted(set(files)) if p.lower().endswith(".png")]
    changed = 0
    total_before = 0
    total_after = 0
    rows = []
    for p in files:
        im = Image.open(p)
        if im.mode != "RGBA":
            continue
        rgba = np.asarray(im.convert("RGBA"))
        rep = {}
        out = clean(rgba, rep)
        if out[:, :, 3].sum() == 0:
            print("ПРОПУЩЕН (всё стало прозрачным): %s" % p)
            continue
        if rep["core"] == 0 and rep["hue"] == 0:
            continue
        Image.fromarray(out, "RGBA").save(p)
        changed += 1
        total_before += rep["before"]
        total_after += rep["after"]
        lost = rep["before"] - rep["after"]
        rows.append((lost, rep["core"], rep["before"], p))
    rows.sort(reverse=True)
    print("изменено файлов: %d" % changed)
    print("непрозрачных: %d -> %d (минус %d px, %.2f%%)"
          % (total_before, total_after, total_before - total_after,
             100.0 * (total_before - total_after) / max(1, total_before)))
    print("\nнаибольшие потери:")
    for lost, core, before, p in rows[:15]:
        print("   -%4d px из %5d (ядро магенты %4d)  %s"
              % (lost, before, core, p))


if __name__ == "__main__":
    main()