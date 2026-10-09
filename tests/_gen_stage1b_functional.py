#!/usr/bin/env python3
"""Stage 1b: regenerate functional buildings (replacing Alice art) via seedream."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_image_kodik import load_key, gen_once, contact_sheet

BG = "flat solid pure magenta background color #FF00FF, no ground plane, no cast shadow"
STYLE = ("game building sprite, single isolated building, 3/4 top-down view "
         "like classic isometric RPG town buildings, hand-painted 2D style, "
         "clean readable silhouette, no characters, no readable text, no other objects")
PROMPTS = {
    "shop": f"Medieval fantasy trade shop building, timber-framed walls, striped fabric awning "
            f"over a small goods stall with crates and sacks, hanging scale sign, "
            f"warm merchant town building, {STYLE}, {BG}",
    "inn": f"Medieval fantasy tavern inn, timber-framed two story building, tiled roof, "
           f"wooden sign with hanging tankard mug, warm glowing windows, chimney with smoke, "
           f"bench and barrel near entrance, {STYLE}, {BG}",
    "blacksmith": f"Medieval fantasy blacksmith forge, stone chimney with smoke, "
                  f"open workshop bay with glowing forge inside, anvil outside under small roof, "
                  f"weapons rack on wall, sooty timber and stone walls, {STYLE}, {BG}",
    "train": f"Medieval fantasy training hall school building, sturdy stone and timber walls, "
             f"sparring dummy and weapon rack near door, shield signs on wall, "
             f"banner, martial academy building, {STYLE}, {BG}",
    "alchemy": f"Medieval fantasy herbalist apothecary shop, living wood and wattle walls, "
               f"sod roof with herbs and flowers, hanging dried herb bundles, "
               f"glass bottles in window, small cauldron sign, mystical nature shop, {STYLE}, {BG}",
    "house": f"Medieval fantasy commoner house, half-timbered walls, clay tile roof, "
             f"small garden fence with flowers, chimney, modest town dwelling, {STYLE}, {BG}",
    "barracks": f"Medieval fantasy town guard barracks, solid stone lower floor timber upper, "
                f"spear rack and shield by door, small watch platform on roof, "
                f"militia garrison building, {STYLE}, {BG}",
}


def main() -> None:
    key = load_key()
    out_dir = Path(__file__).parent.parent / "import" / "_stage1b_functional"
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for name, prompt in PROMPTS.items():
        for v in (1, 2):
            out = out_dir / f"{name}_v{v}.png"
            if out.exists():
                print(f"skip {out}")
                results.append({"model": "seedream", "out": str(out), "cost": 0, "sec": 0})
                continue
            try:
                r = gen_once(key, "bytedance-seed/seedream-5-0-flash", prompt,
                             out, "1024x1024", seed=2000 + v * 31 + hash(name) % 100,
                             n=1, extra=None)
                results.append(r)
            except SystemExit as e:
                print(f"FAIL {name}_v{v}: {e}")
    ok = [r for r in results if Path(r["out"]).exists()]
    labels = [Path(r["out"]).stem for r in ok]
    paths = [Path(r["out"]) for r in ok]
    contact_sheet(paths, out_dir / "_sheet.png", labels=labels, cell=384)
    total = sum(float(r["cost"] or 0) for r in results)
    print(f"\ntotal cost: ${total:.3f}")
    print(f"sheet: {out_dir / '_sheet.png'}")


if __name__ == "__main__":
    main()
