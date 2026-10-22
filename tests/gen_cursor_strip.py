#!/usr/bin/env python3
"""Генерация листа кадров тематического КУРСОРА + прелёт сырого PNG.

КОНВЕЙЕР (по правилам памяти об ИИ-генерациях):
  1. Промт согласуется с игроком ДО запуска. Одна попытка -> показать путь
     листа и прелёт-отчёт -> ждать вердикт «годен / перегенерировать».
     Число попыток решает игрок.
  2. Модель: microsoft/mai-image-2.6-flash ($0.031/лист, проверено 21.10).
     mai рисует фон РОЗОВЫМ, поэтому после генерации всегда гоняется
     normalize_bg() (flood-fill -> точная маджента), импорт из gen_hero_strip.
  3. Формат листа: РОВНО 4 кадра в ОДНОМ ряду (урок инцидента hm1, 21.10:
     два ряда — жёсткая ошибка).
  4. Прелёт: однотонный фон, 4 фигуры, зазоры >= 28, поле до края >= 3.
     Проверок «тени/толщины/линии ног» нет: курсор висит в воздухе и не
     является фигурой человека.

Запуск:
  python tests/gen_cursor_strip.py normal --seed N
  python tests/gen_cursor_strip.py cast --check import/Cursor/cursor_cast.png
Вывод: import/Cursor/cursor_<variant>.png + контакт-лист не нужен (прелёт
  печатает цифры, лист смотрит игрок).
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "import" / "Cursor"
EDGE_MIN = 3
MODEL = "microsoft/mai-image-2.6-flash"
SIZE = "1024x1024"

# --- Концепты (на одобрение игрока) ----------------------------------------
# normal — обычный курсор: витая тёмно-бронзовая стрелка-перо с тёплым
# янтарным свечением у острия; 4 кадра — пульс свечения и искра.
NORMAL_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of MOUSE
CURSOR ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game will
cut this image apart and play the panels one after another as the mouse cursor.
The cursor object in every panel: ONE ornate arrow cursor like a quill-tipped
pointer, dark aged bronze metal with a leather-wrapped handle, glowing amber
rune light near the sharp tip. The tip points to the UPPER LEFT corner, the tail
sinks to the lower right. Thick clean readable silhouette, bold simple shapes,
no thin filigree, no tiny details, no text, no numbers, no background scenery.

ANIMATION, 4 panels left to right in ONE horizontal row:
Panel 1: the cursor with a small warm amber glow at the tip.
Panel 2: the glow a little brighter, one tiny golden spark floating just off the tip.
Panel 3: the glow at its brightest, the spark slightly higher.
Panel 4: the glow calm again, equal to panel 1.
The cursor shape itself does NOT move, rotate, bend or change size between
panels - only the glow and the spark change.

LAYOUT RULES, these matter more than the drawing:
- exactly 4 separate cursor objects in a single horizontal row, evenly spaced
- each object at most 20 percent of the image width, same size in every panel
- HUGE empty gaps of pure background between neighbouring objects
- every object keeps a strip of clear empty background on ALL FOUR sides,
  at least 40 pixels on each side; NOTHING may touch or cross the image border
- TWO ROWS IS A HARD ERROR: all 4 objects stand on ONE single horizontal line

ABSOLUTELY NO GROUND SHADOW, no floor, no reflection, no gradient background.
Background: one single flat vivid magenta (255, 0, 255), perfectly uniform.
EXCLUDE: text, letters, numbers, captions, grid lines, borders, watermark,
duplicate cursors, hands."""

# cast — курсор-прицел: парящий рунный круг холодного бирюзового пламени;
# внутри ТРИ руны РАЗНЫХ СТИХИЙ (игрок 22.10): огонь — красно-оранжевая,
# вода — синяя, воздух — бледно-белая. 4 кадра — вращение и пульс.
CAST_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of MOUSE
CURSOR ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game will
cut this image apart and play the panels one after another as the SPELL
TARGETING cursor shown while the player aims a spell. The cursor object in
every panel: ONE floating magical sigil - a small circle of cold teal flame
with THREE glowing runes inside it, each rune a DIFFERENT ELEMENT COLOR: the
first rune glowing RED-ORANGE like fire, the second rune glowing BLUE like
water, the third rune glowing PALE WHITE like air/wind. All three runes sit
inside the circle, evenly spaced, clearly separated from each other and from
the teal ring. Bright cyan core. Bold simple shapes, thick readable silhouette,
no thin filigree, no tiny details, no letters, no real characters, no
background scenery. The runes are simple abstract glyphs made of short thick
glowing strokes, NOT readable letters.

