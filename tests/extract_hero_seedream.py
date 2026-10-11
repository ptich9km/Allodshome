#!/usr/bin/env python3
"""Нарезка геройских атласов seedream в кадры units_db.

Контракт кадра (тот же, что у ork_mage_a52, проверен замером):
холст 64x64, высота контента 52, низ контента на y=62, центрирование по X.

Раскладка кадров повторяет unit_anim.gd для dirs=8:
  idle   frame = dir                              -> 0..7
  move   frame = idle_phases + dir*move + phase  -> 8..23
  attack frame = idle_phases + move*8 + dir*4 + phase -> 24..55
Итого 56 кадров.

Magenta снимается заливкой от краёв ячейки (фон связен), остатки - порогом
по оттенку (r-g и b-g высокие одновременно). Порог по связности тут не
работает: диффузия оставляет пурпур в просветах, а связность заливает
настоящие тёмные детали брони.

Использование:
  python tests/extract_hero_seedream.py            # нарезать
  python tests/extract_hero_seedream.py --check    # только замеры, без записи
"""
import argparse
from collections import deque
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
IMPORT = REPO / "import"
OUT = REPO / "assets" / "units" / "heroes" / "sw_seed"

CANVAS = 64
CONTENT_H = 52
FEET_Y = 62

DIRS = 8
IDLE_PHASES = 8
MOVE_PHASES = 2
ATTACK_PHASES = 2

# Остатки пурпура после заливки: у магенты r-g и b-g высокие ОДНОВРЕМЕННО.
MAG_RG = 45
MAG_BG = 40
# Мягкий срез альфы по пурпурности (минимум/максимум превышения min(r,b) над g).
MAG_LO = 15
MAG_HI = 50

TURN8 = IMPORT / "_hero_idle.png"     # 8 направлений, стойка
ATK_A_SRC = IMPORT / "_hero_atk_a.png"   # замах + удар
ATK_B_SRC = IMPORT / "_hero_atk_b.png"   # спад + возврат
WALK_SRC = IMPORT / "_hero_walk.png"     # два шага

IDLE = "idle"
ATK_A = "atkA"
ATK_B = "atkB"
WALK = "walk"


def is_magenta(px: int) -> bool:
    r = (px >> 16) & 0xFF
    g = (px >> 8) & 0xFF
    b = px & 0xFF
    return (r - g) > MAG_RG and (b - g) > MAG_BG


def load_rgb(path: Path):
    return Image.open(path).convert("RGB")


def cut_background(im: Image.Image) -> Image.Image:
    """Порог по пурпуру + отсечение по главной компоненте.

    Заливка от краёв здесь НЕ работает: ячейки атласа обведены тёмно-серыми
    линиями сетки, фон внутри ячейки от них отрезан, и заливка не доходит до
    пурпура - он остаётся прямоугольником вокруг фигуры. Поэтому фон ищется
    по цвету везде, а оставшиеся крапинки пурпура внутри силуэта и тёмные
    линии сетки убирает отсечение по главной компоненте.
    """
    w, h = im.size
    px = im.load()
    fg = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if not is_magenta((r << 16) | (g << 8) | b):
                fg[y * w + x] = 1

    # главная компонента связности (4-связная)
    lab = bytearray(w * h)
    best_id = -1
    best_size = 0
    cur = 1
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if not fg[i] or lab[i]:
                continue
            q = deque([(x, y)])
            lab[i] = cur
            n = 0
            while q:
                cx, cy = q.popleft()
                n += 1
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = cx + dx, cy + dy
                    if 0 <= xx < w and 0 <= yy < h:
                        j = yy * w + xx
                        if fg[j] and not lab[j]:
                            lab[j] = cur
                            q.append((xx, yy))
            if n > best_size:
                best_size = n
                best_id = cur
            cur += 1

    if best_size == 0:
        raise SystemExit("пустая ячейка: персонаж не найден")

    # Эрозия на 1 px: seedream отдаёт JPEG, и по контуру фигуры остаётся
    # пурпурный ринг от магентового фона. Он связен с фигурой, поэтому
    # переживает отсечение по компоненте, но это не арт - это кайма.
    keep = bytearray(w * h)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            i = y * w + x
            if (lab[i] == best_id and lab[i - 1] == best_id and lab[i + 1] == best_id
                    and lab[i - w] == best_id and lab[i + w] == best_id):
                keep[i] = 1

    out = im.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            if not keep[y * w + x]:
                op[x, y] = (255, 0, 255)
    return out


GRID_INSET = 8


def _bg_mask(im: Image.Image):
    w, h = im.size
    a = im.tobytes()
    mask = bytearray(w * h)
    for i in range(w * h):
        r = a[i * 3]
        g = a[i * 3 + 1]
        b = a[i * 3 + 2]
        if not ((r - g) > MAG_RG and (b - g) > MAG_BG):
            mask[i] = 1
    return mask, w, h


