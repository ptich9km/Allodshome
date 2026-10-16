#!/usr/bin/env python3
"""Замер КАЖДОЙ фигуры в полосе: размер, содержимое, поля до края кадра.

Зачем. `preflight` меряет полосу целиком (фон, число фигур, зазоры, тень,
линия ног, толщина) и не отвечает на вопрос «а не срезана ли фигура краем
кадра» и «а не разложены ли 4 панели в две строки». Именно эти два класса
проходили зелёным:

  * полоса смерти орк-женщины `hero_die_oc2.png`: фигура #1 обрезана слева
    (поле L=0), фигура #4 обрезана справа (R=0), панели 2 и 3 слиплись
    (зазор 0);
  * полоса ходьбы `hero_walk_oc2.png`: 8 фигур в две строки вместо 4 в ряд;
  * `hero_die_nb5.png` и `hero_attack_nb6.png` при `preflight` дают ОДНУ
    компоненту во весь кадр, потому что фон не мажента, а розовый;
  * `extract_hero_nb.py:172` берёт `boxes[:expect]` - лишние компоненты
    отбрасываются молча, без предупреждения.

Замер идёт ТЕМ ЖЕ путём, что и нарезка в игру (`bg_ref` + `cut_mask` +
`row_band` из `extract_hero_nb.py`), а не через `magenta_mask`: на части
полос фон не мажента, и замер по маженте считает фон фигурой.

Правило проекта: свойство, на котором строится геймплей, нельзя утверждать
глазом. Здесь меряем bbox каждой компоненты, расстояние до каждого из
четырёх краёв кадра и число строк, на которые модель разложила панели.

Запуск:
    python tests/measure_strip_figures.py                  # все полосы героев
    python tests/measure_strip_figures.py --tag oc2        # один набор
    python tests/measure_strip_figures.py --files a.png b.png
    python tests/measure_strip_figures.py --monsters       # полосы зверей

Код возврата: 0 - все полосы целы, 1 - есть брак.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tests"))

from extract_hero_nb import bg_ref, cut_mask, row_band, components  # noqa: E402

# Минимальное поле от bbox фигуры до края кадра. Меньше - фигура упирается
# в край, то есть кадр срезан по нему (дефект 15.10 у обоих орков).
EDGE_MIN = 3
# Компонента шире этой доли ширины кадра - почти наверняка слипшиеся соседи.
WIDTH_FRAC_MAX = 0.85
# Компонента шире МЕДИАНЫ во столько раз - слипшаяся пара соседей. Этот порог
# ловит случай, которого не видит WIDTH_FRAC_MAX: полоса удара суккуба (16.10)
# дала три компоненты шириной 540, 1185 и 529 px на холсте 2528 — слипшаяся
# пара занимает 47% ширины кадра и порог 0.85 проходит, а медиана 540px
# отдаёт 1185/540 = 2.2.
MERGE_RATIO = 1.6
# Панели одной фазы обязаны стоять на одной линии ног (feet_tol у preflight).
FEET_TOL = 14
# «Лёжащая плашмя» фигура: во столько раз шире, чем выше. Порог из журнала
# 16.10, отделяет брак-сидение (1.57-1.67) от нормы (2.26-3.84).
LYING_RATIO = 2.0

HERO_PHASES = ("stand", "walk", "attack", "die")


def _alpha(path: Path) -> np.ndarray:
    """Продакшн-маска: фон снимается цветом угла, а не мажентой."""
    a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    return cut_mask(a, bg_ref(a))


def _rows(boxes: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int]]:
    """Сгруппировать компоненты в строки по вертикальным перекрытию -> [(y0,y1,n)]."""
    rows: list[tuple[int, int, int]] = []
    for y0, y1, _x0, _x1 in sorted(boxes):
        placed = False
        for i, (ry0, ry1, n) in enumerate(rows):
            if min(ry1, y1) - max(ry0, y0) > (ry1 - ry0) * 0.4:
                rows[i] = (min(ry0, y0), max(ry1, y1), n + 1)
                placed = True
                break
        if not placed:
            rows.append((y0, y1, 1))
    return sorted(rows)


def measure(path: Path, check_feet: bool = True) -> tuple[bool, list[str]]:
    lines: list[str] = []
    img = Image.open(path)
    W, H = img.size
    alpha = _alpha(path)

    strong = alpha > 0.5
    band_y0, band_y1 = row_band(strong)
    all_boxes = components(alpha)
    band_boxes = [b for b in all_boxes if band_y1 >= b[0] and band_y0 <= b[1]]

    lines.append(f"{path.name}  {W}x{H}  компонент всего {len(all_boxes)}, в выбранной полосе {len(band_boxes)}")

    if not band_boxes:
        lines.append("    БРАК: фигур не найдено")
        return False, lines

    ok = True
    rows = _rows(all_boxes)
    if len(rows) > 1:
        detail = ", ".join(f"y={y0}..{y1} ({n} шт)" for y0, y1, n in rows)
        lines.append(f"    БРАК: панели разложены в {len(rows)} строки, а не в один ряд: {detail}")
        lines.append("          В игру уедет только одна строка, остальные отброшены молча")
        ok = False

    if len(band_boxes) > 4:
        lines.append(f"    БРАК: в полосе {len(band_boxes)} панелей вместо 4 - лишние отброшены молча")
        ok = False

    widths = sorted(b[3] - b[2] + 1 for b in band_boxes)
    median_w = widths[len(widths) // 2] if widths else 0
    feet: list[int] = []
    for i, (y0, y1, x0, x1) in enumerate(band_boxes, start=1):
        w, h = x1 - x0 + 1, y1 - y0 + 1
        pad_l, pad_t = x0, y0
        pad_r, pad_b = W - 1 - x1, H - 1 - y1
        edge = min(pad_l, pad_t, pad_r, pad_b)
        ratio = w / h if h else 0.0
        feet.append(y1)

        flags: list[str] = []
        if edge < EDGE_MIN:
            flags.append(f"ОБРЕЗАНА КРАЕМ (поля L{pad_l} T{pad_t} R{pad_r} B{pad_b})")
        if w >= W * WIDTH_FRAC_MAX:
            flags.append("ШИРИНА ПОЧТИ ВО ВСЮ ПОЛОСУ (слипшиеся соседи)")
        if median_w and w >= median_w * MERGE_RATIO:
            flags.append(f"ШИРИНА В {w / median_w:.1f} РАЗ БОЛЬШЕ МЕДИАНЫ {median_w} "
                         f"(это две слипшиеся фигуры)")
        if h >= H * 0.98:
            flags.append("ВЫСОТА ВО ВСЮ ПОЛОСУ (обрезана сверху/снизу)")

        mark = "БРАК" if flags else "ок  "
        if flags:
            ok = False
        lines.append(
            f"    {mark} #{i} {w:>4}x{h:<5} w/h={ratio:4.2f} "
            f"поля L{pad_l:<5} T{pad_t:<5} R{pad_r:<5} B{pad_b:<5}"
            + ("  <- " + "; ".join(flags) if flags else "")
        )

    if len(feet) > 1:
        spread = max(feet) - min(feet)
        if not check_feet:
            # Фаза парения: панели стоят на РАЗНОЙ высоте по замыслу («4
            # clearly different body heights»), поэтому общая линия ног тут не
            # дефект, а требование промта. Тот же класс, что толщина на
            # компактных позах: метрика меряет не главное свойство.
            lines.append(f"    ноги: разброс {spread}px - фаза парения, проверка отключена")
        else:
            mark = "ок  " if spread <= FEET_TOL else "БРАК"
            if spread > FEET_TOL:
                ok = False
                lines.append(f"    {mark} ЛИНИЯ НОГ: разброс {spread}px по {len(feet)} панелям (норма <= {FEET_TOL})")
            else:
                lines.append(f"    {mark} ЛИНИЯ НОГ: разброс {spread}px")

    lying = [i for i, b in enumerate(band_boxes, 1)
             if (b[1] - b[0]) and (b[3] - b[2] + 1) / (b[1] - b[0] + 1) >= LYING_RATIO]
    if lying:
        lines.append(f"    подсказка: панели {lying} лежат плашмя (w/h >= {LYING_RATIO}) - для фазы смерти это норма")

    if len(band_boxes) > 1:
        order = sorted(band_boxes, key=lambda b: b[2])
        gaps = [b[2] - a[3] - 1 for a, b in zip(order, order[1:])]
        mark = "ок  " if min(gaps) > 0 else "БРАК"
        if min(gaps) <= 0:
            ok = False
        lines.append(f"    {mark} ЗАЗОРЫ: {gaps}  (минимум {min(gaps)}; <=0 = панели слиплись)")
    return ok, lines


def main() -> int:
    global EDGE_MIN
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="", help="тег полос героя: nb5 | nb6 | oc1 | oc2")
    ap.add_argument("--files", nargs="*", default=[], help="конкретные PNG для замера")
    ap.add_argument("--monsters", action="store_true", help="полосы зверей из import/Monsters")
    ap.add_argument("--edge-min", type=int, default=EDGE_MIN, help="минимальное поле до края кадра")
    ap.add_argument("--flight", action="store_true",
                    help="полоса фазы парения: панели стоят на разной высоте по "
                         "замыслу, проверка общей линии ног отключается")
    args = ap.parse_args()
    EDGE_MIN = args.edge_min

    targets: list[Path] = []
    if args.files:
        targets = [Path(f) for f in args.files]
    elif args.tag:
        targets = [REPO / "import" / "Player" / f"hero_{p}_{args.tag}.png" for p in HERO_PHASES]
        targets.append(REPO / "import" / "Player" / f"hero_die_{args.tag}_v2.png")
    elif args.monsters:
        for entry in sorted((REPO / "assets" / "units" / "monsters").glob("*/_entry.json")):
            for src in sorted((REPO / "import" / "Monsters").glob(f"{entry.parent.name}_*.png")):
                targets.append(src)
    else:
        for tag in ("nb5", "nb6", "oc1", "oc2"):
            targets += [REPO / "import" / "Player" / f"hero_{p}_{tag}.png" for p in HERO_PHASES]
        targets.append(REPO / "import" / "Player" / "hero_die_oc1_v2.png")

    existing = [t for t in targets if t.exists()]
    if not existing:
        print("полосы не найдены")
        return 1

    bad = 0
    for t in existing:
        ok, lines = measure(t, check_feet=not args.flight)
        print("\n".join(lines))
        print()
        if not ok:
            bad += 1

    print(f"ИТОГ: полос с браком {bad} из {len(existing)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
