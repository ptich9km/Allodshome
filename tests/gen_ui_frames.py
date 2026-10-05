#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генератор 9-slice рамок интерфейса Mirotokhome.

Правило одного файла: рамки рисуются здесь кодом, потому что в проекте их
должны быть согласованы между собой, а палитра берётся из дизайн-системы
(`scripts/ui_theme.gd`). Вручную их рисовать бессмысленно — 4 файла должны
совпадать по толщине линий и цвету золота.

Запуск:
    python tests/gen_ui_frames.py            # сгенерировать
    python tests/gen_ui_frames.py --check    # сверить SHA256 с регенерацией
    python tests/gen_ui_frames.py --report   # сводка по параметрам

Инварианты (проверяются в gen, падение = исключение):
  * поля 9-slice меньше размера картинки, иначе центр схлопнется в ноль;
  * центр плитки — одноцветный (иначе растяжка даст градиентный шов);
  * альфа есть, PNG 32-bit RGBA.
"""

import hashlib
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "ui", "frames")
DB_PATH = os.path.join(OUT_DIR, "frames_db.json")

# Палитра. Дублирует scripts/ui_theme.gd — этот файл на Python, там на GDScript,
# общей константы быть не может. Значения обязаны совпадать, иначе рамка и
# панель разойдутся по цвету. Сторож на равенство живёт в
# tests/ui_design_system_smoke.gd.
BG = (18, 14, 11, 255)            # PANEL_BG
EDGE = (122, 74, 30, 255)         # PANEL_EDGE
EDGE_DIM = (79, 49, 21, 255)      # промежуточная линия
ACCENT = (255, 196, 77, 255)      # ACCENT
ACCENT_DIM = (202, 140, 61, 255)  # ACCENT_DIM
SHADOW = (8, 6, 5, 255)           # тень/утопленность

# Итоговый размер каждой рамки и поля 9-slice.
# Размеры раздельные по X и Y: у divider высота 16, и при полях 8+8=16 центр по
# Y схлопывался бы в ноль. Проверка на одной ширине это пропускала — теперь
# `_validate` смотрит обе оси.
SPECS = [
    # (имя, ширина, высота, поля слева/сверху/справа/снизу)
    ("panel_frame", 96, 96, (28, 28, 28, 28)),
    ("window_frame", 96, 96, (32, 32, 32, 32)),
    ("slot", 48, 48, (12, 12, 12, 12)),
    ("divider", 64, 16, (16, 7, 16, 7)),
]


def _panel_frame(size: int, margin: int) -> Image.Image:
    """Двойная рамка с угловыми скобками. Центр — одноцветный BG."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Заливка тела панели — непрозрачная, требование «без прозрачности».
    d.rectangle([0, 0, size - 1, size - 1], fill=BG)

    # Внешняя линия и внутренняя — 6 px внутрь.
    d.rectangle([0, 0, size - 1, size - 1], outline=EDGE, width=1)
    d.rectangle([5, 5, size - 6, size - 6], outline=EDGE_DIM, width=1)

    # Угловые скобки — короткие утолщённые отрезки, читаются как «скоба».
    arm = margin - 8
    for cx, cy, sx, sy in (
        (7, 7, 1, 1),
        (size - 8, 7, -1, 1),
        (7, size - 8, 1, -1),
        (size - 8, size - 8, -1, -1),
    ):
        d.line([(cx, cy), (cx + sx * arm, cy)], fill=ACCENT_DIM, width=2)
        d.line([(cx, cy), (cx, cy + sy * arm)], fill=ACCENT_DIM, width=2)

    return img


def _window_frame(size: int, margin: int) -> Image.Image:
    """Более тяжёлая рамка для крупных окон: рамка толще, углы крупнее."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, size - 1, size - 1], fill=BG)
    d.rectangle([0, 0, size - 1, size - 1], outline=ACCENT_DIM, width=2)
    d.rectangle([4, 4, size - 5, size - 5], outline=EDGE, width=1)
    d.rectangle([9, 9, size - 10, size - 10], outline=EDGE_DIM, width=1)

    # Углы: ромбовидный маркер, он читается даже на мелком окне.
    arm = margin - 10
    for cx, cy, sx, sy in (
        (10, 10, 1, 1),
        (size - 11, 10, -1, 1),
        (10, size - 11, 1, -1),
        (size - 11, size - 11, -1, -1),
    ):
        d.line([(cx, cy), (cx + sx * arm, cy)], fill=ACCENT, width=3)
        d.line([(cx, cy), (cx, cy + sy * arm)], fill=ACCENT, width=3)
        d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=ACCENT)

    return img


def _slot(size: int, margin: int) -> Image.Image:
    """Утопленная ячейка: тень сверху-слева, блик снизу-справа."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, size - 1, size - 1], fill=BG)
    # Тень (сверху и слева) и блик (снизу и справа) — вдавливание.
    d.line([(0, 0), (size - 1, 0)], fill=SHADOW, width=2)
    d.line([(0, 0), (0, size - 1)], fill=SHADOW, width=2)
    d.line([(0, size - 1), (size - 1, size - 1)], fill=EDGE_DIM, width=1)
    d.line([(size - 1, 0), (size - 1, size - 1)], fill=EDGE_DIM, width=1)
    # Тонкий контур по периметру.
    d.rectangle([0, 0, size - 1, size - 1], outline=EDGE)

    return img


