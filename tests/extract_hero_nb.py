#!/usr/bin/env python3
"""Набор героя из полос Nano Banana (google/gemini-nano-banana-2.1), 4 панели.

Почему 4 панели, а не 8 (замер 14.10): 8 фигур по ~190px на 1536px физически
не помещаются — в промежутках удара было 15-72px ЧУЖОЙ руки, в промежутках
смерти до 234px. Четыре фигуры занимают по ~380px, зазоры выходят 50-285px.

Почему «сильный» порог (замер 14.10): полоса удара пришла с двумя рядами —
сверху полупрозрачные призрачные фигуры, снизу настоящие. Отличаются они
насыщенностью: у настоящих пиксели далеко от цвета фона (сталь/кожа/ткань),
у призраков размыты и к фону близки. Поэтому фигуры ищем по dist > 120,
а вырезку делаем заливкой от краёв по расстоянию до цвета углов.

Ряды: у полосы удара призраки и фигуры в одних колонках, поэтому сначала
режем изображение по горизонтали и берём полосу с максимумом «сильных»
пикселей.

Контракт набора: dirs=1 + зеркало, холст 64x64, низ контента y=62,
idle 1 + move 4 + attack 3 + dying 4 = 12 кадров.

Почему в ударе 3, а не 4 (замер 14.10): 4-я панель полосы удара совпала с
3-й — та же полная вытяжка, разницы в позе нет. Цикл замыкается сам:
стойка -> замах -> удар -> возврат в стойку (1-й кадр = последний).
"""
import argparse
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "import" / "Player"

# Полосы и наборы. Мужская ветка (nb5) — по умолчанию, женская (nb6)
# добавляется флагами, чтобы старая команда из журнала работала как раньше.
SETS = {
    "nb5": ("war_men", "war men"),
    "nb6": ("war_women", "war women"),
}

OUT_W, OUT_H, FEET_Y, TARGET_H = 64, 64, 62, 54
TOL = 45          # заливка фона от краёв
STRONG = 120      # порог «настоящей» фигуры против призрака
MIN_COL = 5       # колонка короче — не фигура


def bg_ref(a):
    h, w, _ = a.shape
    corners = np.concatenate([
        a[:24, :24].reshape(-1, 3), a[:24, -24:].reshape(-1, 3),
        a[-24:, :24].reshape(-1, 3), a[-24:, -24:].reshape(-1, 3)])
    return np.median(corners, axis=0)


def cut_mask(a, ref, tol=TOL):
    h, w, _ = a.shape
    dist = np.sqrt(((a - ref) ** 2).sum(axis=2))
    dark_magenta = (a[..., 1] < a[..., 2] - 25) & ((a[..., 0] - a[..., 1]) > 60)
    near = (dist <= tol) | dark_magenta
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    fg = ~seen
    fg &= ~near
    return fg.astype(np.float32)


def row_band(strong):
    """Горизонтальные полосы контента; берём ту, где больше «сильных» пикселей.

    Замер 14.10: модель на двух полос из четырёх вернула 8 фигур в ДВА ряда
    (у удара второй ряд дословно копия первого). Берём один ряд — 4 фигуры,
    вторая копия нам не нужна. Если полос больше двух, это уже не «лишний ряд»,
    а мусор, и такой кадр лучше забраковать loudly, чем молча взять верхний.
    """
    rows = strong.sum(axis=1)
    active = rows >= 5
    bands, start = [], -1
    for y, v in enumerate(active):
        if v and start < 0:
            start = y
        elif not v and start >= 0:
            bands.append((start, y - 1))
            start = -1
    if start >= 0:
        bands.append((start, len(active) - 1))
    if len(bands) > 2:
        print(f"    ВНИМАНИЕ: полос контента {len(bands)} — это не лишний ряд, "
              f"а мусор: {bands}")
    best, best_area = bands[0], -1
    for y0, y1 in bands:
        area = int(strong[y0:y1 + 1].sum())
        print(f"    полоса y={y0}..{y1} h={y1 - y0 + 1} сильных={area}")
        if area > best_area:
            best, best_area = (y0, y1), area
    if len(bands) > 1:
        print(f"    берём полосу с максимумом сильных: y={best[0]}..{best[1]}")
    return best


