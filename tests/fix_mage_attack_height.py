# -*- coding: utf-8 -*-
"""Фикс «проседания и похудения» фигуры в attack-кадрах героев-магов.

СИМПТОМ (игрок, 22.10): у магов любой расы/пола в атаке фигура ниже на голову
И «худеет» — причём не во всей анимации, а в отдельных фазах. Замер alpha-bbox
96 кадров (8 наборов x 12): низ непрозрачной области у ВСЕХ кадров на одной
линии (bottom=62), а высота И ширина фигуры в attack-кадрах меньше стойки
(напр. druid_men 42x20 против 54x21): mai-image-2.6-flash нарисовала атаку
уменьшенной фигурой (посох поднят — фигуру ужало в кадр). История: v1 тянула только по Y (фигуры «похудели» — отклонено игроком);
v2 масштабировала пропорционально по общему bbox — обманута поднятым посохом:
кадр «полного роста» за счёт посоха, а тело мельче, голова скачет (отзыв
игрока 22.10: «лучше пусть посох зарезается, чем голова скачет»).

ФИКС (программная деривация одобренных кадров, без ИИ-генерации):
мера — ТЕЛО, а не bbox. body_top = первая сверху строка с непрозрачными
пикселями шириной >= BODY_MIN_W (посох 2-4 px, голова шире). Каждый кадр
attack-блока (6-8, 1-based) с дефицитом ТЕЛА >= MIN_DEFICIT px масштабируется
ПРОПОРЦИОНАЛЬНО (обе оси, LANCZOS) так, чтобы тело было в рост тела idle-кадра,
и вклеивается с якорем НИЗ-ЦЕНТР прежнего содержимого. Посох/кончики, вышедшие
за холст 64x64, ОБРЕЗАЮТСЯ — одобрено игроком («пусть посох зарезается»).

Прецедент осознанного ресемплинга: LANCZOS/BICUBIC в
tests/gen_loot_icons_derived.py (nearest даёт рваную лесенку на кромках).

Запуск:
  python tests/fix_mage_attack_height.py --report   # только отчёт, без записи
  python tests/fix_mage_attack_height.py --build    # правит PNG на месте
  python tests/fix_mage_attack_height.py --check    # сверяет: фикс применён
Контакт-листы до/после пишутся в wip/mage_attack_fix/ при --build.

ВНИМАНИЕ: правит уже нарезанные 12-кадровые наборы. Если наборы когда-нибудь
перерезаются tests/extract_hero_nb.py из полос, этот скрипт нужно запустить
заново после нарезки (дефект живёт в исходных полосах mai).
"""
import argparse
import os

from PIL import Image

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "assets", "units", "hero")
PREVIEW_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "wip", "mage_attack_fix")
SETS = [
    "mage_human_men", "mage_human_women",
    "mage_orc_men", "mage_orc_women",
    "mage_undead_men", "mage_undead_women",
    "mage_druid_men", "mage_druid_women",
]
# Раскладка 12-кадрового набора: 1 idle, 2-5 walk, 6-8 attack, 9-12 dying.
IDLE_FRAME = 1
ATTACK_FRAMES = (6, 7, 8)
# Дефицит высоты ТЕЛА (px) меньше этого не правим: масштабирование ради пары
# пикселей не оправдано и вносит лёгкий блюр.
MIN_DEFICIT = 2
# Минимальная ширина непрозрачной строки, считающаяся телом (посох тоньше).
BODY_MIN_W = 6


def frame_path(set_name: str, n: int) -> str:
    return os.path.join(BASE, set_name, "sprites-%03d.png" % n)


def content_height(img: Image.Image) -> int:
    b = img.getbbox()
    return 0 if b is None else b[3] - b[1]


def body_top(img: Image.Image) -> int:
    """Верх ТЕЛА: первая сверху строка с непрозрачными пикселями >= BODY_MIN_W.

    Поднятый вертикальный посох даёт строки шириной 2-4 px и телом не
    считается; голова всегда шире. Возвращает -1, если кадр пуст.
    """
    alpha = img.getchannel("A")
    w = img.width
    for y in range(img.height):
        cnt = sum(alpha.getpixel((x, y)) > 0 for x in range(w))
        if cnt >= BODY_MIN_W:
            return y
    return -1


