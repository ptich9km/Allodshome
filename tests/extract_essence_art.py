#!/usr/bin/env python3
"""Cut the approved essence sheet (tests/gen_essence_art.py) into 4 frames.

Frames land in assets/ui/essence/essence-000..003.png (32 px canvas, the same
steps as the quest icons: connected columns -> LANCZOS -> alpha-unmix from the
magenta background). The four frames share one fit, so the vial does not jump
in size between the phases.

Run only after the player approved the sheet:
  python tests/extract_essence_art.py
  python tests/extract_essence_art.py --src import/Quest/essence.png
Then in Godot: --headless --import (new PNGs do not load without it).
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_quest_art import column_runs, sheet, unmix_frame  # noqa: E402
from extract_quest_art import fg_mask  # noqa: E402

SRC = REPO / "import" / "Quest" / "essence.png"
OUT_DIR = REPO / "assets" / "ui" / "essence"
PREFIX = "essence"
COUNT = 4
CANVAS = 32
CONTENT = 28


def process(src):
	img = Image.open(src).convert("RGB")
	fg = fg_mask(img)
	runs = column_runs(img, COUNT)
	crops = []
	for x0, x1 in runs:
		ys, _ = fg[:, x0:x1 + 1].nonzero()
		if ys.size == 0:
			raise SystemExit("empty essence frame - sheet rejected")
		crops.append(img.crop((x0, int(ys.min()), x1 + 1, int(ys.max()) + 1)))
	big_w = max(c.size[0] for c in crops)
	big_h = max(c.size[1] for c in crops)
	scale = CONTENT / max(big_w, big_h)
	frames = []
	for crop in crops:
		cw, ch = crop.size
		crop = crop.resize((max(1, round(cw * scale)), max(1, round(ch * scale))),
						   Image.LANCZOS)
		rgba = Image.fromarray(unmix_frame(crop, fg_mask(crop)), "RGBA")
		out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
		out.paste(rgba, ((CANVAS - rgba.size[0]) // 2,
						 (CANVAS - rgba.size[1]) // 2))
		frames.append(out)
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	for i, fr in enumerate(frames):
		fr.save(OUT_DIR / f"{PREFIX}-{i:03d}.png")
	sheet_path = sheet(frames, CANVAS, OUT_DIR / f"_{PREFIX}_sheet.png")
	print(f"essence: {COUNT} frames -> {OUT_DIR / PREFIX}-000...png, "
		  f"contact sheet {sheet_path}")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--src", default="")
	args = ap.parse_args()
	src = Path(args.src) if args.src else SRC
	if not src.exists():
		raise SystemExit(f"no source sheet: {src}")
	process(src)
	print("do not forget: --headless --import in Godot before parsing")


if __name__ == "__main__":
	main()
