#!/usr/bin/env python3
"""Нарезка сгенерированных атласов предметов в иконки (19.10, v2).

Вход: import/items_atlas/<metal>/{metal}_weapons.png, {metal}_armor.png
      + extra/<metal>_<name>.png (точечные догенерации).
Карта ячеек ЯВНАЯ (правило игрока: модель сбивается с порядка).

v2 - после замечаний игрока (розовая кайма, вырезы, обрезанные рукоятки):
  1. Кеинг ВСЕГО листа, а не ячейки: предмет может вылезать за границы
     своей ячейки - клеточный кроп обрезал рукояти/кончики.
  2. Ключ = B - G (пурпурность), а не дистанция RGB: фон всех листов -
     ярко-пурпурный (B сильно больше G), а красная кожа/бронза/тёмные
     рукояти дают B-G около нуля. Пороги калибруются по фону самого листа.
  3. Альфа-рамп + анмикс цвета (c - (1-a)*bg)/a + эрозия края 1 px -
     убирает розовую кайму.
  4. Связные компоненты (BFS) - каждый предмет отдельный; привязка к имени
     по центроиду. Мелочь (< 400 px) отбрасывается.

Выход: import/items_atlas/_sliced/<metal>/<имя>.png + _contact_sliced.png
НИЧЕГО в assets/ не пишется - установка только после одобрения игрока.

Usage:
  python tests/slice_items_atlas.py            # нарезать всё
  python tests/slice_items_atlas.py --nearest  # масштаб NEAREST вместо LANCZOS
"""
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "import" / "items_atlas"
OUT = ROOT / "_sliced"

CELL = 256            # 1024/4
MIN_AREA = 400        # отбрасывать мелочь (шум кеинга)

WEAPON_T = {"bronze": "cheap", "iron": "common", "gold": "good"}
ARMOR_T = WEAPON_T

# --- карты ячеек (кол, ряд) -> имя, по фактическому содержимому листов ---
# имя отсутствует в карте = компонент не берём. "extra" - имена из
# точечных догенераций (отдельные файлы).
WEAPON_MAP = {
    "bronze": {
        # 20.10: перегенерация (nano-banana) - модель шла строго по списку
        # WEAPONS, раскладка: ряд1 mace/2h_mace, ряд2 spear/pike/bow/crossbow,
        # ряд3 shield. two_handed_mace теперь на основном листе.
        (0, 0): "dagger", (1, 0): "one_handed_sword", (2, 0): "saber",
        (3, 0): "greatsword", (0, 1): "one_handed_axe",
        (1, 1): "two_handed_axe", (2, 1): "one_handed_mace",
        (3, 1): "two_handed_mace", (0, 2): "one_handed_spear",
        (1, 2): "two_handed_spear", (2, 2): "bow", (3, 2): "crossbow",
        (0, 3): "shield",
        "extra": [],
    },
    "iron": {
        # 20.10: regeneration (nano-banana) - strict WEAPONS reading order,
        # all 13 items on the sheet, no extras needed.
        (0, 0): "dagger", (1, 0): "one_handed_sword", (2, 0): "saber",
        (3, 0): "greatsword", (0, 1): "one_handed_axe",
        (1, 1): "two_handed_axe", (2, 1): "one_handed_mace",
        (3, 1): "two_handed_mace", (0, 2): "one_handed_spear",
        (1, 2): "two_handed_spear", (2, 2): "bow", (3, 2): "crossbow",
        (0, 3): "shield",
        "extra": [],
    },

    "gold": {
        # 20.10: regeneration (nano-banana) - strict WEAPONS reading order,
        # all 13 items on the sheet, no extras needed.
        (0, 0): "dagger", (1, 0): "one_handed_sword", (2, 0): "saber",
        (3, 0): "greatsword", (0, 1): "one_handed_axe",
        (1, 1): "two_handed_axe", (2, 1): "one_handed_mace",
        (3, 1): "two_handed_mace", (0, 2): "one_handed_spear",
        (1, 2): "two_handed_spear", (2, 2): "bow", (3, 2): "crossbow",
        (0, 3): "shield",
        "extra": [],
    },

}

