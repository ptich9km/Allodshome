#!/usr/bin/env python3
"""AI art sheets for town head quests + a preflight of the raw PNG.

WHY. Quests (scripts/quest_system.gd, 22.10) need hand-made art, not programmatic
drawing: markers above the head of the head ("!" - there are offers,
"?" - there is something to turn in), a new gold coin face and five quest item
icons marked as quest items (sword, amulet, armor, scroll, book).

PIPELINE (per the rules for AI generations in project memory):
  1. The prompt is agreed with the player BEFORE the run. One attempt -> show
     the sheet path and the preflight report -> wait for "accepted / regenerate".
     The player decides how many attempts there will be.
  2. The same model as the cursors of 22.10: microsoft/mai-image-2.6-flash
     ($0.031/sheet). mai paints the background PINK, so normalize_bg() always
     runs after generation (flood-fill -> exact magenta), imported from
     gen_hero_strip.
  3. Sheet layout by kind (LAYOUT):
     * strip  - EXACTLY 4 frames in ONE row (marker animation: a light spin);
     * grid   - 5 items in one row (quest item icons);
     * single - ONE object in the centre (coin).
     Two rows of objects is a hard error (incident hm1, 21.10).
  4. Preflight: flat background, expected object count, gaps >= MIN_GAP,
     margin to the edge >= EDGE_MIN, consistent size; for item icons also the
     HUMANNESS check (see below). The stability check follows the motion kind:
     a spinning mark keeps its top and bottom lines, a settling coin keeps its
     centres on one line and its width.

HUMANNESS (player requirement 22.10: the "mechanical" cursor drawn by code was
rejected). Programmatic drawing gives perfectly straight lines, even gradients
and identical thickness - the model almost never makes those. The preflight
rejects a sheet when the inner fill of an object is too uniform (flat fill =
mechanical) or the object is a pair of perfectly parallel rectangles (a cursor
from code). It is a coarse filter: the verdict stays with the player, the
numbers are printed honestly.

Run:
  python tests/gen_quest_art.py marks_available --seed N
  python tests/gen_quest_art.py items --seed N
  python tests/gen_quest_art.py coin --seed N
  python tests/gen_quest_art.py items --check import/Quest/quest_items.png
Output: import/Quest/quest_<variant>.png (slicing - tests/extract_quest_art.py
  only after the player approves the sheet).
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "import" / "Quest"
EDGE_MIN = 3
MIN_GAP = 28
MODEL = "microsoft/mai-image-2.6-flash"
SIZE = "1024x1024"
## Spin markers: how far the top and the bottom lines of the frames may drift
## (pixels of the 1024 sheet) - the mark must not bob or change scale.
SPIN_LINE_TOL = 24
## Coin sway: the centres of the 4 phases on one horizontal line and the
## widths within this spread (pixels of the 1024 sheet). The tops and the
## bottoms legally move - the coin is squashed vertically frame by frame.
COIN_CENTRE_TOL = 24
COIN_WIDTH_TOL = 60

# Shared prompt tail: layout, background and bans (identical for every kind).
LAYOUT_TAIL = """
LAYOUT RULES, these matter more than the drawing:
{layout}
- HUGE empty gaps of pure background between neighbouring objects
- every object keeps a strip of clear empty background on ALL FOUR sides,
  at least 40 pixels on each side; NOTHING may touch or cross the image border

ABSOLUTELY NO GROUND SHADOW, no floor, no reflection, no gradient background.
Background: one single flat vivid magenta (255, 0, 255), perfectly uniform.
EXCLUDE: text, letters, numbers, captions, grid lines, borders, watermark,
duplicate objects, hands.

