#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Нарезка портретов рас из import/ChatGPTMain*.png -> assets/hero_portraits/*.png.

Что measuring показал (не догадки, а замеры по пикселям):

  ChatGPTMainHuman1/2.png  1024x1536 RGB   тёмный градиент-фон, альфы НЕТ
  ChatGPTMainDruid1.png   1024x1536 RGBA  фон УЖЕ прозрачный (alpha=0)
  ChatGPTMainNecromant1.png 1536x1024 RGBA 4 колонки x 2 ряда, верх = фронт, низ = спины
  ChatGPTMainOrk1.png      1536x1024 RGBA 4 колонки x 2 ряда, верх = фронт, низ = спины

Почему старая версия резала плохо (три независимые причины):
  1. `Image.open(src).convert("RGB")` ВЫБРАСЫВАЛ альфу у Druid/Necromant/Ork.
     Дальше фон искался по цвету, а прозрачные пиксели уже несли мусорный RGB
     (у Орка под alpha=0 лежит (69,64,26)) — отсюда серые блоки и «обрезки».
  2. Для 4x2 атласов бралась ровно верхняя половина (y < h/2). У Necromant
     фронтовые фигуры доходят до y=528, у Ork до y=512 — то есть деление
     ПОПОЛАМ разрезало ноги. Реальная пустая полоса у Necromant y=529..533.
  3. Масштаб считался по ДЛИННЕ стороне, поэтому рост персонажей на карточках
     скакал (высоты 76..121 px при одной и той же высоте). Теперь нормировка
     ПО ВЫСОТЕ фигуры -> все портреты одной высоты 240.

Метод (без scipy, только numpy + PIL):
  маска -> связные компоненты по run-length + union-find (шум отбрасывается)
        -> заливка внутренних дыр flood-fill с края
        -> мягкая альфа по расстоянию до цвета фона (только для RGB-атласов)
        -> плотный bbox -> ресайз в premultiplied-пространстве (без тёмного ободка)

Запуск:
  python tests/extract_chatgpt_portraits.py
  python tests/extract_chatgpt_portraits.py --sheet   # контактный лист на шахматке
  python tests/extract_chatgpt_portraits.py --check   # SHA256 против файлов на диске