ANIMATION, 4 panels left to right in ONE horizontal row:
Panel 1: the sigil circle with its rune gap rotated 0 degrees, calm glow.
Panel 2: the sigil rotated 90 degrees clockwise, glow a little brighter.
Panel 3: the sigil rotated 180 degrees, glow at its brightest, small flame
licks curling outward.
Panel 4: the sigil rotated 270 degrees, glow calm again.
The sigil keeps the SAME size and the SAME circular shape in all panels - only
rotation and glow change. The THREE runes KEEP THEIR ELEMENT COLORS in every
panel: the fire rune stays red-orange, the water rune stays blue, the air rune
stays pale white. It does NOT drift, tilt or wobble.

LAYOUT RULES, these matter more than the drawing:
- exactly 4 separate sigil objects in a single horizontal row, evenly spaced
- each object at most 20 percent of the image width, same size in every panel
- HUGE empty gaps of pure background between neighbouring objects
- every object keeps a strip of clear empty background on ALL FOUR sides,
  at least 40 pixels on each side; NOTHING may touch or cross the image border
- TWO ROWS IS A HARD ERROR: all 4 objects stand on ONE single horizontal line

ABSOLUTELY NO GROUND SHADOW, no floor, no reflection, no gradient background.
Background: one single flat vivid magenta (255, 0, 255), perfectly uniform.
EXCLUDE: text, letters, numbers, captions, grid lines, borders, watermark,
duplicate sigils, hands."""

# buy — курсор покупки: золотая монета и кожаный кошелёк; 4 кадра — монета
# подпрыгивает/переворачивается, кошелёк чуть вздрагивает.
BUY_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of MOUSE
CURSOR ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game will
cut this image apart and play the panels one after another as the cursor shown
while the player can BUY items in a shop. The cursor object in every panel: ONE
small leather coin purse with a drawstring, tied shut, warm brown leather, with
ONE large gold coin hovering just above its open mouth, the coin tilted slightly
and glinting. Bold simple shapes, thick readable silhouette, no tiny details,
no text, no numbers, no background scenery.

ANIMATION, 4 panels left to right in ONE horizontal row:
Panel 1: coin resting just above the purse opening, calm.
Panel 2: the coin has bounced UP a little and turned, a small white glint on
its edge.
Panel 3: the coin is higher and tilted the other way, the purse strings pulled
slightly taut.
Panel 4: the coin has dropped back to the panel-1 position, calm again.
Only the coin moves; the purse shape and position stay the same in all panels.

LAYOUT RULES, these matter more than the drawing:
- exactly 4 separate objects in a single horizontal row, evenly spaced
- each object at most 20 percent of the image width, same size in every panel
- HUGE empty gaps of pure background between neighbouring objects
- every object keeps a strip of clear empty background on ALL FOUR sides,
  at least 40 pixels on each side; NOTHING may touch or cross the image border
- TWO ROWS IS A HARD ERROR: all 4 objects stand on ONE single horizontal line

ABSOLUTELY NO GROUND SHADOW, no floor, no reflection, no gradient background.
Background: one single flat vivid magenta (255, 0, 255), perfectly uniform.
EXCLUDE: text, letters, numbers, captions, grid lines, borders, watermark,
duplicate objects, hands."""

# work — курсор мастерской: кузнечный молот; 4 кадра — замах и удар с искрой.
WORK_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of MOUSE
CURSOR ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game will
cut this image apart and play the panels one after another as the cursor shown
while the player works in a SMITHY/WORKSHOP (crafting, repairing). The cursor
object in every panel: ONE blacksmith hammer seen from the side - a dark iron
head on a sturdy wooden handle, the head at the UPPER LEFT, the handle sinking
to the lower right, like a cursor arrow made of a hammer. Bold simple shapes,
thick readable silhouette, no tiny details, no text, no background scenery.

ANIMATION, 4 panels left to right in ONE horizontal row:
Panel 1: the hammer held still, calm.
Panel 2: the hammer has tilted a little counter-clockwise, as if starting a
swing, one small orange spark near the iron head.
Panel 3: the hammer tilted the other way, as if striking down, a small orange
spark burst at the head face.
Panel 4: the hammer back to the panel-1 resting position, calm.
The hammer does NOT change size or shape between panels, only a small tilt and
the spark change.

