#!/usr/bin/env python3
"""Генерация полосы анимации + ПРЕДПОЛЁТНАЯ проверка сырого PNG.

КОНВЕЙЕР (повторяемый, 4 шага):
  1. ПРАВИМ ПРОМТ, а не режем картинку. Проверка ниже меряет толщину фигуры,
     и модель обязана выдать её сама.
  2. Генерируем ОДНУ полосу, обычно `stand` — самая дешёвая проверка ракурса
     и телосложения, ~$0.06. Не все четыре полосы вслепую: покрытие ~$0.24.
  3. Смотрим превью и СРАЗУ гоняем preflight по тому же файлу:
       python tests/gen_hero_strip.py stand --check import/Player/hero_stand_nb5.png --panels 4
     Префлайт печатает толщину по каждой фигуре. Норма >= 0.36, городские NPC
     дают 0.48-0.59. Если ниже — ракурс или телосложение не те, правь промт.
  4. Только когда полоса прошла, генерируем остальные и собираем набор:
       python tests/extract_hero_nb.py

  Модель и цена: google/gemini-nano-banana-2.1, ~$0.054-0.061 за 1536x1024.
  Seedream дешевле, но теряет персонажа между вызовами; Flux блокируется
  модерацией. Подробности замеров — в AGENTS.md, журнал от 14.10.

Проблема, из-за которой полосы не резались (14.10): seedream рисует мягкую
тень ПОД фигурами, тень идёт полосой через весь кадр и склеивает соседей в
одну компоненту — вырезка физически не может их разделить. Плюс фигуры жмутся
друг к другу. Поэтому:
  - промт запрещает тень, пол и линию пола ЖЁСТКО;
  - после генерации кадр проверяется замером ПРОВЕРКА ИДЁТ ДО ПОКАЗА ЧЕЛОВЕКУ:
    тень под фигурами, число фигур, зазоры, линия ног, однотонность фона,
    ТОЛЩИНА ФИГУРЫ.

Запуск:
  python tests/gen_hero_strip.py stand --panels 4
  python tests/gen_hero_strip.py stand --check import/Player/hero_stand_v1.png --panels 4
"""
import argparse
import re
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "import" / "Player"
MODEL = "google/gemini-nano-banana-2.1"
SIZE = "1536x1024"

CHARACTER = """ONE single character repeated in every panel: a broad-shouldered, sturdy adult
human warrior, light skin, short brown hair, short trimmed brown beard, no cape,
no helmet. He wears a rounded polished silver steel breastplate, small silver
shoulder pads, an olive-green knee-length tunic, a wide brown leather belt, brown
leather gauntlets, dark grey trousers and brown leather knee-high boots."""

# Женщина-войн. Снаряжение и палитра РОВНО мужские — набор должен читаться как
# та же армия, а не другой game (урок 14.10: «стиль не совпадает» оказалось
# ложной жалобой, но единый стиль всё равно дешевле проверять). Отличия только
# очевидные: длинные волосы, никакой бороды, женское телосложение.
#
# Толщина. Женская фигура по умолчанию выходит уже мужской, а норма preflight
# одна и та же (>= 0.36) — иначе она станет новой «жердью». Поэтому ширина
# задана явно и теми же словами, что и у мужчины, плюс отдельно запрещена
# слишком худая талия: у боина с мечом замеры были 0.48-0.59.
CHARACTER_F = """ONE single character repeated in every panel: a broad-shouldered, sturdy adult
human warrior WOMAN, light skin, long brown hair hanging loose over her shoulders
and down her back, no beard, no cape, no helmet. She wears the same rounded
polished silver steel breastplate, small silver shoulder pads, an olive-green
knee-length tunic, a wide brown leather belt, brown leather gauntlets, dark grey
trousers and brown leather knee-high boots."""

