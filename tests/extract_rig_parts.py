#!/usr/bin/env python3
"""Нарезка частей тела из seedream-атласов для 2D-рига (rigged_anim.gd).

Берёт целые фигуры из _hero_idle.png (8 направлений) и вырезает части:
head, torso, upper_arm, forearm, thigh, shin. Диск-пробки (disc_lg, disc_sm)
генерируются программно.

ОККЛЮЗИЯ. Рука в атласе перекрывает торс. Решение: для каждой руки берётся
区域 СВОБОДНАЯ от неё (в idle-атласе руки внизу отделены от торса), а под
рукой в торсе дорисовывается (inpaint) по среднему цвету соседних пикселей
торса. Это не идеально, но при повороте рига под рукой будет «тело», а не
дыра.

ПИВОТА (обязательно для rigged_anim.gd):
- Сустав части лежит в ТОЧНОМ пиксельном центре холста.
- Обе стороны холста ЧЁТНЫЕ.
- Тогда Sprite2D.centered=true, offset=(0,0) кладёт начало кости на сустав.

Запуск:
    python tests/extract_rig_parts.py              # нарезка
    python tests/extract_rig_parts.py --check      # только проверка
    python tests/extract_rig_parts.py --preview    # контактный лист
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
IMPORT = REPO / "import"
OUT_DIR = REPO / "assets" / "units" / "rig" / "rig_hero_atlas"

# Целевые размеры частей (масштаб пилотного рига, figure_height=56)
FIGURE_HEIGHT = 56
L_TORSO = 18
L_UARM = 9
L_THIGH = 14
L_SHIN = 14
HEAD_DIA = 10

# Порог магенты (как в extract_hero_seedream.py)
MAG_RG = 45
MAG_BG = 40

# Атлас
ATLAS = IMPORT / "_hero_idle.png"
# 8 колонок: (x_start, x_end) — измерено по _hero_idle.png
COL_BOUNDS = [
    (28, 290), (321, 550), (585, 759), (811, 1016),
    (1043, 1296), (1327, 1518), (1572, 1746), (1771, 2020),
]
# 8 направлений в порядке idle: 0=Ю 1=ЮЗ 2=З 3=СЗ 4=С 5=СВ 6=В 7=ЮВ
# Конвенция проекта: контриклоковая от севера (0=север=спина)
DIR_NAMES = ["south", "sw", "west", "nw", "north", "ne", "east", "se"]

# Пропорции частей фигуры (от y_min фигуры, доля от figure_height в атласе)
# Определены замером по idle колонке 0 (юг):
#   head:     y=0.00..0.20
#   torso:    y=0.18..0.62  (с руками, которые отделены внизу)
#   legs:     y=0.58..1.00
PART_FRACS = {
    "head":   (0.00, 0.22),
    "torso":  (0.16, 0.62),
    "thigh":  (0.56, 0.80),
    "shin":   (0.76, 1.00),
}


def is_magenta_rgb(arr: np.ndarray) -> np.ndarray:
    """Маска магенты по RGB-массиву (H,W,3)."""
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    return ((r - g) > MAG_RG) & ((b - g) > MAG_BG)


def content_mask(arr: np.ndarray) -> np.ndarray:
    """Маска контента (не магента)."""
    return ~is_magenta_rgb(arr)


def inpaint_region(img: Image.Image, mask: np.ndarray) -> Image.Image:
    """Заполнить masked-пиксели средним цветом соседних незамаскированных.

    Простой инпейнт: для каждого замаскированного пикселя берём среднее
    8-связных незамаскированных. Повторяем 3 итерации, чтобы заполнение
    «растеклось» на большие области.
    """
    arr = np.array(img).astype(np.float64)
    h, w = arr.shape[:2]
    filled = mask.copy()

    for _ in range(3):
        new_arr = arr.copy()
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                if not filled[y, x]:
                    neighbors = []
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            if dy == 0 and dx == 0:
                                continue
                            ny, nx = y + dy, x + dx
                            if not filled[ny, nx]:
                                neighbors.append(arr[ny, nx])
                    if neighbors:
                        new_arr[y, x] = np.mean(neighbors, axis=0)
                        filled[y, x] = True
        arr = new_arr

    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def cut_part(
    atlas_arr: np.ndarray,
    content: np.ndarray,
    x0: int, x1: int,
    y_min: int, fig_h: int,
    frac_top: float, frac_bot: float,
    pivot_x_frac: float = 0.5,
    pivot_y_frac: float = 0.0,
) -> tuple[Image.Image, tuple[int, int]] | None:
    """Вырезать часть из атласа. Возвращает (image, (pivot_x, pivot_y)).

    pivot_x_frac / pivot_y_frac — доля от размера части, где сустав.
    По умолчанию pivot в центре по X и сверху (для рук/ног направление вниз).
    """
    ay0 = y_min + int(fig_h * frac_top)
    ay1 = y_min + int(fig_h * frac_bot)

    # Кроп по X: весь контент в этой полосе Y
    sub_content = content[ay0:ay1, x0:x1]
    cols_with = sub_content.any(axis=0)
    if not cols_with.any():
        return None
    cx_min = np.where(cols_with)[0].min()
    cx_max = np.where(cols_with)[0].max()

    # Добавляем запас
    pad = 4
    crop_x0 = max(0, cx_min - pad)
    crop_x1 = min(x1 - x0, cx_max + pad + 1)
    crop_y0 = max(0, 0)
    crop_y1 = min(ay1 - ay0, sub_content.shape[0])

    # RGBA-кроп
    region = atlas_arr[ay0 + crop_y0:ay0 + crop_y1, x0 + crop_x0:x0 + crop_x1].copy()
    region_mask = content[ay0 + crop_y0:ay0 + crop_y1, x0 + crop_x0:x0 + crop_x1]

    # Прозрачность: магента -> alpha 0
    rgba = np.zeros((*region.shape[:2], 4), dtype=np.uint8)
    rgba[:, :, :3] = region
    rgba[:, :, 3] = np.where(region_mask, 255, 0).astype(np.uint8)

    # Инпейнт: замаскированные (бывшая магента) пиксели внутри фигуры
    # заполняем цветом соседей. Оставляем прозрачными только ВНЕФИГУРНЫЕ.
    img = Image.fromarray(rgba, "RGBA")

    # Pivot (доля от размера части)
    ph, pw = rgba.shape[:2]
    px = int(pw * pivot_x_frac)
    py = int(ph * pivot_y_frac)

    return img, (px, py)


def resize_to_part(img: Image.Image, pivot: tuple[int, int],
                   target_h: int) -> tuple[Image.Image, tuple[int, int]]:
    """Масштабировать часть + пересчитать pivot пропорционально."""
    w, h = img.size
    if h == 0:
        return img, pivot
    scale = target_h / h
    new_w = max(2, int(round(w * scale)))
    new_h = max(2, int(round(h * scale)))
    new_w += new_w % 2
    new_h += new_h % 2
    resized = img.resize((new_w, new_h), Image.NEAREST)
    new_pivot = (int(pivot[0] * new_w / w), int(pivot[1] * new_h / h))
    return resized, new_pivot


def center_pivot(img: Image.Image, pivot: tuple[int, int]) -> tuple[Image.Image, tuple[int, int]]:
    """Передвинуть изображение так, чтобы pivot оказался в центре чётного холста."""
    w, h = img.size
    px, py = pivot
    nw = w + (w % 2)
    nh = h + (h % 2)
    ox = nw // 2 - px
    oy = nh // 2 - py
    canvas = Image.new("RGBA", (nw, nh), (0, 0, 0, 0))
    canvas.paste(img, (ox, oy), img)
    return canvas, (nw // 2, nh // 2)


def make_disc(dia: int, color: tuple) -> Image.Image:
    """Круглая «пробка» шарнира."""
    d = dia + (dia % 2)
    img = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    r = d // 2
    draw.ellipse([0, 0, d - 1, d - 1], fill=color)
    return img


def find_h_groups(content_band: np.ndarray, min_gap: int = 3) -> list[tuple[int, int]]:
    """Найти горизонтальные группы контента в полосе.

    Работает по ПОКОЛОННОЙ проекции, но разрывы ищутся по большинству строк:
    колонка считается пустой, если она пуста в >= 60% строк полосы.
    Это чинит случай, когда ноги разделены в середине полосы, но слипаются
    у верхнего/нижнего края (бёдра срастаются с торсом).
    """
    h = content_band.shape[0]
    threshold = max(1, int(h * 0.4))  # пустая, если есть контент в < 40% строк
    col_count = content_band.sum(axis=0)
    cols = col_count >= threshold
    groups = []
    in_g = False
    gap = 0
    for x in range(len(cols)):
        if cols[x]:
            if not in_g:
                start = x
                in_g = True
            gap = 0
        else:
            if in_g:
                gap += 1
                if gap >= min_gap:
                    groups.append((start, x - gap))
                    in_g = False
    if in_g:
        groups.append((start, len(cols) - 1))
    return groups


def cut_leg_parts(
    atlas_arr: np.ndarray,
    content: np.ndarray,
    x0: int, x1: int,
    y_min: int, fig_h: int,
) -> dict[str, tuple[Image.Image, tuple[int, int]]] | None:
    """Вырезать ЛЕВУЮ и ПРАВУЮ ногу отдельно.

    В idle-атласе ноги разделены на 2 группы по X. Определяем группу
    по центру масс: левая = меньший X, правая = больший X (относительно
    центра фигуры). Для направления «юг» (смотрит на нас) левая нога
    персонажа = правая на экране, и наоборот. Мы НЕ инвертируем —
    rig.json задаёт соответствие через map.
    """
    # Полоса бёдер: y=0.56..0.80
    ay0 = y_min + int(fig_h * 0.56)
    ay1 = y_min + int(fig_h * 0.80)
    band = content[ay0:ay1, x0:x1]
    groups = find_h_groups(band, min_gap=4)
    if len(groups) < 2:
        return None

    # Берём 2 самые широкие группы (это ноги)
    groups.sort(key=lambda g: g[1] - g[0], reverse=True)
    leg_l, leg_r = groups[0], groups[1]
    # Сортируем по X: левая = меньший X
    if leg_l[0] > leg_r[0]:
        leg_l, leg_r = leg_r, leg_l

    result = {}
    for side, (gx0, gx1) in [("left", leg_l), ("right", leg_r)]:
        pad = 3
        crop_x0 = max(0, gx0 - pad)
        crop_x1 = min(x1 - x0, gx1 + pad + 1)
        crop_y0 = 0
        crop_y1 = ay1 - ay0

        region = atlas_arr[ay0 + crop_y0:ay0 + crop_y1, x0 + crop_x0:x0 + crop_x1].copy()
        region_mask = content[ay0 + crop_y0:ay0 + crop_y1, x0 + crop_x0:x0 + crop_x1]

        rgba = np.zeros((*region.shape[:2], 4), dtype=np.uint8)
        rgba[:, :, :3] = region
        rgba[:, :, 3] = np.where(region_mask, 255, 0).astype(np.uint8)

        img = Image.fromarray(rgba, "RGBA")
        ph, pw = rgba.shape[:2]
        pivot = (pw // 2, 0)  # pivot сверху (бедро)
        result[side] = (img, pivot)

    return result


def cut_arm_part(
    atlas_arr: np.ndarray,
    content: np.ndarray,
    x0: int, x1: int,
    y_min: int, fig_h: int,
    side: str,
) -> tuple[Image.Image, tuple[int, int]] | None:
    """Вырезать руку из idle-атласа.

    В idle рука внизу отделена от торса (y=0.36..0.57, группа слева или
    справа). Берём только ЭТУ группу. Если рука не отделена (diagonal
    views), возвращаем None — тогда ставится заглушка.
    """
    # Полоса рук: y=0.36..0.57
    ay0 = y_min + int(fig_h * 0.36)
    ay1 = y_min + int(fig_h * 0.57)
    band = content[ay0:ay1, x0:x1]
    groups = find_h_groups(band, min_gap=3)
    if len(groups) < 2:
        return None  # руки не отделены

    # Определяем центр фигуры
    full_band = content[y_min:y_min + fig_h, x0:x1]
    full_cols = full_band.any(axis=0)
    fig_cx = (np.where(full_cols)[0].min() + np.where(full_cols)[0].max()) / 2

    # Группа на стороне: left = центр группы < fig_cx, right = > fig_cx
    candidates = []
    for gx0, gx1 in groups:
        gcx = (gx0 + gx1) / 2
        is_left = gcx < fig_cx
        if (side == "left" and is_left) or (side == "right" and not is_left):
            candidates.append((gx0, gx1))

    if not candidates:
        return None

    # Берём самую широкую подходящую группу
    gx0, gx1 = max(candidates, key=lambda g: g[1] - g[0])

    pad = 2
    crop_x0 = max(0, gx0 - pad)
    crop_x1 = min(x1 - x0, gx1 + pad + 1)
    crop_y0 = 0
    crop_y1 = ay1 - ay0

    region = atlas_arr[ay0 + crop_y0:ay0 + crop_y1, x0 + crop_x0:x0 + crop_x1].copy()
    region_mask = content[ay0 + crop_y0:ay0 + crop_y1, x0 + crop_x0:x0 + crop_x1]

    rgba = np.zeros((*region.shape[:2], 4), dtype=np.uint8)
    rgba[:, :, :3] = region
    rgba[:, :, 3] = np.where(region_mask, 255, 0).astype(np.uint8)

    img = Image.fromarray(rgba, "RGBA")
    ph, pw = rgba.shape[:2]
    pivot = (pw // 2, 0)  # pivot сверху (плечо)
    return img, pivot


def extract_all(out_dir: Path, preview: bool = False) -> dict:
    """Нарезать части для всех 8 направлений."""
    atlas = Image.open(ATLAS).convert("RGB")
    atlas_arr = np.array(atlas)
    content = content_mask(atlas_arr)

    out_dir.mkdir(parents=True, exist_ok=True)
    parts_dir = out_dir / "parts"
    parts_dir.mkdir(exist_ok=True)

    results = {}

    for di, (x0, x1) in enumerate(COL_BOUNDS):
        dir_name = DIR_NAMES[di]
        sub = content[:, x0:x1]
        rows = sub.any(axis=1)
        y_min = int(np.where(rows)[0].min())
        y_max = int(np.where(rows)[0].max())
        fig_h = y_max - y_min + 1

        dir_parts = {}

        # --- HEAD ---
        frac_t, frac_b = PART_FRACS["head"]
        res = cut_part(atlas_arr, content, x0, x1, y_min, fig_h, frac_t, frac_b,
                       pivot_x_frac=0.5, pivot_y_frac=0.9)
        if res:
            img, pivot = res
            img, pivot = resize_to_part(img, pivot, HEAD_DIA + 4)
            img, pivot = center_pivot(img, pivot)
            fname = f"head_{dir_name}.png"
            img.save(parts_dir / fname)
            dir_parts["head"] = {"file": fname, "size": img.size, "pivot": pivot}

        # --- TORSO ---
        frac_t, frac_b = PART_FRACS["torso"]
        res = cut_part(atlas_arr, content, x0, x1, y_min, fig_h, frac_t, frac_b,
                       pivot_x_frac=0.5, pivot_y_frac=0.0)
        if res:
            img, pivot = res
            img, pivot = resize_to_part(img, pivot, L_TORSO + 6)
            img, pivot = center_pivot(img, pivot)
            fname = f"torso_{dir_name}.png"
            img.save(parts_dir / fname)
            dir_parts["torso"] = {"file": fname, "size": img.size, "pivot": pivot}

        # --- LEGS ---
        legs = cut_leg_parts(atlas_arr, content, x0, x1, y_min, fig_h)
        if legs and len(legs) == 2:
            # Ноги разделены (только south/north) — берём ПРАВУЮ как основную,
            # левую копируем (при повороте рига разница незначима)
            side = "right"
            img, pivot = legs[side]
            th = img.crop((0, 0, img.size[0], img.size[1] // 2))
            th_pivot = (pivot[0], 0)
            th, th_pivot = resize_to_part(th, th_pivot, L_THIGH + 4)
            th, th_pivot = center_pivot(th, th_pivot)
            fname = f"thigh_{dir_name}.png"
            th.save(parts_dir / fname)
            dir_parts["thigh"] = {"file": fname, "size": th.size, "pivot": th_pivot}

            sh = img.crop((0, img.size[1] // 2, img.size[0], img.size[1]))
            sh_pivot = (pivot[0], 0)
            sh, sh_pivot = resize_to_part(sh, sh_pivot, L_SHIN + 4)
            sh, sh_pivot = center_pivot(sh, sh_pivot)
            fname = f"shin_{dir_name}.png"
            sh.save(parts_dir / fname)
            dir_parts["shin"] = {"file": fname, "size": sh.size, "pivot": sh_pivot}
        else:
            # Ноги не разделены — берём обе целиком
            frac_t, frac_b = PART_FRACS["thigh"]
            res = cut_part(atlas_arr, content, x0, x1, y_min, fig_h, frac_t, frac_b,
                           pivot_x_frac=0.5, pivot_y_frac=0.0)
            if res:
                img, pivot = res
                img, pivot = resize_to_part(img, pivot, L_THIGH + 4)
                img, pivot = center_pivot(img, pivot)
                fname = f"thigh_{dir_name}.png"
                img.save(parts_dir / fname)
                dir_parts["thigh"] = {"file": fname, "size": img.size, "pivot": pivot}

            frac_t, frac_b = PART_FRACS["shin"]
            res = cut_part(atlas_arr, content, x0, x1, y_min, fig_h, frac_t, frac_b,
                           pivot_x_frac=0.5, pivot_y_frac=0.0)
            if res:
                img, pivot = res
                img, pivot = resize_to_part(img, pivot, L_SHIN + 4)
                img, pivot = center_pivot(img, pivot)
                fname = f"shin_{dir_name}.png"
                img.save(parts_dir / fname)
                dir_parts["shin"] = {"file": fname, "size": img.size, "pivot": pivot}

        # --- ARMS (заглушки: в idle руки не отделены от торса) ---
        # Руки-палочки одинаковые для всех направлений
        pass

        results[dir_name] = dir_parts
        print(f"  {dir_name}: {len(dir_parts)} частей")

    # Диски (одинаковые для всех направлений)
    make_disc(10, (188, 176, 150, 255)).save(parts_dir / "disc_lg.png")
    make_disc(6, (188, 176, 150, 255)).save(parts_dir / "disc_sm.png")
    # Заглушки рук (пилот-палочки) для каждого направления
    for name in ["upper_arm", "forearm"]:
        fallback = Image.new("RGBA", (8, 20), (0, 0, 0, 0))
        d = ImageDraw.Draw(fallback)
        d.rounded_rectangle([1, 0, 6, 19], radius=3, fill=(162, 162, 168, 255),
                           outline=(54, 54, 60, 255))
        for dn in DIR_NAMES:
            fallback.save(parts_dir / f"{name}_{dn}.png")

    if preview:
        _make_preview(parts_dir, out_dir / "_parts_preview.png")

    return results


def _make_preview(parts_dir: Path, out_path: Path) -> None:
    """Контактный лист всех частей."""
    files = sorted(parts_dir.glob("*.png"))
    if not files:
        return
    cell = 80
    cols = 10
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell + rows * 16), (40, 40, 45, 255))
    draw = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        img = Image.open(f)
        cx = (i % cols) * cell
        cy = (i // cols) * (cell + 16)
        # Центрируем
        ox = cx + (cell - img.size[0]) // 2
        oy = cy + (cell - img.size[1]) // 2
        sheet.paste(img, (ox, oy), img)
        draw.text((cx + 2, cy + cell), f.stem[:12], fill=(200, 200, 200, 255))
    sheet.save(out_path)
    print(f"Preview: {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(OUT_DIR / "hero_atlas"))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()

    out_dir = Path(args.out)
    print(f"Нарезка частей рига из {ATLAS.name} -> {out_dir}")
    results = extract_all(out_dir, preview=args.preview)

    total = sum(len(v) for v in results.values())
    print(f"Итого: {total} частей для {len(results)} направлений")

    if args.check:
        # Проверяем pivot = центр холста
        parts_dir = out_dir / "parts"
        bad = 0
        for f in parts_dir.glob("*.png"):
            img = Image.open(f)
            w, h = img.size
            if w % 2 != 0 or h % 2 != 0:
                print(f"  FAIL {f.name}: нечётный холст {w}x{h}")
                bad += 1
        print(f"Check: {'OK' if bad == 0 else f'{bad} проблем'}")


if __name__ == "__main__":
    main()