LAYOUT RULES, these matter more than the drawing:
- exactly 4 separate objects in a single horizontal row, evenly spaced
- each object at most 20 percent of the image width, same size in every panel
- HUGE empty gaps of pure background between neighbouring objects
- every object keeps a strip of clear empty background on ALL FOUR sides,
  at least 40 pixels on each side; NOTHING may touch or cross the image border
- TWO ROWS IS A HARD ERROR: all 4 objects stand on ONE single horizontal line

ABSOLUTELY NO GROUND SHADOW, no floor, no reflection, no gradient background.
Background: one single flat vivid magenta (255, 0, 255), perfectly uniform.
EXCLUDE: text, letters, numbers, captions, grid lines, borders, watermark,
duplicate objects, hands."""

PROMPTS = {"normal": NORMAL_PROMPT, "cast": CAST_PROMPT,
           "buy": BUY_PROMPT, "work": WORK_PROMPT}


def magenta_mask(a):
    # Тот же признак фона, что в gen_hero_strip: низкий зелёный при высоких R,B.
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (g < 110) & (r > 140) & (b > 140) & ((r - g) > 50)


def preflight(path, expect=4, min_gap=28):
    """Проверка сырого листа курсора. Возвращает (ok, отчёт)."""
    a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    bgm = magenta_mask(a)
    fg = ~bgm
    h, w = fg.shape
    rep = []
    ok = True

    bg_pixels = a[bgm]
    if bg_pixels.size:
        bg_spread = int(bg_pixels.std(axis=0).max())
    else:
        bg_spread = 999
    rep.append(f"фон: {bgm.mean() * 100:.0f}% кадра, разброс sd={bg_spread}")
    ok_bg = bg_pixels.size > 0 and bg_spread < 26

    # Фигуры по связным КОЛОННАМ: курсоры компактны и хвосты не слипаются.
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
    rep.append(f"объектов: {len(runs)}, зазоры: {gaps if gaps else '-'}")
    ok_figs = len(runs) == expect
    ok_gaps = (not gaps) or min(gaps) >= min_gap

    pads = []
    for x0, x1 in runs:
        ys, _ = np.where(fg[:, x0:x1 + 1])
        if ys.size == 0:
            continue
        pads.append((x0, int(ys.min()), w - 1 - x1, h - 1 - int(ys.max())))
    edge_min = min(min(p) for p in pads) if pads else 0
    rep.append(f"поле до края: худшее {edge_min}px (норма >= {EDGE_MIN})")
    ok_edge = bool(pads) and edge_min >= EDGE_MIN

    # Согласованность размера: курсоры должны быть одного масштаба в кадрах.
    sizes = []
    for x0, x1 in runs:
        sub = fg[:, x0:x1 + 1]
        ys, xs = np.where(sub)
        if ys.size == 0:
            continue
        sizes.append(int(xs.max() - xs.min() + 1))
    spread = (max(sizes) - min(sizes)) if sizes else 999
    rep.append(f"ширина объектов: {sizes}, разброс {spread}px (норма <= 60)")
    ok_size = bool(sizes) and spread <= 60

    ok = ok_bg and ok_figs and ok_gaps and ok_edge and ok_size
    for line in rep:
        print("   " + line)
    print(f"   ИТОГ: {'ГОДЕН' if ok else 'БРАК — правь промт'}")
    return ok, rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("variant", choices=("normal", "cast", "buy", "work"))
    ap.add_argument("--out", default="")
    ap.add_argument("--check", default="",
                    help="не генерировать: прогнать прелёт по готовому PNG")
    ap.add_argument("--seed", type=int, default=20261022)
    ap.add_argument("--model", default=MODEL)
    args = ap.parse_args()

    if args.check:
        ok, _ = preflight(args.check)
        return 0 if ok else 1

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from gen_hero_strip import normalize_bg
    from gen_image_kodik import load_key, gen_once

    out = Path(args.out) if args.out else OUT_DIR / f"cursor_{args.variant}.png"
    gen_once(load_key(), args.model, PROMPTS[args.variant], out, SIZE,
             args.seed, 1, None)
    n = normalize_bg(out)
    print(f"нормализация фона: {n} пикселей перекрашено")
    print("предполётная проверка:")
    ok, _ = preflight(str(out))
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