HUMAN MADE LOOK, this is a hard requirement: painted fantasy game art made by
a human artist, with hand-painted shading, visible brush strokes on the
surfaces, slightly irregular hammered edges, soft uneven highlights and small
ageing marks. NOT a computer drawing: no perfectly straight vector lines, no
flat single-color fills, no even mechanical gradients, no identical repeated
thickness, no geometric uniforms."""

LAYOUT_STRIP = """- exactly 4 separate objects in a single horizontal row, evenly spaced
- each object at most 20 percent of the image width, same size in every panel
- TWO ROWS IS A HARD ERROR: all 4 objects stand on ONE single horizontal line"""
LAYOUT_GRID = """- exactly 5 separate objects in a single horizontal row, evenly spaced
- each object at most 15 percent of the image width, same size in every item
- TWO ROWS IS A HARD ERROR: all 5 objects stand on ONE single horizontal line"""
LAYOUT_SINGLE = """- exactly ONE object, centered, its size about 55 percent of the image width"""
LAYOUT_COIN = """- exactly 4 separate coins in a single horizontal row, evenly spaced
- all 4 coins the SAME horizontal width and centered on ONE horizontal line
- TWO ROWS IS A HARD ERROR: all 4 coins stand on ONE single horizontal line"""

# --- Marker "!": there are offers -------------------------------------------
# Player decision 22.10 (v2): NO medallion and no cord - a bare gold exclamation
# mark does not read as a chain; the only motion is a slight spin about its own
# vertical axis, no bobbing and no swinging.
MARKS_AVAILABLE_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of QUEST
MARKER ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game
will cut this image apart and float the frames above the head of the town
elder who GIVES quests.

THE OBJECT, in every panel: ONE bare EXCLAMATION MARK, nothing else. No disc,
no medallion, no cord, no chain, no ring, no frame, no stand, no background
shape - the exclamation mark IS the whole object and it floats free: a bold
cast-gold exclamation mark, thick warm gold with hand-forged metal shading, a
narrow dark outline, soft amber specular highlights and slightly worn edges,
the dot clearly separated from the bar. Reads instantly as "quest here". Bold
simple silhouette, no thin filigree, no tiny details, no text, no letters
other than the single exclamation mark.

ANIMATION, 4 panels left to right in ONE horizontal row - the SAME exclamation
mark seen while it slowly turns about its own VERTICAL axis (a 3D spin shown
frame by frame), like a coin spinning in place:
Panel 1: facing the viewer, the full width.
Panel 2: turned a quarter of the way, the bar a little narrower, its inner side
visible on the right, the dot turned the same way.
Panel 3: turned to nearest edge-on, the narrowest of all four panels, still
clearly the same exclamation mark.
Panel 4: back at about three quarters, already opening up again towards panel 1.
The mark does NOT move up or down, does NOT tilt, swing, rock or bob, and does
NOT change its top and bottom positions in any panel: the dot stays on the
SAME horizontal line in all four panels and the bar top stays on the SAME
line - only the horizontal width and the side shading change.
""" + LAYOUT_TAIL.format(layout=LAYOUT_STRIP)

# --- Marker "?": there is something to turn in ---------------------------------
# Same rule as "!": a bare question mark, only a spin about its own axis.
MARKS_READY_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of QUEST
MARKER ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game
will cut this image apart and float the frames above the head of the town
elder when the player comes back to TURN IN a finished quest.

THE OBJECT, in every panel: ONE bare QUESTION MARK, nothing else. No disc,
no medallion, no cord, no chain, no ring, no frame, no stand, no background
shape - the question mark IS the whole object and it floats free: a bold cast
question mark of pale emerald-green silver metal, thick, with hand-forged
metal shading, a narrow dark outline, soft green specular highlights and a soft
green inner glow, slightly worn edges. Reads instantly as "something to turn
in". Bold simple silhouette, no thin filigree, no tiny details, no text, no
letters other than the single question mark.

ANIMATION, 4 panels left to right in ONE horizontal row - the SAME question
mark seen while it slowly turns about its own VERTICAL axis (a 3D spin shown
frame by frame), like a coin spinning in place:
Panel 1: facing the viewer, the full width.
Panel 2: turned a quarter of the way, a little narrower, its inner side
visible on the right.
Panel 3: turned to nearest edge-on, the narrowest of all four panels, still
clearly the same question mark.
Panel 4: back at about three quarters, already opening up again towards panel 1.
The mark does NOT move up or down, does NOT tilt, swing, rock or bob, and does
NOT change its top and bottom positions in any panel: the hook top stays on the
SAME line and the dot bottom stays on the SAME line - only the horizontal width
and the side shading change.
""" + LAYOUT_TAIL.format(layout=LAYOUT_STRIP)
# --- Money coin: replaces the programmatic tests/gen_gold_coin.py ---------------
# Player decision: a ruler's profile on the obverse. The coin is a SPRITE too:
# 4 phases of a coin settling on the table (a hard spin about its own axis would
# stutter from four frames, so it is the flatten-then-edge-then-open motion).
COIN_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of GOLD COIN
SPIN ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game shows
the coin as the gold-money counter and as a little pile of coins on the ground.

THE OBJECT, in every panel: the SAME single gold coin with a milled rim (beaded
edge). On its face a small CLASSICAL PORTRAIT IN PROFILE of a laurel-crowned
ruler in relief and a laurel branch curving along the rim, plus a few worn
scratches and dents of old age. Warm gold, darker in the recessed relief, a
soft edge highlight from the upper left. Bold simple shapes, thick readable
silhouette, no text, no letters, no numbers, no face details finer than the
brow and the nose.

ANIMATION, 4 panels left to right in ONE horizontal row - the coin turns over
about its own HORIZONTAL axis while settling flat on the table, exactly the
frames of that motion:
Panel 1: face-on to the viewer, a perfect full circle, its full diameter.
Panel 2: squeezed vertically (an ellipse about 70 percent as tall as panel 1),
the thick rim edge visible under the face.
Panel 3: seen almost edge-on - a narrow horizontal bar of the rim thickness,
its full width still the same as in panel 1.
Panel 4: squeezed vertically again, the same ellipse as panel 2 (the coin
opening back up).
The CENTRE of the coin stays on ONE horizontal line in all four panels and its
HORIZONTAL width stays the same in all four panels: the coin does NOT move left
or right, does NOT move up or down, does NOT rock or wobble, and does NOT
change size. Only the vertical squash and the visible thickness change.
""" + LAYOUT_TAIL.format(layout=LAYOUT_COIN)