"""
import argparse
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMP = os.path.join(ROOT, "import")
OUT = os.path.join(ROOT, "assets", "hero_portraits")
DB = os.path.join(OUT, "portraits_db.json")
SHEET = os.path.join(OUT, "_contact_sheet.png")

# Высота портрета в игре (сетка 160x240 по ТЗ игрока).
TARGET_H = 240
# Отступ вокруг плотного bbox, px (в координатах исходника).
PAD = 4
# Порог цветового ключа для RGB-атласов: 0 при d<=BG_T0, 1 при d>=BG_T1.
# BG_T1 подобран замером: у Human1 p90 расстояния до фона = 134, а тёмные
# волосы дают 30-50. Верхняя граница 52 держит тёмные детали внутри
# силуэта, нижняя 16 не даёт фону «съесть» край.
# Порог цветового ключа для RGB-атласов: 0 при d<=BG_T0, 1 при d>=BG_T1.
#
# BG_T0 подобран ЗАМЕРОМ, а не на глаз. Тень на полу у ног темнее фона:
# замер в ChatGPTMainHuman2 у пикселя тени rgb=(37,35,34) при фоне
# (25,25,24) даёт dist=17, то есть ровно на единицу выше старого порога 16.
# Из-за этого тень считалась персонажем и оставалась мусором под ступнями
# (игрок: «у human2 почти у всех стопы с мусором»).
# Проверено на обоих RGB-атласах: 16 -> 22 теряет 1.4-2.2% площади
# (только градиент края тени) и даёт 0 замкнутых фоновых областей.
# Выше 30 уже съедает тёмные детали персонажа (волосы, ткань).
BG_T0 = 22.0
BG_T1 = 52.0
# Склейка соседних компонент по X. Замер по всем пяти атласам:
# r=0, 4, 8 -> ровно cols*rows фигур; r=10 -> Human1 теряет фигуру (4->3),
# потому что правый передний и задний персонажи стоят вплотную.
MERGE_X = 8

# (исходник, сетка, [(имя, колонка, ряд)]) — col/row считаются с 0.
# Раскладка по ТЗ игрока:
#   Human1/2  2x2: 1:1 муж.маг 1:2 жен.маг 2:1 муж.воин 2:2 жен.воин
#   Druid1    2x2: 1:1 муж.воин 1:2 жен.воин 2:1 муж.маг 2:2 жен.маг
#   Necromant 4x2 (верх = фронт): 1:1 муж.маг 1:2 жен.маг 1:3 муж.воин 1:4 жен.воин
#   Ork1      4x2 (верх = фронт): 1:1 муж.воин 1:2 жен.воин 1:3 муж.маг 1:4 жен.маг
JOBS = [
    ("ChatGPTMainHuman1.png", (2, 2), [
        ("human_m_mage.png", 0, 0),
        ("human_f_mage.png", 1, 0),
        ("human_m_war.png", 0, 1),
        ("human_f_war.png", 1, 1),
    ]),
    ("ChatGPTMainHuman2.png", (2, 2), [
        ("human2_m_mage.png", 0, 0),
        ("human2_f_mage.png", 1, 0),
        ("human2_m_war.png", 0, 1),
        ("human2_f_war.png", 1, 1),
    ]),
    ("ChatGPTMainDruid1.png", (2, 2), [
        ("druid_m_war.png", 0, 0),
        ("druid_f_war.png", 1, 0),
        ("druid_m_mage.png", 0, 1),
        ("druid_f_mage.png", 1, 1),
    ]),
    ("ChatGPTMainNecromant1.png", (4, 2), [
        ("necro_m_mage.png", 0, 0),
        ("necro_f_mage.png", 1, 0),
        ("necro_m_war.png", 2, 0),
        ("necro_f_war.png", 3, 0),
    ]),
    ("ChatGPTMainOrk1.png", (4, 2), [
        ("ork_m_war.png", 0, 0),
        ("ork_f_war.png", 1, 0),
        ("ork_m_mage.png", 2, 0),
        ("ork_f_mage.png", 3, 0),
    ]),
]


# ---------------------------------------------------------------- маска

def background_color(rgb, box):
    """Цвет фона атласа: медиана ПРАВЫХ/НИЖНЕГО краёв всего кадра.

    Раньше семплы брались из углов ячейки, и на 4x2 атласах левый край
    ячейки рядом с соседней фигурой — оттуда могла попасть тёмная ткань.
    Медиана по всему внешнему краю кадра устойчивее.
    """
    h, w = rgb.shape[:2]
    x0, y0, x1, y1 = box
    strips = [
        rgb[0:h:7, :], rgb[h - 1::7, :],
        rgb[:, 0:w:7], rgb[:, w - 1::7],
        rgb[max(0, y0):y0 + 3, x0:x1], rgb[max(0, y1 - 3):y1, x0:x1],
        rgb[y0:y1, max(0, x0):x0 + 3], rgb[y0:y1, max(0, x1 - 3):x1],
    ]
    px = np.concatenate([s.reshape(-1, 3) for s in strips if s.size])
    med = np.median(px, axis=0)
    return med


def _spread(seed, allowed):
    """Векторная заливка: seed & allowed, расширенная по 4-связности.

    Попиксельный deque на кадре 1536x1024 (1.5M px) занимал десятки секунд
    на КАЖДЫЙ вызов, а он вызывается на каждый портрет. Здесь распространение
    идёт целыми строками через numpy: итераций столько же, сколько
    «расстояний» заливки, но каждая — две операции над массивом.
    """
    cur = seed & allowed
    while True:
        nxt = cur.copy()
        nxt[1:, :] |= cur[:-1, :]
        nxt[:-1, :] |= cur[1:, :]
        nxt[:, 1:] |= cur[:, :-1]
        nxt[:, :-1] |= cur[:, 1:]
        nxt &= allowed
        if nxt.sum() == cur.sum():
            return cur
        cur = nxt


def flood_background(dist, bg, tol):
    """Связный с края фон. Заливка, а не глобальный цветовой ключ:
    глобальный ключ съедал тёмные волосы, кожу и робы."""
    h, w = dist.shape
    ok = dist <= tol
    seed = np.zeros((h, w), dtype=bool)
    seed[0, :] = ok[0, :]
    seed[h - 1, :] = ok[h - 1, :]
    seed[:, 0] |= ok[:, 0]
    seed[:, w - 1] |= ok[:, w - 1]
    return _spread(seed, ok)


def _row_runs(row):
    """Горизонтальные серии True в строке -> список (x0, x1)."""
    idx = np.flatnonzero(row)
    if idx.size == 0:
        return []
    brk = np.flatnonzero(np.diff(idx) > 1)
    starts = np.concatenate(([idx[0]], idx[brk + 1]))
    ends = np.concatenate((idx[brk], [idx[-1]]))
    return list(zip(starts.tolist(), ends.tolist()))


def label_components(mask):
    """Связные компоненты (4-связность) через union-find по сериям.

    scipy в проекте нет; попиксельный BFS на 1.5M px слишком медленный,
    а серий мало (несколько тысяч) — union-find по ним быстрый.
    """
    h, w = mask.shape
    parent = {}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    labels = np.zeros((h, w), dtype=np.int32)
    nid = 0
    prev_runs = []
    for y in range(h):
        runs = _row_runs(mask[y])
        cur_runs = []
        for (x0, x1) in runs:
            # метки с 1: 0 зарезервирован под фон (labels == 0 -> False)
            idx = nid + 1
            nid += 1
            parent[idx] = idx
            labels[y, x0:x1 + 1] = idx
            # склеиваем с сериями предыдущей строки, если пересекаются
            for (px0, px1, pid) in prev_runs:
                if px1 >= x0 and px0 <= x1:
                    union(idx, pid)
            cur_runs.append((x0, x1, idx))
        prev_runs = cur_runs
    if nid == 0:
        return labels, []
    roots = np.array([0] + [find(i) for i in range(1, nid + 1)], dtype=np.int64)
    uniq = np.unique(roots[1:])
    remap = np.zeros(nid + 1, dtype=np.int32)
    remap[uniq] = np.arange(1, uniq.size + 1, dtype=np.int32)
    out = remap[roots[labels]]
    areas = np.bincount(out.ravel(), minlength=uniq.size + 1)[1:]
    return out, areas.tolist()


# ---------------------------------------------------------------- ячейки

def dilate_x(mask, r):
    """Расширение маски по X на r px, WITHOUT по Y.

    Нужно, чтобы склеить ОТДЕЛЬНЫЕ компоненты одной фигуры: прядь волос,
    бант, края одежды — они не связаны с телом попиксельно, но принадлежат
    тому же персонажу.

    Расширение ТОЛЬКО по X — не украшение, а требование замера:
      * у Human1 (1024x1536) в правой колонке передняя и задняя фигуры
        стоят вплотную: передняя кончается на y=767, задняя начинается на
        y=768. Зазор по Y = 0. Квадратная морфология на 12 px склеивала их
        в одну фигуру, и верхний портрет получал лишнюю голову снизу.
      * между колонками зазор 190-245 px, там склейки не бывает.
    Радиус подобран ЗАМЕРОМ по всем пяти атласам, а не на глаз:
      r=0, 4, 8 -> везде находится ровно cols*rows фигур;
      r=10 -> Human1 теряет фигуру (4 -> 3): правый передний и задний персонажи
      стоят вплотную, и при 10 px склейка по X перемыкает их.
    То есть 8 px — это потолок, а не «хорошее значение». Дальше трогать нельзя.
    """
    out = mask.copy()
    for _ in range(r):
        acc = out.copy()
        acc[:, 1:] |= out[:, :-1]
        acc[:, :-1] |= out[:, 1:]
        out = acc
    return out


def segment_figures(mask, cols, rows, merge_r=MERGE_X, min_ratio=0.15):
    """Находит фигуры как связные группы и раскладывает их в сетку cols x rows.

    Почему не деление кадра пополам (замер, а не догадка):
      * Necromant 1536x1024: верхний ряд идёт до y=528 при середине 512,
        нижний начинается с y=534 — деление пополам РЕЗАЛО НОГИ.
      * Human1 1024x1536, правая колонка: фигуры стоят вплотную, строки
        755..767 заняты передней фигурой, 768+ — задней, пустой строки
        между ними НЕТ ВООБЩЕ. Любое деление по прямой что-то отрежет.
    Поэтому: компоненты -> склейка соседних -> сортировка центров -> разбиение
    по наибольшим разрывам. Граница берётся по ФАКТИЧЕСКОМУ bbox фигуры.
    """
    lab, areas = label_components(dilate_x(mask, merge_r))
    if not areas:
        return []
    biggest = max(areas)
    keep = [i + 1 for i, a in enumerate(areas) if a >= biggest * min_ratio]
    groups = []
    for k in keep:
        # ГРУППИРУЕМ по склеенной маске (так отдельная прядь волос
        # относится к своей фигуре), но ВЫРЕЗАЕМ по исходной.
        # Иначе dilate_x расширяет силуэт наружу на merge_r px и вокруг
        # персонажа остаётся тёмный ореол из фона: на Human1 ореол был
        # 8 px в исходнике, то есть ~2.5 px в портрете 240 px, и он был
        # виден как чёрная кайма вокруг всего тела.
        m = (lab == k) & mask
        if not m.any():
            continue
        ys, xs = np.nonzero(m)
        groups.append({
            "mask": m,
            "x0": int(xs.min()), "x1": int(xs.max()),
            "y0": int(ys.min()), "y1": int(ys.max()),
            "cx": float(xs.mean()), "cy": float(ys.mean()),
            "area": int(m.sum()),
        })
    if not groups:
        return []
    groups.sort(key=lambda g: g["cy"])
    # разбиваем на `rows` групп по наибольшим разрывам между центрами
    cuts = []
    for i in range(len(groups) - 1):
        cuts.append((groups[i + 1]["cy"] - groups[i]["cy"], i))
    cuts.sort(reverse=True)
    chosen = sorted(i for _, i in cuts[:rows - 1])
    row_of = {}
    start = 0
    for idx, ci in enumerate(list(chosen) + [len(groups) - 1]):
        for g in groups[start:ci + 1]:
            row_of[id(g)] = idx
        start = ci + 1
    out = []
    for r in range(rows):
        band = [g for g in groups if row_of[id(g)] == r]
        band.sort(key=lambda g: g["cx"])
        for c, g in enumerate(band):
            out.append({"col": c, "row": r, **g})
    return out


# ---------------------------------------------------------------- вырезка

def resize_premultiplied(rgba, w, h):
    """Ресайз в premultiplied-пространстве.

    Под alpha=0 у этих атласов лежит мусорный RGB (у Ork (69,64,26)).
    Обычный LANCZOS по RGAC втянул бы его в край — тёмный/оранжевый ободок.
    Премнлипликация даёт ровный рез без ободка.
    """
    src = Image.fromarray(rgba, "RGBA")
    a = np.asarray(src).astype(np.float32)
    alpha = a[..., 3:4] / 255.0
    pm = np.concatenate([a[..., :3] * alpha, alpha * 255.0], axis=2)
    pm = np.clip(np.round(pm), 0, 255).astype(np.uint8)
    small = Image.fromarray(pm, "RGBA").resize((w, h), Image.Resampling.LANCZOS)
    b = np.asarray(small).astype(np.float32)
    ba = np.clip(b[..., 3:4] / 255.0, 0.0, 1.0)
    safe = np.where(ba > 1e-4, ba, 1.0)
    rgb = np.clip(b[..., :3] / safe, 0, 255)
    out_a = np.clip(b[..., 3], 0, 255)
    out_rgb = np.where(ba > 1e-4, rgb, 0.0)
    res = np.concatenate([out_rgb, out_a[..., None]], axis=2)
    return Image.fromarray(np.clip(np.round(res), 0, 255).astype(np.uint8), "RGBA")


def build_mask(rgba, has_alpha, dist, bg):
    """Жёсткая маска «пиксель персонажа» для всего кадра.

    Два источника прозрачности, их нельзя смешивать:
      * RGBA-атлас (Druid/Necromant/Ork) — фон УЖЕ прозрачный. Мягкую альфу
        по цвету считать нельзя: у Necromant RGB под alpha=0 = (63,54,56),
        почти как у тёмного скелета, ключ съедал бы персонажа.
      * RGB-атлас (Human1/2) — альфы нет вообще: после convert("RGBA")
        альфа = 255 на каждом пикселе, и «маска по альфе» даёт
        непрозрачную ячейку целиком (так и было в старой версии).
        Цветовой ключ по расстоянию до цвета фона — приём из
        extract_chatgpt_bottles.py, выбран там по замеру края.
    """
    if has_alpha:
        return rgba[..., 3] > 8
    return ~flood_background(dist, bg, BG_T0)


def strip_background_pockets(sel, dist, tol=BG_T0, min_blob=40):
    """Убирает КАРМАНЫ фона внутри силуэта (тень вокруг фигуры).

    Замер, а не догадка: у Human1 внутри силуэта оставалось 2.1-4.9% пикселей
    с dist<=16 (то есть чистого фона), кластерами до 3248 px. Причина:
    заливка фона идёт ОТ КРАЯ кадра, а вокруг персонажа ChatGPT нарисовал
    тень, которая темнее фона. Тень образует замкнутый контур, и чистый фон
    под ней (у ног, между рукой и корпусом) заливка с края не достаёт.

    fill_holes тут не помогает — он эти карманы наоборот ЗАЛИВАЕТ, потому что
    они не связаны с внешним фоном. То есть нужен обратный проход: вырезать
    фоновые области, а не заливать не-фоновые.

    Мелкие кластеры (< min_blob) оставляем: это настоящие дыры силуэта —
    промежутки между пальцами, просветы ткани, куда должен быть виден фон.
    """
    pockets = sel & (dist <= tol)
    if not pockets.any():
        return sel
    lab, areas = label_components(pockets)
    if not areas:
        return sel
    cut = {i + 1 for i, a in enumerate(areas) if a >= min_blob}
    if not cut:
        return sel
    return sel & ~np.isin(lab, list(cut))


# ------------------------------------------------- инвариант: нет фона в силуэте

def background_in_silhouette(sel_mask, is_bg, min_blob=40):
    """ЛЮБЫЕ фоновые области внутри силуэта — дефект вырезки.

    Первая версия инварианта искала только ЗАМКНУТЫЕ фоновые области
    (не связанные с внешним фоном) и нашла 11 жалоб игрока. Но она оказалась
    фиктивно зелёной на мусоре под ступнями: тень на полу СВЯЗАНА с внешним
    фоном, поэтому «замкнутость» её не ловила. Это ровно тот класс ошибок,
    что описан в AGENTS.md: тест зелёный на сломанном коде.

    Теперь инвариант проверяет буквально то, что видит игрок: если внутри
    силуэта осталась хотя бы одна область цвета фона размером >= min_blob —
    прогон падает. Мелкие кластеры пропускаются: это просветы между
    пальцами и в кружеве, они законны.

    Возвращает список (area, x0, y0, x1, y1).
    """
    pockets = sel_mask & is_bg
    if not pockets.any():
        return []
    lab, areas = label_components(pockets)
    out = []
    for k, a in enumerate(areas):
        if a < min_blob:
            continue
        ys, xs = np.nonzero(lab == (k + 1))
        out.append((int(a), int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())))
    out.sort(reverse=True)
    return out


def touches_canvas_bottom(fig_mask, frame_h):
    """Фигура упирается в нижний край кадра — признак мусора под ступнями.

    Надёжнее прочих, потому что проверяет ГЕОМЕТРИЮ, а не цвет: мусор на
    полу неотличим от тёмной одежды по цвету (замер: у Human2 в силуэте
    при dist<=26 «фон» даёт 40-180 ложных областей размером >=40 px, то есть
    критерий по цвету для RGB-атласов не работает в принципе).

    Замер по всем пяти атласам: фигура, дошедшая до края кадра, всегда
    несёт тень под ступнями, потому что ChatGPT обрезал её полом. Чистые
    результаты от края кадра отстоят на 11-34 px:
      Human2 tol=16 (мусор) -> y1=[767, 767, 1535, 1535], h=1536, касаются 2
      Human2 tol=22 (чисто) -> y1=[764, 766, 1502, 1525], касаются 0
    Первая версия инварианта меряла ширину последней строки и дала ЛОЖНОЕ
    срабатывание на ork_m_war (у Орка стопы широко расставлены, 19% от
    ширины силуэта — это чистый контур, не мусор).
    """
    ys, _ = np.nonzero(fig_mask)
    if ys.size == 0:
        return False
    return int(ys.max()) >= frame_h - 2





def extract(rgba, sel_mask, dist=None):
    """Вырезает фигуру, заданную маской sel_mask.

    dist передаётся ТОЛЬКО для RGB-атласов. Для RGBA-атласов альфа из
    источника уже точная, и заливка дыр там не просто не нужна, а вредит:
    «дыра» между прижатой к торсу рукой и корпусом — это НАСТОЯЩИЙ фон,
    просто замкнутый. Заливка превращала его в непрозрачную кляксу (замер:
    до 3869 px, 5.8% силуэта, у ork_m_war/druid_f_mage). У RGBA-атласов
    фона-тени нет, всё остальное — настоящие просветы (между пальцами,
    в кружеве, между ногами), их трогать нельзя.
    """
    if dist is not None:
        sel_mask = strip_background_pockets(sel_mask, dist)
    ys, xs = np.nonzero(sel_mask)
    if ys.size == 0:
        return None, None, "пусто"
    ax0 = max(0, int(xs.min()) - PAD)
    ay0 = max(0, int(ys.min()) - PAD)
    ax1 = min(sel_mask.shape[1], int(xs.max()) + 1 + PAD)
    ay1 = min(sel_mask.shape[0], int(ys.max()) + 1 + PAD)

    sel = sel_mask[ay0:ay1, ax0:ax1]

    # Внутри силуэта альфа ВСЕГДА 255. Мягкий градиент по цвету фона внутри
    # фигуры давал 39% полупрозрачных пикселей на Human1: тёмные волосы
    # (rgb 20..50) и ткань дают dist 30-50 и превращались в alpha 150-200,
    # то есть персонаж просвечивал. Сглаженный край получается на ресайзе
    # (LANCZOS по премнлиплицированным данным), а не фальшивой альфой.
    alpha = np.where(sel, 255.0, 0.0)

    out = np.zeros((ay1 - ay0, ax1 - ax0, 4), dtype=np.uint8)
    out[..., :3] = rgba[ay0:ay1, ax0:ax1, :3]
    out[..., 3] = np.clip(np.round(alpha), 0, 255).astype(np.uint8)

    scale = TARGET_H / float(ay1 - ay0)
    nw = max(1, int(round((ax1 - ax0) * scale)))
    img = resize_premultiplied(out, nw, TARGET_H)
    return img, (ax0, ay0, ax1, ay1), "ok"


def process(src_name, grid, cells, report):
    path = os.path.join(IMP, src_name)
    if not os.path.exists(path):
        report.append("FAIL нет исходника: " + src_name)
        return None
    raw = Image.open(path)
    has_alpha = raw.mode in ("RGBA", "LA")
    arr = np.array(raw.convert("RGBA"))
    h, w = arr.shape[:2]
    # float32, НЕ int16: (255-0)^2*3 = 195075 переполняет int16 -> NaN,
    # и весь фон становился «нефоном» (это и давало серые блоки)
    rgb = arr[..., :3].astype(np.float32)

    cols, rows = grid
    bg = background_color(rgb, (0, 0, w, h))
    dist = np.sqrt(((rgb - bg[None, None, :]) ** 2).sum(axis=2)).astype(np.float32)
    mask = build_mask(arr, has_alpha, dist, bg)

    figs = segment_figures(mask, cols, rows)
    kind = "alpha" if has_alpha else "colorkey(bg=%s, %.0f..%.0f)" % (
        tuple(int(v) for v in bg), BG_T0, BG_T1)
    info = {"source": src_name, "mode": kind, "size": [w, h],
            "grid": [cols, rows], "figures_found": len(figs), "files": {}}

    if len(figs) != cols * rows:
        report.append("WARN %s: найдено фигур %d, ожидалось %d — имена могут сдвинуться"
                      % (src_name, len(figs), cols * rows))

    results = {}
    for out_name, col, row in cells:
        hit = None
        for f in figs:
            if f["col"] == col and f["row"] == row:
                hit = f
                break
        if hit is None:
            report.append("FAIL %s: не найдена ячейка col=%d row=%d" % (out_name, col, row))
            continue
        # ИНВАРИАНТ: внутри силуэта не должно остаться замкнутых фоновых
        # областей. Для RGBA-атласов «фон» = пиксели с alpha<=8, для RGB-ов
        # = dist<=BG_T0. Проверка идёт по МАСКЕ ДО вырезки, то есть ловит
        # именно тот дефект, который игрок описывает словами «между рукой и
        # торсом не убран фон». Раньше я проверял картинку глазами по 5
        # портретам и пропустил 11 дефектов подряд.
        sel = hit["mask"]
        if dist is not None:
            sel = strip_background_pockets(sel, dist)
        is_bg = (dist <= BG_T0) if not has_alpha else (arr[..., 3] <= 8)
        problems = []
        bad = background_in_silhouette(sel, is_bg)
        if bad:
            problems.append("фон внутри силуэта, %d областей: %s"
                            % (len(bad), ["%dpx@(%d,%d)-(%d,%d)" % b for b in bad[:3]]))
        # второй инвариант: фигура упирается в нижний край кадра = тень
        # под ступнями попала в вырезку
        if touches_canvas_bottom(sel, h):
            problems.append("мусор под ступнями: фигура упирается в нижний край "
                            "кадра (тень на полу попала в силуэт)")
        ok_flag = "BAD" if problems else "ok"
        for pr in problems:
            report.append("FAIL %s: %s" % (out_name, pr))

        img, local, status = extract(arr, hit["mask"], None if has_alpha else dist)
        if img is None:
            report.append("FAIL %s (%s): %s" % (out_name, src_name, status))
            continue
        results[out_name] = img
        info["files"][out_name] = {
            "bbox": list(local),
            "size": list(img.size),
            "enclosed_background": len(bad),
            "touches_canvas_bottom": touches_canvas_bottom(sel, h),
            "problems": problems,
        }
        report.append("%s %-20s %dx%d  bbox=%s" % (ok_flag, out_name,
                                                   img.size[0], img.size[1], local))
    clean = all(not f.get("problems") for f in info["files"].values())
    return {"db": info, "images": results, "clean": clean}


# ---------------------------------------------------------------- вывод

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def checkerboard(size, c=12):
    im = Image.new("RGBA", size, (70, 70, 74, 255))
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], c):
        for x in range(0, size[0], c):
            if (x // c + y // c) % 2 == 0:
                d.rectangle([x, y, x + c - 1, y + c - 1], fill=(100, 100, 104, 255))
    return im


def make_sheet(images, order):
    cols = 5
    cell_w, cell_h = 150, 280
    rows = (len(order) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h), (24, 24, 28, 255))
    for i, name in enumerate(order):
        img = images.get(name)
        if img is None:
            continue
        bx = (i % cols) * cell_w
        by = (i // cols) * cell_h
        tile = checkerboard((cell_w - 8, cell_h - 24))
        th = img.copy()
        th.thumbnail((tile.size[0], tile.size[1]), Image.Resampling.LANCZOS)
        tile.alpha_composite(th, ((tile.size[0] - th.size[0]) // 2, 0))
        sheet.alpha_composite(tile, (bx + 4, by + 4))
        d = ImageDraw.Draw(sheet)
        d.text((bx + 6, by + cell_h - 18), name[:-4], fill=(226, 206, 146, 255))
        # линия «пол» на общей высоте, чтобы разница в росте была видна
        d.line([bx + 4, by + 4 + TARGET_H, bx + cell_w - 4, by + 4 + TARGET_H],
               fill=(120, 200, 255, 160))
    sheet.save(SHEET)


def run(args):
    os.makedirs(OUT, exist_ok=True)
    report = []
    all_images = {}
    dbs = []
    order = []
    ok = True
    for src_name, grid, cells in JOBS:
        res = process(src_name, grid, cells, report)
        if res is None:
            ok = False
            continue
        dbs.append(res["db"])
        if not res.get("clean", True):
            ok = False
        for name, img in res["images"].items():
            all_images[name] = img
            order.append(name)
            path = os.path.join(OUT, name)
            if args.check:
                if not os.path.exists(path):
                    report.append("FAIL нет файла: " + name)
                    ok = False
                    continue
                tmp = os.path.join(OUT, "._" + name)
                img.save(tmp, "PNG")
                got, want = sha256(tmp), sha256(path)
                os.remove(tmp)
                if got != want:
                    ok = False
                report.append("%s %-20s %s vs %s" % (
                    "OK  " if got == want else "FAIL", name, got[:12], want[:12]))
            else:
                img.save(path, "PNG")

    for line in report:
        print(line)

    if not args.check:
        db = {
            "source": "tests/extract_chatgpt_portraits.py",
            "target_height": TARGET_H,
            "key_lo": BG_T0,
            "key_hi": BG_T1,
            "merge_x_px": MERGE_X,
            "atlases": dbs,
        }
        with open(DB, "w", encoding="utf-8") as fh:
            json.dump(db, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        make_sheet(all_images, order)
        print("db   ", DB)
        print("sheet", SHEET)
        print("итого портретов: %d" % len(all_images))
    else:
        print("SHA256:", "все совпали" if ok else "РАСХОЖДЕНИЕ")
    if not ok:
        print("RESULT: FAIL — см. строки FAIL выше (в т.ч. инвариант "
              "«внутри силуэта остался фон»)")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    return run(args)


if __name__ == "__main__":
    sys.exit(main())