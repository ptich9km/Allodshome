#!/usr/bin/env python3
"""Генератор ПАЛОЧНЫХ частей для пилота 2D-рига (rigged_anim.gd).

ЗАЧЕМ ИМЕННО ПАЛОЧКИ. Референс godot-pixel-cutout-rig (MIT) рекомендует ровно
это: «Build and test your entire animation set on them first, then drop your real
art onto the IDENTICAL pivots later — zero re-animation, because the clips key
bone rotation, not the art». Клипы ключат вращение костей, поэтому арт можно
подменить позже без переанимации.

Части намеренно РАСТРОВЫЕ PNG, а не вектор: поворот спрайта под nearest-фильтром
даёт настоящее мерцание пикселей, и артефакт виден там, где его не показал бы
заливной вектор. Когда риг читается чисто, подмена частей — чистая работа с
артом.

КОНВЕНЦИЯ ПИВОТА (главное правило, из-за которого пропадает вся позиционная
арифметика): сустав части лежит в ТОЧНОМ пиксельном центре холста. Тогда в
Godot достаточно `Sprite2D.centered = true`, `offset = (0,0)`, `position = (0,0)`
под костью — начало кости совпадает с суставом. Обе стороны холста ЧЁТНЫЕ, иначе
`size/2` попадает в полупиксель: под nearest мылится и рвёт швы.

МАСШТАБ. Референс рассчитан на фигуру ~112 px. У нас юниты ~52-60 px, поэтому
таблица пересчитана: рост фигуры = L_torso + head_dia + L_thigh + L_shin = 56.
Те же пропорции, другой масштаб — иначе пилот судился бы не по тому размеру,
по которому судится игра.

Происхождение: адаптация tools/make_stick_parts.py из
https://github.com/haingt-dev/godot-pixel-cutout-rig (MIT, (c) 2026 haingt.dev).
Изменены таблица размеров под наш масштаб и вывод.

Запуск:
    python tests/gen_rig_parts.py --out assets/units/rig/rig_pilot/parts
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

FILL = (162, 162, 168, 255)     # сердцевина: значение в середине, читаются и тени, и свет
OUTLINE = (54, 54, 60, 255)     # контур 1 px, запечён в часть (дисциплина обводки)
DISC = (188, 176, 150, 255)     # тёплая «пробка» шарнира — читается как шар
PAD = 2                         # прозрачный запас по краям (запас на недобор)

# Целевой рост фигуры в пикселях. Рост = L_torso + head_dia + L_thigh + L_shin.
FIGURE_HEIGHT = 56
L_TORSO = 18
L_UARM = 9
L_THIGH = 14
L_SHIN = 14
HEAD_DIA = 10


def _capsule(w: int, length: int, direction: str) -> Image.Image:
    """Капсула шириной `w`, от сустава на `length`. Сустав — в центре холста.

    direction='down' -> непрозрачное тело НИЖЕ сустава (руки, ноги);
    'up' -> ВЫШЕ (торс). Округлая крышка со стороны сустава — та самая форма,
    которая при повороте не вскрывает щель в шарнире.
    """
    cw = w + 2 * PAD
    cw += cw % 2                              # чётная ширина -> pivot x = cw//2 целый
    ch = 2 * length + 2 * PAD                 # уже чётная
    img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cw // 2
    piv_y = ch // 2
    r = w // 2
    if direction == "down":
        top, bot = piv_y, piv_y + length
    else:
        top, bot = piv_y - length, piv_y
    d.rounded_rectangle([cx - r, top - r, cx + r, bot + r], radius=r,
                        fill=FILL, outline=OUTLINE, width=1)
    return img


def _circle(dia: int, pivot: str, nub: bool = False) -> Image.Image:
    """Круг диаметром `dia`; pivot='bottom' -> круг НАД центром (голова на шее).
    Необязательный бугорок на +x помечает, куда смотрит профиль."""
    r = dia // 2
    side_pad = PAD + (3 if nub else 0)       # симметричный запас, бугорок не сдвинет центр
    cw = dia + 2 * side_pad
    cw += cw % 2
    ch = 2 * dia + 2 * PAD
    img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cw // 2
    piv_y = ch // 2
    cy = piv_y - r if pivot == "bottom" else piv_y
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=FILL, outline=OUTLINE, width=1)
    if nub:
        d.ellipse([cx + r - 2, cy - 2, cx + r + 2, cy + 2], fill=FILL, outline=OUTLINE, width=1)
    return img


def _disc(r: int) -> Image.Image:
    """Шарнирная «пробка» диаметром 2r; сустав в центре. Маскирует шов."""
    s = 2 * r + 2 * PAD
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s // 2
    d.ellipse([c - r, c - r, c + r, c + r], fill=DISC, outline=OUTLINE, width=1)
    return img


# Таблица под НАШ масштаб (референс: 16/38, 18, 7/24, 6/24, 9/28, 8/28).
PARTS = {
    "torso": _capsule(9, L_TORSO, "up"),      # сустав = таз (низ), торс растёт вверх
    "head": _circle(HEAD_DIA, "bottom", nub=True),  # сустав = шея, голова + бугорок носа
    "upper_arm": _capsule(4, L_UARM, "down"),  # сустав = плечо (верх)
    "forearm": _capsule(3, L_UARM, "down"),    # сустав = локоть; дальняя крышка = кисть
    "thigh": _capsule(5, L_THIGH, "down"),     # сувают = бедро (верх)
    "shin": _capsule(4, L_SHIN, "down"),       # сустав = колено; дальняя крышка = стопа
    "disc_lg": _disc(3),                       # таз / плечо
    "disc_sm": _disc(2),                       # колено / локоть
}


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate stick parts for the 2D cutout rig pilot.")
    ap.add_argument("--out", type=Path, required=True, help="output parts directory")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    problems: list[str] = []
    for name, img in PARTS.items():
        # Конвенция проверяется ЗДЕСЬ, а не на глаз: сустав обязан лечь в
        # точный центр холста, иначе риг разъедется и швы поедут.
        if img.width % 2 or img.height % 2:
            problems.append(f"{name}: нечётный холст {img.width}x{img.height}")
        alpha = img.getchannel("A")
        bbox = alpha.getbbox()
        if bbox is None:
            problems.append(f"{name}: часть пустая")
        p = args.out / f"{name}.png"
        img.save(p)
        print(f"[saved] {p.name:12s} {img.width}x{img.height}  pivot=({img.width // 2},{img.height // 2})")

    total = L_TORSO + HEAD_DIA + L_THIGH + L_SHIN
    print(f"[done] {len(PARTS)} parts -> {args.out}")
    print(f"[geometry] L_torso={L_TORSO} head={HEAD_DIA} L_thigh={L_THIGH} "
          f"L_shin={L_SHIN} -> figure height {total} (цель {FIGURE_HEIGHT})")
    if total != FIGURE_HEIGHT:
        problems.append(f"рост фигуры {total} != заявленному {FIGURE_HEIGHT}")

    if problems:
        for pr in problems:
            print("[FAIL] " + pr)
        raise SystemExit(1)
    print("[check] все части чётные, суставы в центре, рост сходится")


if __name__ == "__main__":
    main()