#!/usr/bin/env python3
"""Stage 3: new trees/bushes/rocks replacing Allods art via seedream."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_image_kodik import load_key, gen_once, contact_sheet

BG = "flat solid pure magenta background color #FF00FF, no ground plane, no cast shadow"
# 10.10: ЗАПРЕТ НА ТОНКИЕ ЭЛЕМЕНТЫ. Проверено на Willow - нити свисающих ветвей
# тонкие и полупрозрачные, смешиваются с фоном, и после вырезания магенты
# остаётся до 0.55% крапа (в остальных деревьях и зданиях - 0%). Тонкое не
# режется чисто ни по цвету, ни по связности: края у него полупрозрачные.
# Просим крупные сплошные формы, а не « wispy / thin / wispy strands».
NO_THIN = ("solid chunky shapes, every element at least a few pixels thick, "
           "no thin wispy strands, no narrow ribbons, no fine filaments, "
           "no semi-transparent details, solid opaque foliage and limbs")
STYLE = ("single small game nature sprite, 3/4 top-down view like classic isometric RPG "
         "map decorations, hand-painted 2D style, clean readable silhouette, "
         f"{NO_THIN}, "
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
    "tree_willow": f"Weeping willow tree with a rounded full crown and only a few "
                   f"thick drooping limbs near ground, no long hanging strands, "
                   f"mystical swamp-edge tree, {STYLE}, {BG}",
    "bush_berry": f"Round green bush with small red berries, forest undergrowth, "
                  f"{STYLE}, {BG}",
    # sand biome
    "palm": f"Single desert palm tree with curved trunk and fan fronds, "
            f"oasis palm, {STYLE}, {BG}",
    "cactus": f"Tall saguaro cactus with two arms, desert plant, "
              f"{STYLE}, {BG}",
    # mud / swamp
    # 17.10: переделаны по просьбе игрока. Причина фиолетового измерена, а не
    # угадана: `tree_dead` вышел на 89% сине-фиолетовых пикселей, тогда как у
    # принятого дуба фиолетовых <1%, а розовых (тёплых) 10%. Виновник промта —
    # сочетание "twisted grey branches" + "haunted swamp tree": модель отрисовала
    # серый как фиолетовый. Слово `grey` убрано (серый берётся из тепла и земли,
    # а не из названия цвета), добавлен прямой запрет фиолетового и требование
    # совпасть по тону с дубом.
    "tree_dead": f"Dead bare tree, thick twisted branches with NO leaves, dry weathered "
                 f"warm grey-brown bark, sun-bleached pale tan wood, a few short broken "
                 f"stubs, natural forest deadfall, "
                 f"STRICTLY NO purple, NO violet, NO blue, NO magenta, NO glowing "
                 f"magic colour — bark is warm brown and pale tan only, "
                 f"same earthy brown palette as an oak tree, "
                 f"{STYLE}, {BG}",
    "bush_thorn": f"Spiky thorny bramble bush, thick dark brown woody branches with a few "
                  f"dry dull olive leaves, low tangled scrub, "
                  f"STRICTLY NO purple, NO violet, NO blue, NO magenta, "
                  f"brown and dull olive only, same earthy palette as an oak tree, "
                  f"{STYLE}, {BG}",
    # rocks (any biome)
    "rock": f"Single medium grey boulder with moss patches, fantasy RPG map rock, "
            f"{STYLE}, {BG}",
    "rock2": f"Cluster of two mossy stones different sizes, forest rock formation, "
             f"{STYLE}, {BG}",
}


def main() -> None:
    # 17.10: добавлен выбор объектов и модели. Скрипт по умолчанию ударил бы по
    # ВСЕМ 19 объектам, а нужно было два; модель и количество кандидатов —
    # решение игрока (по умолчанию тот же seedream, что и раньше).
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="объекты через запятую, пусто = все")
    ap.add_argument("--model", default="bytedance-seed/seedream-5-0-flash")
    ap.add_argument("--n", type=int, default=1, help="кандидатов на объект")
    ap.add_argument("--force", action="store_true", help="перегенерировать, даже если файл есть")
    args = ap.parse_args()

    key = load_key()
    out_dir = Path(__file__).parent.parent / "import" / "_stage3_nature"
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.only:
        wanted = [s.strip() for s in args.only.split(",") if s.strip()]
        unknown = [w for w in wanted if w not in PROMPTS]
        if unknown:
            raise SystemExit(f"нет таких объектов: {unknown}")
        prompts = {k: PROMPTS[k] for k in wanted}
    else:
        prompts = PROMPTS

    results = []
    for name, prompt in prompts.items():
        # При n>1 каждый кандидат пишется отдельным файлом: один промт с
        # несколькими кандидатами смешивается в коллаж, из которого потом
        # нельзя вырезать ни один нормальный спрайт.
        for i in range(args.n):
            suffix = "" if args.n == 1 else f"_c{i}"
            out = out_dir / f"{name}{suffix}.png"
            if out.exists() and not args.force:
                print(f"skip {out}")
                results.append({"model": args.model, "out": str(out), "cost": 0, "sec": 0})
                continue
            try:
                r = gen_once(key, args.model, prompt, out, "1024x1024",
                             seed=4000 + (hash(name) % 100) + i * 7,
                             n=1, extra=None)
                results.append(r)
            except SystemExit as e:
                print(f"FAIL {name}{suffix}: {e}")
    ok = [r for r in results if Path(r["out"]).exists()]
    labels = [Path(r["out"]).stem for r in ok]
    paths = [Path(r["out"]) for r in ok]
    contact_sheet(paths, out_dir / "_sheet.png", labels=labels, cell=384)
    total = sum(float(r["cost"] or 0) for r in results)
    print(f"\ntotal cost: ${total:.3f}")
    print(f"sheet: {out_dir / '_sheet.png'}")


if __name__ == "__main__":
    main()