ARMOR_MAP = {
    "bronze": {
        (0, 0): "light_head", (1, 0): "light_chest", (2, 0): "light_bracers",
        (3, 0): "light_gloves", (0, 1): "light_legs", (1, 1): "light_ring",
        (2, 1): "light_amulet", (3, 1): "heavy_head",
        (0, 2): "heavy_chest", (1, 2): "heavy_bracers",
        (2, 2): "heavy_gloves", (3, 2): "heavy_legs",
        (1, 3): "heavy_ring", (0, 3): "heavy_amulet",
    },
    "iron": {
        # 20.10: regeneration - ARMOR reading order.
        (0, 0): "light_head", (1, 0): "light_chest", (2, 0): "light_bracers",
        (3, 0): "light_gloves", (0, 1): "light_legs", (1, 1): "light_ring",
        (2, 1): "light_amulet", (3, 1): "heavy_head",
        (0, 2): "heavy_chest", (1, 2): "heavy_bracers",
        (2, 2): "heavy_gloves", (3, 2): "heavy_legs",
        (0, 3): "heavy_ring", (1, 3): "heavy_amulet",
        "extra": [],
    },

    "gold": {
        # 20.10: regeneration - ARMOR reading order.
        (0, 0): "light_head", (1, 0): "light_chest", (2, 0): "light_bracers",
        (3, 0): "light_gloves", (0, 1): "light_legs", (1, 1): "light_ring",
        (2, 1): "light_amulet", (3, 1): "heavy_head",
        (0, 2): "heavy_chest", (1, 2): "heavy_bracers",
        (2, 2): "heavy_gloves", (3, 2): "heavy_legs",
        (0, 3): "heavy_ring", (1, 3): "heavy_amulet",
        "extra": [],
    },

}