def label_keep_largest(alpha):
    m = alpha > 0.5
    h, w = m.shape
    lab = np.zeros((h, w), dtype=np.int32)
    cur = 0
    for y in range(h):
        row = m[y]
        for x in range(w):
            if not row[x] or lab[y, x]:
                continue
            cur += 1
            stack = [(y, x)]
            lab[y, x] = cur
            while stack:
                cy, cx = stack.pop()
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = cur
                        stack.append((ny, nx))
    if cur <= 1:
        return alpha
    areas = np.bincount(lab.ravel(), minlength=cur + 1)
    areas[0] = 0
    keep = areas >= areas.max() * 0.25
    keep[0] = False
    out = alpha.copy()
    out[~keep[lab]] = 0.0
    return out


def figures_of(path, expect):
    a = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    ref = bg_ref(a)
    dist = np.sqrt(((a - ref) ** 2).sum(axis=2))
    strong = dist > STRONG
    y0, y1 = row_band(strong)
    alpha_full = cut_mask(a, ref)
    alpha = alpha_full[y0:y1 + 1]

    col = (alpha > 0.5).sum(axis=0)
    active = col >= MIN_COL
    runs, start = [], -1
    for x, v in enumerate(active):
        if v and start < 0:
            start = x
        elif not v and start >= 0:
            runs.append((start, x - 1))
            start = -1
    if start >= 0:
        runs.append((start, len(active) - 1))
    print(f"    фигур найдено: {len(runs)} (ожидалось {expect})")

    # Соприкасающиеся фигуры дают один широкий кусок (замер 14.10: в полосе
    # удара третий кусок 1322px против ~500 у остальных — это две фигуры,
    # кулаки коснулись). Делим такой кусок по минимуму профиля колонок.
    if runs:
        changed = True
        while changed:
            changed = False
            # Медиана пересчитывается НА КАЖДОМ проходе. Раньше она считалась
            # один раз до цикла, и это ломало дорез кусков из трёх фигур:
            # первый проход резал 1842px пополам, второй видел 1174px против
            # старой медианы 1197 и не резал их больше (женская полоса удара
            # 14.10: слиплись фигуры 2, 3 и 4 — процесс останавливался на 3).
            med = float(np.median([b - a0 for a0, b in runs]))
            out = []
            for x0, x1 in runs:
                if x1 - x0 > med * 1.5 and (x1 - x0) > 40:
                    prof = alpha[:, x0:x1 + 1].sum(axis=0).astype(float)
                    lo, hi = int(len(prof) * 0.25), int(len(prof) * 0.75)
                    cut = lo + int(np.argmin(prof[lo:hi]))
                    print(f"    дорез слипшегося куска x={x0}..{x1} на x={x0 + cut}")
                    out += [(x0, x0 + cut), (x0 + cut + 1, x1)]
                    changed = True
                else:
                    out.append((x0, x1))
            runs = out
        if len(runs) != expect:
            print(f"    после дореза фигур: {len(runs)} (ожидалось {expect})")

    out = []
    for x0, x1 in runs:
        sub = alpha[:, x0:x1 + 1]
        sub = label_keep_largest(sub)
        ys, xs = np.where(sub > 0.5)
        if ys.size == 0:
            out.append(None)
            continue
        ry0, ry1, rx0, rx1 = int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max())
        full = alpha_full[y0 + ry0:y0 + ry1 + 1, x0 + rx0:x0 + rx1 + 1]
        crop = a[y0 + ry0:y0 + ry1 + 1, x0 + rx0:x0 + rx1 + 1]
        print(f"      w={rx1 - rx0 + 1} h={ry1 - ry0 + 1}")
        out.append((crop, full))
    return out


