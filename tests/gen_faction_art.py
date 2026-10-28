#!/usr/bin/env python3
"""Генерация листов арта для фракционной брони и бирок (KodikRouter).

ПУТЬ ПРОВЕРЕН НА АТЛАСЕ БРОНИ: одна картинка = раскладка предметов в ряд,
потом нарезка на отдельные иконки. Здесь 9 запросов:

  8 листов брони — по одному на набор (4 фракции × тяжёлый/лёгкий),
  в каждом 4 предмета в ряд: шлем, нагрудник, наручи, сапоги;
  1 лист бирок — 4 бирки в ряд.

Стиль — как у атласа `import/ChatGPTArmor1.png` (painted inventory icons,
мягкий студийный свет), но фон МАГЕНТНЫЙ: на белом фоне сталь не откеить
(правило 10.10: генерация на плоской магенте 255,0,255).

Листы кладутся в import/faction_art/ (не в assets: сначала визуальная
проверка игроком, нарезка — отдельным скриптом extract_faction_art.py).

Запуск:
  python tests/gen_faction_art.py --dry-run
  python tests/gen_faction_art.py --only humans:heavy
  python tests/gen_faction_art.py --all
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_image_kodik import gen_once, load_key  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "import" / "faction_art"
MANIFEST = OUT_DIR / "_manifest.json"

# Проверенная на героях модель: держит «несколько отдельных объектов в ряд»
# и не сваливает их в кучу.
MODEL = "google/gemini-nano-banana-2.1"
SIZE = "1536x1024"

FACTIONS = {
    "humans": "the Alliance of Light: polished silver-blue steel, royal blue cloth "
              "accents, a small golden eagle emblem",
    "ork": "the Fire Hordes: brutal dark iron, rust-red cloth accents, jagged "
           "edges, a small fang emblem",
    "necro": "the Reapers: blackened steel with pale bone trim, cold violet cloth, "
             "a faint green glow, a small skull emblem",
    "druid": "the Circle of Druids: weathered bronze and dark leather, deep green "
             "cloth accents, leaf motifs",
}

KITS = {
    "heavy": ("HEAVY PLATE ARMOR for a warrior: (1) a full plate helmet, "
              "(2) a plate cuirass, (3) ONE single plate bracer (one arm piece "
              "only, not a pair), (4) ONE pair of armoured boots standing together"),
    "light": ("LIGHT LEATHER ARMOR for a mage: (1) a leather hood, "
              "(2) a studded leather scale cuirass, (3) ONE single leather "
              "bracer (one arm piece only, not a pair), (4) ONE pair of "
              "leather boots standing together"),
    "magic": ("MAGIC CLOTH ROBES for a mage: (1) a tall pointed wizard hat, "
              "(2) a long flowing robe with a wide decorated hem, (3) ONE single "
              "cloth bracer (one arm piece only, not a pair), (4) ONE pair of "
              "cloth shoes standing together"),
}

## Магический комплект: у каждой фракции своя школа, но крой общий (мантия).
MAGIC_STYLES = {
    "humans": "the Alliance of Light: arcane blue silk with golden rune "
              "embroidery and a small golden eagle emblem",
    "ork": "the Fire Hordes: shamanic cloth in rust-red and charcoal, bone "
           "charms, a small fang emblem",
    "necro": "the Reapers: funeral violet silk with pale bone trim, faint green "
             "runes, a small skull emblem",
    "druid": "the Circle of Druids: deep green woven cloth with bronze leaf "
             "embroidery and a small leaf emblem",
}

COMMON = """
Four separate objects in ONE horizontal row, left to right, evenly spaced, all at
the same scale, each drawn in FRONT view as a single standalone inventory icon.
Painted style of a high-end fantasy RPG inventory: soft studio light from the
upper left, clean dark outline, 3-4 value planes, rich but restrained palette,
sharp readable silhouette. Each object is a piece of equipment only - no person,
no mannequin, no hands, no body inside it.

SIZE: each object takes about one quarter of the image width. The gaps between
neighbouring objects are pure background, at least 80 pixels wide; NOTHING of any
kind may cross those gaps. Keep at least 40 pixels of pure background on ALL four
sides of the image - no object may touch or be cut by the border.