# --- Quest items: 5 icons marked as "quest item".
# Player decision: a forged frame with runic scrollwork around every item.
ITEMS_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of FIVE
SEPARATE QUEST ITEM ICONS for a 2D fantasy tactical RPG video game. The game
cuts the five icons apart and shows each one in a small quest slot, so every
item must be recognizable by silhouette alone and the five must look like ONE
matching icon set.

The five items, LEFT to RIGHT in this exact order:
1. a straight one-handed SWORD, silver blade pointing up, cross guard, leather grip;
2. an oval AMULET on a chain, a glowing blue gemstone set in a silver frame;
3. a steel CHESTPLATE (breastplate) armor piece with shoulder plates;
4. a rolled parchment SCROLL tied with a red ribbon, one end curling outward;
5. a bound BOOK with metal-clasped corners and a rune on its cover.

UNIFORM QUEST MARK: EACH of the five items is framed by the SAME heavy dark
forged-iron border the game uses to mark quest items - ornate runic scrollwork
at the corners and a small glowing amber rune stud in the middle of the top
edge. The frames are drawn in the SAME style, colour and thickness on all five
items; only the item inside the frame differs. The item sits fully inside its
frame, nothing pokes through the frame, and the inside of the frame is EMPTY
background: NO coloured panel, no red or pink plate, no gradient behind the
item.

All five icons are the SAME size, stand on the SAME horizontal line, and every
frame has the same vertical proportions.
""" + LAYOUT_TAIL.format(layout=LAYOUT_GRID)

# --- HUD command icons: inventory / follow / attack / guard / stop -------------
# Five buttons under the minimap are 32 px and show an icon instead of a word
# (player decision 23.10: the text row was 248 px wide in a 175 px column).
CMD_ICON_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of FIVE
SEPARATE HUD COMMAND ICONS for a 2D fantasy tactical RPG video game. The game
cuts the five icons apart and puts each one into a small 32x32 button under the
minimap, so every icon must be recognizable by silhouette alone at that size,
and the five must look like ONE matching icon set painted by the same artist.

The five objects, LEFT to RIGHT in this exact order:
1. INVENTORY: a single leather belt SATCHEL with a flap, a small iron buckle and
   a short strap, seen slightly from the front;
2. FOLLOW: two heavy BOOT PRINTS on the ground, one behind the other, pointing
   the same way (the track of someone walking ahead);
3. ATTACK: a single straight SWORD pointing up, silver blade, dark crossguard,
   leather grip - one weapon, not a pile of weapons;
4. GUARD: a round wooden SHIELD with an iron rim and a riveted boss in the
   middle, seen face-on;
5. STOP: a broad X made of two crossed iron bars with worn forged edges
   (the universal "halt / cancel" sign), nothing else.

UNIFORM SET: all five icons share the SAME hand-painted fantasy style, the SAME
warm dark iron and amber colour accents, the SAME heavy dark outline, and the
SAME visual weight. They are flat icon art, not 3D renders, not tied to a
perspective scene. No frame around an icon, no badge, no circle, no plate behind
the object - each object IS the whole icon and floats free.

READABILITY: bold simple silhouette, thick shapes, no thin filigree, no tiny
details, no text, no letters, no numbers. Each icon fills about the same share
of its own cell and must still be readable when shrunk to 32 pixels.
""" + LAYOUT_TAIL.format(layout=LAYOUT_GRID)

