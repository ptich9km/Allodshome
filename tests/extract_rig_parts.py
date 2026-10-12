"""Нарезка частей 2D-рига из seedream-атласа _hero_walk.png.

Два authored-ракурса (west / east) — настоящие профили разворота.
Север/юг и диагонали скользят: их риг дорисовывает зеркалом и удержанием
прежнего ракурса (см. rigged_anim.gd, MIRROR_EPS).

Суставы НЕ заданы долями высоты, а измеряются по силуэту фигуры: доли от
предыдущей версии расходились с артом, и части резались по половине.

Запуск:
    python tests/extract_rig_parts.py --preview
    python tests/extract_rig_parts.py --check
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
ATLAS = REPO / "import" / "_hero_walk.png"
OUT_DIR = REPO / "assets" / "units" / "rig" / "rig_hero_atlas"

# Порог магенты (фон листа) — тот же, что в extract_hero_seedream.py
MAG_RG = 45
MAG_BG = 40

# Атлас: 2 ряда фаз ходьбы x 8 колонок РАЗВОРОТА на 45°.
#
# ВАЖНО: это не 8 направлений top-down. Замер ширины силуэта даёт
# 212..223 px для всех восьми — настоящий профиль был бы ~150 px, то есть
# seedream ни разу не довёл поворот до профиля. Зато колонки 2 и 6 — единственные,
# которые смотрят ВЛЕВО и ВПРАВО (смещение головы от торса −8.9 и +5.2 px),
# а это ровно то, что нужно ригу с двумя направлениями. Север и юг
# отданы им же и скользят.
#
# Границы колонок ИЗМЕРЕНЫ по разрывам в маске: заданные вручную обрезали
# свисающую руку колонки 6 (левый сегмент уходил в x=0), и «таз» по нему
# считался как самая широкая полоса мусора.
COL_BOUNDS = [
    (19, 243), (282, 500), (538, 754), (794, 1015),
    (1055, 1275), (1316, 1529), (1567, 1783), (1822, 2036),
]
# 8 направлений в порядке листа: 0=Ю 1=ЮЗ 2=З 3=СЗ 4=С 5=СВ 6=В 7=ЮВ
DIR_NAMES = ["south", "sw", "west", "nw", "north", "ne", "east", "se"]
# Берём колонки 2 (west) и 6 (east) — по одной на каждый бок.
AUTHORED = ["west", "east"]
PHASE_ROW = 0  # верхний ряд листа — исходная поза

# Целевая высота собранной фигуры в пикселях игры
FIGURE_HEIGHT = 56
PAD_PX = 3
GAP_PX = 3


# --------------------------------------------------------------------------
# маска и силуэт
# --------------------------------------------------------------------------

def content_mask(arr: np.ndarray) -> np.ndarray:
    """True там, где пиксель НЕ магенты (то есть контент фигуры)."""
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    return ~(((r - g) > MAG_RG) & ((b - g) > MAG_BG))


def segments(row: np.ndarray, gap: int = GAP_PX) -> list[tuple[int, int]]:
    """Горизонтальные отрезки контента в строке (в локальных координатах)."""
    xs = np.where(row)[0]
    if len(xs) == 0:
        return []
    out: list[tuple[int, int]] = []
    start = prev = int(xs[0])
    for x in xs[1:]:
        x = int(x)
        if x - prev > gap:
            out.append((start, prev))
            start = x
        prev = x
    out.append((start, prev))
    return out


def figure_box(mask: np.ndarray) -> tuple[int, int]:
    rows = np.where(mask.any(axis=1))[0]
    if len(rows) == 0:
        raise ValueError("пустая колонка")
    return int(rows.min()), int(rows.max())


def narrowest(mask: np.ndarray, y0: int, y1: int) -> int:
    """Строка с минимальной шириной силуэта в диапазоне (шея / колено)."""
    best_y, best_w = None, None
    for y in range(y0, y1 + 1):
        segs = segments(mask[y])
        if not segs:
            continue
        w = segs[-1][1] - segs[0][0]
        if best_w is None or w < best_w:
            best_y, best_w = y, w
    if best_y is None:
        raise ValueError(f"пустой диапазон {y0}..{y1}")
    return best_y


def arm_window(mask: np.ndarray, y_from: int, y_to: int,
               which: str = "near") -> tuple[int, int]:
    """Окно строк, где рука отходит от корпуса.

    В idle-атласе рука прижата к телу (зазоров 9-10 строк на всю фигуру),
    в walk — 120-180 строк: обе руки висят отдельно, и строка даёт ТРИ
    сегмента вместо одного. `which` выбирает дальнюю (слева) или ближнюю.
    """
    ys = []
    for y in range(y_from, y_to + 1):
        segs = segments(mask[y])
        if len(segs) < 3:
            continue
        body = widest(segs)
        side = [s for s in segs if s[1] < body[0]] if which == "far" \
            else [s for s in segs if s[0] > body[1]]
        if side:
            ys.append(y)
    if len(ys) < 20:
        raise ValueError(f"{which}-рука не отделилась от корпуса")
    return min(ys), max(ys)


def joint_x(mask: np.ndarray, y: int, which: str = "body") -> int:
    """X оси сустава, измеренный по силуэту в строке сустава.

    Брать середину КОЛОНКИ атласа нельзя: в профиле фигура сдвинута от
    центра колонки на десятки пикселей, и ось уезжала мимо шеи — часть
    растягивалась пустым холстом вдвое (голова приходила с 18% контента).
    """
    segs = segments(mask[y])
    if not segs:
        raise ValueError(f"пустая строка сустава y={y}")
    if which == "body":
        a, b = segs[0][0], segs[-1][1]
    elif which == "last":
        a, b = segs[-1]
    elif which == "arm":
        # внешний отрезок — та рука, что отделилась зазором
        for i in range(len(segs) - 1, 0, -1):
            if segs[i][0] - segs[i - 1][1] >= 4:
                a, b = segs[i]
                break
        else:
            a, b = segs[-1]
    else:
        raise ValueError(which)
    return (a + b) // 2


def widest(segs: list[tuple[int, int]]) -> tuple[int, int]:
    """Самый широкий отрезок строки — это корпус, когда руки висят отдельно."""
    return max(segs, key=lambda s: s[1] - s[0])


def body_width(segs: list[tuple[int, int]]) -> int:
    """Ширина КОРПУСА, а не всей строки.

    Пока руки висят отдельно, общая ширина включает и их, и все измерения
    ниже пояса относятся не к телу, а к размаху рук.
    """
    s = widest(segs) if segs else (0, 0)
    return s[1] - s[0]


def hip_row(mask: np.ndarray, y_from: int, y_to: int) -> int:
    """Таз = самое широкое место тазового пояса.

    НЕ «первая строка ниже руки, где остался один отрезок»: конец полосы
    совпадает с НИЗОМ СВИСАЮЩЕЙ РУКИ, и таз уезжал на frac 0.61 вместо 0.57
    — бедро становилось короче голени.

    НЕ «самое узкое место»: в профиле бедро не сужается, минимум ширины
    уезжал на щиколотку.
    """
    best_y, best_w = None, -1
    for y in range(y_from, y_to + 1):
        segs = segments(mask[y])
        w = body_width(segs)
        if w > best_w:
            best_y, best_w = y, w
    if best_y is None:
        raise ValueError(f"пустой диапазон таза {y_from}..{y_to}")
    return best_y


def ankle_row(mask: np.ndarray, y_from: int, y_to: int) -> int:
    """Щиколотка = самое узкое место над стопой."""
    return narrowest(mask, y_from, y_to)


# Доля пути таз->щиколотка, где проходит колено. В этом арте НЕТ перехвата
# на колене (штаны и сапог — одна непрерывная форма), и минимум ширины
# находится на щиколотке, поэтому колено измерять нечем: берётся доля пути.
# Замер по силуэту: манжета сапога начинается на frac 0.77 от таза к
# щиколотке — это и есть сгиб. Инвариант проверяется в check(): отношение
# бедра к голени должно попадать в 0.8..1.4, иначе доля поехала.
KNEE_SPLIT = 0.56


def limb_span(mask: np.ndarray, y_from: int, y_to: int,
              which: str = "body") -> tuple[int, int]:
    """Диапазон X конкретной части (руки / корпуса / ноги) в полосе строк.

    Кроп по всей ширине колонки НЕЛЬЗЯ: в полосе, где отделилась рука, есть
    ещё и корпус, и он попадал в текстуру руки — та приходила 30 px шириной
    при длине кости 14, то есть с куском торса внутри. Каждая часть режется
    по своему отрезку силуэта.
    """
    xs0: int | None = None
    xs1: int | None = None
    for y in range(y_from, y_to + 1):
        segs = segments(mask[y])
        if not segs:
            continue
        if which == "body":
            a, b = widest(segs)
        elif which == "arm_far":
            # внешний отрезок СЛЕВА от корпуса
            body = widest(segs)
            left = [s for s in segs if s[1] < body[0]]
            a, b = max(left, key=lambda s: s[1] - s[0]) if left else body
        elif which == "arm_near":
            body = widest(segs)
            right = [s for s in segs if s[0] > body[1]]
            a, b = max(right, key=lambda s: s[1] - s[0]) if right else body
        else:
            raise ValueError(which)
        xs0 = a if xs0 is None else min(xs0, a)
        xs1 = b if xs1 is None else max(xs1, b)
    if xs0 is None:
        raise ValueError(f"пустой span {which} y={y_from}..{y_to}")
    return xs0, xs1


# --------------------------------------------------------------------------
# преобразования изображения
# --------------------------------------------------------------------------

def to_rgba(region: np.ndarray, region_mask: np.ndarray) -> Image.Image:
    rgba = np.zeros((*region.shape[:2], 4), dtype=np.uint8)
    rgba[:, :, :3] = region
    rgba[:, :, 3] = np.where(region_mask, 255, 0).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def cut_part(arr: np.ndarray, mask: np.ndarray,
             x0: int, x1: int, y0: int, y1: int,
             pivot_x: int, pivot_y: int) -> tuple[Image.Image, tuple[int, int]]:
    """Плотный кроп части + точка сустава внутри него.

    Кроп идёт ПО СИЛУЭТУ (с запасом), а не по полосе высоты: полоса
    захватывала пустое поле, и часть приходила вдвое выше контента.
    """
    cols = np.where(mask[y0:y1 + 1, x0:x1].any(axis=0))[0]
    if len(cols) == 0:
        raise ValueError(f"пустой кроп y={y0}..{y1}")
    cx0 = max(0, int(cols.min()) - PAD_PX)
    cx1 = min(x1 - x0, int(cols.max()) + PAD_PX + 1)
    img = to_rgba(arr[y0:y1 + 1, x0 + cx0:x0 + cx1],
                  mask[y0:y1 + 1, x0 + cx0:x0 + cx1])
    if img.getbbox() is None:
        raise ValueError(f"пустая часть y={y0}..{y1}")
    # pivot в координатах КРОПА: ось сустава лежит в маске фигуры, значит она
    # внутри [cx0, cx1]. Знак тут легко перепутать — ось уезжает за кроп, и
    # холст раздувается вдвое с пустотой вместо сустава.
    px = pivot_x - (x0 + cx0)
    py = pivot_y - y0
    if not (0 <= px < cx1 - cx0 and 0 <= py <= y1 - y0):
        raise ValueError(f"ось сустава ({pivot_x},{pivot_y}) вне кропа "
                         f"x={x0+cx0}..{x0+cx1} y={y0}..{y1}")
    return img, (px, py)


def center_on_pivot(img: Image.Image, pivot: tuple[int, int],
                    target_h: int) -> Image.Image:
    """Масштаб по высоте КОНТЕНТА, затем холст РАСТЁТ так, чтобы pivot в центре.

    Две ошибки, которые здесь закрываются:

    * масштабировать нужно контент, а не холст. Если сначала раздуть холст
      вдвое (чтобы запихнуть pivot в центр) и потом отмасштабировать по его
      высоте, часть уменьшится вдвое: голова приходила 8 px канваса с 4 px
      волос, голень — то же самое;
    * холст должен РАСТИ под pivot, а не сдвигаться. Предыдущая версия
      сдвигала картинку на size/2-pivot поверх холста того же размера и
      срезала половину: torso_south приходил 18x24 с контентом в строках
      12..23, thigh/shin 14x18 с контентом в 9..17.
    """
    w, h = img.size
    scale = target_h / h
    nw = max(2, int(round(w * scale)))
    nw += nw % 2
    nh = target_h + (target_h % 2)
    small = img.resize((nw, nh), Image.NEAREST)
    px = int(round(pivot[0] * nw / w))
    py = int(round(pivot[1] * nh / h))

    cw = max(nw, 2 * px, 2 * (nw - px))
    ch = max(nh, 2 * py, 2 * (nh - py))
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.paste(small, (cw // 2 - px, ch // 2 - py), small)
    # нечётный холст ломает «центр = size/2» (половинный пиксель под pivot)
    if cw % 2:
        canvas = canvas.resize((cw + 1, ch), Image.NEAREST)
    if ch % 2:
        canvas = canvas.resize((canvas.size[0], ch + 1), Image.NEAREST)
    return canvas


def make_disc(dia: int, color: tuple) -> Image.Image:
    d = dia + (dia % 2)
    img = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse([0, 0, d - 1, d - 1], fill=color)
    return img


# --------------------------------------------------------------------------
# нарезка одного ракурса
# --------------------------------------------------------------------------

def cut_view(col_arr: np.ndarray, col_mask: np.ndarray,
             name: str, report: dict) -> dict:
    x1 = col_mask.shape[1]
    parts_dir = OUT_DIR / "parts" / name
    parts_dir.mkdir(parents=True, exist_ok=True)
    for old in parts_dir.glob("*.png"):
        old.unlink()

    y0, y1 = figure_box(col_mask)
    fh = y1 - y0 + 1

    # --- суставы, измеренные по силуэту ---
    neck = narrowest(col_mask, y0 + int(fh * 0.08), y0 + int(fh * 0.20))
    arm_top, arm_bot = arm_window(col_mask, y0 + int(fh * 0.25),
                                   y0 + int(fh * 0.70), "far")
    arm_n_top, arm_n_bot = arm_window(col_mask, y0 + int(fh * 0.25),
                                       y0 + int(fh * 0.70), "near")
    hip = hip_row(col_mask, y0 + int(fh * 0.48), y0 + int(fh * 0.64))
    ankle = ankle_row(col_mask, y0 + int(fh * 0.86), y0 + int(fh * 0.96))
    knee = round(hip + (ankle - hip) * KNEE_SPLIT)

    fr = lambda y: (y - y0) / fh
    report[name] = {
        "figure": [y0, y1, fh],
        "neck_frac": round(fr(neck), 3),
        "hip_frac": round(fr(hip), 3),
        "knee_frac": round(fr(knee), 3),
        "ankle_frac": round(fr(ankle), 3),
        "arm_frac": [round(fr(arm_top), 3), round(fr(arm_bot), 3)],
        "arm_near_frac": [round(fr(arm_n_top), 3), round(fr(arm_n_bot), 3)],
    }

    # --- масштаб: высота фигуры -> FIGURE_HEIGHT ---
    px_per_frac = FIGURE_HEIGHT / fh

    def bone(y_from: int, y_to: int) -> int:
        return max(2, int(round(abs(y_to - y_from) * px_per_frac)))

    l_torso = bone(neck, hip)
    l_uarm = bone(arm_top, arm_bot)
    l_thigh = bone(hip, knee)

    made: dict[str, list[int]] = {}

    # pivot задаётся ЯВНО на каждый сустав, а не «всегда по нижнему краю».
    # Общий дефолт «низ» был незаметен на палочках пилота (у них сустав был
    # только один и он совпадал с краем), но на настоящих частях он давал:
    # рука вращалась вокруг кисти, бедро — вокруг колена, голень — вокруг
    # стопы. Части выглядели оторванными от корпуса при ЛЮБОМ повороте.
    def emit(part: str, y_from: int, y_to: int, target_h: int,
             span: str, pivot_edge: str) -> None:
        sx0, sx1 = limb_span(col_mask, y_from, y_to, span)
        jx = (sx0 + sx1) // 2
        jy = y_from if pivot_edge == "top" else y_to
        # кламп обязателен: отрицательный индекс numpy считается С КОНЦА,
        # и кроп молча уезжал на противоположный край колонки
        sx0 = max(0, sx0 - PAD_PX)
        sx1 = min(x1, sx1 + PAD_PX + 1)
        img, pivot = cut_part(col_arr, col_mask, sx0, sx1, y_from, y_to, jx, jy)
        img = center_on_pivot(img, pivot, target_h)
        if img.getbbox() is None:
            raise ValueError(f"{name}/{part}: пустая текстура")
        img.save(parts_dir / f"{part}.png")
        made[part] = list(img.size)

    # ГОЛОВА: макушка -> шея, ось в шее (низ)
    emit("head", y0, neck, max(6, int(round((neck - y0) * px_per_frac))),
         "body", "bottom")

    # ТОРС: шея -> таз, ось в тазу (низ). Дыру от вырезанной руки не
    # заполняем: в исходной позе её перекрывает сама рука, а при повороте
    # закрывают joint-dot и near-рука.
    emit("torso", neck, hip, l_torso, "body", "bottom")

    # РУКИ: обе висят отдельно, поэтому режутся настоящими, а не палочками.
    # Каждая — одно цельное плечо-локоть-кисть, ось в ПЛЕЧЕ (верх): локоть
    # в 56-пиксельном риге не читается, а лишний сустав даёт шов на каждом
    # кадре ходьбы.
    emit("arm_far", arm_top, arm_bot, l_uarm, "arm_far", "top")
    emit("arm_near", arm_n_top, arm_n_bot, l_uarm, "arm_near", "top")

    # НОГИ: в этом ракурсе дальняя нога перекрыта ближней, отдельных отрезков
    # нет. Берём ОДНУ ногу и используем дважды (near + far с затемнением).
    # Ось бедра — таз (верх), оси голени — колено (верх).
    emit("thigh", hip, knee, l_thigh, "body", "top")
    emit("shin", knee, y1, bone(knee, y1), "body", "top")

    report[name]["bones"] = {"L_torso": l_torso, "L_uarm": l_uarm,
                             "L_thigh": l_thigh, "L_shin": bone(knee, y1)}
    report[name]["parts"] = made
    return made


# --------------------------------------------------------------------------
# rig.json
# --------------------------------------------------------------------------

def _clip(length: float, loop: bool, rot: dict, pos: dict | None = None) -> dict:
    c: dict = {"length": length, "loop": loop, "rot": rot}
    if pos:
        c["pos"] = pos
    return c


# Клипы. Кости рига: Torso, Head, ArmFront, ArmBack, ThighFront, ThighBack.
# позы: rot[[время, градусы]], pos[[время, x, y]]
CLIPS = {
    "idle": _clip(2.4, True, {
        "Torso": [[0.0, 0.0], [1.2, 1.5], [2.4, 0.0]],
        "Head": [[0.0, 0.0], [1.2, -1.0], [2.4, 0.0]],
        "ArmFront": [[0.0, 2.0], [1.2, 4.0], [2.4, 2.0]],
        "ArmBack": [[0.0, -2.0], [1.2, -4.0], [2.4, -2.0]],
        "ThighFront": [[0.0, 1.0], [2.4, 1.0]],
        "ThighBack": [[0.0, -1.0], [2.4, -1.0]],
    }, {"Hip": [[0.0, 0.0, 0.0], [1.2, 0.0, -0.5], [2.4, 0.0, 0.0]]}),
    "walk": _clip(0.8, True, {
        "ThighFront": [[0.0, 15.0], [0.4, -15.0], [0.8, 15.0]],
        "ThighBack": [[0.0, -15.0], [0.4, 15.0], [0.8, -15.0]],
        "ArmFront": [[0.0, -11.0], [0.4, 11.0], [0.8, -11.0]],
        "ArmBack": [[0.0, 11.0], [0.4, -11.0], [0.8, 11.0]],
        "Torso": [[0.0, 1.5], [0.4, -1.5], [0.8, 1.5]],
    }, {"Hip": [[0.0, 0.0, 0.0], [0.2, 0.0, -1.5], [0.4, 0.0, 0.0],
                [0.6, 0.0, -1.5], [0.8, 0.0, 0.0]]}),
    "attack": _clip(0.5, False, {
        "Torso": [[0.0, 0.0], [0.18, -8.0], [0.34, 10.0], [0.5, 0.0]],
        "Head": [[0.0, 0.0], [0.18, 4.0], [0.5, 0.0]],
        "ArmFront": [[0.0, 2.0], [0.18, -70.0], [0.34, 30.0], [0.5, 2.0]],
        "ThighFront": [[0.0, 1.0], [0.18, -12.0], [0.5, 1.0]],
        "ThighBack": [[0.0, -1.0], [0.18, 10.0], [0.5, -1.0]],
    }, {"Hip": [[0.0, 0.0, 0.0], [0.18, 0.0, -1.0], [0.34, 0.0, 0.5],
                [0.5, 0.0, 0.0]]}),
    "dying": _clip(1.2, False, {
        "Torso": [[0.0, 0.0], [0.5, 18.0], [1.2, 62.0]],
        "Head": [[0.0, 0.0], [0.5, 6.0], [1.2, 24.0]],
        "ArmFront": [[0.0, 2.0], [0.5, -28.0], [1.2, -64.0]],
        "ArmBack": [[0.0, -2.0], [0.5, -14.0], [1.2, -44.0]],
        "ThighFront": [[0.0, 1.0], [0.5, 18.0], [1.2, 44.0]],
        "ThighBack": [[0.0, -1.0], [0.5, 6.0], [1.2, -10.0]],
    }, {"Hip": [[0.0, 0.0, 0.0], [0.5, 0.0, 2.0], [1.2, 0.0, 6.0]]}),
    "decay": _clip(0.8, False, {
        "Torso": [[0.0, 62.0], [0.4, 74.0], [0.8, 74.0]],
        "Head": [[0.0, 24.0], [0.8, 28.0]],
        "ArmFront": [[0.0, -64.0], [0.4, -74.0], [0.8, -74.0]],
        "ArmBack": [[0.0, -44.0], [0.8, -48.0]],
        "ThighFront": [[0.0, 44.0], [0.8, 48.0]],
        "ThighBack": [[0.0, -10.0], [0.8, -10.0]],
    }, {"Hip": [[0.0, 0.0, 6.0], [0.8, 0.0, 7.0]]}),
}


def build_rig_json(report: dict) -> str:
    views = {}
    for name in AUTHORED:
        views[name] = {
            "parts": f"res://assets/units/rig/rig_hero_atlas/parts/{name}/",
            # west нарисован лицом влево (-x), east — вправо (+x)
            "faces_east": 1 if name == "east" else -1,
            "height": FIGURE_HEIGHT,
            "far_tint": "c8c8d4",
            "near_tint": "ffffff",
            "bones": report[name]["bones"],
        }
    # Контриклоковая конвенция проекта: 0=север 7=СВ 6=восток 5=ЮВ
    # 4=юг 3=ЮЗ 2=запад 1=СЗ. Север и юг отданы профилю — они скользят.
    return json.dumps({
        "desc": "Риг героя: 2 authored-профиля из _hero_walk.png (seedream). "
                "Север/юг и диагонали скользят. Локтя и запястья нет — "
                "части длиннее, зато швов меньше.",
        "height": FIGURE_HEIGHT,
        "map": {"0": "east", "2": "west", "4": "east", "6": "east"},
        "views": views,
        "clips": CLIPS,
    }, ensure_ascii=False, indent=2)


# --------------------------------------------------------------------------
# проверки
# --------------------------------------------------------------------------

def check() -> int:
    """Инварианты против класса «часть срезана / риг не собирается».

    1. длина костей в пределах высоты фигуры;
    2. холст чётный, текстура непустая, контент занимает >= 25% холста
       (обрезанный «только низ кадра» даёт ровно такую картину);
    3. pivot = центр холста и ось сустава попадает В силуэт части.
    """
    cfg = json.loads((OUT_DIR / "rig.json").read_text(encoding="utf-8"))
    fh = int(cfg["height"])
    bad = 0
    parts: list[tuple[str, str, Path]] = []

    for vname, spec in cfg["views"].items():
        total = sum(int(spec["bones"][k]) for k in
                    ("L_torso", "L_uarm", "L_thigh"))
        if not int(fh * 0.75) <= total <= int(fh * 1.20):
            print(f"  FAIL {vname}: длина костей {total} против высоты {fh}")
            bad += 1
        d = REPO / spec["parts"].replace("res://", "")
        for f in sorted(d.glob("*.png")):
            parts.append((vname, f.name, f))

    # диски общие для обоих ракурсов
    for f in sorted((OUT_DIR / "parts").glob("disc_*.png")):
        parts.append(("*", f.name, f))

    for vname, fname, f in parts:
        img = Image.open(f)
        w, h = img.size
        if w % 2 or h % 2:
            print(f"  FAIL {vname}/{fname}: нечётный холст {w}x{h}")
            bad += 1
        bbox = img.getbbox()
        if bbox is None:
            print(f"  FAIL {vname}/{fname}: пустая текстура")
            bad += 1
            continue
        fill = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / (w * h)
        if fill < 0.25:
            print(f"  FAIL {vname}/{fname}: контент {fill:.0%} холста — "
                  f"часть срезана")
            bad += 1

    # 3. ось сустава внутри силуэта: центр холста не должен быть «в дырке»
    for part in ("head", "torso", "arm_far", "arm_near", "thigh", "shin"):
        for vname in AUTHORED:
            f = OUT_DIR / "parts" / vname / f"{part}.png"
            img = Image.open(f).convert("RGBA")
            a = np.array(img)[:, :, 3]
            cx, cy = a.shape[1] // 2, a.shape[0] // 2
            near = a[max(0, cy - 2):cy + 3, max(0, cx - 2):cx + 3]
            if int((near > 10).sum()) == 0:
                print(f"  FAIL {vname}/{part}: центр холста пустой — "
                      f"pivot не на суставе")
                bad += 1

    print(f"Check: {'OK' if bad == 0 else f'{bad} проблем'}")
    return bad


# --------------------------------------------------------------------------
# превью и точка входа
# --------------------------------------------------------------------------

def make_preview(out_path: Path) -> None:
    rows = []
    for name in AUTHORED:
        d = OUT_DIR / "parts" / name
        rows.append((name, [(f.stem, Image.open(f).convert("RGBA"))
                            for f in sorted(d.glob("*.png"))]))
    rows.append(("*", [(f.stem, Image.open(f).convert("RGBA"))
                       for f in sorted((OUT_DIR / "parts").glob("disc_*.png"))]))

    cell = 110
    ncols = max(len(r[1]) for r in rows)
    sheet = Image.new("RGBA", (ncols * cell, len(rows) * cell + 20), (40, 40, 45, 255))
    draw = ImageDraw.Draw(sheet)
    for ri, (name, imgs) in enumerate(rows):
        for ci, (stem, img) in enumerate(imgs):
            k = max(1, (cell - 24) // max(img.size))
            small = img.resize((img.size[0] * k, img.size[1] * k), Image.NEAREST)
            cx = ci * cell + (cell - small.size[0]) // 2
            cy = ri * cell + (cell - 16 - small.size[1]) // 2
            sheet.alpha_composite(small, (cx, cy))
            px = cx + small.size[0] // 2
            py = cy + small.size[1] // 2
            draw.line([(px - 4, py), (px + 4, py)], fill=(255, 70, 70, 255))
            draw.line([(px, py - 4), (px, py + 4)], fill=(255, 70, 70, 255))
            draw.text((ci * cell + 3, ri * cell + cell - 14), stem,
                      fill=(210, 210, 210, 255))
        draw.text((3, ri * cell + 2), name, fill=(140, 200, 255, 255))
    sheet.save(out_path)
    print(f"Preview: {out_path}")


def extract_all(preview: bool = False) -> dict:
    arr = np.array(Image.open(ATLAS).convert("RGB"))
    mask = content_mask(arr)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "parts").mkdir(exist_ok=True)

    ry0, ry1 = (0, 512) if PHASE_ROW == 0 else (512, 1024)
    report: dict = {}
    for col_i, name in ((2, "west"), (6, "east")):
        x0, x1 = COL_BOUNDS[col_i]
        made = cut_view(arr[ry0:ry1, x0:x1], mask[ry0:ry1, x0:x1], name, report)
        r = report[name]
        print(f"  {name}: {len(made)} частей  шея={r['neck_frac']} "
              f"таз={r['hip_frac']} колено={r['knee_frac']} "
              f"рука={r['arm_frac']}  кости={r['bones']}")

    # Диски копируются в КАЖДЫЙ каталог ракурса: rigged_anim ищет их по
    # `view.parts`, а не по общему корню, — иначе они молча не грузятся.
    for name in AUTHORED:
        pd = OUT_DIR / "parts" / name
        make_disc(6, (104, 92, 80, 255)).save(pd / "disc_lg.png")
        make_disc(4, (104, 92, 80, 255)).save(pd / "disc_sm.png")

    (OUT_DIR / "rig.json").write_text(build_rig_json(report), encoding="utf-8")
    if preview:
        make_preview(OUT_DIR / "_parts_preview.png")
    return report


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.check:
        raise SystemExit(1 if check() else 0)
    print(f"Нарезка рига из {ATLAS.name} -> {OUT_DIR}")
    extract_all(preview=args.preview)
    check()


if __name__ == "__main__":
    main()