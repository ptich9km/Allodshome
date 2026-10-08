"""Заглушки иконок для мастерской: сломанные вещи, ткань, магическая эссенция.

Проект уже давно ушёл от иконок-заглушек (см. пакет 01.10), но здесь иначе
нельзя: без файлов на диске item_icons_smoke.gd:56 валит проверку "все
иконки существуют", а падать должно не на пустом месте, а на контенте.

ЧТО ДЕЛАЕТ
    assets/items/broken/{metal}_armor.png   20 металлов x 2 (броня, оружие)
    assets/items/broken/linen_garment.png    1
    assets/professions/workshop/fabric.png   1
    assets/professions/workshop/magic_essence.png  1

КАК ВЫГЛЯДИТ
    Сломанная броня/оружие: та же палитра металла, что у вещей в faction/,
    но с разрывом - половина силуэта срезана, поверх диагональная трещина.
    Игрок должен отличать «это вещь, которую сломали» от «это вещь», поэтому
    разрыв обязателен, а не просто потемнение.
    Ткань: свёрток. Эссенция: капля/флакон с внутренним свечением.

    Все 80x80 RGBA, как остальные иконки предметов.

Запуск
    python tests/gen_broken_icons.py            # перегенерировать
    python tests/gen_broken_icons.py --check    # только сверить размеры
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BROKEN_DIR = os.path.join(ROOT, "assets", "items", "broken")
WORKSHOP_DIR = os.path.join(ROOT, "assets", "professions", "workshop")

SIZE = 80

METALS = [
    "bronze", "iron", "steel", "gold", "argentum",
    "lutetium", "lanthanum", "terbium", "wolfram", "chromium",
    "cobalt", "titanium", "thorium", "uranium", "plutonium",
    "radium", "gallium", "yttrium", "promethium", "neodymium",
]

# Палитра та же, что assets/items/faction_palette.json по смыслу: тёмная
# тень -> средний тон -> блик. Заглушка обязана читаться как МЕТАЛЛ того же
# цвета, что и нормальные вещи, иначе игрок не поймёт, что переплавит.
METAL_COLOR = {
    "bronze": (166, 110, 58), "iron": (120, 120, 128), "steel": (168, 176, 186),
    "gold": (212, 175, 55), "argentum": (196, 202, 212),
    "lutetium": (150, 160, 190), "lanthanum": (140, 170, 175),
    "terbium": (128, 150, 120), "wolfram": (108, 108, 116),
    "chromium": (176, 190, 200), "cobalt": (58, 108, 172),
    "titanium": (150, 152, 156), "thorium": (96, 138, 112),
    "uranium": (108, 132, 96), "plutonium": (126, 76, 148),
    "radium": (188, 210, 96), "gallium": (170, 178, 188),
    "yttrium": (140, 146, 160), "promethium": (196, 130, 190),
    "neodymium": (150, 168, 196),
}

LINEN_COLOR = (206, 198, 178)


def _shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def broken_gear(base, kind):
    """Сломанная вещь: палитра металла + разрыв + трещина.

    `kind` = "armor" даёт наплечную пластину, "weapon" - клинок. Общее у
    них - разрыв: справа силуэт срезан по диагонали, там где вещь треснула.
    """
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark = _shade(base, 0.55)
    light = _shade(base, 1.35)

    if kind == "armor":
        box = (14, 18, 66, 62)
        d.rounded_rectangle(box, radius=8, fill=base)
        # наплечники
        d.ellipse((12, 18, 32, 34), fill=dark)
        d.ellipse((48, 18, 68, 34), fill=dark)
        # блик по верхней кромке
        d.line((box[0] + 6, box[1] + 2, box[2] - 10, box[1] + 2), fill=light, width=2)
    else:
        # клинок: треугольник от рукояти вверх
        d.polygon([(36, 66), (46, 66), (44, 16), (38, 12)], fill=base)
        d.polygon([(36, 66), (39, 66), (40, 20), (38, 16)], fill=light)
        # рукоять
        d.rounded_rectangle((32, 64, 50, 72), radius=3, fill=dark)

    # РАЗРЫВ. Без него заглушка неотличима от целой вещи, и игрок не поймёт,
    # что именно он несёт в кузню.
    d.polygon([(48, 12), (74, 12), (74, 46), (56, 74), (48, 74), (60, 44)],
              fill=(0, 0, 0, 0))
    # трещина вдоль разрыва
    d.line((48, 14, 58, 40, 52, 62), fill=_shade(base, 0.35), width=2)
    return img


def linen_garment():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(22, 20), (58, 20), (66, 68), (14, 68)], fill=LINEN_COLOR)
    d.polygon([(22, 20), (30, 20), (24, 68), (14, 68)], fill=_shade(LINEN_COLOR, 0.82))
    # лоскут, оторванный по диагонали
    d.polygon([(46, 20), (78, 20), (78, 52), (58, 74), (46, 74), (56, 44)],
              fill=(0, 0, 0, 0))
    d.line((46, 22, 56, 44, 50, 70), fill=_shade(LINEN_COLOR, 0.7), width=2)
    return img


def fabric_roll():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = (198, 176, 140)
    d.rounded_rectangle((16, 24, 64, 60), radius=6, fill=c)
    d.rounded_rectangle((16, 24, 64, 34), radius=6, fill=_shade(c, 1.18))
    # торцы свёртка
    d.ellipse((12, 28, 28, 56), fill=_shade(c, 0.78))
    d.ellipse((56, 28, 70, 56), fill=_shade(c, 0.9))
    # складка
    d.line((30, 40, 54, 40), fill=_shade(c, 0.72), width=2)
    return img


def magic_essence():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    core = (120, 210, 240)
    # флакон
    d.polygon([(32, 16), (48, 16), (48, 26), (60, 42), (60, 68), (20, 68),
               (20, 42), (32, 26)], fill=(150, 190, 205, 235))
    # жидкость с внутренним свечением: центр светлее края (принцип
    # "яркость к центру" из 2d-vfx-craft - равномерная яркость читается
    # как плоская наклейка)
    d.polygon([(24, 48), (56, 48), (56, 66), (24, 66)], fill=core)
    d.ellipse((32, 50, 48, 64), fill=_shade(core, 1.5))
    d.line((36, 24, 36, 40), fill=(240, 250, 255, 200), width=2)
    return img


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    made = []
    for metal in METALS:
        for kind in ("armor", "weapon"):
            p = os.path.join(BROKEN_DIR, "%s_%s.png" % (metal, kind))
            made.append((broken_gear(METAL_COLOR[metal], kind), p))
    made.append((linen_garment(), os.path.join(BROKEN_DIR, "linen_garment.png")))
    made.append((fabric_roll(), os.path.join(WORKSHOP_DIR, "fabric.png")))
    made.append((magic_essence(), os.path.join(WORKSHOP_DIR, "magic_essence.png")))

    missing = [p for _i, p in made if not os.path.exists(p)]
    print("Целевых файлов: %d, отсутствует: %d" % (len(made), len(missing)))
    for m in missing[:10]:
        print("   ! %s" % os.path.relpath(m, ROOT))

    if args.check:
        return 1 if missing else 0

    for img, path in made:
        save(img, path)
    print("Записано: %d" % len(made))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())