PROMPTS = {
	"marks_available": MARKS_AVAILABLE_PROMPT,
	"marks_ready": MARKS_READY_PROMPT,
	"coin": COIN_PROMPT,
	"items": ITEMS_PROMPT,
	"cmd_icons": CMD_ICON_PROMPT,
}

# Expected object count, minimal gap and the motion kind by variant.
LAYOUT = {
	"marks_available": {"count": 4, "gap": MIN_GAP, "spin": True},
	"marks_ready": {"count": 4, "gap": MIN_GAP, "spin": True},
	"coin": {"count": 4, "gap": MIN_GAP, "spin": False, "sway": True},
	"items": {"count": 5, "gap": MIN_GAP, "spin": False},
	"cmd_icons": {"count": 5, "gap": 10, "spin": False, "merge_at": 1,
				  "width_tol": 130},
}


def magenta_mask(a):
	# Same background test as in gen_cursor_strip / gen_hero_strip.
	r, g, b = a[..., 0], a[..., 1], a[..., 2]
	return (g < 110) & (r > 140) & (b > 140) & ((r - g) > 50)


def _column_runs(fg, min_col=3):
	cols = fg.sum(axis=0)
	active = cols >= min_col
	runs, start = [], -1
	for x, v in enumerate(active):
		if v and start < 0:
			start = x
		elif not v and start >= 0:
			runs.append((start, x - 1))
			start = -1
	if start >= 0:
		runs.append((start, len(active) - 1))
	return runs


def _interior(a, fg):
	"""Object pixels whose 4 neighbours are object pixels too (no edges)."""
	sub = fg[1:-1, 1:-1] & fg[:-2, 1:-1] & fg[2:, 1:-1] & fg[1:-1, :-2] & fg[1:-1, 2:]
	return a[1:-1, 1:-1][sub]


def humanness(a, fg, runs):
	"""Signs of "drawn by a human" rather than "drawn by code".

	flat - share of pixels whose local variance inside the object is almost
	zero (a flat fill, like the coloured rectangles of a cursor from code);
	parallel - share of objects whose row widths are constant (a rectangle).
	Returns (ok, report text).
	"""
	inner = _interior(a, fg)
	if inner.size == 0:
		return False, "humanness: object interior is empty"
	mean = inner.mean()
	spread = float(np.abs(inner.astype(np.float64) - mean).mean())
	# flat fill: mean spread inside the object < 9 levels per channel
	flat = spread < 9.0
	# rectangles: width per row
	parallel = 0
	for x0, x1 in runs:
		sub = fg[:, x0:x1 + 1]
		widths = sub.sum(axis=1)
		widths = widths[widths > 0]
		if widths.size and int(widths.max() - widths.min()) <= 2:
			parallel += 1
	text = (f"humanness: inner spread {spread:.1f} (flat fill at < 9), "
			f"rectangles {parallel}/{len(runs)}")
	return (not flat) and parallel == 0, text


