#!/usr/bin/env python3
"""Нарезка листа курсора в кадры игры: assets/ui/cursor/{normal,cast}/.

КОНВЕЙЕР (запускать только после одобрения игроком листа из gen_cursor_strip):
  python tests/extract_cursor_frames.py --variant normal
  python tests/extract_cursor_frames.py --variant cast
  ... затем в Godot: --headless --import (новые PNG без импорта не грузятся).

Что делает:
  * режет лист по 4 равным четвертям ширины (объекты компактны и не слипаются
    хвостами, компоненты не нужны — прелёт гарантирует зазоры);
  * альфа развымешивается математически (v2, 22.10, вердикт игрока «уже
    лучше»): пиксель листа = alpha·цвет + (1-alpha)·маджента; alpha берётся
    проекцией (px - BG) на направление (средний цвет объекта - BG), цвет
    очищается обратной подстановкой. Прежняя цепочка (жёсткая маска +
    defringe + эрозия alpha MinFilter(3)) съедала тонкие линии: шток стрелы
    в 32 px имеет толщину 1-2 px, после эрозии оставалось 69 непрозрачных
    px из ожидаемых ~190 — «узкая стрела с непонятным свечением»;
  * масштабирует LANCZOS так, чтобы самая длинная сторона = CONTENT
    (26 px в холсте 32×32). Ресемплинг LANCZOS — осознанное исключение из
    правила nearest (прецедент gen_loot_icons_derived.py), документирован;
  * привязка в холсте по варианту: normal — якорь ВЕРХ-ЛЕВО (острие стрелки),
    cast — якорь ЦЕНТР (сигил);
  * hotspot в cursor_meta.json: normal = верхний-левый пиксель КРУПНЕЙШЕЙ
    связной компоненты кадра 0 (перо; рядом парящая искра-огонёк не должна
    стать hotspot), cast = центр объекта;
  * пишет _contact_sheet.png для просмотра игроком.

Выход: assets/ui/cursor/<variant>/cursor-000.png… + cursor_meta.json
       assets/ui/cursor/<variant>_contact_sheet.png
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "import" / "Cursor"
OUT_ROOT = REPO / "assets" / "ui" / "cursor"
PANELS = 4
CANVAS = 32
CONTENT = 26  # самая длинная сторона контента внутри холста


def fg_mask(img):
    a = np.array(img.convert("RGB")).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bg = (g < 110) & (r > 140) & (b > 140) & ((r - g) > 50)
    return ~bg


def unmix_frame(crop, cm):
    """RGBA из RGB-кропа: alpha и цвет развымешиваются от мадженты (v2).

    пиксель = alpha·fg + (1-alpha)·BG, BG=(255,0,255). Направление d =
    средний цвет объекта - BG; alpha = проекция (px-BG) на d, цвет =
    (px-(1-alpha)·BG)/alpha с клампом. Полупрозрачные кромки сохраняются,
    эрозии нет — она съедала тонкие линии (инцидент 22.10).
    """
    px = np.asarray(crop, dtype=float)
    bg = np.array([255.0, 0.0, 255.0])
    fgm = px[cm].mean(axis=0)
    d = fgm - bg
    denom = max(float(np.linalg.norm(d)) ** 2, 1e-6)
    t = np.clip(((px - bg) @ d) / denom, 0.0, 1.0)
    tt = np.maximum(t[..., None], 1e-3)
    clean = np.clip((px - (1.0 - tt) * bg) / tt, 0, 255)
    out = np.concatenate([clean, t[..., None] * 255.0], axis=2)
    return out.astype(np.uint8)


def largest_component_top_left(alpha):
    """Верхний-левый пиксель крупнейшей связной компоненты (4-связность)."""
    m = alpha > 0
    h, w = m.shape
    lab = np.zeros((h, w), np.int32)
    cur = 0
    best_lab, best_area = 0, 0
    for yy in range(h):
        for xx in range(w):
            if not m[yy, xx] or lab[yy, xx]:
                continue
            cur += 1
            stack = [(yy, xx)]
            lab[yy, xx] = cur
            area = 0
            while stack:
                cy, cx = stack.pop()
                area += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = cur
                        stack.append((ny, nx))
            if area > best_area:
                best_area, best_lab = area, cur
    wys, wxs = np.where((lab == best_lab) & m)
    return [int(wxs.min()), int(wys.min())]


def process(src_path, variant):
    img = Image.open(src_path).convert("RGB")
    w, h = img.size
    mask = fg_mask(img)
    frames = []
    for i in range(PANELS):
        x0, x1 = w * i // PANELS, w * (i + 1) // PANELS
        sub = mask[:, x0:x1]
        ys, xs = np.where(sub)
        if ys.size == 0:
            raise SystemExit(f"кадр {i} пуст — лист не годен")
        box = (x0 + int(xs.min()), int(ys.min()),
               x0 + int(xs.max()) + 1, int(ys.max()) + 1)
        crop = img.crop(box)
        # пропорционально до CONTENT, LANCZOS (см. докстринг)
        cw, ch = crop.size
        scale = CONTENT / max(cw, ch)
        crop = crop.resize((max(1, round(cw * scale)), max(1, round(ch * scale))),
                           Image.LANCZOS)
        cm = fg_mask(crop)
        rgba = unmix_frame(crop, cm)
        crop = Image.fromarray(rgba, "RGBA")

        canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        if variant == "normal":
            # острие стрелки — в верх-лево холста, hotspot = острие
            px = 1
            py = 1
        else:
            # сигил — по центру холста
            px = (CANVAS - crop.size[0]) // 2
            py = (CANVAS - crop.size[1]) // 2
        canvas.paste(crop, (px, py))
        frames.append(np.array(canvas))

    out_dir = OUT_ROOT / variant
    out_dir.mkdir(parents=True, exist_ok=True)
    hotspot = (largest_component_top_left(frames[0][..., 3])
               if variant == "normal" else [CANVAS // 2, CANVAS // 2])
    for i, fr in enumerate(frames):
        Image.fromarray(fr).save(out_dir / f"cursor-{i:03d}.png")
    meta = {"variant": variant, "canvas": CANVAS, "frames": PANELS,
            "hotspot": hotspot, "source": str(src_path.relative_to(REPO))}
    (out_dir / "cursor_meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

    # контакт-лист 1×4 на тёмном фоне (курсоры полупрозрачные)
    sheet = Image.new("RGB", (CANVAS * PANELS, CANVAS), (24, 20, 16))
    for i, fr in enumerate(frames):
        sheet.paste(Image.fromarray(fr), (CANVAS * i, 0), Image.fromarray(fr))
    sheet_path = OUT_ROOT / f"{variant}_contact_sheet.png"
    sheet.save(sheet_path)
    op = int(sum((fr[..., 3] > 128).sum() for fr in frames))
    print(f"{variant}: {PANELS} кадров -> {out_dir}, непрозрачных px всего {op}")
    print(f"hotspot {hotspot}, метаданные + контакт-лист: {sheet_path}")
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=("normal", "cast", "buy", "work"),
                    required=True)
    ap.add_argument("--src", default="")
    args = ap.parse_args()
    src = Path(args.src) if args.src else SRC / f"cursor_{args.variant}.png"
    if not src.exists():
        raise SystemExit(f"нет исходного листа: {src}")
    process(src, args.variant)
    print("не забыть: --headless --import в Godot до парсинга")


if __name__ == "__main__":
    main()
