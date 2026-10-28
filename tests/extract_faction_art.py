#!/usr/bin/env python3
"""Нарезка листов фракционного арта в игровые иконки 72×80.

ВХОД: import/faction_art/{faction_<раса>_<kit>.png, tags.png} — листы, снятые
gen_faction_art.py (4 предмета в ряд на магенте).

ВЫХОД:
  assets/items/faction_sets/<раса>/<kit>_<slot>.png  (32 иконки)
  assets/items/tags/tag_<раса>.png                   (4 иконки)
  import/faction_art/_icons_sheet.png                (контактный лист)

ПОЧЕМУ НЕ РЕЗАТЬ ПО СЕТКЕ. Модель не держит одинаковые отступы: у одной
фракции браслет нарисован одной деталью, у другой парой, у нежити сверху
бывает «призрачный» дубль ряда. Поэтому:
  1) фон откеивается маджентой (magenta_mask из gen_hero_strip);
  2) выбирается ПОЛОСА с наибольшей массой альфы — дубли сверху/снизу
     отбрасываются;
  3) внутри полосы колонки кластеризуются по пустым зазорам и сливаются до
     РОВНО четырёх групп (шлем, нагрудник, наручи, сапоги);
  4) группа обрезается по своему bbox, масштабируется в 72×80 с полем 3 px,
     край премиксится от мадженты (без розовой каймы).

Запуск:
  python tests/extract_faction_art.py --report
  python tests/extract_faction_art.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from gen_hero_strip import magenta_mask, components  # noqa: E402

SRC = ROOT / "import" / "faction_art"
SETS_OUT = ROOT / "assets" / "items" / "faction_sets"
TAGS_OUT = ROOT / "assets" / "items" / "tags"
SHEET_OUT = SRC / "_icons_sheet.png"
REPORT = SRC / "_icons_report.json"

RACES = ["humans", "ork", "necro", "druid"]
KITS = ["heavy", "light"]
SLOTS = ["head", "body", "hands", "feet"]
ICON_W, ICON_H = 72, 80
MARGIN = 3


def load_alpha(path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """RGB листа + мягкая альфа по расстоянию до фона (магента)."""
    a = np.array(Image.open(path).convert("RGB"))
    h, w = a.shape[:2]
    corners = np.concatenate([a[:30, :30].reshape(-1, 3), a[:30, -30:].reshape(-1, 3),
                              a[-30:, :30].reshape(-1, 3), a[-30:, -30:].reshape(-1, 3)])
    bg = np.median(corners, axis=0).astype(np.int32)
    diff = np.abs(a.astype(np.int32) - bg).max(axis=2).astype(np.float32)
    # 30 — шум сжатия, 110 — уже уверенно предмет
    alpha = np.clip((diff - 30.0) / 80.0, 0.0, 1.0)
    # Дополнительный признак фона: маджента (низкий зелёный при высоких R/B)
    m = magenta_mask(a)
    alpha[m] = 0.0
    # Призрачные дубли модели — полупрозрачный предмет ПОВЕРХ мадженты: их
    # пиксели сохраняют розовый тон (R и B заметно выше зелёного), даже когда
    # расстояние до фона уже большое. Это не «магента-фон», поэтому обычный
    # ключ их не берёт; гасим отдельно. Сталь/золото/кожа под правило не
    # попадают: у них зелёный не ниже красного и синего.
    r = a[..., 0].astype(np.int32)
    g = a[..., 1].astype(np.int32)
    b = a[..., 2].astype(np.int32)
    ghost = ((r - g) > 40) & ((b - g) > 15) & (g < 170)
    alpha[ghost] = 0.0
    return a, alpha, bg


def pick_band(alpha: np.ndarray) -> tuple[int, int]:
    """Полоса-ряд с наибольшей массой: отсекает призрачные дубли сверху.

    У модели бывает «второй, призрачный» ряд предметов выше основного (некруп
    heavy, 29.10). Он тоже плотный, поэтому «самая массивная полоса» может
    оказаться им. Правило: среди полос, сравнимых по массе (>= 25% от лучшей),
    берём САМУЮ НИЖНЮЮ — дубли появляются над рядом, а не под ним.
    """
    h, w = alpha.shape
    rows = (alpha > 0.35).sum(axis=1)
    thr = max(2, w // 200)
    on = rows > thr
    bands = []
    y = 0
    while y < h:
        if not on[y]:
            y += 1
            continue
        y0 = y
        while y < h and on[y]:
            y += 1
        bands.append((y0, y, int(rows[y0:y].sum())))
    if not bands:
        return (0, h)
    best_mass = max(b[2] for b in bands)
    good = [b for b in bands if b[2] >= best_mass * 0.25]
    y0, y1, _ = max(good, key=lambda b: b[0])
    return (y0, y1)


def label_components(band: np.ndarray):
    """Связные компоненты + их маска-метки (своя, а не из gen_hero_strip:
    там возвращаются только bbox, и bbox соседа «съедал» чужие пиксели)."""
    m = band > 0.35
    h, w = m.shape
    labels = np.zeros((h, w), np.int32)
    boxes = []
    cur = 0
    for y in range(h):
        for x in range(w):
            if not m[y, x] or labels[y, x]:
                continue
            cur += 1
            stack = [(y, x)]
            labels[y, x] = cur
            ys, xs = [y], [x]
            while stack:
                cy, cx = stack.pop()
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = cur
                        stack.append((ny, nx))
                        ys.append(ny)
                        xs.append(nx)
            boxes.append((min(ys), max(ys), min(xs), max(xs), cur,
                          len(ys)))
    return labels, boxes


def cluster_items(alpha: np.ndarray, y0: int, y1: int, want: int = 4):
    """Четыре группы предметов; каждая группа — список компонент (bbox + id).

    Группировка по «ближайшему центру к четверти ширины», а не по зазорам:
    зазоры обманывают (у нежити сапоги стоят дальше от наруча, чем друг от
    друга; у друида есть отдельный ремешок над наручем). Четверти же заданы
    самим промтом («каждый предмет ~четверть ширины»), поэтому компонент
    уходит в свою четверть даже когда предметы перекрываются по X.
    """
    band = alpha.copy()
    band[:y0] = 0.0
    band[y1:] = 0.0
    labels, comps = label_components(band)
    if not comps:
        return []
    total = float((band > 0.35).sum())
    comps = [b for b in comps if b[5] >= total * 0.002]
    if not comps:
        return []
    xs0 = min(b[2] for b in comps)
    xs1 = max(b[3] for b in comps)
    span = max(1, xs1 - xs0)
    anchors = [xs0 + span * (i + 0.5) / want for i in range(want)]
    groups: list = [[] for _ in range(want)]
    for b in comps:
        c = (b[2] + b[3]) * 0.5
        idx = min(range(want), key=lambda i: abs(c - anchors[i]))
        groups[idx].append(b)
    if any(not g for g in groups):
        # Страховка: схлопываем самые близкие центры, как раньше.
        groups = [[b] for b in comps]
        while len(groups) > want:
            best = None
            best_d = None
            for i in range(len(groups)):
                for j in range(i + 1, len(groups)):
                    bi = _group_box(groups[i])
                    bj = _group_box(groups[j])
                    d = abs((bi[2] + bi[3]) * 0.5 - (bj[2] + bj[3]) * 0.5)
                    if best_d is None or d < best_d:
                        best_d = d
                        best = (i, j)
            i, j = best
            groups[i] = groups[i] + groups[j]
            del groups[j]
    groups.sort(key=lambda g: min(b[2] for b in g))
    # Внутри группы выкидываем вертикальных «сирот»: модель иногда рисует
    # отдельный висящий ремешок/обрывок ткани над предметом (друид heavy:
    # зелёная дуга над наручем). Держим компоненты, чей центр по Y в пределах
    # 0.6 высоты главной компоненты.
    cleaned = []
    for g in groups:
        main = max(g, key=lambda b: b[5])
        cy = (main[0] + main[1]) * 0.5
        h = max(1, main[1] - main[0])
        keep = [b for b in g if abs((b[0] + b[1]) * 0.5 - cy) <= h * 0.6]
        cleaned.append(keep if keep else [main])
    groups = cleaned
    for g in groups:
        g.sort(key=lambda b: b[4])
    return groups, labels


def _group_box(group: list) -> tuple:
    return (min(b[0] for b in group), max(b[1] for b in group),
            min(b[2] for b in group), max(b[3] for b in group))


def unpremultiply(rgb: np.ndarray, alpha: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """Убрать маджентную кайму: rgb = (rgb - (1-a)*bg)/a на кромке."""
    out = rgb.astype(np.float32).copy()
    a = alpha[..., None]
    fg = np.where(a > 0.01, (out - (1.0 - a) * bg[None, None, :]) / np.maximum(a, 0.01), 0.0)
    out = np.clip(fg, 0, 255).astype(np.uint8)
    out[alpha <= 0.01] = 0
    return out


def cut_one(a, alpha, labels: np.ndarray, bg, group: list) -> Image.Image:
    # Маска ТОЛЬКО своих компонент (по меткам, а не по bbox): bbox группы
    # может налезать на соседний предмет, и вырезка по нему ловила его полоску
    # — «слева виден кусок чего-то» (29.10).
    ids = [int(b[4]) for b in group]
    mask = np.where(np.isin(labels, ids), alpha, 0.0)
    ys, xs = np.where(mask > 0.25)
    if len(xs) == 0:
        return Image.new("RGBA", (ICON_W, ICON_H), (0, 0, 0, 0))
    gy0, gy1 = int(ys.min()), int(ys.max()) + 1
    gx0, gx1 = int(xs.min()), int(xs.max()) + 1
    sub_a = mask[gy0:gy1, gx0:gx1]
    sub_al = sub_a
    sub_rgb = a[gy0:gy1, gx0:gx1]
    sub_rgb = unpremultiply(sub_rgb, sub_al, bg)
    rgba = np.dstack([sub_rgb, (sub_al * 255).astype(np.uint8)])
    img = Image.fromarray(rgba, "RGBA")
    box_w = ICON_W - MARGIN * 2
    box_h = ICON_H - MARGIN * 2
    scale = min(box_w / img.width, box_h / img.height)
    nw = max(1, int(round(img.width * scale)))
    nh = max(1, int(round(img.height * scale)))
    img = img.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (ICON_W, ICON_H), (0, 0, 0, 0))
    canvas.paste(img, ((ICON_W - nw) // 2, (ICON_H - nh) // 2), img)
    return canvas


def slice_sheet(path: Path, names: list[str], out_dir: Path, rel_prefix: str) -> list:
    a, alpha, bg = load_alpha(path)
    y0, y1 = pick_band(alpha)
    groups, labels = cluster_items(alpha, y0, y1, want=len(names))
    made = []
    for i, name in enumerate(names):
        if i >= len(groups):
            print("  !! %s: групп найдено %d, ждали %d" % (path.name, len(groups), len(names)))
            break
        group = groups[i]
        icon = cut_one(a, alpha, labels, bg, group)
        if out_dir is not None:
            out_dir.mkdir(parents=True, exist_ok=True)
            icon.save(out_dir / (name + ".png"))
        made.append({"name": name,
                     "file": str(out_dir / (name + ".png")) if out_dir is not None else "",
                     "path": "%s/%s.png" % (rel_prefix, name),
                     "box": [int(v) for v in _group_box(group)]})
    return made


def contact_sheet(entries: list, out: Path) -> None:
    cols = 8
    cell = 96
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * cell), (40, 40, 46))
    d = ImageDraw.Draw(sheet)
    for i, e in enumerate(entries):
        img = Image.open(e["file"]).convert("RGBA")
        # 1× (нативный) и 2× рядом: читаемость на реальном размере
        cx = (i % cols) * cell
        cy = (i // cols) * cell
        sheet.paste(img, (cx + 6, cy + 10), img)
        small = img.resize((ICON_W // 2, ICON_H // 2), Image.LANCZOS)
        sheet.paste(small, (cx + 6 + ICON_W + 4, cy + 10), small)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="только проверить листы")
    args = ap.parse_args()

    entries = []
    report = {"sheets": {}, "icons": []}
    for race in RACES:
        for kit in KITS:
            sheet = SRC / ("faction_%s_%s.png" % (race, kit))
            if not sheet.exists():
                print("нет листа %s" % sheet.name)
                continue
            out_dir = SETS_OUT / race
            made = slice_sheet(sheet, ["%s_%s" % (kit, s) for s in SLOTS], out_dir,
                               "res://assets/items/faction_sets/%s" % race) if not args.report \
                else slice_sheet(sheet, ["%s_%s" % (kit, s) for s in SLOTS], None, "")
            # Для отчёта пути всё равно нужны: сохраняем в память нечего, поэтому
            # в режиме --report имена только печатаются.
            if args.report:
                print("%s: групп %d" % (sheet.name, len(made)))
            entries.extend([e for e in made if e.get("path")])
            report["sheets"][sheet.name] = len(made)
    if not args.report:
        tags = SRC / "tags.png"
        if tags.exists():
            made = slice_sheet(tags, ["tag_%s" % r for r in RACES], TAGS_OUT,
                               "res://assets/items/tags")
            entries.extend(made)
            report["sheets"]["tags.png"] = len(made)
        report["icons"] = entries
        REPORT.write_text(json.dumps(report, indent=1, ensure_ascii=False),
                          encoding="utf-8")
        contact_sheet(entries, SHEET_OUT)
        print("иконок: %d, контактный лист: %s" % (len(entries), SHEET_OUT))
        if len(entries) != 36:
            print("RESULT: FAIL — ожидали 36 иконок, получили %d" % len(entries))
            return 1
        print("RESULT: OK extract_faction_art")
    return 0


if __name__ == "__main__":
    sys.exit(main())