Background: one single flat vivid magenta (255, 0, 255), perfectly uniform
everywhere. No gradient, no vignette, no texture.

ABSOLUTELY NO ground, no floor line, no cast shadow, no contact shadow, no
reflection, no pedestal, no frame, no grid, no panel, no ruler.

EXCLUDE: text, letters, numbers, captions, labels, watermark, signature,
duplicate objects, weapons, scenery.
"""


def armor_prompt(race: str, kit: str) -> str:
    style = MAGIC_STYLES[race] if kit == "magic" else FACTIONS[race]
    return ("A clean high-resolution game asset sheet with four pieces of %s.\n"
            "Faction style: %s.\n%s\n"
            "Order left to right is fixed: headwear, body garment, bracer, shoes."
            % (KITS[kit], style, COMMON))


def tags_prompt() -> str:
    return """A clean high-resolution game asset sheet with FOUR metal dog-tag
trophies in one horizontal row, left to right:
(1) a polished silver-blue tag with a simple stamped eagle silhouette,
(2) a rusted dark-iron tag with a stamped fang silhouette,
(3) a blackened violet tag with a stamped skull silhouette,
(4) a green-bronze tag with a stamped leaf silhouette.
Each tag is a flat metal plate with a punched hole and a short piece of chain,
slightly weathered and scratched, painted as a fantasy RPG trophy icon.

The stamped shapes are SILHOUETTES ONLY - absolutely no letters, no words,
no numbers, no engraved text on any tag.
""" + COMMON


def sheet_id(race: str, kit: str) -> str:
    return "faction_%s_%s" % (race, kit)


def load_manifest() -> dict:
    if MANIFEST.exists():
        try:
            return json.loads(MANIFEST.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
    return {}


def save_manifest(data: dict) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(data, indent=1, ensure_ascii=False),
                        encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="humans:heavy или tags")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="перегенерировать готовые листы")
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--seed", type=int, default=None)
    args = ap.parse_args()

    jobs = [(race, kit) for race in FACTIONS for kit in KITS] + [("tags", "")]
    if args.only:
        if args.only != "tags":
            race, _, kit = args.only.partition(":")
            if race not in FACTIONS or kit not in KITS:
                print("неизвестный набор %r (пример: humans:heavy, tags)" % args.only)
                return 2
            selected = [(race, kit)]
        else:
            selected = [("tags", "")]
    else:
        selected = jobs

    if args.dry_run:
        print("будет сгенерировано листов: %d" % len(selected))
        for race, kit in selected:
            name = "tags" if race == "tags" else sheet_id(race, kit)
            prompt = tags_prompt() if race == "tags" else armor_prompt(race, kit)
            print("  %-28s %d символов промта" % (name, len(prompt)))
        return 0

    key = load_key()
    manifest = load_manifest()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total_cost = 0.0
    for race, kit in selected:
        name = "tags" if race == "tags" else sheet_id(race, kit)
        out = OUT_DIR / (name + ".png")
        prompt = tags_prompt() if race == "tags" else armor_prompt(race, kit)
        print("--- %s ---" % name)
        # Повторные запуски не тратят деньги: уже готовый лист пропускаем.
        if out.exists() and not args.force:
            print("уже есть: %s (пропуск; --force перегенерирует)" % out.name)
            continue
        t0 = time.time()
        res = gen_once(key, args.model, prompt, out, SIZE, args.seed, 1, None)
        manifest[name] = {
            "file": out.name, "model": args.model, "size": SIZE,
            "seed": args.seed, "prompt": prompt,
            "cost": res.get("cost"), "sec": res.get("sec"),
            "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
            "approved": False,
        }
        save_manifest(manifest)
        try:
            total_cost += float(res.get("cost", 0) or 0)
        except (TypeError, ValueError):
            pass
        print("    %.0f c, стоимость %s" % (time.time() - t0, res.get("cost")))
    print("готово, суммарная стоимость по ответам API: $%.4f" % total_cost)
    print("проверь листы в %s, потом режем extract_faction_art.py" % OUT_DIR)
    return 0


if __name__ == "__main__":
    sys.exit(main())