# Ракурс. Замер 14.10: «SIDE VIEW facing RIGHT» дал силуэт 0.24 ширины к высоте —
# фигура вчетверо ниже, чем широка, «жердь». Это не ошибка размера: профиль по
# определению самый узкий ракурс, видно только бок, оба плеча не читаются.
# Городские NPC дают 0.48-0.59, потому что развёрнуты к камере. Просим три
# четверти: оба плеча видны, но лицо, грудь и носки всё ещё смотрят вправо —
# иначе зеркало влево/вправо перестанет читаться в бою.
VIEW = ("THREE-QUARTER VIEW: the whole body is turned about 30 degrees towards the "
        "viewer, so BOTH shoulders, BOTH arms and the full width of the chest are "
        "visible, and the figure looks broad across its silhouette. He still clearly "
        "reads as facing RIGHT: the face, the chest and the toes point to the right "
        "and NOT towards the viewer.")

VIEW_F = ("THREE-QUARTER VIEW: the whole body is turned about 30 degrees towards the "
          "viewer, so BOTH shoulders, BOTH arms and the full width of the chest are "
          "visible, and the figure looks broad across its silhouette. She still "
          "clearly reads as facing RIGHT: the face, the chest and the toes point to "
          "the right and NOT towards the viewer.")

# Телосложение. Отдельным блоком, потому что слово «lean» в описании персонажа
# модель понимает буквально и рисует именно жердь — это была первая причина
# тонкой фигуры, ракурс её только усиливал.
PROPORTIONS = """BODY PROPORTIONS - this matters as much as the pose, the figure must NOT be a stick:
- broad-shouldered and solid, thick torso, sturdy heavy-set build
- the SHOULDERS are the widest part of his silhouette, clearly broader than his hips
- because both arms are visible from this angle, the body outline is roughly one
  third as wide as the figure is tall
- thick thighs and calves, solid boots, the torso is a filled shape with no gaps
- do NOT draw him slim, lean, thin, gaunt, lanky or stick-like"""

PROPORTIONS_F = """BODY PROPORTIONS - this matters as much as the pose, the figure must NOT be a stick:
- broad-shouldered and solid, thick torso, sturdy athletic build
- the SHOULDERS are the widest part of her silhouette, clearly broader than her hips
- the hips are NOT narrow: a slim waist under the breastplate, but the hip and
  thigh area stays as wide as the male figure's, this is an armoured soldier
- because both arms are visible from this angle, the body outline is roughly one
  third as wide as the figure is tall
- thick thighs and calves, solid boots, the torso is a filled shape with no gaps
- do NOT draw her slim, skinny, thin, gaunt, lanky, scrawny or stick-like"""

ANIMS = {
    "walk": """WALKING CYCLE, 8 panels left to right in one horizontal row.
The legs alternate between a WIDE stride and a NARROW passing pose:
panels 1 and 5 are the wide stride with the legs far apart,
panels 3 and 7 are the narrow passing pose with the feet almost touching.
All 8 panels are DIFFERENT leg positions of one calm walking step.
He is drawn walking, torso upright, arms swinging
gently and kept close to the body. He does not run and does not lunge.""",

    "stand": """IDLE STANCE, 8 panels left to right in one horizontal row. He stands still,
feet hip width, arms relaxed at his sides, only a subtle breathing difference
between panels.""",

    "attack": """FIST PUNCH, 8 panels left to right in one horizontal row.
Panel 1 guard stance with both fists up, panel 2 right fist cocked back,
panel 3 driving forward, panel 4 arm fully extended straight ahead,
panel 5 still extended, panel 6 retracting, panel 7 guard returning,
panel 8 guard stance, feet planted, no weapon.""",

    "die": """DEATH BY A BLOW TO THE CHEST, 8 panels left to right in one horizontal row.
Panel 1 standing upright with both arms flung wide open to the sides,
panel 2 sinking down with knees bent and arms still wide,
panel 3 sitting on the ground leaning back on his hands,
panel 4 falling backwards, panel 5 lying on his back on the ground,
panels 6, 7, 8 lying flat on his back face up, still. He NEVER lies face down.
""",
}

