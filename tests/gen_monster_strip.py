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
        "move": "run", "attack": "bite",
    },
    "squirrel": {
        "name": "a huge dark brown squirrel beast",
        "detail": ("a squirrel shape scaled up to the size of a large dog, long "
                   "sharp claws on the front paws, big bushy tail arched over "
                   "the back, huge front teeth, small mean eyes"),
        "move": "run", "attack": "bite",
    },
    "bee": {
        "name": "a huge armored hornet the size of a horse",
        "detail": ("black and yellow chitin plates, six legs, two transparent "
                   "wings, a long sharp stinging stinger, big compound eyes"),
        "move": "fly", "attack": "sting",
    },
    "dino": {
        "name": "a huge brown-green raptor dinosaur",
        "detail": ("thick scaled legs, small forearms with long claws, a long "
                   "heavy tail held low, a heavy head with sharp teeth, a row of "
                   "spikes along the spine"),
        "move": "run", "attack": "bite",
    },
    # --- добавлены 15.10 по списку игрока ---
    "bat": {
        "name": "a huge grey-black monstrous bat",
        "detail": ("wide leathery wings with visible finger bones and torn edges, "
                   "hairy brown fur on the chest, large pointed ears, wide open "
                   "mouth with small sharp teeth, hooked claws"),
        "move": "fly", "attack": "bite",
    },
    "dragon": {
        "name": "a huge dark green dragon",
        "detail": ("thick scaled hide, large bat-like wings folded at the sides, a "
                   "long heavy tail, a broad horned head, glowing orange slit "
                   "eyes, sharp teeth"),
        "move": "fly", "attack": "breath",
    },
    "ghost": {
        "name": "a huge pale ghostly spectre",
        "detail": ("a translucent glowing white-blue vapour shaped like a hunched "
                   "humanoid, hollow black eye sockets, long wispy arms, the lower "
                   "body trailing off into ragged smoke instead of legs, and "
                   "NO WINGS of any kind"),
        "move": "hover", "attack": "cast",
    },
    "succubus": {
        "name": "a tall beautiful dark-skinned demon woman",
        "detail": ("long curved black horns, wide membranous bat wings, black "
                   "hooves instead of feet, a long barbed tail, glowing yellow "
                   "eyes, dark hair, wearing dark leather armour"),
        "move": "fly", "attack": "cast",
    },
}

# Фаза «идёт или летит». Игрок, 15.10: стоит, идёт или летит, атакует, заваливается
# набок. Раньше был один галоп на всех — но летящим зверям галоп по земле
# рисовать бессмысленно, поэтому движение разведено по виду.
ANIM_MOVE = {
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
    "fly": """A FLIGHT, 4 panels left to right in one row, seen in mid air with clear
empty background all around the body and no ground under it.
Panel 1: the wings are fully spread open and level, body gliding forward.
Panel 2: the wings beat DOWN, the wing tips below the body, the body sinking.
Panel 3: the wings are folded halfway up at the top of the beat, body at its
highest point.
Panel 4: the wings are spread wide open again at the start of the next beat.
The 4 panels must show 4 clearly different wing positions. Its legs hang relaxed
below the body and barely move, the flying is done with the wings.
""",
    # Для тех, у кого крыльев НЕТ. Общий текст полёта говорит «взмах крыльев»,
    # и призрак отрастил себе крылья, которых в описании не было (15.10):
    # контактные листы показали ангела с белыми крыльями вместо бесногого
    # парящего силуэта.
    "hover": """A HOVERING DRIFT, 4 panels left to right in one row, seen in mid air with
clear empty background all around the body and NO ground under it.
Panel 1: the body glides forward level, the trailing smoke streaming out behind.
Panel 2: the body sinks slightly, the smoke streaming behind gets longer and
thinner, the arms drift downwards.
Panel 3: the body rises to its highest point, the smoke gathers up around it, the
arms drift upwards.
Panel 4: the body glides forward level again at the start of the next drift.
The 4 panels must show 4 clearly different heights of the body. It has NO wings
at all - it moves by floating and drifting, its lower body trailing off into
ragged smoke. Do NOT give it wings.
""",
}

