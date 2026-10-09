#!/usr/bin/env python3
"""Stage 3: new trees/bushes/rocks replacing Allods art via seedream."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_image_kodik import load_key, gen_once, contact_sheet

BG = "flat solid pure magenta background color #FF00FF, no ground plane, no cast shadow"
STYLE = ("single small game nature sprite, 3/4 top-down view like classic isometric RPG "
         "map decorations, hand-painted 2D style, clean readable silhouette, "
         "no characters, no text, no other objects, one element only")
PROMPTS = {
    # grass biome trees
    "tree_oak": f"Full round deciduous oak tree with dense green canopy and brown trunk, "
                f"summer fantasy forest tree, {STYLE}, {BG}",
    "tree_oak2": f"Tall leafy maple tree with slightly red-tinged crown, sturdy trunk, "
                 f"fantasy RPG forest tree, {STYLE}, {BG}",
    "tree_pine": f"Pointed pine spruce tree with dark green needles, conical shape, "
                 f"fantasy forest evergreen, {STYLE}, {BG}",
    # soil biome
    "tree_birch": f"Slender birch tree with white bark and light green foliage, "
                  f"fantasy RPG tree, {STYLE}, {BG}",
    "tree_willow": f"Weeping willow tree with drooping branches near ground, "
                   f"mystical swamp-edge tree, {STYLE}, {BG}",
    "bush_berry": f"Round green bush with small red berries, forest undergrowth, "
                  f"{STYLE}, {BG}",
    # sand biome
    "palm": f"Single desert palm tree with curved trunk and fan fronds, "
            f"oasis palm, {STYLE}, {BG}",
    "cactus": f"Tall saguaro cactus with two arms, desert plant, "
              f"{STYLE}, {BG}",
    # mud / swamp
    "tree_dead": f"Dead bare tree with twisted grey branches no leaves, "
                 f"haunted swamp tree, {STYLE}, {BG}",
    "bush_thorn": f"Spiky thorny bramble bush with dark twisted branches, "
                  f"swamp undergrowth, {STYLE}, {BG}",
    # rocks (any biome)
    "rock": f"Single medium grey boulder with moss patches, fantasy RPG map rock, "
            f"{STYLE}, {BG}",
    "rock2": f"Cluster of two mossy stones different sizes, forest rock formation, "
             f"{STYLE}, {BG}",
}


def main() -> None:
    key = load_key()
    out_dir = Path(__file__).parent.parent / "import" / "_stage3_nature"
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for name, prompt in PROMPTS.items():
        out = out_dir / f"{name}.png"
        if out.exists():
            print(f"skip {out}")
            results.append({"model": "seedream", "out": str(out), "cost": 0, "sec": 0})
            continue
        try:
            r = gen_once(key, "bytedance-seed/seedream-5-0-flash", prompt,
                         out, "1024x1024", seed=4000 + hash(name) % 100,
                         n=1, extra=None)
            results.append(r)
        except SystemExit as e:
            print(f"FAIL {name}: {e}")
    ok = [r for r in results if Path(r["out"]).exists()]
    labels = [Path(r["out"]).stem for r in ok]
    paths = [Path(r["out"]) for r in ok]
    contact_sheet(paths, out_dir / "_sheet.png", labels=labels, cell=384)
    total = sum(float(r["cost"] or 0) for r in results)
    print(f"\ntotal cost: ${total:.3f}")
    print(f"sheet: {out_dir / '_sheet.png'}")


if __name__ == "__main__":
    main()
