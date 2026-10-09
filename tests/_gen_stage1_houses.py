#!/usr/bin/env python3
"""Batch generate race houses via KodikRouter seedream. Stage 1 review sheet."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_image_kodik import load_key, gen_once, contact_sheet

BG = "flat solid pure magenta background color #FF00FF, no ground plane, no cast shadow"
STYLE = ("game building sprite, single isolated building, 3/4 top-down view "
         "like classic isometric RPG town buildings, hand-painted 2D style, "
         "clean readable silhouette, no characters, no text, no signage text, no other objects")
PROMPTS = {
    "ork_a": f"Crude orcish warren house built from rough dark timber and beast hides, "
             f"jagged uneven roof with bone and horn decorations, leather flaps as door, "
             f"warlike tribal settlement building, {STYLE}, {BG}",
    "ork_b": f"Orcish chieftain hut, heavy logs and stone foundation, tusks and skulls "
             f"mounted above entrance, smoky chimney, tattered banners, "
             f"brutal tribal architecture, {STYLE}, {BG}",
    "decor_ork": f"Small orcish camp structure, watchtower of rough wood with hide canopy "
                 f"and spear stakes, tribal decoration, {STYLE}, {BG}",
    "druid_a": f"Druid woodland cottage grown from a living tree with thatched mossy roof, "
               f"round wooden door, vines and leaves, glowing runes on wood, "
               f"nature circle sanctuary, {STYLE}, {BG}",
    "druid_b": f"Druid herbalist hut, wattle-and-daub walls, thick sod roof with flowers, "
               f"herb bundles hanging, standing stones at corners, mystical forest dwelling, "
               f"{STYLE}, {BG}",
    "decor_druid": f"Small druidic shrine, standing stones with carved runes and moss, "
                   f"small altar with offering bowl, forest ritual site, {STYLE}, {BG}",
    "necro_a": f"Undead crypt mausoleum of grey cracked stone, bone decorations, "
               f"iron-bound door, faint cold purple glow from windows, crow statues, "
               f"grim necropolis building, {STYLE}, {BG}",
    "necro_b": f"Gravekeeper hut beside a small open grave, rotting dark wood, "
               f"sculls and dried herbs, crooked fence with bones, eerie pale lantern, "
               f"death cult dwelling, {STYLE}, {BG}",
    "decor_necro": f"Small broken crypt entrance with bone piles and dead tree, "
                   f"ravens perched, cold mist at base, graveyard decoration, {STYLE}, {BG}",
}


def main() -> None:
    key = load_key()
    out_dir = Path(__file__).parent.parent / "import" / "_stage1_houses"
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for name, prompt in PROMPTS.items():
        for v in (1, 2):
            out = out_dir / f"{name}_v{v}.png"
            if out.exists():
                print(f"skip {out}")
                results.append({"model": "seedream-5-0-flash", "out": str(out),
                                "cost": 0, "sec": 0})
                continue
            try:
                r = gen_once(key, "bytedance-seed/seedream-5-0-flash", prompt,
                             out, "1024x1024", seed=1000 + v * 17 + hash(name) % 100,
                             n=1, extra=None)
                results.append(r)
            except SystemExit as e:
                print(f"FAIL {name}_v{v}: {e}")
    labels = [Path(r["out"]).stem for r in results if Path(r["out"]).exists()]
    paths = [Path(r["out"]) for r in results if Path(r["out"]).exists()]
    contact_sheet(paths, out_dir / "_sheet.png", labels=labels, cell=384)
    total = sum(float(r["cost"] or 0) for r in results)
    print(f"\ntotal cost: ${total:.3f}")
    print(f"sheet: {out_dir / '_sheet.png'}")


if __name__ == "__main__":
    main()
