#!/usr/bin/env python3
"""Stage 2: small map props (barrels, crates, lanterns, sacks) via seedream."""
import io
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from gen_image_kodik import load_key, gen_once, contact_sheet

BG = "flat solid pure magenta background color #FF00FF, no ground plane, no cast shadow"
STYLE = ("single small game prop sprite, 3/4 top-down view like classic isometric RPG "
         "town decorations, hand-painted 2D style, clean readable silhouette, "
         "no characters, no text, no other objects, one prop only")
PROMPTS = {
    "barrel": f"Wooden beer barrel with metal hoops, slightly worn, medieval tavern prop, {STYLE}, {BG}",
    "barrel_b": f"Stack of two wooden barrels with iron bands and a small wooden lid, {STYLE}, {BG}",
    "crate": f"Wooden shipping crate with planks and iron corners, merchant goods box, {STYLE}, {BG}",
    "crate_b": f"Stack of two wooden crates, one open with apples visible inside, {STYLE}, {BG}",
    "lantern": f"Iron street lantern post with warm glowing glass, medieval town lamp, {STYLE}, {BG}",
    "lantern_b": f"Hanging wooden and iron lantern on a short post, cozy warm light, {STYLE}, {BG}",
    "sack": f"Burlap grain sack tied with rope, slightly open with grain spilling, medieval market prop, {STYLE}, {BG}",
    "pot": f"Clay pot with green herbs growing, small medieval dwelling decoration, {STYLE}, {BG}",
}


def main() -> None:
    key = load_key()
    out_dir = Path(__file__).parent.parent / "import" / "_stage2_props"
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
                         out, "1024x1024", seed=3000 + hash(name) % 100,
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
