#!/usr/bin/env python3
"""Slicing of approved AI quest sheets into game assets.

PIPELINE (run only after the player approves the sheets from gen_quest_art):
  python tests/extract_quest_art.py --variant marks_available
  python tests/extract_quest_art.py --variant marks_ready
  python tests/extract_quest_art.py --variant items
  python tests/extract_quest_art.py --variant coin
  ... then in Godot: --headless --import (new PNGs do not load without it).

What it does:
  * cuts the sheet by connected COLUMNS (objects are compact and the preflight
    guarantees the gaps), so the sheet order = the SPEC order, not geometric
    quarters: for 5 items the quarters do not line up with the objects;
  * items only: the model painted the inside of every forged frame with a
    CRIMSON PLATE instead of leaving the empty background (player verdict
    22.10: accept the sheet, clear the plate in code - it is more exact than
    asking the model again). drop_plate() floods the plate out of a window
    inside the frame ring, so the iron ring and the item survive untouched, and
    the background stays exactly magenta for the alpha unmix;
  * unmixes alpha mathematically (v2 from extract_cursor_frames, player verdict
    'better already'): pixel = alpha*color + (1-alpha)*magenta; the color is
    restored by the inverse substitution, no erosion;
  * scales with LANCZOS - a deliberate exception from the nearest rule
    (precedent gen_loot_icons_derived.py: nearest gives ragged edges);
  * canvas and anchor by kind:
      marks_<kind> - 24x24, centred (the marker floats above the head of the
        head, scripts/quest_marker.gd reads marks/<kind>-NNN.png, 4 frames);
      items        - 32x32, centred (the quest slot in the panel and on the
        ground; scripts/quest_panel.gd reads items/<icon>.png);
      coin         - 4 frames 32x32, centred (a SPRITE: the coin sways
        frame by frame, scripts/quest_icons.gd reads coin/gold_coin-NNN.png).
        The frames are squashed vertically so the width is fitted to 28px and
        the sway reads as "the coin settles"; the path
        assets/loot_icons/gold_coin.png is kept on purpose: loot_icons.gd:
        gold_icon(), tests/loot_icon_smoke.gd and tests/loot_ground_smoke.gd
        rely on it, so this variant never writes there.
  * writes _contact_sheet.png - the player looks at the result before it goes
    into the game.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "import" / "Quest"
MARKS_DIR = REPO / "assets" / "ui" / "quest" / "marks"
ITEMS_DIR = REPO / "assets" / "ui" / "quest" / "items"
COIN_DIR = REPO / "assets" / "ui" / "quest" / "coin"

# Kind -> (folder, name prefix, frame count, canvas, content)
VARIANTS = {
	"marks_available": (MARKS_DIR, "available", 4, 24, 20),
	"marks_ready": (MARKS_DIR, "ready", 4, 24, 20),
	"coin": (COIN_DIR, "gold_coin", 4, 32, 28),
}

# Item order in the sheet (matches gen_quest_art.ITEMS_PROMPT and the icon
# keys of assets/quests/quest_db.json).
ITEM_NAMES = ["quest_sword", "quest_amulet", "quest_armor", "quest_scroll",
			  "quest_book"]
ITEM_CANVAS = 32
ITEM_CONTENT = 28
# The crimson plate the model painted inside the frames of the items sheet
# (measured on import/Quest/quest_items.png: about 171, 6, 96; the lit corners
# give a red channel up to 230).
PLATE_RED = 80
PLATE_GREEN_MAX = 75
PLATE_BLUE_MIN = 45
# Red dominance over green: the plate is crimson, the amber rune stud and the
# gold highlights are green-dominant.
PLATE_DOMINANCE = 60
# The window starts this many pixels past the strict plate bounds: the iron
# ring of the frame is never reached (a window is kept off the frame wood and
# its golden corner leaves).
FRAME_DEPTH = 8
# A plate pixel is at least this much redder than green; iron is neutral grey
# and the dark crimson fringe under the ring edge stays a few levels below it.
PLATE_RED_GREEN_GAP = 40
# The fringe (76, 6, 45): the purple of the crimson in shadow wins over the
# blue, unlike the grey-blue iron of the ring.
PLATE_FRINGE_GAP = 20
PLATE_FRINGE_BLUE_MAX = 60


def fg_mask(img):
	a = np.array(img.convert("RGB")).astype(np.int32)
	r, g, b = a[..., 0], a[..., 1], a[..., 2]
	bg = (g < 110) & (r > 140) & (b > 140) & ((r - g) > 50)
	return ~bg


def unmix_frame(crop, cm):
	"""RGBA from an RGB crop: alpha and color are unmixed from magenta (v2)."""
	px = np.asarray(crop, dtype=float)
	bg = np.array([255.0, 0.0, 255.0])
	fgm = px[cm].mean(axis=0)
	d = fgm - bg
	denom = max(float(np.linalg.norm(d)) ** 2, 1e-6)
	t = np.clip(((px - bg) @ d) / denom, 0.0, 1.0)
	tt = np.maximum(t[..., None], 1e-3)
	clean = np.clip((px - (1.0 - tt) * bg) / tt, 0, 255)
	out = np.concatenate([clean, t[..., None] * 255.0], axis=2)
	return out.astype(np.uint8)


def plate_mask(a):
	"""Crimson plate of the items sheet: crimson pixels of one shade.

	The plate is about 171, 6, 96 and the lit corners reach 230 in the red
	channel; the darker shade right under the frame edge stays below
	PLATE_RED and is left to the ring, the item rarely dips into crimson.
	"""
	r, g, b = a[..., 0], a[..., 1], a[..., 2]
	return ((r >= PLATE_RED) & (g <= PLATE_GREEN_MAX) & (b >= PLATE_BLUE_MIN)
			& ((r - g) >= PLATE_DOMINANCE))


def drop_plate(img):
	"""Paint the crimson plate inside every frame with the background magenta.

	The frame ring, its runes, the amber stud and the item stay as they are.
	The window of the flood is cut from the strict plate mask with FRAME_DEPTH
	inwards, so it never reaches the ring. The window holds the crimson plate
	(about 171, 6, 96) with its purple shadow fringe (about 76, 6, 45), and
	the item sitting on it. Two filters, both red-dominant, so the neutral
	grey-blue iron and the amber gold never match: the strict crimson and the
	shadow fringe. Every pixel of the window that matches is repainted with the
	exact background colour, which the alpha unmix of cut_object() turns
	transparent. The plate is one flat fill (plus its fringe), so no pixel-connect
	walk is needed - and the item splits it into islands anyway.
	"""
	a = np.array(img.convert("RGB")).astype(np.int32)
	fg = fg_mask(img)
	plate = plate_mask(a)
	r, g, b = a[..., 0], a[..., 1], a[..., 2]
	reddish = (((r - g >= PLATE_RED_GREEN_GAP) & (b >= PLATE_BLUE_MIN))
			   | ((r - g >= PLATE_FRINGE_GAP) & (b <= PLATE_FRINGE_BLUE_MAX)))
	total = 0
	for x0, x1 in column_runs(img, len(ITEM_NAMES)):
		ys, _ = np.where(fg[:, x0:x1 + 1])
		if ys.size == 0:
			raise SystemExit("empty object - sheet rejected")
		y0, y1 = int(ys.min()), int(ys.max())
		local = plate[y0:y1 + 1, x0:x1 + 1]
		rows = np.where(local.sum(axis=1) >= 30)[0]
		if rows.size == 0:
			raise SystemExit(f"no plate in frame {x0}..{x1} - sheet needs a new prompt")
		top = y0 + int(rows.min()) + FRAME_DEPTH
		bottom = y0 + int(rows.max()) - FRAME_DEPTH
		mid = plate_mask(a[top:bottom + 1, x0:x1 + 1])
		cols = np.where(mid.sum(axis=0) >= 10)[0]
		if cols.size == 0:
			raise SystemExit(f"no plate in frame {x0}..{x1} - sheet needs a new prompt")
		left = x0 + int(cols.min()) + FRAME_DEPTH
		right = x0 + int(cols.max()) - FRAME_DEPTH
		win = reddish[top:bottom + 1, left:right + 1]
		a[top:bottom + 1, left:right + 1][win] = (255, 0, 255)
		total += int(win.sum())
		print(f"  frame {x0}..{x1}: window {left}..{right} x {top}..{bottom}, "
			  f"plate {int(win.sum())} px")
	print(f"plate: {total} pixels repainted to the background")
	return Image.fromarray(a.astype(np.uint8), "RGB")


def column_runs(img, expect):
	"""Connected object columns; exactly expect of them, otherwise SystemExit."""
	fg = fg_mask(img)
	active = fg.sum(axis=0) >= (1 if expect == 1 else 3)
	runs, start = [], -1
	for x, v in enumerate(active):
		if v and start < 0:
			start = x
		elif not v and start >= 0:
			runs.append((start, x - 1))
			start = -1
	if start >= 0:
		runs.append((start, len(active) - 1))
	if len(runs) != expect:
		raise SystemExit(f"{len(runs)} objects, expected {expect} - sheet rejected")
	return runs


def cut_object(img, x0, x1, canvas, content):
	"""Object crop -> RGBA -> centred on a canvas x canvas canvas."""
	fg = fg_mask(img)
	ys, _ = np.where(fg[:, x0:x1 + 1])
	if ys.size == 0:
		raise SystemExit("empty object - sheet rejected")
	box = (x0, int(ys.min()), x1 + 1, int(ys.max()) + 1)
	crop = img.crop(box)
	cw, ch = crop.size
	scale = content / max(cw, ch)
	crop = crop.resize((max(1, round(cw * scale)), max(1, round(ch * scale))),
					   Image.LANCZOS)
	rgba = Image.fromarray(unmix_frame(crop, fg_mask(crop)), "RGBA")
	out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
	out.paste(rgba, ((canvas - rgba.size[0]) // 2,
					 (canvas - rgba.size[1]) // 2))
	return out


def sheet(frames, canvas, path):
	"""Contact sheet 1xN on a dark background (the icons are translucent)."""
	img = Image.new("RGB", (canvas * len(frames), canvas), (24, 20, 16))
	for i, fr in enumerate(frames):
		img.paste(fr, (canvas * i, 0), fr)
	img.save(path)
	return path


def process_marks(variant, src):
	folder, prefix, count, canvas, content = VARIANTS[variant]
	img = Image.open(src).convert("RGB")
	runs = column_runs(img, count)
	frames = [cut_object(img, x0, x1, canvas, content) for x0, x1 in runs]
	folder.mkdir(parents=True, exist_ok=True)
	for i, fr in enumerate(frames):
		fr.save(folder / f"{prefix}-{i:03d}.png")
	sheet_path = sheet(frames, canvas, folder / f"_{prefix}_sheet.png")
	print(f"{variant}: {count} frames -> {folder / prefix}-000..png, "
		  f"contact sheet {sheet_path}")


def process_items(src):
	img = drop_plate(Image.open(src).convert("RGB"))
	runs = column_runs(img, len(ITEM_NAMES))
	ITEMS_DIR.mkdir(parents=True, exist_ok=True)
	frames = []
	for name, (x0, x1) in zip(ITEM_NAMES, runs):
		fr = cut_object(img, x0, x1, ITEM_CANVAS, ITEM_CONTENT)
		fr.save(ITEMS_DIR / f"{name}.png")
		frames.append(fr)
	sheet_path = sheet(frames, ITEM_CANVAS, ITEMS_DIR / "_items_sheet.png")
	print(f"items: {len(ITEM_NAMES)} icons -> {ITEMS_DIR}, "
		  f"contact sheet {sheet_path}")


def process_coin(src):
	"""4 sway phases -> coin/gold_coin-NNN.png.

	The coin is drawn in the same frame at every phase and only squashed
	vertically, so the fit is by WIDTH and by the max height of the strip: a
	per-frame fit would blow the thin edge-on phase up to full height.
	"""
	folder, prefix, count, canvas, content = VARIANTS["coin"]
	img = Image.open(src).convert("RGB")
	fg = fg_mask(img)
	runs = column_runs(img, count)
	crops = []
	for x0, x1 in runs:
		ys, _ = np.where(fg[:, x0:x1 + 1])
		if ys.size == 0:
			raise SystemExit("empty coin phase - sheet rejected")
		crops.append(img.crop((x0, int(ys.min()), x1 + 1, int(ys.max()) + 1)))
	big_w = max(c.size[0] for c in crops)
	big_h = max(c.size[1] for c in crops)
	scale = content / max(big_w, big_h)
	frames = []
	for crop in crops:
		cw, ch = crop.size
		crop = crop.resize((max(1, round(cw * scale)), max(1, round(ch * scale))),
						   Image.LANCZOS)
		rgba = Image.fromarray(unmix_frame(crop, fg_mask(crop)), "RGBA")
		out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
		out.paste(rgba, ((canvas - rgba.size[0]) // 2,
						 (canvas - rgba.size[1]) // 2))
		frames.append(out)
	folder.mkdir(parents=True, exist_ok=True)
	for i, fr in enumerate(frames):
		fr.save(folder / f"{prefix}-{i:03d}.png")
	sheet_path = sheet(frames, canvas, folder / f"_{prefix}_sheet.png")
	sizes = [f"{f.size[0]}x{f.size[1]}" for f in frames]
	print(f"coin: {count} phases -> {folder / prefix}-000..png ({sizes}), "
		  f"contact sheet {sheet_path}")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--variant", required=True,
					choices=("marks_available", "marks_ready", "items", "coin"))
	ap.add_argument("--src", default="")
	args = ap.parse_args()
	src = Path(args.src) if args.src else SRC / f"quest_{args.variant}.png"
	if not src.exists():
		raise SystemExit(f"no source sheet: {src}")
	if args.variant == "items":
		process_items(src)
	elif args.variant == "coin":
		process_coin(src)
	else:
		process_marks(args.variant, src)
	print("do not forget: --headless --import in Godot before parsing")


if __name__ == "__main__":
	main()
