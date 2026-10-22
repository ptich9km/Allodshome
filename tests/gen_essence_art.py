#!/usr/bin/env python3
"""AI art sheet for the magic essence: 4 sway frames + a preflight of the raw PNG.

WHY. The upgrade of a crafted item to Master costs magic essence
(CraftDB.ESSENCE_KEY), but the icon of that item (assets/professions/workshop/
magic_essence.png) is a leftover placeholder of the deleted
tests/gen_broken_icons.py - the player complaint 22.10 "the essence has no
art, it is not shown in the drop, the craft or the inventory".

PIPELINE (per the rules for AI generations in project memory):
  1. The prompt is agreed with the player BEFORE the run. One attempt -> show
     the sheet path and the preflight report -> wait for "accepted / regenerate".
     The player decides how many attempts there will be.
  2. Same generator as the quest art (tests/gen_quest_art.py):
     microsoft/mai-image-2.6-flash ($0.031/sheet), normalize_bg() after every
     run (mai paints the background pink).
  3. Sheet layout: EXACTLY 4 objects in ONE horizontal row. Two rows is a hard
     error (incident hm1, 21.10).
  4. Preflight: flat background, object count, gaps >= MIN_GAP, margin to the
     edge, consistent size, and the glow-stability check - the vial must not
     move up or down between the frames, only its inner light changes.

Run:
  python tests/gen_essence_art.py --seed N
  python tests/gen_essence_art.py --check import/Quest/essence.png
Output: import/Quest/essence.png (slicing only after the player approves the
  sheet: tests/extract_essence_art.py).
"""
import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "import" / "Quest"
SIZE = "1024x1024"

# Layout and preflight are shared with the quest art: one pipeline, one set of
# rules, so the essence sheet is judged by the same numbers.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_quest_art import (  # noqa: E402
	LAYOUT_TAIL, MIN_GAP, MODEL, preflight,
)

LAYOUT_STRIP = """- exactly 4 separate objects in a single horizontal row, evenly spaced
- each object at most 20 percent of the image width, same size in every panel
- TWO ROWS IS A HARD ERROR: all 4 objects stand on ONE single horizontal line"""

ESSENCE_PROMPT = """PURPOSE, read this first: you are drawing ONE SPRITESHEET STRIP of MAGIC
ESSENCE ANIMATION FRAMES for a 2D fantasy tactical RPG video game. The game
cuts the four frames apart and plays them in a loop as the icon of the Magic
Essence item: in the monster drop on the ground, in the craft cost row and in
the inventory slot. The item is a rare crafting material, so it must read at
32 pixels as "a glowing vial of magic".

THE OBJECT, in every panel: the SAME small round-bottomed GLASS VIAL sealed
with a cork stopper and a thin wax seal, standing upright. Inside the glass, a
swirling drop of liquid light: pale violet and turquoise, with a few tiny
sparks and a faint inner glow. The glass is thick, with a soft highlight down
the left side and a darker line along the right, hand-painted on a dark glass
surface. A narrow simple pewter collar around the neck, no labels, no paper,
no chain, no stand, no plate, no frame around the vial. Bold readable
silhouette, thick shapes, no tiny filigree.

ANIMATION, 4 panels left to right in ONE horizontal row - the SAME vial pulsing
with inner light, like a slow breathing glow:
Panel 1: the inner light soft and low, one swirl visible.
Panel 2: the light brighter, the swirl turned a little to the right.
Panel 3: the brightest panel, the swirl stretched high, sparks rising.
Panel 4: the light settling back down, the swirl low again.
The vial does NOT move, does NOT grow, does NOT tilt, does NOT bob and does
NOT change its position in any panel: its cork top stays on the SAME line and
its base stays on the SAME line - only the glow inside the glass and the swirl
change.
""" + LAYOUT_TAIL.format(layout=LAYOUT_STRIP)

SOURCES = {
	"essence": (ESSENCE_PROMPT, {"count": 4, "gap": MIN_GAP, "spin": True}),
}


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("variant", choices=tuple(SOURCES.keys()), nargs="?", default="essence")
	ap.add_argument("--out", default="")
	ap.add_argument("--check", default="",
					help="do not generate: run the preflight on an existing PNG")
	ap.add_argument("--seed", type=int, default=20261022)
	ap.add_argument("--model", default=MODEL)
	args = ap.parse_args()

	prompt, lay = SOURCES[args.variant]
	if args.check:
		ok, _ = preflight(args.check, lay["count"], lay["gap"], spin=lay["spin"])
		return 0 if ok else 1

	sys.path.insert(0, str(Path(__file__).resolve().parent))
	from gen_hero_strip import normalize_bg
	from gen_image_kodik import load_key, gen_once

	out = Path(args.out) if args.out else OUT_DIR / f"{args.variant}.png"
	out.parent.mkdir(parents=True, exist_ok=True)
	gen_once(load_key(), args.model, prompt, out, SIZE, args.seed, 1, None)
	n = normalize_bg(out)
	print(f"background normalization: {n} pixels repainted")
	print("preflight:")
	ok, _ = preflight(str(out), lay["count"], lay["gap"], spin=lay["spin"])
	return 0 if ok else 2


if __name__ == "__main__":
	sys.exit(main())
