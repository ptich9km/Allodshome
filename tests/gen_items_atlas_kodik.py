#!/usr/bin/env python3
"""Генерация атласов оружия/брони для 3 металлов через KodikRouter (19.10).

Металлы: bronze (тир cheap), iron (common), gold (good). Сталь не генерируем -
она уже есть как base/base_w.

Раскладка АТЛАСА (решение игрока): 2 листа на металл вместо 39/42 одиночных
картинок:
  weapons sheet - 13 типов оружия, сетка 4x4 (13 ячеек + 3 пустые),
  armor sheet   - 14 предметов (light: head/chest/bracers/gloves/legs/ring/
                  amulet; heavy: те же 7), сетка 4x4 (14 ячеек).

Модель: ming-image-0.1 (free, решение игрока); при провале/style-FAIL -
recraft-v4.1-flash ($0.007/шт) через --model.

Промты соблюдают docs/art-direction-brief.md: пиксель-арт-иконка, тёмный
тонированный контур, свет слева-сверху, БЕЗ текста/подписей, фон однотонный
для кеинга.

Usage:
  python tests/gen_items_atlas_kodik.py                # 6 атласов ming (free)
  python tests/gen_items_atlas_kodik.py --dry-run      # только промты
  python tests/gen_items_atlas_kodik.py --only bronze  # один металл
  python tests/gen_image_kodik.py не вызываем напрямую - здесь свой цикл
"""
import argparse
import base64
import json
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_image_kodik import load_key, _req  # noqa: E402

OUT_ROOT = REPO / "import" / "items_atlas"

# Тир качества каждого металла (как в gen_faction_armor_tint: quality = tier).
METALS = {
    "bronze": {"tier": "cheap", "ru": "бронза", "desc":
        "polished bronze metal with warm orange-brown color, clean smooth "
        "surface, no patina, no corrosion, no dark spots"},
    "iron": {"tier": "common", "ru": "железо", "desc":
        "plain iron metal with cool gray steel color and simple rivets"},
    "gold": {"tier": "good", "ru": "золото", "desc":
        "polished gold metal with rich yellow color and fine engraved trim"},
}

WEAPONS = [
    "dagger", "one_handed_sword", "saber", "greatsword",
    "one_handed_axe", "two_handed_axe", "one_handed_mace", "two_handed_mace",
    "one_handed_spear", "two_handed_spear", "bow", "crossbow", "shield",
]

ARMOR = [
    "light_head", "light_chest", "light_bracers", "light_gloves",
    "light_legs", "light_ring", "light_amulet",
    "heavy_head", "heavy_chest", "heavy_bracers", "heavy_gloves",
    "heavy_legs", "heavy_ring", "heavy_amulet",
]

WEAPON_DESC = {
    "dagger": "short dagger", "one_handed_sword": "one-handed arming sword",
    "saber": "curved saber", "greatsword": "large two-handed greatsword",
    "one_handed_axe": "one-handed battle axe",
    "two_handed_axe": "great two-handed axe",
    "one_handed_mace": "one-handed mace",
    "two_handed_mace": "great two-handed mace",
    "one_handed_spear": "one-handed short spear",
    "two_handed_spear": "long pike spear",
    "bow": "wood recurve bow", "crossbow": "crossbow",
    "shield": "round wooden shield with metal boss",
}

ARMOR_DESC = {
    "light_head": "padded leather cap", "light_chest": "quilted leather vest",
    "light_bracers": "leather arm bracers", "light_gloves": "leather gloves",
    "light_legs": "leather trousers", "light_ring": "small ring",
    "light_amulet": "small amulet on cord",
    "heavy_head": "full metal helmet", "heavy_chest": "plate cuirass",
    "heavy_bracers": "metal vambraces", "heavy_gloves": "metal gauntlets",
    "heavy_legs": "plate greaves", "heavy_ring": "metal signet ring",
    "heavy_amulet": "metal medallion amulet",
}

STYLE = (
    "Game asset icon sheet, retro fantasy RPG pixel art, 32-bit era style, "
    "crisp pixel edges, dark tinted outline (not pure black), light from "
    "upper left, flat solid magenta #FF00FF background, items laid out in a "
    "neat regular GRID with equal spacing, each item centered in its grid "
    "cell, item fully inside its cell, no text, no labels, no numbers, "
    "no borders between cells, no shadows outside items"
)

STRICT = (
    "IMPORTANT: every item is entirely inside its own grid cell and does "
    "not touch the cell borders; never draw an item across two cells; "
    "cells without an item are completely empty plain magenta background.")


def weapons_prompt(metal: str, info: dict) -> str:
    lines = [f"{WEAPON_DESC[w]} made of {info['desc']}" for w in WEAPONS]
    return (f"4x4 grid sheet with exactly {len(WEAPONS)} icons, one per cell, "
            f"reading order left to right top to bottom: " + "; ".join(lines)
            + ". " + STYLE)


def armor_prompt(metal: str, info: dict) -> str:
    lines = [f"{ARMOR_DESC[a]} with {info['desc']} accents" for a in ARMOR]
    return (f"4x4 grid sheet with exactly {len(ARMOR)} icons, one per cell, "
            f"reading order left to right top to bottom: " + "; ".join(lines)
            + ". " + STYLE)


def gen(key: str, model: str, prompt: str, out: Path) -> dict:
    body = {"model": model, "prompt": prompt, "n": 1,
            "response_format": "b64_json", "size": "1024x1024"}
    t0 = time.time()
    resp = _req("POST", "/images", body, key, timeout=600)
    dt = time.time() - t0
    data = resp.get("data", [])
    if not data or not data[0].get("b64_json"):
        raise RuntimeError("no b64_json: %s" % json.dumps(resp)[:300])
    raw = base64.b64decode(data[0]["b64_json"])
    if raw[:3] == b"\xff\xd8\xff":
        import io
        from PIL import Image
        img = Image.open(io.BytesIO(raw))
        buf = io.BytesIO()
        img.save(buf, "PNG")
        raw = buf.getvalue()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(raw)
    usage = resp.get("usage", {})
    print("OK  %-52s %4d KB %5.1fs cost=%s" % (
        out.name, len(raw) // 1024, dt, usage.get("cost", "?")))
    return {"out": str(out), "cost": usage.get("cost", "?"), "sec": round(dt, 1)}


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model", default="inclusionai/ming-image-0.1")
    ap.add_argument("--only", default="", help="bronze|iron|gold")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    key = load_key()
    results = []
    for metal, info in METALS.items():
        if args.only and metal != args.only:
            continue
        for kind, prompt_fn in (("weapons", weapons_prompt), ("armor", armor_prompt)):
            out = OUT_ROOT / metal / ("%s_%s.png" % (metal, kind))
            prompt = prompt_fn(metal, info)
            if args.strict:
                prompt += " " + STRICT
            if args.dry_run:
                print("--- %s %s ---\n%s\n" % (metal, kind, prompt))
                continue
            if out.exists() and not args.force:
                print("SKIP %s (есть)" % out.name)
                continue
            try:
                results.append(gen(key, args.model, prompt, out))
            except Exception as e:
                print("FAIL %s %s: %s" % (metal, kind, e))
    if results:
        (OUT_ROOT / "summary.json").write_text(
            json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
