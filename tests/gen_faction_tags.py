"""Фракционные бирки: генерация иконок и записей в item_db.json.

Пакет B переработки ковки (28.10): фракционные наборы брони делаются из
стали + трофейных бирок. Бирка — предмет-трофей, который падает со стражника
форпоста. Пакет A вывел из игры 16 фракционных металлов; бирки занимают их
место как «фракционный» ингредиент, но без новых металлов и без перекраски
брони.

ПОЧЕМУ ГЕНЕРАТОР, А НЕ РУЧНАЯ ПРАВКА. Иконки бирок — процедурные (жетон с
пробитым отверстием и клеймом фракции), а не ИИ-арт: 4 файла по 72x80
рисуются детерминированно и проверяются `--check`. Ручная правка
item_db.json ломала бы round-trip (indent=1, CRLF, UTF-8 без эскейпов),
который проверялся в пакете A.

Раскладка иконки (72x80, как у фракционной брони):
  - жетон со скошенным низом, тёмная кромка, светлая фаска;
  - отверстие под шнур сверху;
  - клеймо фракции (меч, клык, череп, лист) цветом фракции.

Запуск:
    python tests/gen_faction_tags.py --check
    python tests/gen_faction_tags.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
ICON_DIR = os.path.join(ROOT, "assets", "items", "tags")
ICON_REL = "res://assets/items/tags/"

W, H = 72, 80

# Раса -> (ключ предмета, русское имя, английское имя, цвет клейма, форма клейма)
TAGS = {
    "humans": ("Alliance Tag", "Бирка Альянса", "Alliance Tag",
               (86, 140, 214), "sword"),
    "ork": ("Horde Tag", "Бирка Орды", "Horde Tag",
            (198, 92, 52), "fangs"),
    "necro": ("Reaper Tag", "Бирка Пожинателей", "Reaper Tag",
              (140, 176, 108), "skull"),
    "druid": ("Circle Tag", "Бирка Круга", "Circle Tag",
              (92, 158, 96), "leaf"),
}

METAL = (176, 176, 170)
METAL_DARK = (96, 96, 92)
METAL_LIGHT = (222, 222, 214)
RIM = (52, 52, 48)


def _tag_shape() -> list[tuple[int, int]]:
    """Контур жетона: прямоугольник со скошенными нижними углами."""
    left, top, right = 16, 14, W - 16
    bottom = H - 18
    bevel = 9
    return [
        (left + bevel, top),
        (right - bevel, top),
        (right, top + bevel),
        (right, bottom - bevel),
        (right - bevel, bottom),
        (left + bevel, bottom),
        (left, bottom - bevel),
        (left, top + bevel),
    ]


def _draw_glyph(d: ImageDraw.ImageDraw, kind: str, color: tuple[int, int, int]) -> None:
    cx, cy = W // 2, 40
    if kind == "sword":
        d.rectangle([cx - 2, cy - 11, cx + 2, cy + 6], fill=color)
        d.polygon([(cx - 6, cy - 12), (cx + 6, cy - 12), (cx, cy - 20)], fill=color)
        d.rectangle([cx - 9, cy + 5, cx + 9, cy + 8], fill=color)
        d.rectangle([cx - 2, cy + 8, cx + 2, cy + 16], fill=color)
    elif kind == "fangs":
        d.polygon([(cx - 12, cy - 14), (cx - 3, cy + 2), (cx - 6, cy + 15),
                   (cx - 10, cy + 1)], fill=color)
        d.polygon([(cx + 12, cy - 14), (cx + 3, cy + 2), (cx + 6, cy + 15),
                   (cx + 10, cy + 1)], fill=color)
        d.rectangle([cx - 11, cy - 17, cx + 11, cy - 13], fill=color)
    elif kind == "skull":
        d.ellipse([cx - 12, cy - 17, cx + 12, cy + 7], fill=color)
        d.rectangle([cx - 7, cy + 5, cx + 7, cy + 14], fill=color)
        for dx in (-5, 5):
            d.ellipse([cx + dx - 3, cy - 8, cx + dx + 3, cy - 2], fill=METAL_DARK)
        d.rectangle([cx - 1, cy + 1, cx + 1, cy + 6], fill=METAL_DARK)
    elif kind == "leaf":
        d.polygon([(cx, cy - 18), (cx + 11, cy - 4), (cx, cy + 16),
                   (cx - 11, cy - 4)], fill=color)
        d.line([(cx, cy - 14), (cx, cy + 12)], fill=METAL_DARK, width=2)


def build_icon(race: str, rebuild: bool = False) -> None:
    key, _ru, _en, color, glyph = TAGS[race]
    out = os.path.join(str(ICON_DIR), "tag_%s.png" % race)
    # 29.10: иконки бирок теперь рисует ИИ (extract_faction_art.py). Существующий
    # файл не перезаписываем, иначе процедурная заглушка затрёт арт.
    if not rebuild and os.path.exists(out):
        return
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shape = _tag_shape()
    # тень под жетоном
    d.polygon([(x + 2, y + 3) for x, y in shape], fill=(0, 0, 0, 70))
    d.polygon(shape, fill=METAL, outline=RIM)
    # фаска сверху-слева и тень снизу
    d.line([shape[0], shape[1], shape[2]], fill=METAL_LIGHT, width=2)
    d.line([shape[5], shape[6], shape[7]], fill=METAL_DARK, width=2)
    # отверстие под шнур: прозрачная дырка, вокруг — тёмная кромка
    d.ellipse([W // 2 - 5, 17, W // 2 + 5, 27], fill=RIM)
    d.ellipse([W // 2 - 3, 19, W // 2 + 3, 25], fill=(0, 0, 0, 0))
    # клеймо фракции
    _draw_glyph(d, glyph, color)
    # вмятина-царапины: тонкие тёмные штрихи, чтобы жетон не читался как
    # геометрическая заливка
    d.line([(20, 62), (30, 58)], fill=METAL_DARK, width=1)
    d.line([(24, 66), (34, 63)], fill=METAL_DARK, width=1)
    out = os.path.join(str(ICON_DIR), "tag_%s.png" % race)
    os.makedirs(str(ICON_DIR), exist_ok=True)
    img.save(out)
    print("icon:", os.path.relpath(out, ROOT), "->", key)


def load_db() -> list:
    with open(DB, "r", encoding="utf-8", newline="") as f:
        return json.load(f)


def save_db(items: list) -> None:
    # Формат пакета A: indent=1, UTF-8 без эскейпов, CRLF, хвост CRLF.
    text = json.dumps(items, ensure_ascii=False, indent=1)
    with open(DB, "w", encoding="utf-8", newline="") as f:
        f.write(text.replace("\n", "\r\n") + "\r\n")


def _entry(item_id: int, race: str) -> dict:
    key, ru, en, _color, _glyph = TAGS[race]
    return {
        "id": item_id,
        "key": key,
        "name_ru": ru,
        "name_en": en,
        "quality": "Tag",
        "material": "None",
        "type": "Trophy",
        "price": 40,
        "weight": 0.1,
        "damage_min": 0,
        "damage_max": 0,
        "to_hit": 0,
        "defence": 0,
        "absorption": 0,
        "magcap": 0,
        "level": 1,
        "effects": [],
        "icon": ICON_REL + "tag_%s.png" % race,
    }


def apply(rebuild_icons: bool = False) -> int:
    items = load_db()
    keys = {it.get("key") for it in items}
    next_id = max(int(it.get("id", 0)) for it in items) + 1
    added = 0
    for race, (key, _ru, _en, _c, _g) in TAGS.items():
        build_icon(race, rebuild_icons)
        if key in keys:
            continue
        items.append(_entry(next_id, race))
        next_id += 1
        added += 1
    save_db(items)
    print("item_db: добавлено %d записей, всего %d" % (added, len(items)))
    return 0


def check() -> int:
    fails = []
    items = load_db()
    by_key = {it.get("key"): it for it in items}
    for race, (key, _ru, _en, _c, _g) in TAGS.items():
        icon = ICON_REL + "tag_%s.png" % race
        path = os.path.join(ROOT, icon.replace("res://", "").replace("/", os.sep))
        if not os.path.exists(path):
            fails.append("нет иконки %s" % icon)
        it = by_key.get(key)
        if not it:
            fails.append("нет записи %s" % key)
            continue
        if it.get("icon") != icon:
            fails.append("%s: icon=%s, ждали %s" % (key, it.get("icon"), icon))
        if it.get("type") != "Trophy" or it.get("quality") != "Tag":
            fails.append("%s: type/quality не Trophy/Tag" % key)
    # id=0 — исторический «нет id» у части старых записей, его не считаем.
    ids = [int(it.get("id", 0)) for it in items if int(it.get("id", 0)) != 0]
    if len(ids) != len(set(ids)):
        fails.append("дубли id в item_db")
    if fails:
        print("RESULT: FAIL gen_faction_tags --check")
        for f in fails:
            print("  -", f)
        return 1
    print("RESULT: OK gen_faction_tags (предметов: %d)" % len(items))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--rebuild-icons", action="store_true",
                    help="перерисовать процедурные бирки (затрёт ИИ-арт!)")
    args = ap.parse_args()
    return check() if args.check else apply(args.rebuild_icons)


if __name__ == "__main__":
    sys.exit(main())
