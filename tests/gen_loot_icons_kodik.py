#!/usr/bin/env python3
"""Дроп-иконки (видна на земле при выпадении из НПЦ) для 3 металлов (20.10).

Отличие от gen_items_atlas_kodik.py (иконки инвентаря): здесь предмет лежит
НА ЗЕМЛЕ, вид чуть сверху (как в игре смотрит герой), читаемый силуэт.
Раскладка и карты ячеек - те же, что у инвентарных атласов, поэтому нарезка
идёт тем же slice_items_atlas.py (импорт WEAPON_MAP/ARMOR_MAP/slice_sheet).

Usage:
  python tests/gen_loot_icons_kodik.py                # 6 листов
  python tests/gen_loot_icons_kodik.py --only bronze  # один металл
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_items_atlas_kodik as G  # noqa: E402
from gen_image_kodik import load_key  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
OUT_ROOT = REPO / "import" / "loot_icons"

GROUND_STYLE = (
    "Sprite sheet for game, retro fantasy RPG pixel art dropped loot icons, "
    "32-bit era style, crisp pixel edges, dark tinted outline (not pure "
    "black), light from upper left, each item LYING FLAT ON THE GROUND as "
    "if dropped by a defeated monster, slight top-down three-quarter view, "
    "flat solid magenta #FF00FF background, items laid out in a neat "
    "regular GRID with equal spacing, each item centered in its grid cell, "
    "item fully inside its cell, no small details, no ribbons, no banners, "
    "no straps, no text, no labels, no numbers, no shadows outside items"
)


def loot_prompt(metal: str, info: dict, kind: str) -> str:
    if kind == "weapons":
        lines = [f"{G.WEAPON_DESC[w]} made of {info['desc']}" for w in G.WEAPONS]
        n = len(G.WEAPONS)
    else:
        lines = [f"{G.ARMOR_DESC[a]} with {info['desc']} accents" for a in G.ARMOR]
        n = len(G.ARMOR)
    return (f"4x4 grid sheet with exactly {n} icons, one per cell, "
            f"reading order left to right top to bottom: " + "; ".join(lines)
            + ". " + GROUND_STYLE)


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model", default="google/gemini-nano-banana-2.1")
    ap.add_argument("--only", default="", help="bronze|iron|gold")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    key = load_key()
    results = []
    for metal, info in G.METALS.items():
        if args.only and metal != args.only:
            continue
        for kind in ("weapons", "armor"):
            out = OUT_ROOT / metal / ("%s_%s.png" % (metal, kind))
            prompt = loot_prompt(metal, info, kind)
            if args.dry_run:
                print("--- %s %s ---\n%s\n" % (metal, kind, prompt))
                continue
            if out.exists() and not args.force:
                print("SKIP %s (есть)" % out.name)
                continue
            try:
                results.append(G.gen(key, args.model, prompt, out))
            except Exception as e:
                print("FAIL %s %s: %s" % (metal, kind, e))
    if results:
        import json
        (OUT_ROOT / "summary.json").write_text(
            json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
