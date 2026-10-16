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
  python tests/gen_monster_strip.py wolf stand --check import/Monsters/wolf_stand_nb1.png --panels 4
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
        "detail": "long curved black horns, membranous bat wings that she keeps "
                  "FOLDED CLOSED against her back, black hooves instead of feet, a "
                  "long barbed tail, glowing yellow eyes, dark hair, wearing dark "
                  "leather armour",
        "move": "glide", "attack": "cast", "die": "kneel",
        # Ширина задана по той же причине, что и троллю: крылатое существо
        # не влезает в четыре панели в ряд. Успешный `glide` это доказал —
        # достаточно сложить крылья и потребовать узкий силуэт.
        "width": "EACH FIGURE AT MOST 20% OF THE IMAGE WIDTH: the wings stay "
                 "folded flat against the back, the arms stay close to the body, "
                 "nothing sticks out to the sides, and a wide empty gap separates "
                 "every figure from the next. Leave the outermost 6% of the image "
                 "on the LEFT and on the RIGHT completely EMPTY - no part of any "
                 "figure may touch the edge of the picture.",
    },
    # 17.10: два вида по просьбе игрока. Оба двуногие, поэтому `move = legs`
    # и `die = legs` (падение набок описано для двуногих).
    # Людоед: описание намеренно без «человеческого лица» — иначе модель
    # рисует почти человека, и зверь перестаёт быть Серым.
    "cannibal": {
        "name": "a tall gaunt wild humanoid beast",
        "detail": "sallow grey-green skin stretched over a thin frame, a long narrow "
                  "head with a wide flat nose and a lipless mouth full of yellow "
                  "teeth, sunken pale eyes, long thin clawed fingers, bare feet, "
                  "wearing only a ragged hide loincloth, a butchered human bone "
                  "hanging from a cord at its belt",
        "move": "legs", "attack": "bite", "die": "legs",
    },
    "troll": {
        "name": "a stocky mossy troll",
        # Слова размера УБРАНЫ после двух замеров: 600 px при норме 557 (22%).
        # Модель дважды проигнорировала «20% ширины», но каждый раз рисовала
        # «huge massive broad-shouldered» — то есть размер в описании
        # перевешивал цифру. В игре тролль того же размера, что остальные
        # Серые (все кадры ~54 px), поэтому «огромный» на картинке ничего не
        # даёт, а ширину портит.
        "detail": "mossy grey-green skin, a wide flat head with a heavy brow and blunt "
                  "teeth, small deep-set yellow eyes, thick forearms, a rope belt with "
                  "a pouch, holding a gnarled wooden club resting UPRIGHT on his "
                  "shoulder so that it points straight up and never sideways",
        "move": "legs", "attack": "smash", "die": "legs",
        "width": "EACH FIGURE AT MOST 20% OF THE IMAGE WIDTH: the feet close "
                 "together, the legs not spread, both free arms close to the body, "
                 "the club standing vertically above the shoulder, nothing sticking "
                 "out to the sides. Leave a wide empty gap on both sides of every "
                 "figure. Exactly 4 figures, all the SAME size, in a SINGLE row.",
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
    # Двуногие. Появилось вместе с людоедом и троллем (17.10): у четвероногих
    # фаза `run` требует «does NOT rear up on its hind legs», а оба новых вида
    # ходят на двух ногах, и этот запрет с ними прямо противоречил бы описанию.
    "legs": """A WALK ON TWO LEGS, 4 panels left to right in one row, seen from the side
walking across the ground.
Panel 1: standing tall on both legs, one leg forward and one back, arms at the sides.
Panel 2: stepping forward, the front leg swinging ahead of the body, the shoulders
rocking slightly.
Panel 3: passing, the legs gathered UNDER the body, one foot just leaving the ground,
the hips highest.
Panel 4: the trailing leg swinging forward, the body stretched out, arms swinging
slightly in the opposite direction to the legs.
The 4 panels must show 4 clearly different leg positions. It stays UPRIGHT on two
legs in every panel and NEVER drops onto all fours, NEVER crouches down on its
front limbs, and its silhouette stays no wider than its own shoulders.
EXACTLY 4 figures, all at the SAME size and the same height, drawn in a SINGLE
horizontal row of 4 - never 8 figures, never two rows, never one figure under
another, and never a fifth figure added anywhere.
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
    # Узкий силуэт для существ, которые в полёте иначе не влезают в полосу:
    # у суккуба раскрытые крылья давали 600-900 px на панель, и четыре таких
    # не помещались в ряд на холсте 2528 px (замер 17.10: нужно 2798).
    "glide": """A COMPACT HOVERING FLIGHT, 4 panels left to right in one row, seen in mid
air with clear empty background all around the body and no ground under it.
The wings stay FOLDED CLOSE AGAINST THE BODY at all times - the whole silhouette
is no wider than the creature's own shoulders, and NEVER spreads out sideways.
Panel 1: wings folded tight against the back, body held upright, hovering.
Panel 2: the folded wings lift slightly, the body rises a little.
Panel 3: the folded wings sweep down close to the flanks, the body sinks a
little, legs tucked up behind.
Panel 4: the folded wings return to the back, body at the highest point.
The 4 panels must show 4 clearly different body heights. The wings NEVER open
out, NEVER spread wide, and nothing of the creature sticks out sideways.""",
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
    # Тролль (17.10). Отдельная фаза, а не `bite`: троллю положено бить дубиной,
    # и общий текст кусания заставил бы его открывать пасть.
    "smash": """A CLUB SMASH, 4 panels left to right in one row.
Panel 1: standing upright on two legs, the heavy wooden club held low at its side,
both hands on it, still.
Panel 2: the club raised high above the head with both arms, the body leaning back,
the mouth open in a roar.
Panel 3: the club swung down and forward, hitting the ground in front of the feet,
the body leaning hard forward, dust kicking up at the point of impact.
Panel 4: the club resting on the ground in front after the swing, the body still
leaning forward, arms lowering.
The 4 panels must show 4 clearly different club positions. It NEVER lies down and
NEVER sits during the smash, it stays upright on two legs, and the club stays a
solid thick shape in every panel.
The swing stays COMPACT and close to the body: the club only reaches a little way
in FRONT of the feet and NEVER sweeps out to the side, so every panel is about as
wide as the standing body. All 4 figures are at the SAME size in a SINGLE row.
""",
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
The wings stay FOLDED CLOSED AGAINST THE BACK throughout the whole cast - they
NEVER open, NEVER spread out sideways, and the silhouette stays no wider than the
body's own shoulders. The glow gathers between the hands, not between the wings.
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
# Падение существа с КРЫЛЬЯМИ (17.10). Существующий `legs` требует
    # «arms spreading out for balance», и при падении крылья расправляются:
    # замер полосы — ширина фигуры растёт 467 → 640 → 666 → 725 px, последняя
    # панель лежит плашмя (w/h 2.51), и четыре такие не помещаются в ряд.
    # Успешная фаза полёта `glide` работает ровно потому, что крылья там
    # описаны отдельной фразой. Здесь — то же требование для падения.
    # Смерть «осесть на колени» (17.10, решение игрока). Причина: упасть плашмя
    # для крылатого существа физически не влезает в полосу — замер: ширина
    # фигуры растёт 488 → 566 → 735 → 660 px, и 4 панели в ряд на холсте
    # 2528 px не помещаются даже без зазоров. Поза на коленях узкая: тело
    # вертикально, крылья сложены, ничего не распластано по земле.
    "kneel": """A COLLAPSE TO THE KNEES, 4 panels left to right in ONE horizontal row.
The body stays UPRIGHT the whole time - she sinks DOWN onto her knees, she never
tips over and never lies down. The wings stay FOLDED CLOSED against the back at
all times, the arms hang close to the body, and nothing spreads out sideways: the
silhouette is no wider than her shoulders in every panel.
Panel 1: standing upright on two legs, wings folded on the back, still alive.
Panel 2: the knees buckling, the body sinking down, the head lowering.
Panel 3: down on both knees, the body upright but low, the head bowed forward, the
folded wings still tight against the back.
Panel 4: kneeling still, head sunk low, arms slack at the sides, eyes closed, the
folded wings resting against the back. She NEVER falls flat and NEVER lies down.
The knees of the kneeling panels touch the SAME ground line as the feet in panel 1
- the body never floats and never sinks through the ground. All 4 figures are the
SAME size in a SINGLE horizontal row, with an empty margin at both edges.
""",
    "glide_fall": """A FALL TO THE SIDE, 4 panels left to right in ONE horizontal row.
The wings stay FOLDED CLOSED AGAINST THE BACK at all times, exactly as in the
flight panels - they NEVER open, NEVER spread out sideways, and nothing of the
body or the wings ever sticks out to the side. The whole silhouette stays no
wider than her own shoulders in every panel.
Panel 1: standing upright on two legs, wings folded tight on the back, still alive.
Panel 2: the whole body tilting sideways, the folded wings still tight to the back,
arms staying close to the body instead of spreading out.
Panel 3: falling sideways, one shoulder and one hip touching the ground, wings
still folded flat against the back, the knees starting to draw in.
Panel 4: lying on her SIDE on the ground in a COMPACT CURLED pose - the knees
drawn UP towards the chest, the arms tucked in, the wings still folded tight
against the back. She NEVER lies stretched out straight and NEVER lies on her
back or on her belly.
The lying figure stays CURLLED and COMPACT: its length from head to knee is
clearly SHORTER than the standing figure is tall, and its width is no more than
half its length. It NEVER spreads out flat like a starfish.
The lowest point of the lying body touches the same ground line as the feet in
panel 1 - the body never floats. All 4 figures are the SAME size in a SINGLE row.
""",
    "legs": """A FALL TO THE SIDE, 4 panels left to right in ONE horizontal row.
Panel 1: standing upright on two legs, both arms at the sides, still alive.
Panel 2: the whole body tilting sideways, arms spreading out for balance.
Panel 3: falling sideways, one shoulder and one hip touching the ground.
Panel 4: lying flat on its SIDE on the ground, arms slack, eyes closed, head
resting on the ground. It NEVER lies on its back and NEVER on its belly.
EVERY lying panel must REST ON THE GROUND: the lowest point of the body touches
exactly the same ground line as the feet in panel 1, the body is never floating,
never hovering and never raised above the ground. All 4 panels are drawn at the
same figure size and in a SINGLE row, never one under another.
""",
}


def build_prompt(monster: str, anim: str) -> str:
    spec = MONSTERS[monster]
    character = (f"ONE single animal repeated in every panel: {spec['name']}, "
                 f"{spec['detail']}. Same individual creature in every panel.")
    # Правило ширины вида, если оно есть (см. тролля).
    width = f"\n\n{spec['width']}" if spec.get("width") else ""
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
        # Раньше фаза смерти выбиралась сравнением строки: `"legs" if
        # name.endswith("demon woman") else move`. Проверка по окончанию описания
        # ломается от любой правки формулировки и молча выбирала падение набок
        # четвероногому. Теперь вид задаёт фару сам полем `die`.
        body = ANIM_DIE[spec.get("die", spec["move"])]
    else:
        raise KeyError(anim)
    return f"{character}{width}\n\n{PROPORTIONS}\n\n{VIEW}\n\n{body}\n\n{LAYOUT4}"


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
        OUT_DIR / f"{args.monster}_{args.anim}_nb1.png"
    gen_once(load_key(), args.model, build_prompt(args.monster, args.anim),
             out, SIZE, args.seed, 1, None)
    print("предполётная проверка:")
    ok, _ = preflight(str(out), expect=args.panels, min_gap=40)
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())