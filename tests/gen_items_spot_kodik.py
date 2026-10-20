#!/usr/bin/env python3
"""Точечная догенерация отсутствующих предметов (19.10, после аудита атласов).

6 картинок recraft-v4.1-flash (~$0.042): то, чего не хватает на атласах
после ручного разбора игрока и агента. Результаты в
import/items_atlas/<metal>/extra/<metal>_<name>.png

20.10: v2 - точечные правки после разбора игрока (перегенерируем ТОЛЬКО
битые предметы, атласы не трогаем): одиночные тяжёлые перчатки (пара
срасталась в кашу), золотые медальон/кольцо/лук с магента-кромкой.
Модель - google/gemini-nano-banana-2.1 (ming-image-0.1 ключу запрещён).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_image_kodik import load_key  # noqa: E402
from gen_items_atlas_kodik import OUT_ROOT, gen  # noqa: E402

STYLE = ("retro fantasy RPG game asset icon, pixel art, 32-bit era style, "
         "crisp pixel edges, dark tinted outline, light from upper left, "
         "flat solid magenta #FF00FF background, single item centered, "
         "no text, no shadow")

SPOT = [
    ("iron", "heavy_gloves",
     "single metal gauntlet, one glove only, hand armor made of plain iron, "
     "cool gray metal, simple rivets, fingers slightly curved"),
    ("gold", "heavy_gloves",
     "single metal gauntlet, one glove only, hand armor made of polished "
     "gold, rich yellow color, fine engraved trim, fingers slightly curved"),
    ("gold", "heavy_amulet",
     "round gold medallion amulet on a leather cord, polished gold, rich "
     "yellow color, engraved sun symbol, clean crisp edges"),
    ("gold", "heavy_ring",
     "large gold signet ring, polished gold, rich yellow color, engraved "
     "seal on the bezel, clean crisp edges"),
    ("gold", "bow",
     "wood recurve bow with gold-tipped limbs, strung bowstring, clean "
     "crisp edges, no magenta colors"),
]


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true",
                    help="перегенерировать существующие extra-файлы")
    ap.add_argument("--model", default="google/gemini-nano-banana-2.1")
    args = ap.parse_args()
    key = load_key()
    total = 0.0
    for metal, name, desc in SPOT:
        out = OUT_ROOT / metal / "extra" / ("%s_%s.png" % (metal, name))
        if out.exists() and not args.force:
            print("SKIP %s" % out.name)
            continue
        r = gen(key, args.model, desc + ". " + STYLE, out)
        try:
            total += float(str(r["cost"]).replace("$", ""))
        except ValueError:
            pass
    print("ИТОГО: $%.3f" % total)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