LAYOUT4 = """LAYOUT RULES, these matter more than the drawing:
- exactly 4 separate figures in a single horizontal row, evenly spaced
- HUGE empty gaps between the figures: at least 150 pixels of completely empty
  background between the right edge of one figure and the left edge of the next
- every figure the same size, feet on the same horizontal line, full body from
  head to boots inside its own space, nothing cropped

ABSOLUTELY NO GROUND SHADOW, no cast shadow, no dark blur under the boots, no
floor, no ground plane, no horizontal line, no surface, no reflection. The area
under and around every figure must be the same flat background as the rest of
the image.

Background: one single flat vivid magenta (255, 0, 255), perfectly uniform.
EXCLUDE: text, letters, numbers, captions, grid lines, borders, weapons,
scenery, signature, watermark, duplicate figures."""

# 4 панели: 8 фигур на 1536px физически не помещаются — фигуры ~190px шириной
# наезжают друг на друга, и резать полосу нечем (замер 14.10: в промежутках
# удара 15-72px чужой руки, в промежутках смерти до 234px).
ANIMS4 = {
    "stand": """AN IDLE STANCE, 4 panels left to right in one row.
Panel 1: standing still, feet about hip width apart, both arms hanging relaxed
at his sides, shoulders level, calm neutral face.
Panels 2, 3 and 4: the exact same standing pose with only a tiny breathing
difference in the rise of his chest. He does not move his feet at all.
""",

    "die": """A FALL TO THE GROUND, 4 panels left to right in one row.
Panel 1: standing upright, both arms flung wide open to the sides.
Panel 2: sinking down, knees bent, body lowering towards the ground.
Panel 3: sitting on the ground, leaning back on his hands, legs out.
Panel 4: lying flat on his back on the ground, face and chest pointing up.
He NEVER lies face down. """,

    "attack": """A FIST PUNCH, 4 panels left to right in one row.
Panel 1: guard stance, both fists up in front of his chest.
Panel 2: right fist cocked back beside his shoulder.
Panel 3: right arm driving forward, fist half way out.
Panel 4: right arm fully extended straight ahead at shoulder height, fist closed.
Feet planted, no weapon. """,

    "walk": """A WALKING CYCLE, 4 panels left to right in one row, calm even walking pace.
Panel 1 CONTACT: the front heel just touched the ground, the back leg is stretched
far behind, legs at their widest apart, body upright, spine perfectly straight.
Panel 2 DOWN: his weight sinks onto the front leg, his body is at its lowest point
of the step, the back leg is still stretched behind pushing off. His SPINE STAYS
PERFECTLY UPRIGHT and straight - he does NOT crouch, does NOT bend forward at the
waist, does NOT squat and is NOT running.
Panel 3 PASSING: the back foot swings forward and steps right up beside the front
foot, the legs are TOGETHER, feet almost touching, his body at its highest and
tallest, spine straight.
Panel 4 PUSH OFF: he rises onto the toes of the back foot, the back leg trailing
at an angle, the front leg starting to reach forward, body rising.
The 4 panels must show 4 clearly different leg positions, each about a quarter of
a step apart.""",
}

LAYOUT = """LAYOUT RULES, these matter more than the drawing:
- exactly 8 separate figures in a single horizontal row, evenly spaced
- HUGE empty gaps of pure background between the figures, at least 100 pixels of
  completely empty background between the right edge of one figure and the left
  edge of the next one; nothing of any kind may pass through those gaps
- every figure the same size, feet on the same horizontal line, full body from
  head to boots inside its own space, nothing cropped
- each figure fills the image height, from the very top of the head to the very
  bottom of the boots, leaving only small equal margins

ABSOLUTELY NO GROUND SHADOW, no cast shadow, no dark blur under the boots, no
floor, no ground plane, no horizontal line, no surface, no reflection. The area
under and around every figure must be the same flat background as the rest of
the image.

Background: one single flat vivid magenta (255, 0, 255), perfectly uniform.
EXCLUDE: text, letters, numbers, captions, grid lines, borders, weapons,
scenery, signature, watermark, duplicate figures."""


def magenta_mask(a):
    # Чистая мажента (255,0,255): каналы R и B РАВНЫ, поэтому условие вида
    # r-b > 8 её не берёт (ошибка 14.10: «фон 1%» на заведомо мажентной
    # картинке). Признак фона — низкий зелёный канал при высоких R и B.
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (g < 110) & (r > 140) & (b > 140) & ((r - g) > 50)