# Фаза атаки — по виду. Игрок, 15.10: обычно кусает, но дракон и суккуб маги.
# Раньше был один текст на всех, и магу пришлось бы изображать кусание лапой.
ANIM_ATTACK = {
    "bite": """A BITE, 4 panels left to right in one row.
Panel 1: standing still, head forward, mouth closed, alert.
Panel 2: the head pulled back and slightly up, mouth wide open, jaws spread,
teeth bared.
Panel 3: the head lunged forward and DOWN, mouth wide open, biting at the air.
Panel 4: the same open mouth biting, just a touch further down.
It NEVER lies down during the bite, its legs stay planted.
""",
    "sting": """A STING, 4 panels left to right in one row.
Panel 1: hovering in place, body still, the stinger held back under the tail.
Panel 2: the whole body arches up and back, the stinger raised and aimed forward,
wings beating hard.
Panel 3: the body drives forward and DOWN, the stinger thrust straight ahead,
wings swept back.
Panel 4: the same thrust a touch further forward, wings starting to reopen.
It NEVER lies down during the sting, it keeps hovering.
""",
    "breath": """A BREATH OF FIRE, 4 panels left to right in one row.
Panel 1: standing its ground, head lowered, mouth closed, a dull glow building
inside its throat.
Panel 2: the head raised high, mouth wide open, the throat now a bright orange
glow.
Panel 3: the head thrust forward and DOWN, a burst of orange fire pouring out of
the open mouth into the air.
Panel 4: the same forward pour of fire, a little further along and weaker.
It NEVER lies down during the attack, it keeps its wings and body steady.
""",
    "cast": """A CASTING SPELL, 4 panels left to right in one row.
Panel 1: hovering or standing still, arms lowered, a faint glow between the hands.
Panel 2: both arms raised high above the head, the glow between the hands bright.
Panel 3: both arms thrust forward and DOWN, a bright bolt or burst of light
leaving the hands.
Panel 4: the same bolt a little further along, the arms still extended.
It NEVER lies down during the cast, its body stays upright in the air.
""",
}

# Фаза смерти (игрок, 15.10): заваливается набок. Раньше текст был один и
# описывал падение с ног, что для летящих и беспногих выглядит неверно.
ANIM_DIE = {
    "run": """A FALL TO THE SIDE, 4 panels left to right in one row.
Panel 1: standing on all four legs, head up, still alert.
Panel 2: staggering, its front legs buckle, the whole body tilting sideways.
Panel 3: falling over sideways, the shoulder and the hip touching the ground.
Panel 4: lying flat on its SIDE on the ground, legs stretched out, eyes closed,
head resting on the ground. It NEVER lies on its back and NEVER on its belly.
""",
    "fly": """A FALL TO THE SIDE, 4 panels left to right in one row.
Panel 1: hovering upright, wings spread, still alive.
Panel 2: tilting sideways in the air, wings sagging, the body starting to drop.
Panel 3: falling sideways, one shoulder and one hip lower than the rest, wings
folded and drooping.
Panel 4: lying flat on its SIDE on the ground, wings slack and folded against the
body, eyes closed, head resting on the ground. It NEVER lies on its back and
NEVER on its belly.
""",
    # Падение без крыльев — см. ANIM_MOVE["hover"], почему их две версии.
    "hover": """A FALL TO THE SIDE, 4 panels left to right in one row.
Panel 1: hovering upright, still alive, the smoke streaming out behind.
Panel 2: tilting sideways in the air, the smoke trailing, the body starting to drop.
Panel 3: falling sideways, one shoulder lower than the other, the smoke pooling
around the sinking body.
Panel 4: lying flat on its SIDE on the ground, the smoke spread out flat around
it, eyes closed, head resting on the ground. It NEVER lies on its back and NEVER
on its belly.
""",
    "legs": """A FALL TO THE SIDE, 4 panels left to right in one row.
Panel 1: standing upright, both arms at the sides, still alive.
Panel 2: the whole body tilting sideways, arms spreading out for balance.
Panel 3: falling sideways, one shoulder and one hip touching the ground.
Panel 4: lying flat on its SIDE on the ground, arms slack, eyes closed, head
resting on the ground. It NEVER lies on its back and NEVER on its belly.
""",
}


def build_prompt(monster: str, anim: str) -> str:
    spec = MONSTERS[monster]
    character = (f"ONE single animal repeated in every panel: {spec['name']}, "
                 f"{spec['detail']}. Same individual creature in every panel.")
    if anim == "stand":
        body = """AN IDLE STANCE, 4 panels left to right in one row.
Panel 1: holding still, weight evenly, head up, calm but alert.
Panels 2, 3 and 4: the exact same pose with only a tiny breathing difference in
the rise of its chest. It does not move its feet at all.
"""
    elif anim == "move":
        body = ANIM_MOVE[spec["move"]]
    elif anim == "attack":
        body = ANIM_ATTACK[spec["attack"]]
    elif anim == "die":
        body = ANIM_DIE["legs" if spec["name"].endswith("demon woman") else spec["move"]]
    else:
        raise KeyError(anim)
    return f"{character}\n\n{PROPORTIONS}\n\n{VIEW}\n\n{body}\n\n{LAYOUT4}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("monster", choices=sorted(MONSTERS))
    ap.add_argument("anim", choices=("stand", "move", "attack", "die"))
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