def preflight(path, count=4, min_gap=MIN_GAP, check_human=True, spin=False,
			  sway=False, merge_at=None, width_tol=60):
	"""Check a raw sheet. Returns (ok, report lines).

	spin - the objects turn about their own vertical axis, so the WIDTH of a
	frame legally shrinks (an edge-on frame is the narrowest one). For such
	sheets the widths are only reported, and the stability check moves to the
	HEIGHT: the mark must not bob up and down or change scale, so the tops and
	the bottoms of the objects stay on two horizontal lines.
	sway - a settling coin: it is squashed vertically frame by frame, so the
	tops and the bottoms legally move and only the CENTRES must stay on one
	horizontal line while the HORIZONTAL width stays the same (the coin does
	not travel and does not change size).
	merge_at - the model may draw ONE icon as two separate shapes (the two boot
	prints of "follow"). If the sheet has count+1 objects, the objects at
	merge_at and merge_at+1 are treated as one icon.
	width_tol - how much icon widths may differ. Icons of different shapes
	(sword vs shield vs bag) are not equal in width by design.
	"""
	a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
	bgm = magenta_mask(a)
	fg = ~bgm
	h, w = fg.shape
	rep = []

	bg_pixels = a[bgm]
	bg_spread = int(bg_pixels.std(axis=0).max()) if bg_pixels.size else 999
	rep.append(f"background: {bgm.mean() * 100:.0f}% of the frame, sd={bg_spread}")
	ok_bg = bg_pixels.size > 0 and bg_spread < 26

	runs = _column_runs(fg, 1 if count == 1 else 3)
	merged = False
	if merge_at is not None and len(runs) == count + 1 and 0 <= merge_at < len(runs) - 1:
		runs[merge_at] = (runs[merge_at][0], runs[merge_at + 1][1])
		del runs[merge_at + 1]
		merged = True
	gaps = [runs[i + 1][0] - runs[i][1] - 1 for i in range(len(runs) - 1)]
	rep.append(f"objects: {len(runs)}" + (" (two shapes merged into one icon)" if merged else "")
			   + f", gaps: {gaps if gaps else '-'}")
	ok_figs = len(runs) == count
	ok_gaps = (not gaps) or min(gaps) >= min_gap

	pads = []
	sizes = []
	tops = []
	bottoms = []
	for x0, x1 in runs:
		ys, xs = np.where(fg[:, x0:x1 + 1])
		if ys.size == 0:
			continue
		pads.append((x0, int(ys.min()), w - 1 - x1, h - 1 - int(ys.max())))
		sizes.append(int(xs.max() - xs.min() + 1))
		tops.append(int(ys.min()))
		bottoms.append(int(ys.max()))
	edge_min = min(min(p) for p in pads) if pads else 0
	rep.append(f"margin to the edge: worst {edge_min}px (norm >= {EDGE_MIN})")
	ok_edge = bool(pads) and edge_min >= EDGE_MIN

	spread = (max(sizes) - min(sizes)) if sizes else 999
	if spin:
		rep.append(f"object widths: {sizes}, spread {spread}px (spin: reported only)")
		t_reach = (max(tops) - min(tops)) if tops else 999
		b_reach = (max(bottoms) - min(bottoms)) if bottoms else 999
		rep.append(f"top line / bottom line drift: {t_reach}px / {b_reach}px "
					f"(norm <= {SPIN_LINE_TOL})")
		ok_size = bool(sizes) and t_reach <= SPIN_LINE_TOL \
			and b_reach <= SPIN_LINE_TOL and min(sizes) >= 8
	elif sway:
		centres = [(t + b) // 2 for t, b in zip(tops, bottoms)]
		drift = (max(centres) - min(centres)) if centres else 999
		rep.append(f"object centres: {centres}, drift {drift}px "
					f"(norm <= {COIN_CENTRE_TOL})")
		rep.append(f"object widths: {sizes}, spread {spread}px "
					f"(norm <= {COIN_WIDTH_TOL})")
		ok_size = bool(sizes) and drift <= COIN_CENTRE_TOL \
			and spread <= COIN_WIDTH_TOL and min(sizes) >= 8
	else:
		rep.append(f"object widths: {sizes}, spread {spread}px (norm <= {width_tol})")
		ok_size = bool(sizes) and spread <= width_tol

	ok_bg_and = ok_bg and ok_figs and ok_gaps and ok_edge and ok_size
	ok_human = True
	if check_human and runs:
		ok_human, text = humanness(a, fg, runs)
		rep.append(text)

	ok = ok_bg_and and ok_human
	for line in rep:
		print("   " + line)
	print(f"   VERDICT: {'FIT' if ok else 'REJECT - fix the prompt'}")
	return ok, rep


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("variant", choices=tuple(PROMPTS.keys()))
	ap.add_argument("--out", default="")
	ap.add_argument("--check", default="",
					help="do not generate: run the preflight on an existing PNG")
	ap.add_argument("--seed", type=int, default=20261022)
	ap.add_argument("--model", default=MODEL)
	args = ap.parse_args()

	lay = LAYOUT[args.variant]
	if args.check:
		ok, _ = preflight(args.check, lay["count"], lay["gap"],
						  spin=lay["spin"], sway=lay.get("sway", False),
						  merge_at=lay.get("merge_at"),
						  width_tol=lay.get("width_tol", 60))
		return 0 if ok else 1

	sys.path.insert(0, str(Path(__file__).resolve().parent))
	from gen_hero_strip import normalize_bg
	from gen_image_kodik import load_key, gen_once

	out = Path(args.out) if args.out else OUT_DIR / f"quest_{args.variant}.png"
	out.parent.mkdir(parents=True, exist_ok=True)
	gen_once(load_key(), args.model, PROMPTS[args.variant], out, SIZE,
			 args.seed, 1, None)
	n = normalize_bg(out)
	print(f"background normalization: {n} pixels repainted")
	print("preflight:")
	ok, _ = preflight(str(out), lay["count"], lay["gap"], spin=lay["spin"],
					  sway=lay.get("sway", False), merge_at=lay.get("merge_at"),
					  width_tol=lay.get("width_tol", 60))
	return 0 if ok else 2


if __name__ == "__main__":
	sys.exit(main())