MIN_GAP = 30


def _bands(empty: list, n: int) -> list:
    """Полосы пустых строк/столбцов -> границы сегментов (границы ячеек).

    Узкие полосы игнорируются: щель между ногами шириной 7 px - это не
    разделитель ячеек, и без фильтра лист 2048x1022 делится на 10 ячеек
    вместо 8.
    """
    cuts = []
    i = 0
    while i < n:
        if empty[i]:
            j = i
            while j + 1 < n and empty[j + 1]:
                j += 1
            if j - i + 1 >= MIN_GAP:
                cuts.append((i, j))
            i = j + 1
        else:
            i += 1
    return cuts


def _runs(segments: list, n: int) -> list:
    """Из полос вырезает неп��стырные участки (ячейки)."""
    runs = []
    prev_end = 0
    for (s, e) in segments:
        if s > prev_end:
            runs.append((prev_end, s))
        prev_end = e + 1
    if prev_end < n:
        runs.append((prev_end, n))
    return runs


def _erase_grid_lines(mask: list, w: int, h: int, max_run: int = 12,
                      fill: float = 0.8) -> list:
    """Стирает тёмные линии сетки.

    Без этого шага разметка компонент не работает вовсе: линия идёт через весь
    атлас и соединяет все фигуры в одну компоненту (замер: move - одна
    компонента 1024x1024 на все 24 фигуры, atkA - 2048x1024).

    Линия - это узкая (не шире max_run) полоса колонок, в которой фон занят
    почти по всей высоте; фигура такой полосой быть не может, она занимает
    меньше трети высоты.
    """
    col_cnt = [0] * w
    row_cnt = [0] * h
    for y in range(h):
        row = y * w
        for x in range(w):
            if mask[row + x]:
                col_cnt[x] += 1
                row_cnt[y] += 1

    thr_c = fill * h
    thr_r = fill * w
    drop_c = bytearray(w)
    x = 0
    while x < w:
        if col_cnt[x] >= thr_c:
            j = x
            while j + 1 < w and col_cnt[j + 1] >= thr_c:
                j += 1
            if j - x + 1 <= max_run:
                for k in range(x, j + 1):
                    drop_c[k] = 1
            x = j + 1
        else:
            x += 1

    drop_r = bytearray(h)
    y = 0
    while y < h:
        if row_cnt[y] >= thr_r:
            j = y
            while j + 1 < h and row_cnt[j + 1] >= thr_r:
                j += 1
            if j - y + 1 <= max_run:
                for k in range(y, j + 1):
                    drop_r[k] = 1
            y = j + 1
        else:
            y += 1

    if not any(drop_c) and not any(drop_r):
        return mask

    out = list(mask)
    for y in range(h):
        if drop_r[y]:
            for x in range(w):
                out[y * w + x] = 0
        else:
            row = y * w
            for x in range(w):
                if drop_c[x]:
                    out[row + x] = 0
    return out


MERGE_GAP = 8


def _merge_near(figs: list) -> list:
    """Склеивает компоненты, оказавшиеся рядом: отрезанный кусок фигуры или
    две слипшиеся фигуры в одной компоненте дают лишние боксы."""
    boxes = [list(f) for f in figs]
    changed = True
    while changed:
        changed = False
        for i in range(len(boxes)):
            if boxes[i] is None:
                continue
            for j in range(i + 1, len(boxes)):
                if boxes[j] is None:
                    continue
                a, b = boxes[i], boxes[j]
                gap_x = max(a[0] - b[2], b[0] - a[2])
                gap_y = max(a[1] - b[3], b[1] - a[3])
                ov_y = min(a[3], b[3]) - max(a[1], b[1])
                if gap_x <= MERGE_GAP and gap_y <= MERGE_GAP and ov_y > 0:
                    boxes[i] = [min(a[0], b[0]), min(a[1], b[1]),
                                max(a[2], b[2]), max(a[3], b[3]),
                                a[4] + b[4]]
                    boxes[j] = None
                    changed = True
                    break
            if changed:
                break
    return [b for b in boxes if b is not None]