def fix_frame(img: Image.Image, target_body_h: int):
    """Пропорционально увеличить содержимое кадра до target_h по высоте.

    Якорь — НИЗ-ЦЕНТР прежней непрозрачной области: стопы остаются на своей
    линии земли, фигура не смещается вбок. Возвращает (новый кадр, старая
    высота) или (None, h), если масштабировать нечего.
    """
    b = img.getbbox()
    if b is None:
        return None, 0, 0
    bt = body_top(img)
    if bt < 0:
        return None, 0, 0
    body_h = b[3] - bt
    if target_body_h - body_h < MIN_DEFICIT or body_h <= 0:
        return None, body_h, bt
    region = img.crop(b)
    f = target_body_h / float(body_h)
    new_w = max(1, int(round(region.width * f)))
    new_h = max(1, int(round(region.height * f)))
    scaled = region.resize((new_w, new_h), Image.LANCZOS)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    cx = (b[0] + b[2]) // 2
    # НИЗ содержимого (b[3]) на месте — стопы на линии земли; тело получает
    # рост стойки. Всё, что не влезло в холст сверху (посох), обрезается.
    out.paste(scaled, (cx - new_w // 2, b[3] - new_h))
    return out, body_h, bt


def process(set_name: str, build: bool):
    idle = Image.open(frame_path(set_name, IDLE_FRAME)).convert("RGBA")
    idle_bt = body_top(idle)
    idle_b = idle.getbbox()
    target_body_h = idle_b[3] - idle_bt
    rows = []
    for n in ATTACK_FRAMES:
        img = Image.open(frame_path(set_name, n)).convert("RGBA")
        fixed, body_h, bt = fix_frame(img, target_body_h)
        deficit = target_body_h - body_h
        rows.append((n, body_h, bt, deficit, fixed is not None))
        if build and fixed is not None:
            fixed.save(frame_path(set_name, n))
    if build:
        _save_preview(set_name, idle, rows)
    return rows, target_body_h


def _save_preview(set_name: str, idle: Image.Image, rows: list) -> None:
    """Контакт-лист: idle + attack-кадры ДО и ПОСЛЕ (кадр с диска после build)."""
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scale = 3
    fw, fh = idle.width * scale, idle.height * scale
    cells = [("idle", idle)]
    for n, _bh, _bt, _d, _fixed in rows:
        cells.append(("before %d" % n, Image.open(frame_path(set_name, n)).convert("RGBA")))
    for n, _bh, _bt, _d, _fixed in rows:
        cells.append(("after %d" % n, Image.open(frame_path(set_name, n)).convert("RGBA")))
    sheet = Image.new("RGBA", (fw * len(cells), fh + 18), (32, 32, 32, 255))
    for i, (_label, img) in enumerate(cells):
        big = img.resize((fw, fh), Image.NEAREST)
        sheet.paste(big, (i * fw, 18))
    sheet.save(os.path.join(PREVIEW_DIR, "%s.png" % set_name))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    build = args.build and not args.report
    changed = 0
    for s in SETS:
        rows, target_body_h = process(s, build)
        print("--- %s (idle_body_h=%d) ---" % (s, target_body_h))
        for n, body_h, bt, deficit, fixed in rows:
            mark = "FIXED" if fixed else ("ok" if deficit < MIN_DEFICIT else "SKIP?")
            print("  frame %d: body_h=%d body_top=%d deficit=%d -> %s"
                  % (n, body_h, bt, deficit, mark))
            if fixed:
                changed += 1
    if args.check:
        print("CHECK: %d frames were normalized this run" % changed)
    elif build:
        print("BUILD: %d frames normalized, previews in %s" % (changed, PREVIEW_DIR))
    else:
        print("REPORT only (use --build to apply)")


if __name__ == "__main__":
    main()