def sheet_bg(rgb: Image.Image) -> tuple[int, int, int]:
    """Медианный цвет рамки листа (8 px) - фон известен надёжно."""
    w, h = rgb.size
    px = rgb.load()
    ring = []
    for x in range(w):
        for y in list(range(8)) + list(range(h - 8, h)):
            ring.append(px[x, y])
    for y in range(h):
        for x in list(range(8)) + list(range(w - 8, w)):
            ring.append(px[x, y])
    ring.sort(key=lambda p: p[0] * 10000 + p[1] * 100 + p[2])
    return ring[len(ring) // 2]


def matte_sheet(rgb: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    """Кеинг всего листа: альфа по (B - G) с калибровкой от фона,
    анмикс полупрозрачных пикселей, эрозия края 1 px."""
    w, h = rgb.size
    px = rgb.load()
    bg_k = bg[2] - bg[1]              # пурпурность фона
    t_op = bg_k - 70                  # ниже - полностью непрозрачно
    t_tr = bg_k - 25                  # выше - полностью прозрачно
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            k = b - g
            if k <= t_op:
                opx[x, y] = (r, g, b, 255)
            elif k >= t_tr:
                continue
            else:
                a = (t_tr - k) / float(t_tr - t_op)
                nr = int(max(0, min(255, (r - (1 - a) * bg[0]) / a)))
                ng = int(max(0, min(255, (g - (1 - a) * bg[1]) / a)))
                nb = int(max(0, min(255, (b - (1 - a) * bg[2]) / a)))
                opx[x, y] = (nr, ng, nb, int(a * 255))
    # эрозия альфы на 1 px: срезает остаточную розовую кайму
    a_ch = out.getchannel("A").filter(ImageFilter.MinFilter(3))
    out.putalpha(a_ch)
    return out


def defringe(rgba: Image.Image) -> Image.Image:
    """20.10: срез магента-бахромы - пиксели цвета фона внутри/по краю
    предмета (r и b сильно выше g) делают прозрачными."""
    px = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and r - g > 100 and b - g > 100:
                px[x, y] = (r, g, b, 0)
    return rgba


def components(rgba: Image.Image) -> list[dict]:
    """Связные компоненты непрозрачных пикселей (4-связность, BFS)."""
    w, h = rgba.size
    a = rgba.getchannel("A").load()
    seen = [[False] * w for _ in range(h)]
    comps = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or a[sx, sy] < 128:
                continue
            q = deque([(sx, sy)])
            seen[sy][sx] = True
            area = 0
            x0, y0, x1, y1 = sx, sy, sx, sy
            while q:
                x, y = q.popleft()
                area += 1
                if x < x0: x0 = x
                if y < y0: y0 = y
                if x > x1: x1 = x
                if y > y1: y1 = y
                for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
                    if 0 <= nx < w and 0 <= ny < h \
                            and not seen[ny][nx] and a[nx, ny] >= 128:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if area >= MIN_AREA:
                comps.append({
                    "bbox": (x0, y0, x1 + 1, y1 + 1), "area": area,
                    "cx": (x0 + x1) / 2.0, "cy": (y0 + y1) / 2.0,
                })
    # 20.10: листы с нарисованными линиями сетки дают гигантскую "паутину"
    # (bbox на весь лист) - выбрасываем, иначе она склеивается с предметом.
    # паутина = bbox практически на весь лист (сетка линий у nano-banana);
    # крупный одиночный предмет занимает 70-90% холста - его не трогаем.
    comps = [c for c in comps
             if (c["bbox"][2] - c["bbox"][0]) < w * 0.9
             or (c["bbox"][3] - c["bbox"][1]) < h * 0.9]
    return comps


def fit(img: Image.Image, tw: int, th: int, nearest: bool) -> Image.Image:
    """Вписать содержимое в tw x th с сохранением пропорций, по центру."""
    s = min(tw / img.width, th / img.height)
    nw, nh = max(1, round(img.width * s)), max(1, round(img.height * s))
    res = img.resize((nw, nh),
                     Image.NEAREST if nearest else Image.LANCZOS)
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.paste(res, ((tw - nw) // 2, (th - nh) // 2))
    return canvas


def extract_component(sheet_rgba: Image.Image, comp: dict) -> Image.Image:
    x0, y0, x1, y1 = comp["bbox"]
    return sheet_rgba.crop((x0, y0, x1, y1))


def slice_sheet(path: Path, cell_map: dict, out_dir: Path, suffix: str,
                size: tuple[int, int], nearest: bool) -> list[Path]:
    rgb = Image.open(path).convert("RGB")
    bg = sheet_bg(rgb)
    rgba = defringe(matte_sheet(rgb, bg))
    comps = components(rgba)
    out_dir.mkdir(parents=True, exist_ok=True)
    # v3 (20.10): парные предметы (перчатки/наручи/поножи) распадаются на
    # две компоненты - группируем по ячейке и режем по объединённому bbox.
    made = []
    by_cell = {}
    for comp in comps:
        col = int(comp["cx"] // CELL)
        row = int(comp["cy"] // CELL)
        if (col, row) not in cell_map:
            continue
        by_cell.setdefault((col, row), []).append(comp)
    for key, group in by_cell.items():
        x0 = min(c["bbox"][0] for c in group)
        y0 = min(c["bbox"][1] for c in group)
        x1 = max(c["bbox"][2] for c in group)
        y1 = max(c["bbox"][3] for c in group)
        icon = fit(rgba.crop((x0, y0, x1, y1)), size[0], size[1], nearest)
        dst = out_dir / ("%s_%s.png" % (cell_map[key], suffix))
        icon.save(dst)
        made.append(dst)
    return made


def slice_extra(path: Path, name: str, out_dir: Path, suffix: str,
                size: tuple[int, int], nearest: bool) -> Path | None:
    rgb = Image.open(path).convert("RGB")
    bg = sheet_bg(rgb)
    rgba = defringe(matte_sheet(rgb, bg))
    comps = sorted(components(rgba), key=lambda c: -c["area"])
    if not comps:
        print("  ПУСТО extra %s" % name)
        return None
    dst = out_dir / ("%s_%s.png" % (name, suffix))
    fit(extract_component(rgba, comps[0]), size[0], size[1], nearest).save(dst)
    return dst


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    nearest = "--nearest" in sys.argv
    all_made = []
    for metal in ("bronze", "iron", "gold"):
        w_map = WEAPON_MAP[metal]
        a_map = ARMOR_MAP[metal]
        w_dir = OUT / metal / "weapons"
        made = slice_sheet(ROOT / metal / ("%s_weapons.png" % metal),
                           w_map, w_dir, WEAPON_T[metal], (72, 80), nearest)
        for name in w_map.get("extra", []):
            p = slice_extra(ROOT / metal / "extra" / ("%s_%s.png" % (metal, name)),
                            name, w_dir, WEAPON_T[metal], (72, 80), nearest)
            if p:
                made.append(p)
        print("%s weapons: %d" % (metal, len(made)))
        all_made += made

        a_dir = OUT / metal / "armor"
        made = slice_sheet(ROOT / metal / ("%s_armor.png" % metal),
                           a_map, a_dir, ARMOR_T[metal], (72, 80), nearest)
        for name in a_map.get("extra", []):
            p = slice_extra(ROOT / metal / "extra" / ("%s_%s.png" % (metal, name)),
                            name, a_dir, ARMOR_T[metal], (72, 80), nearest)
            if p:
                made.append(p)
        print("%s armor: %d" % (metal, len(made)))
        all_made += made

    if all_made:
        cell = 84
        cols = 10
        rows = (len(all_made) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * cell), (40, 40, 46))
        for i, p in enumerate(all_made):
            im = Image.open(p).convert("RGBA")
            sheet.paste(im, ((i % cols) * cell + 6, (i // cols) * cell + 6),
                        im)
        out = OUT / "_contact_sliced.png"
        sheet.save(out)
        print("ЛИСТ НАРЕЗАННОГО: %s (%d иконок)" % (out, len(all_made)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