def _divider(size_w: int, size_h: int, margin_v: int) -> Image.Image:
    """Горизонтальная линейка под заголовком.

    Ключевое: растягиваемая СЕРЕДИНА должна быть одноцветной тонкой линией.
    Первый вариант клал ромб в центр, и при 9-slice растягивании (текстура
    64 px -> ширина панели 420 px) ромб превращался в толстую жёлтую полосу.
    Поэтому орнамент живёт только в крайних плитках, которые не растягиваются.
    """
    img = Image.new("RGBA", (size_w, size_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cy = size_h // 2
    half = size_w // 2

    # Ромбы у самого края — в крайних плитках, они не растягиваются.
    r = size_h // 2 - 1
    for cx in (5, size_w - 6):
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)],
                  fill=ACCENT)

    # Тонкая линия по всей длине. В середине она и должна быть без украшений.
    d.line([(3, cy), (size_w - 4, cy)], fill=EDGE_DIM, width=1)

    return img


BUILDERS = {
    "panel_frame": lambda s, m: _panel_frame(s, m),
    "window_frame": lambda s, m: _window_frame(s, m),
    "slot": lambda s, m: _slot(s, m),
    "divider": lambda s, m: _divider(s, 16, m),
}


def render(name: str, w: int, h: int, margins: tuple) -> Image.Image:
    img = BUILDERS[name](w, h)
    left, top, right, bottom = margins
    # Обе оси: центр плитки должен остаться хотя бы в 1 px, иначе 9-slice
    # в Godot схлопнется и рамка рассыплется.
    assert left + right < w and top + bottom < h, \
        "%s: поля 9-slice %s не помещаются в %dx%d, центр схлопнется" % (
            name, margins, w, h)
    assert img.size == (w, h), "%s: размер %s вместо %dx%d" % (
        name, img.size, w, h)
    assert img.mode == "RGBA", "%s: ожидался RGBA" % name
    return img


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    args = sys.argv[1:]
    if "--help" in args or "-h" in args:
        print(__doc__)
        return 0
    check = "--check" in args
    report = "--report" in args

    os.makedirs(OUT_DIR, exist_ok=True)
    db = {
        "palette": {
            "panel_bg": "#%02x%02x%02x" % BG[:3],
            "panel_edge": "#%02x%02x%02x" % EDGE[:3],
            "panel_edge_dim": "#%02x%02x%02x" % EDGE_DIM[:3],
            "accent": "#%02x%02x%02x" % ACCENT[:3],
            "accent_dim": "#%02x%02x%02x" % ACCENT_DIM[:3],
            "shadow": "#%02x%02x%02x" % SHADOW[:3],
        },
        "source": "tests/gen_ui_frames.py",
        "usage": [
            "StyleBoxTexture + texture_margin_* в UiKit.add_frame()",
            "panel_frame — тело панели и оверлеев главного меню",
            "window_frame — крупные окна (слоты загрузки)",
            "slot — ячейка инвентаря/полки",
            "divider — линейка под заголовком, растягивается по ширине",
        ],
        "frames": {},
    }

    ok = True
    for name, w, h, margins in SPECS:
        path = os.path.join(OUT_DIR, name + ".png")
        img = render(name, w, h, margins)
        db["frames"][name] = {
            "size": [img.size[0], img.size[1]],
            "texture_margin": {
                "left": margins[0], "top": margins[1],
                "right": margins[2], "bottom": margins[3],
            },
        }
        if check:
            if not os.path.exists(path):
                print("FAIL %s: файла нет" % name)
                ok = False
                continue
            tmp = os.path.join(OUT_DIR, "._%s.tmp.png" % name)
            img.save(tmp)
            got, want = sha256(tmp), sha256(path)
            os.remove(tmp)
            mark = "OK  " if got == want else "FAIL"
            if got != want:
                ok = False
            print("%s %-13s %s  %s" % (mark, name, got[:16], want[:16]))
        else:
            img.save(path)
            print("saved %-13s %dx%d  margins=%s" % (
                name, img.size[0], img.size[1], margins))

    if report:
        print(json.dumps(db, ensure_ascii=False, indent=2))

    if not check:
        with open(DB_PATH, "w", encoding="utf-8") as fh:
            json.dump(db, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("saved %s" % os.path.relpath(DB_PATH, ROOT))
    else:
        print("SHA256: %s" % ("все рамки совпадают с регенерацией"
                              if ok else "ЕСТЬ РАСХОЖДЕНИЯ"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())