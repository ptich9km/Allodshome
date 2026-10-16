#!/usr/bin/env python3
"""Нарезка ИИ-полосы ЗВЕРЯ в игровой набор, 4 панели на полосу.

Замер 15.10: модель на одну и ту же просьбу «4 фигуры в один ряд» отдала
четыре разные раскладки — 4x1, 4x2, 2x2 и 2x2 с разной высотой. Плюс у
зверей фигуры соприкасаются (хвост волка упирается в спину соседа, крыло
дракона в крыло), и колоночные прогоны сливаются в один — проба раскладки
`tests/strip_layout.py` на `dragon_move_nb1.png` насчитала 2 фигуры там, где
их четыре. Поэтому нарезка:
  - обходит ВСЕ ряды, а не берёт «лучший»;
  - если фигур меньше ожидаемого, разрезает самый широкий кусок по минимуму
    профиля колонок — тем же приёмом, что и extract_hero_nb.py.

Хелперы (`cut_mask`, `label_keep_largest`, `fit`) ИМПОРТИРУЮТСЯ из
extract_hero_nb.py, а не копируются: контракт холста 64x64 и точки земли y=62
общий с героем.

Запуск:
  python tests/extract_monster_nb.py wolf
  python tests/extract_monster_nb.py            # все звери с полосами на диске
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_hero_nb import cut_mask, bg_ref, label_keep_largest, fit  # noqa: E402
from gen_hero_strip import components  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "import" / "Monsters"
OUT_ROOT = REPO / "assets" / "units" / "monsters"

OUT_W, OUT_H, FEET_Y = 64, 64, 62
# Зверь вписывается в холст ОБЕИМИ осями. Раньше масштаб считался только по
# высоте, и бегущий волк (в исходнике 1148px шириной при 529px высоты) после
# подгонки под 54px становился 117px шириной — шире холста в 64px, и paste
# срезал по 26px с каждой стороны. В игру уезжали волки без головы: 15.10.
TARGET_H = 54
TARGET_W = 62
MIN_COL = 3       # колонка короче — не фигура
MIN_ROW = 5       # строка короче — не фигура
ROW_TOL = 50      # разброс линии стоп внутри одной строки панелей, px
EDGE_MIN = 3      # поле от фигуры до края кадра; меньше — кадр срезан по нему

# Блоки набора. Тот же контракт, что у героя, плюс decay=0: зверь не
# рассыпается, а лежит (игрок, 15.10: «умирает — заваливается набок»).
LAYOUT = {"stand": ("idle", 1), "move": ("move", 4),
          "attack": ("attack", 3), "die": ("dying", 4)}
PHASES = {"stand": 1, "move": 4, "attack": 4, "die": 4}


def rows_of(alpha):
    return _runs((alpha.sum(axis=1) >= MIN_ROW).astype(bool))


def group_by_feet(boxes, tol=ROW_TOL):
    """Группировка компонентов в строки по общей линии НИЗА.

    Признак — низ фигуры, а не вертикальное перекрытие: в полёте и в падении
    верх уезжает, а низ остаётся на земле. У полосы bat_move разброс низов
    364 px при высоте фигуры ~700 — перекрытие там не годится вовсе.
    """
    groups = []
    for b in sorted(boxes, key=lambda t: t[1]):
        best, best_d = None, None
        for g in groups:
            d = abs(b[1] - g["feet"])
            if d <= tol and (best_d is None or d < best_d):
                best, best_d = g, d
        if best is None:
            groups.append({"feet": b[1], "boxes": [b]})
        else:
            n = len(best["boxes"])
            best["feet"] = (best["feet"] * n + b[1]) // (n + 1)
            best["boxes"].append(b)
    return [g["boxes"] for g in groups]


def cols_of(alpha, y0, y1):
    return _runs((alpha[y0:y1 + 1].sum(axis=0) >= MIN_COL).astype(bool))


def _runs(flag):
    out, start = [], -1
    for i, v in enumerate(flag):
        if v and start < 0:
            start = i
        elif not v and start >= 0:
            out.append((start, i - 1))
            start = -1
    if start >= 0:
        out.append((start, len(flag) - 1))
    return out


def cells(alpha, expect):
    """Ячейки в порядке чтения: сперва связные компоненты, потом геометрия."""
    boxes = components(alpha)
    print(f"    компонент-зверей: {len(boxes)} (ожидалось {expect})")
    if len(boxes) >= expect:
        if len(boxes) > expect:
            # 25 из 30 полос Серых (аудит 17.10) пришли с панелями в ДВЕ строки:
            # модель отдаёт 4+4, и boxes[:expect] брал верхний ряд МОЛЧА. Звери
            # в игре смотрятся хорошо именно потому, что верхний ряд и есть
            # правильный, но это нигде не было записано и не проверялось.
            if expect == 1:
                # Стойка - одна панель, выбирать строку не из чего.
                return boxes[:1], len(set(b[0] for b in boxes))
            groups = sorted(group_by_feet(boxes), key=lambda g: min(b[0] for b in g))
            for gi, g in enumerate(groups, 1):
                print(f"      строка {gi}: зверей {len(g)}, "
                      f"стопы {min(b[1] for b in g)}..{max(b[1] for b in g)}")
            exact = [g for g in groups if len(g) == expect]
            if len(exact) == 1:
                print(f"      берём строку с {expect} зверями "
                      f"(остальные отброшены: {len(boxes) - expect})")
                return sorted(exact[0], key=lambda b: b[2])
            print(f"      строк с ровно {expect} зверями: {len(exact)} — "
                  f"однозначно выбрать нельзя, берём первые {expect}")
        return boxes[:expect], len(set(b[0] for b in boxes))
    rows = rows_of(alpha)
    out = []
    for y0, y1 in rows:
        for x0, x1 in cols_of(alpha, y0, y1):
            out.append((y0, y1, x0, x1))
    guard = 0
    while guard < 40:
        guard += 1
        widths = [c[3] - c[2] for c in out]
        if len(widths) < 2:
            break
        med = float(np.median(widths))
        widest = max(out, key=lambda c: c[3] - c[2])
        if (widest[3] - widest[2]) <= med * 1.6 and len(out) >= expect:
            break
        if not _split_one(alpha, out, widest):
            break
    return out, len(rows)
    rows = rows_of(alpha)
    out = []
    for y0, y1 in rows:
        for x0, x1 in cols_of(alpha, y0, y1):
            out.append((y0, y1, x0, x1))
    guard = 0
    while guard < 40:
        guard += 1
        widths = [c[3] - c[2] for c in out]
        if len(widths) < 2:
            break
        med = float(np.median(widths))
        widest = max(out, key=lambda c: c[3] - c[2])
        # нечего делить: ширина в пределах нормы, либо ячеек уже хватает
        if (widest[3] - widest[2]) <= med * 1.6 and len(out) >= expect:
            break
        if not _split_one(alpha, out, widest):
            break
    return out, len(rows)


def _split_one(alpha, out, target):
    y0, y1, x0, x1 = target
    if x1 - x0 < 20:
        return False
    prof = alpha[y0:y1 + 1, x0:x1 + 1].sum(axis=0).astype(float)
    lo, hi = int(len(prof) * 0.30), int(len(prof) * 0.70)
    if hi - lo < 5:
        return False
    cut = x0 + lo + int(np.argmin(prof[lo:hi]))
    if cut <= x0 or cut >= x1:
        return False
    print(f"    дорез слипшегося x={x0}..{x1} по x={cut}")
    out[out.index(target)] = (y0, y1, x0, cut)
    out.append((y0, y1, cut + 1, x1))
    out.sort(key=lambda c: (c[0], c[2]))
    return True


def cut_figures(path: Path, expect: int):
    a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    alpha = cut_mask(a, bg_ref(a))
    box, nrows = cells(alpha, expect)
    print(f"    рядов: {nrows}, ячеек: {len(box)} (ожидалось {expect})")
    out = []
    for y0, y1, x0, x1 in box:
        sub = alpha[y0:y1 + 1, x0:x1 + 1]
        sub = label_keep_largest(sub)
        ys, xs = np.where(sub > 0.5)
        if ys.size == 0:
            out.append(None)
            continue
        ry0, ry1, rx0, rx1 = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
        full = sub[ry0:ry1 + 1, rx0:rx1 + 1]
        crop = a[y0 + ry0:y0 + ry1 + 1, x0 + rx0:x0 + rx1 + 1]
        print(f"      {full.shape[1]}x{full.shape[0]}")
        out.append((crop, full))
    return out


def build_set(name: str, target_h: int, dry_run: bool = False) -> bool:
    figs = {}
    for anim in ("stand", "move", "attack", "die"):
        path = SRC / f"{name}_{anim}_nb1.png"
        if not path.exists():
            print(f"  {name}/{anim}: полосы нет, пропуск")
            return False
        print(f"{name}/{anim}: {path.name}")
        got = cut_figures(path, PHASES[anim])
        if len(got) < PHASES[anim] or any(g is None for g in got[:PHASES[anim]]):
            print(f"  БРАК {name}/{anim}: ячеек {len(got)}, нужно {PHASES[anim]}")
            return False
        figs[anim] = got[: LAYOUT[anim][1]]

    out_dir = OUT_ROOT / name
    out_dir.mkdir(parents=True, exist_ok=True)
    if not dry_run:
        for old in sorted(out_dir.glob("sprites-*.png")):
            old.unlink()
    frames = []
    for anim in ("stand", "move", "attack", "die"):
        block = figs[anim]
        # Масштаб блока — по самому высокому И самому широкому, иначе широкий
        # зверь (бегущий волк) не влезает в холст и срезается по бокам.
        max_h = max(al.shape[0] for _, al in block)
        max_w = max(al.shape[1] for _, al in block)
        scale = min(TARGET_H / max_h, TARGET_W / max_w)
        print(f"  {anim}: высоты {[al.shape[0] for _, al in block]} "
              f"ширины {[al.shape[1] for _, al in block]} scale={scale:.4f}")
        for rgb, al in block:
            frames.append(fit(rgb, al, scale))

    if dry_run:
        # Считаем и сравниваем, НИЧЕГО не записывая. Без этого набор зверей,
        # принятый игроком, можно затереть слепой пересборкой всех семи сразу:
        # скрипт без аргументов берёт их все.
        import hashlib
        import io
        changed = []
        for i, fr in enumerate(frames):
            target = out_dir / f"sprites-{i + 1:03d}.png"
            if not target.exists():
                changed.append(f"sprites-{i + 1:03d}.png ОТСУТСТВУЕТ")
                continue
            buf = io.BytesIO()
            fr.save(buf, format="PNG")
            if hashlib.sha256(target.read_bytes()).hexdigest() != \
                    hashlib.sha256(buf.getvalue()).hexdigest():
                changed.append(f"sprites-{i + 1:03d}.png ИЗМЕНЯЕТСЯ")
        if changed:
            print(f"  DRY-RUN: изменились бы {len(changed)} из {len(frames)}:")
            for line in changed:
                print(f"    {line}")
        else:
            print(f"  DRY-RUN: все {len(frames)} кадров совпали бы байт в байт")
        return True

    for i, fr in enumerate(frames):
        fr.save(out_dir / f"sprites-{i + 1:03d}.png")

    entry = {
        "desc": f"Monster {name}, Gemini Nano Banana strips, three-quarter east view "
                "+ mirror, idle1+move4+attack3+dying4",
        "folder": f"monsters/{name}", "frames": len(frames), "prefix": "sprites",
        "dirs": 1, "idle_phases": 1, "move": 4, "move_begin": 0,
        "attack": 3, "dying": 4, "decay": 0, "cast": 0, "idle": 0,
        "move_f": [], "move_t": [], "attack_f": [], "attack_t": [],
        "die_f": [], "dying_t": [],
        "w": OUT_W, "h": OUT_H, "cx": OUT_W // 2, "cy": FEET_Y,
        "tile": None, "projectile": -1, "palette": 5, "blocks": 4,
        "resist": {"fire": 10, "water": 10, "air": 10, "earth": 10, "astral": 10},
    }
    (out_dir / "_entry.json").write_text(
        json.dumps(entry, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    _contact_sheet(frames, out_dir / "_contact_sheet.png")
    print(f"  записано кадров: {len(frames)} -> {out_dir}")
    return True


def _contact_sheet(frames, dst: Path) -> None:
    """Лист для ревью глазами: тесты меряют индексы и файлы, а не арт."""
    cols = 4
    rows = (len(frames) + cols - 1) // cols
    sheet = np.zeros((rows * OUT_H, cols * OUT_W, 3), np.uint8)
    for i, fr in enumerate(frames):
        arr = np.array(fr)
        yy, xx = np.mgrid[0:OUT_H, 0:OUT_W]
        chk = np.where(((xx // 8) + (yy // 8)) % 2 == 0, 90, 60).astype(np.uint8)
        cell = np.dstack([chk, chk, chk])
        m = arr[:, :, 3] > 8
        cell[m] = arr[:, :, :3][m]
        r, c = divmod(i, cols)
        sheet[r * OUT_H:(r + 1) * OUT_H, c * OUT_W:(c + 1) * OUT_W] = cell
    Image.fromarray(sheet).resize(
        (cols * OUT_W * 3, rows * OUT_H * 3), Image.NEAREST).save(dst)


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry_run = "--dry-run" in sys.argv[1:]
    names = args or sorted({
        re.match(r"([a-z]+)_", p.name).group(1)
        for p in SRC.glob("*_nb1.png") if re.match(r"([a-z]+)_", p.name)})
    print("звери:", ", ".join(names))
    if dry_run:
        print("РЕЖИМ DRY-RUN: ничего не будет записано на диск")
    ok = []
    for name in names:
        print(f"=== {name}")
        if build_set(name, 54, dry_run=dry_run):
            ok.append(name)
        else:
            print(f"  {name}: набор НЕ СОБРАН")
    print(f"\nсобрано наборов: {len(ok)} из {len(names)} -> {ok}")
    return 0 if len(ok) == len(names) else 2


if __name__ == "__main__":
    sys.exit(main())