def fit(rgb, alpha, scale):
    h, w = alpha.shape
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    a_src = (alpha * 255).astype(np.uint8)
    prem = (rgb.astype(np.float32) * alpha[:, :, None]).astype(np.uint8)
    a_s = np.asarray(Image.fromarray(a_src, "L").resize((nw, nh), Image.Resampling.BOX), np.float32) / 255
    p_s = np.asarray(Image.fromarray(prem, "RGB").resize((nw, nh), Image.Resampling.BOX), np.float32)
    rgb_s = np.clip(p_s / np.maximum(a_s, 1e-4)[:, :, None], 0, 255)
    a_s = np.where(a_s < 0.25, 0.0, np.minimum(1.0, a_s * 1.35))
    arr = np.dstack([rgb_s.round().astype(np.uint8), (a_s * 255).round().astype(np.uint8)])
    # Осколок соседней фигуры может возникнуть уже ПОСЛЕ уменьшения (в
    # источнике он касался руки, а на 64px отделился). Отбрасываем всё,
    # что меньше 15% главной компоненты — итоговой картинки, не источника.
    m = arr[:, :, 3] > 32
    lab = np.zeros(m.shape, np.int32)
    cur = 0
    h2, w2 = m.shape
    for y in range(h2):
        for x in range(w2):
            if not m[y, x] or lab[y, x]:
                continue
            cur += 1
            stack = [(y, x)]
            lab[y, x] = cur
            while stack:
                cy, cx = stack.pop()
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h2 and 0 <= nx < w2 and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = cur
                        stack.append((ny, nx))
    if cur > 1:
        areas = np.bincount(lab.ravel(), minlength=cur + 1)
        areas[0] = 0
        keep = areas >= areas.max() * 0.15
        keep[0] = False
        arr[~keep[lab], 3] = 0
        print(f"      убран осколок: {int(m.sum() - keep[lab].sum())} px")
    fr = Image.fromarray(arr, "RGBA")
    cell = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
    cell.paste(fr, ((OUT_W - nw) // 2, FEET_Y - nh), fr)
    return cell


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="nb5", choices=sorted(SETS),
                    help="тег полос: nb5 — воин, nb6 — воительница")
    args = ap.parse_args()

    out_folder, out_label = SETS[args.tag]
    out_dir = REPO / "assets" / "units" / "hero" / out_folder
    out_dir.mkdir(parents=True, exist_ok=True)

    blocks = []
    for name, fname, expect, take in [
        ("idle", f"hero_stand_{args.tag}.png", 4, 1),
        ("walk", f"hero_walk_{args.tag}.png", 4, 4),
        ("attack", f"hero_attack_{args.tag}.png", 4, 3),
        ("dying", f"hero_die_{args.tag}.png", 4, 4),
    ]:
        print(f"{name}: {fname}")
        figs = figures_of(SRC / fname, expect)
        if len(figs) != expect or any(f is None for f in figs):
            print(f"FAIL: {name} — фигур {len(figs)}, годных {sum(f is not None for f in figs)}")
            return 1
        blocks.append((name, figs[:take]))

    frames = []
    for name, figs in blocks:
        scale = TARGET_H / max(al.shape[0] for _, al in figs)
        print(f"{name}: max h={max(al.shape[0] for _, al in figs)} scale={scale:.4f}")
        for rgb, al in figs:
            frames.append(fit(rgb, al, scale))

    # Старые кадры от прошлых сборок (25 штук) удаляем: база объявит frames=13,
    # но лишние файлы остались бы в репозитории и импортировались движком.
    for old in sorted(out_dir.glob("sprites-*.png")):
        old.unlink()
    for i, fr in enumerate(frames):
        fr.save(out_dir / f"sprites-{i + 1:03d}.png")
    print(f"записано кадров: {len(frames)}")

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
    Image.fromarray(sheet).resize((cols * OUT_W * 3, rows * OUT_H * 3), Image.NEAREST) \
        .save(out_dir / "_contact_sheet.png")

    entry = {
        "desc": f"Hero: {out_label}, Gemini 3.1 Flash image preview 4-panel strips, "
                "three-quarter east view + mirror, idle1+move4+attack3+dying4",
        "folder": f"hero/{out_folder}", "frames": len(frames), "prefix": "sprites",
        "dirs": 1, "idle_phases": 1, "move": 4, "move_begin": 0,
        "attack": 3, "dying": 4, "decay": 0, "cast": 0, "idle": 0,
        "move_f": [], "move_t": [], "attack_f": [], "attack_t": [], "die_f": [], "dying_t": [],
        "w": OUT_W, "h": OUT_H, "cx": OUT_W // 2, "cy": FEET_Y,
        "tile": None, "projectile": -1, "palette": 0, "blocks": 4,
        "resist": {"fire": 10, "water": 10, "air": 10, "earth": 10, "astral": 10},
    }
    (out_dir / "_entry.json").write_text(json.dumps(entry, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print("обновлён _entry.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())