def detect_figures(im: Image.Image):
    """Возвращает список (x0, y0, x1, y1, area) - bbox каждой фигуры.

    Раскладку задаёт seedream сам, поэтому ячейки не ищутся: ищутся сами фигуры
    как связные компоненты после стирания линий сетки. Количество сверяется
    вызывающим - при несовпадении генерация повторяется.
    """
    mask, w, h = _bg_mask(im)
    mask = _erase_grid_lines(mask, w, h)
    lab = [0] * (w * h)
    cur = 0
    figs = []
    min_area = max(2000, (w * h) // 3000)
    for i in range(w * h):
        if not mask[i] or lab[i]:
            continue
        cur += 1
        q = deque([i])
        lab[i] = cur
        n = 0
        x0 = y0 = 1 << 30
        x1 = y1 = -1
        while q:
            p = q.popleft()
            n += 1
            y, x = divmod(p, w)
            if x < x0:
                x0 = x
            if x > x1:
                x1 = x
            if y < y0:
                y0 = y
            if y > y1:
                y1 = y
            if x > 0 and mask[p - 1] and not lab[p - 1]:
                lab[p - 1] = cur
                q.append(p - 1)
            if x + 1 < w and mask[p + 1] and not lab[p + 1]:
                lab[p + 1] = cur
                q.append(p + 1)
            if y > 0 and mask[p - w] and not lab[p - w]:
                lab[p - w] = cur
                q.append(p - w)
            if y + 1 < h and mask[p + w] and not lab[p + w]:
                lab[p + w] = cur
                q.append(p + w)
        bw, bh = x1 - x0 + 1, y1 - y0 + 1
        if n < min_area:
            continue
        # линейная структура = остаток линии сетки
        if max(bw, bh) / max(1, min(bw, bh)) > 15:
            continue
        figs.append((x0, y0, x1, y1, n))
    return _merge_near(figs)


def detect_grid(im: Image.Image):
    """Сетка атласа находится по полосам почти полностью пурпурных полос.

    Строгий тест «все пиксели фона» не работает: seedream отдаёт JPEG, и в
    промежутке остаётся шум, из-за чего 8 ячеек читались как 5 (замер: полосы
    шириной 556 и 756 - это слипшиеся по 2-3 ячейки). Поэтому щель - это
    колонка, где доля персонажа меньше 2%.
    """
    mask, w, h = _bg_mask(im)
    col_empty = []
    for x in range(w):
        cnt = 0
        for y in range(h):
            cnt += mask[y * w + x]
        col_empty.append(cnt <= h * 0.02)
    row_empty = []
    for y in range(h):
        cnt = 0
        row = y * w
        for x in range(w):
            cnt += mask[row + x]
        row_empty.append(cnt <= w * 0.02)
    cols = _runs(_bands(col_empty, w), w)
    rows = _runs(_bands(row_empty, h), h)
    return cols, rows


def cell(im: Image.Image, col: int, row: int, cols: list, rows: list) -> Image.Image:
    """Ячейка по найденным границам, с отступом от краёв полосы."""
    x0, x1 = cols[col]
    y0, y1 = rows[row]
    ins = GRID_INSET
    return im.crop((x0 + ins, y0 + ins, max(x0 + ins + 1, x1 - ins),
                    max(y0 + ins + 1, y1 - ins)))


def _magenta_ness(r: int, g: int, b: int) -> float:
    """0 = не пурпур, 1 = чистый пурпурный фон."""
    lo = min(r, b)
    d = lo - g
    if d <= MAG_LO:
        return 0.0
    if d >= MAG_HI:
        return 1.0
    return (d - MAG_LO) / float(MAG_HI - MAG_LO)


ERODE = 2


def fit(im: Image.Image) -> Image.Image:
    """Контент -> высота 52 -> холст 64x64, низ на y=62, центр по X.

    bbox - прямоугольник, а фигура им не является, поэтому углы прямоугольника
    попадают в кадр вместе с фоном. После вписывания альфа гасится по
    пурпурности с мягким краем: без этого каждый кадр выходил с пурпурной
    рамкой (замер: 414 пурпурных пикселей на фигуре 884 пикселя).

    Перед вписыванием силуэт эродируется на ERODE пикселей. Иначе LANCZOS
    смешивает край фигуры с пурпурным фоном, и по контуру остаётся фиолетовая
    кайма - её уже не поймать гашением, потому что цвет пикселя изменён.
    """
    w, h = im.size
    px = im.load()
    xs0, ys0, xs1, ys1 = w, h, -1, -1
    solid = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if _magenta_ness(r, g, b) < 0.5:
                solid[y][x] = True
                if x < xs0:
                    xs0 = x
                if x > xs1:
                    xs1 = x
                if y < ys0:
                    ys0 = y
                if y > ys1:
                    ys1 = y
    if xs1 < 0:
        raise SystemExit("пустая ячейка: персонаж не найден")

    cw, ch = xs1 - xs0 + 1, ys1 - ys0 + 1
    # Сторож на «фигура не вырезалась, а взялась вся ячейка с линиями сетки».
    # Тогда ширина после вписывания в 52 px схлопывается втрое.
    if cw > ch * 1.2:
        raise SystemExit(
            "подозрение на невырезанную фигуру: bbox %dx%d (ширина > высоты)" % (cw, ch))

    src = im.crop((xs0, ys0, xs1 + 1, ys1 + 1))
    sw, sh = src.size
    sp = src.load()
    eroded = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    ep = eroded.load()
    for y in range(sh):
        for x in range(sw):
            keep = True
            for dy in range(-ERODE, ERODE + 1):
                for dx in range(-ERODE, ERODE + 1):
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= sw or ny >= sh or not solid[ys0 + ny][xs0 + nx]:
                        keep = False
                        break
                if not keep:
                    break
            if keep:
                ep[x, y] = sp[x, y] + (255,)

    scale = CONTENT_H / float(sh)
    nw = max(1, int(round(sw * scale)))
    rgba = eroded.resize((nw, CONTENT_H), Image.LANCZOS)

    ap = rgba.load()
    for y in range(CONTENT_H):
        for x in range(nw):
            r, g, b, a = ap[x, y]
            t = _magenta_ness(r, g, b)
            if t > 0.0:
                r = int(r + (255 - r) * t)
                g = int(g + (0 - g) * t)
                b = int(b + (255 - b) * t)
                ap[x, y] = (r, g, b, int(round(a * (1.0 - t))))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(rgba, ((CANVAS - nw) // 2, FEET_Y - CONTENT_H + 1))
    return canvas


def build():
    """Карта источников: (фаза, направление) -> атлас, колонка, строка.

    Раскладка задаётся промежутками, а не делением на 8: seedream ставит
    полосы как удобно, и жёсткое деление даёт ячейки с полутором персонажа.
    Число ячеек сверяется в check_grid(), при несовпадении атлас
    генерируется заново.
    """
    sources = [
        ("idle", IDLE, 1, TURN8),
        ("atk0", ATK_A, 2, ATK_A_SRC),
        ("atk1", ATK_A, 2, ATK_A_SRC),
        ("move0", WALK, 2, WALK_SRC),
        ("move1", WALK, 2, WALK_SRC),
    ]
    grids = {}
    for tag, path, want_rows, src in sources:
        key = str(src)
        if key not in grids:
            im = load_rgb(src)
            cols, rows = detect_grid(im)
            grids[key] = (im, cols, rows)
            print("%-28s -> %d x %d ячеек (ожидалось 8 x %d)"
                  % (src.name, len(cols), len(rows), want_rows))
        grids[key][0]  # noqa: B018
    return sources, grids


def check_grid(sources, grids) -> None:
    bad = []
    for tag, path, want_rows, src in sources:
        im, cols, rows = grids[str(src)]
        if len(cols) != DIRS or len(rows) != want_rows:
            bad.append("%s: %d x %d вместо %d x %d"
                       % (src.name, len(cols), len(rows), DIRS, want_rows))
    if bad:
        raise SystemExit(
            "раскладка атласа не сошлась, нужен повтор генерации:\n  "
            + "\n  ".join(bad))


def frame_index(name: str, direction: int) -> int:
    if name == "idle":
        return direction
    if name.startswith("move"):
        phase = int(name[4:])
        return IDLE_PHASES + direction * MOVE_PHASES + phase
    if name.startswith("atk"):
        phase = int(name[3:])
        return IDLE_PHASES + MOVE_PHASES * DIRS + direction * ATTACK_PHASES + phase
    raise SystemExit("unknown phase " + name)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="только замеры, не писать")
    args = ap.parse_args()

    sources, grids = build()
    check_grid(sources, grids)

    total = IDLE_PHASES + MOVE_PHASES * DIRS + ATTACK_PHASES * DIRS
    print("кадров в наборе: %d" % total)

    frames = {}
    for tag, path, want_rows, src in sources:
        im, cols, rows = grids[str(src)]
        row_index = {"idle": 0, "move0": 0, "move1": 1,
                     "atk0": 0, "atk1": 1, "atk2": 0, "atk3": 1}[tag]
        for d in range(DIRS):
            raw = cell(im, d, row_index, cols, rows)
            cut = cut_background(raw)
            frames.setdefault(frame_index(tag, d), fit(cut))

    missing = [i for i in range(total) if i not in frames]
    if missing:
        raise SystemExit("нет кадров: %s" % missing)
    print("нарезано кадров: %d" % len(frames))

    widths = []
    heights = []
    feet = []
    for i in range(total):
        a = frames[i].split()[3]
        bb = a.getbbox()
        if bb is None:
            continue
        widths.append(bb[2] - bb[0])
        heights.append(bb[3] - bb[1])
        feet.append(bb[3] - 1)
    print("контент: ширина %d..%d, высота %d..%d, низ %d..%d"
          % (min(widths), max(widths), min(heights), max(heights),
             min(feet), max(feet)))

    if args.check:
        return

    OUT.mkdir(parents=True, exist_ok=True)
    for i in range(total):
        frames[i].save(OUT / ("sprites-%03d.png" % (i + 1)))
    print("записано в", OUT.relative_to(REPO))


if __name__ == "__main__":
    main()