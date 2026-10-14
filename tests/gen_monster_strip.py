#!/usr/bin/env python3
"""Генерация ИИ-полосы ЗВЕРЯ (волк, белка, пчела, динозавр), 4 панели.

Зачем отдельный скрипт, а не ещё один пресет в gen_hero_strip.py: промт героя
написан про человека (плечи, таз, кираса), и подставить туда зверя нельзя —
те же слова модель применит к морде и лапе. Общее у них ровно три вещи, и
они импортируются, а не копируются: разметка панелей, preflight и разрез.

Конвейер тот же (см. gen_hero_strip.py):
  1. ПРАВИМ ПРОМТ, а не режем картинку.
  2. Сначала ОДНА полоса (обычно stand) — самая дешёвая проверка вида.
  3. Смотрим превью и СРАЗУ гоняем preflight по тому же файлу.
  4. Только после «ГОДЕН» добираем остальные полосы и собираем набор.

ФАЗЫ ЗВЕРЯ (игрок, 15.10): стоит, бежит, кусает, ложится на бок умирает.

Запуск:
  python tests/gen_monster_strip.py wolf stand --panels 4
  python tests/gen_monster_strip.py wolf stand --check import/Monsters/wolf_stand_m1.png --panels 4
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_hero_strip import LAYOUT4, preflight  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "import" / "Monsters"

# Модель бесплатная ($0), поэтому на ней можно проверять вид без денег.
MODEL = "inclusionai/ming-image-0.1-design"
SIZE = "1536x1024"

# Ракурс. Для зверя профиль — не брак, а нормальный вид, но карта читается
# только в трёх четвертях: в профиле не видно груди и не видно дальней ноги.
VIEW = ("THREE-QUARTER VIEW: the whole body is turned about 30 degrees towards the "
        "viewer, so the chest, both front legs and the far side of the head are "
        "visible. It still clearly reads as facing RIGHT: the muzzle, the chest "
        "and the toes point to the right and NOT towards the viewer.")

# Пропорции. Для человека порог толщины 0.36, у зверя своя анатомия:
# собака в три четверти шире, чем выше (w/h около 0.9-1.3), и это норма.
PROPORTIONS = """ANIMAL BODY PROPORTIONS - this matters as much as the pose:
- a full-grown adult animal, heavy and powerful, NOT a thin or starving one
- thick neck, broad chest, strong shoulders, heavy muscled legs
- the body outline is clearly WIDER than a standing person of the same height
- solid paws, solid tail, the body is a filled shape with no gaps
- do NOT draw it scrawny, skinny, thin, gaunt, lanky or stick-like"""

MONSTERS = {
    "wolf": {
        "name": "a huge grey-brown dire wolf",
        "detail": ("thick dark fur along the spine, a long heavy bushy tail held "
                   "low, pale yellow eyes, bared yellow teeth in a closed mouth, "
                   "a broad muzzle"),
    },
    "squirrel": {
        "name": "a huge dark brown squirrel beast",
        "detail": ("a squirrel shape scaled up to the size of a large dog, long "
                   "sharp claws on the front paws, big bushy tail arched over "
                   "the back, huge front teeth, small mean eyes"),
    },
    "bee": {
        "name": "a huge armored hornet the size of a horse",
        "detail": ("black and yellow chitin plates, six legs, two transparent "
                   "wings, a long sharp stinging stinger, big compound eyes"),
    },
    "dino": {
        "name": "a huge brown-green raptor dinosaur",
        "detail": ("thick scaled legs, small forearms with long claws, a long "
                   "heavy tail held low, a heavy head with sharp teeth, a row of "
                   "spikes along the spine"),
    },
}

ANIMS = {
    # Стоит: одна поза, как у геройской стойки — самый дешёвый тест вида.
    "stand": """AN IDLE STANCE, 4 panels left to right in one row.
Panel 1: standing still on all four legs, head up, weight evenly on its legs,
tail low, calm but alert.
Panels 2, 3 and 4: the exact same standing pose with only a tiny breathing
difference in the rise of its chest. It does not move its feet at all.
""",

    # Бежит: 4 фазы цикла, как у человека.
    "run": """A GALLOPING RUN, 4 panels left to right in one row.
Panel 1 CONTACT: the front legs stretched forward and the back legs stretched
far behind, legs at their widest apart, body low and horizontal.
Panel 2 DOWN: the body sinks to its lowest point, the front legs under the chest,
the back legs gathered under the belly.
Panel 3 PASSING: the back legs swing forward and pass beside the front legs, the
legs are gathered TOGETHER, the body at its highest.
Panel 4 PUSH OFF: it stretches out again, the back legs trailing behind, the
front legs reaching forward.
The 4 panels must show 4 clearly different leg positions, each about a quarter of
a gallop apart. It does NOT rear up on its hind legs.
""",

    # Кусает: замах, выпад, укус, возврат — третий кадр закрывает цикл.
    "attack": """A BITE, 4 panels left to right in one row.
Panel 1: standing still, head forward, mouth closed, alert.
Panel 2: the head pulled back and slightly up, mouth wide open, jaws spread,
teeth bared.
Panel 3: the head lunged forward and DOWN, mouth wide open, biting at the air.
Panel 4: the same open mouth biting, just a touch further down.
It NEVER lies down during the bite, its legs stay planted.
""",

    # Смерть: ложится на бок. Именно на бок — не на спину, не на пузо.
    "die": """A FALL TO THE SIDE, 4 panels left to right in one row.
Panel 1: standing on all four legs, head up, still alert.
Panel 2: staggering, its front legs buckle, the whole body tilting sideways.
Panel 3: falling over sideways, the shoulder and the hip touching the ground.
Panel 4: lying flat on its SIDE on the ground, legs stretched out, eyes closed,
head resting on the ground. It NEVER lies on its back and NEVER on its belly.
""",
}


def build_prompt(monster: str, anim: str) -> str:
    spec = MONSTERS[monster]
    character = (f"ONE single animal repeated in every panel: {spec['name']}, "
                 f"{spec['detail']}. Same individual animal in every panel.")
    return (f"{character}\n\n{PROPORTIONS}\n\n{VIEW}\n\n{ANIMS[anim]}\n\n{LAYOUT4}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("monster", choices=sorted(MONSTERS))
    ap.add_argument("anim", choices=sorted(ANIMS))
    ap.add_argument("--out", default="")
    ap.add_argument("--check", default="")
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--panels", type=int, default=4, choices=(4, 8))
    ap.add_argument("--seed", type=int, default=20261015)
    args = ap.parse_args()

    if args.check:
        ok, _ = preflight(args.check, expect=args.panels, min_gap=40)
        return 0 if ok else 2

    from gen_image_kodik import gen_once, load_key

    out = Path(args.out) if args.out else \
        OUT_DIR / f"{args.monster}_{args.anim}_m1.png"
    gen_once(load_key(), args.model, build_prompt(args.monster, args.anim),
             out, SIZE, args.seed, 1, None)
    print("предполётная проверка:")
    ok, _ = preflight(str(out), expect=args.panels, min_gap=40)
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())