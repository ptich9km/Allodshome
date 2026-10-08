"""Сравнение «до/после» по габариту ореола.

До = C:/Temp/opencode/portraits_before, После = assets/hero_portraits.
Метрика: сколько СВЕТЛЫХ полупрозрачных пикселей осталось в outermost-кольце
сглаживания (именно они читаются как белые точки на тёмной панели).
Плюс контроль: сколько НЕПРОЗРАЧНЫХ пикселей потеряно (силуэт не должен
пострадать).
"""
import os
import sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AFTER = os.path.join(ROOT, "assets", "hero_portraits")
BEFORE = sys.argv[1] if len(sys.argv) > 1 else \
    r"C:\Temp\opencode\portraits_before"


def near_transparent(al, thr=8):
    tr = al <= thr
    p = np.pad(tr, 1, constant_values=True)
    nb = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
          | p[:-2, :-2] | p[2:, 2:] | p[2:, :-2] | p[:-2, 2:])
    return nb


def stats(path, light_l=150):
    a = np.array(Image.open(path).convert("RGBA")).astype(np.int16)
    al = a[..., 3]
    lum = a[..., :3].max(axis=2)
    ring = (al > 8) & (al < 247) & near_transparent(al)
    return {
        "opaque": int((al >= 247).sum()),
        "ring": int(ring.sum()),
        "ring_light": int((ring & (lum > light_l)).sum()),
        "inside_light": int(((al >= 247) & (lum > light_l)).sum()),
        "opaque_all": int((al > 0).sum()),
    }


def main():
    names = sorted(n for n in os.listdir(AFTER)
                   if n.endswith(".png") and not n.startswith("_"))
    print("%-20s %14s %14s   %s" % ("файл", "ореол ДО", "ореол ПОСЛЕ", "силуэт ДО->ПОСЛЕ"))
    tb = ta = 0
    ob = oa = 0
    for n in names:
        pb = os.path.join(BEFORE, n)
        pa = os.path.join(AFTER, n)
        if not os.path.exists(pb):
            continue
        sb = stats(pb)
        sa = stats(pa)
        tb += sb["ring_light"]
        ta += sa["ring_light"]
        ob += sb["opaque"]
        oa += sa["opaque"]
        print("%-20s %14d %14d   %6d -> %6d"
              % (n, sb["ring_light"], sa["ring_light"],
                 sb["opaque"], sa["opaque"]))
    print("\nИТОГО светлый ореол: %d -> %d  (снято %d, %.0f%%)"
          % (tb, ta, tb - ta, 100.0 * (tb - ta) / max(1, tb)))
    print("НЕПРОЗРАЧНЫЙ силуэт:  %d -> %d  (потеряно %d, %.2f%%)"
          % (ob, oa, ob - oa, 100.0 * (ob - oa) / max(1, ob)))


if __name__ == "__main__":
    main()