def preflight(path, expect=8, min_gap=60, feet_tol=14, min_ratio=0.36):
    """Проверка СЫРОГО png. Возвращает (ok, строки отчёта)."""
    a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    bgm = magenta_mask(a)
    fg = ~bgm
    h, w = fg.shape
    rep = []

    # 1. однотонность фона: разброс ВНУТРИ каждого канала по фоновым пикселям.
    # Раньше брался максимум канала по всем пикселям — у магенты (255,0,255)
    # это всегда даёт большое sd, даже когда фон идеально ровный (ошибка 14.10).
    bg_pixels = a[bgm]
    if bg_pixels.size:
        per_ch = bg_pixels.std(axis=0)
        bg_spread = int(per_ch.max())
    else:
        per_ch = np.zeros(3)
        bg_spread = 999
    rep.append(f"фон: {bgm.mean() * 100:.0f}% кадра, разброс внутри канала sd={bg_spread}")
    ok_bg = bg_pixels.size > 0 and bg_spread < 26

    # 2. фигуры: связные колонки с зазором
    cols = fg.sum(axis=0)
    active = cols >= 3
    runs, start = [], -1
    for x, v in enumerate(active):
        if v and start < 0:
            start = x
        elif not v and start >= 0:
            runs.append((start, x - 1))
            start = -1
    if start >= 0:
        runs.append((start, w - 1))
    gaps = [runs[i + 1][0] - runs[i][1] - 1 for i in range(len(runs) - 1)]
    rep.append(f"фигур: {len(runs)}, зазоры: {gaps if gaps else '-'}")
    ok_figs = len(runs) == expect
    ok_gaps = (not gaps) or min(gaps) >= min_gap

    # 3. тень под фигурами: тёмные пиксели ПОД нижним краем фигуры
    shadow_max = 0
    for x0, x1 in runs:
        ys, _ = np.where(fg[:, x0:x1 + 1])
        if ys.size == 0:
            continue
        feet = int(ys.max())
        band = a[feet + 3:feet + 26, x0:x1 + 1]
        if band.size == 0:
            continue
        dark = (band[:, :, 0] < 140) & (band[:, :, 1] < 110)
        frac = float(dark.sum()) / max(1, dark.size)
        shadow_max = max(shadow_max, frac)
    rep.append(f"тень под фигурами: худшая полоса {shadow_max * 100:.0f}% тёмных пикселей")
    ok_shadow = shadow_max < 0.06

    # 4. линия ног
    feet_y = []
    for x0, x1 in runs:
        ys, _ = np.where(fg[:, x0:x1 + 1])
        if ys.size:
            feet_y.append(int(ys.max()))
    spread = (max(feet_y) - min(feet_y)) if feet_y else 999
    rep.append(f"линия ног: разброс {spread}px по {len(feet_y)} фигурам")
    ok_feet = spread <= feet_tol

    # 5. ТОЛЩИНА ФИГУРЫ. Этой проверки не было 14.10, и это ровно тот класс,
    # что уже ловил проект дважды: метрика, которая не измеряет главное.
    # Полоса пришла с отношением ширины к высоте 0.24 — фигура в 4 раза
    # ниже, чем широка, «жердь». Проверка зазоров и тени её не видели: фигура
    # была корректной, просто неверного телосложения. Городские NPC дают
    # 0.48-0.59 (замер tests/hero_size_probe.gd), поэтому 0.36 - нижняя
    # граница нормы, а не произвольное число.
    ratios = []
    for x0, x1 in runs:
        sub = fg[:, x0:x1 + 1]
        ys, xs = np.where(sub)
        if ys.size == 0:
            continue
        cw = int(xs.max() - xs.min() + 1)
        ch = int(ys.max() - ys.min() + 1)
        ratios.append((cw, ch, cw / max(1, ch)))
    worst = min((r[2] for r in ratios), default=0.0)
    detail = " ".join(f"{r[2]:.2f}" for r in ratios) if ratios else "-"
    rep.append(f"толщина: ширина/высота по фигурам {detail} (худшая {worst:.2f}, "
               f"норма >= {min_ratio:.2f})")
    ok_ratio = bool(ratios) and worst >= min_ratio

    ok = ok_bg and ok_figs and ok_gaps and ok_shadow and ok_feet and ok_ratio
    for line in rep:
        print("   " + line)
    print(f"   ИТОГ: {'ГОДЕН' if ok else 'БРАК — правь промт'}"
          f" (фон {'ок' if ok_bg else 'плохо'}, фигур {'ок' if ok_figs else 'плохо'}, "
          f"зазоры {'ок' if ok_gaps else 'плохо'}, тень {'ок' if ok_shadow else 'ЕСТЬ'}, "
          f"ноги {'ок' if ok_feet else 'плохо'}, "
          f"толщина {'ок' if ok_ratio else 'ЖЕРДЬ — правь ракурс и телосложение'})")
    return ok, rep


def femaleize(text: str) -> str:
    """he/she в английском тексте позы, по границам слов, регистр сохранён."""
    out = re.sub(r"\bHe\b", "She", text)
    out = re.sub(r"\bHis\b", "Her", out)
    out = re.sub(r"\bHe's\b", "She's", out)
    out = re.sub(r"\bhe\b", "she", out)
    out = re.sub(r"\bhis\b", "her", out)
    out = re.sub(r"\bhim\b", "her", out)
    out = re.sub(r"\bhimself\b", "herself", out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("anim")
    ap.add_argument("--out", default="")
    ap.add_argument("--check", default="")
    ap.add_argument("--seed", type=int, default=20261014)
    ap.add_argument("--model", default=MODEL,
                    help="id модели роутера, например black-forest-labs/flux.2-pro")
    ap.add_argument("--panels", type=int, default=8, choices=(4, 8),
                    help="4 панели на картинку — 8 физически не помещаются (14.10)")
    ap.add_argument("--sex", choices=("m", "f"), default="m",
                    help="пол персонажа: m — воин (по умолчанию), f — воительница")
    ap.add_argument("--tag", default="",
                    help="суффикс имени файла, например nb6. По умолчанию — "
                         "тег выбранного пола")
    args = ap.parse_args()

    if args.check:
        ok, _ = preflight(args.check, expect=args.panels,
                          min_gap=40 if args.panels == 4 else 60)
        return 0 if ok else 1

    if args.anim not in (ANIMS4 if args.panels == 4 else ANIMS):
        print(f"неизвестно: {args.anim}")
        return 1
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from gen_image_kodik import load_key, gen_once

    table = ANIMS4 if args.panels == 4 else ANIMS
    layout = LAYOUT4 if args.panels == 4 else LAYOUT
    character = CHARACTER
    proportions = PROPORTIONS
    view = VIEW
    if args.sex == "f":
        character = CHARACTER_F
        proportions = PROPORTIONS_F
        view = VIEW_F
    # Местоимения в тексте поз — английские, и оставленные «He/his» модель
    # рисует мужчину поверх женского описания персонажа. Замена по границам
    # слов, регистр сохраняется, чтобы «He does NOT crouch» не стало «She
    # does not». Проверяется, что после замены не осталось мужских форм.
    pose = table[args.anim]
    if args.sex == "f":
        pose = femaleize(pose)
        for leftover in ("He ", "His ", "his ", "him ", "He's"):
            if leftover in pose:
                raise ValueError(f"в позе '{args.anim}' осталось мужское "
                                 f"местоимение: {leftover!r}")
    # Порядок блоков значим: характер -> телосложение -> ракурс -> поза ->
    # раскладка. Телосложение и ракурс стоят ДО описания позы, потому что
    # «SIDE VIEW» в конце промта перебивал «lean» в начале: узкий ракурс
    # побеждал при слове «broad» (замер 14.10: 0.24 ширины к высоте).
    prompt = (f"{character}\n\n{proportions}\n\n{view}\n\n{pose}\n\n{layout}")
    tag = args.tag or ("nb5" if args.sex == "m" else "nb6")
    out = Path(args.out) if args.out else OUT_DIR / f"hero_{args.anim}_{tag}.png"
    gen_once(load_key(), args.model, prompt, out, SIZE, args.seed, 1, None)
    print("предполётная проверка:")
    ok, _ = preflight(str(out), expect=args.panels, min_gap=40 if args.panels == 4 else 60)
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())