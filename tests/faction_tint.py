#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Общий дуотон по светлоте: перекраска base-текстур в цвет металла.

Вынесено из gen_faction_armor_tint.py, потому что ту же формулу применяет
gen_faction_weapon_tint.py, а копировать её во второй генератор нельзя: два
источника одной формулы разъезжаются, и через месяц неизвестно, какой из них
правильный.

Метод - дуотон по светлоте: тон исходника заменяется на цвет металла, а
светлота и внутренние блики берутся из исходного пикселя. Так сохраняется
объём и детализация, а предмет читается как «сделан из этого металла».

Почему не зональная перекраска («только металл, кожу оставить»): замер
assets/items/base показал, что зоны по цвету неразделимы. Синяя рубашка
light_shirt_common даёт 52% насыщенных пикселей, золотое кольцо
heavy_ring_elite - 61%, то есть «самоцвет» и «ткань» выглядят одинаково.

Почему именно рампа тень->свет, а не multiply цветом: multiply гасит
светлые участки (светлая рубашка уходила бы в грязь) и не даёт
металлического блика.

Запуск (не самостоятельный - импортируется):
    from faction_tint import duotone, color_stats, load_palette
"""

from __future__ import annotations

import colorsys
import hashlib
import io
import json
import os

from PIL import Image

# Путь к палитре считается от этого файла, а не от текущего каталога, чтобы
# генератор работал из любой точки.
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE = os.path.join(_ROOT, "assets", "items", "faction_palette.json")

# Форма рампы, в которую подставляется цвет металла.
#
# SHADOW_MUL: нижняя точка рампы = цвет * SHADOW_MUL. Держим её почти у чёрного.
#   Было 0.22 - и это ломало: настоящий чёрный (0.0) поднимался до 0.25, и
#   детализированный визор шлема превращался в плоское тёмно-серое пятно,
#   которое глаз читал как дырку. Замер области визора heavy_head_common:
#   размах светлоты падал с 1.000 (base) до 0.749 (после дуотона) при почти
#   неизменной средней 0.361 - то есть тени просто поднялись и размазались.
#   При 0.04 железная тень = (4,4,5), и глубина возвращается.
#   За это НЕ отвечает calibrate() ниже: он поднимает СЕРЕДИНУ рампы ради
#   читаемости тёмных металлов на тёмном UI - это независимая ось.
SHADOW_MUL = 0.04
HILIGHT_MIX = 0.72      # блик = mix(цвет, белый, 0.72)

# Порог, ниже которого металл считается тёмным и середина рампы поднимается,
# иначе предмет сливается с тёмным UI склада. Замер по палитре:
#   тёмные  (V <= 0.45): cobalt 0.55, plutonium 0.31, thorium 0.35,
#                        wolfram 0.39, yttrium 0.63 -> поднимаем все V < 0.62
#   светлые (V >= 0.65): lutetium 0.90, terbium 0.94, neodymium 0.78 -> не трогаем
DARK_V = 0.62
DARK_MID_V = 0.46       # до какого значения опускать середину тёмного металла

# Порог «схлопывания» объёма. Сканер ловит падение РАЗМАХА светлоты, а не
# хромы: хрома падает у любого нейтрального металла by design (у железа
# (120,120,125) собственная хрома = 5, поэтому и выход почти серый, и это
# правильно). Первая версия сканера брала хрому и завалила бы 34 файла из 342,
# выглядя правдоподобно и показывая ровно то, что чинить не надо.
VOLUME_RATIO_MIN = 0.75

# Качество = тир металла (решение игрока, 1:1). Из-за этого на каждый металл
# приходится РОВНО один файл на слот: 4 металла <-> 4 качества. Раньше здесь
# был цикл по всем TIERS и выдавалось 4 копии одного тира с разной
# детализацией рисунка (1368 файлов вместо 342).
TIERS = ["cheap", "common", "good", "elite"]


def load_palette(path: str | None = None) -> dict:
    with open(path or PALETTE, encoding="utf-8") as fh:
        return json.load(fh)


def palette_metals(pal: dict) -> list:
    """Все металлы палитры списком: {metal, tier, color, group, is_base}."""
    out = []
    for group, gdata in pal["groups"].items():
        for m in gdata["metals"]:
            out.append({
                "metal": m["metal"],
                "tier": m["tier"],
                "color": tuple(m["color"]),
                "group": group,
                "is_base": bool(m.get("is_base")),
            })
    return out


def calibrate(rgb):
    """Поднимает середину рампы у слишком тёмных металлов.

    Возвращает (shadow, mid, hilight) - уже готовые цвета.
    Замер: у cobalt (60,80,140) V=0.55 и у plutonium (60,40,80) V=0.31 середина
    рампа даёт почти чёрные пиксели, предмет не читается на тёмном фоне."""
    r, g, b = rgb
    v = max(r, g, b) / 255.0
    if v < DARK_V:
        # поднимаем середину до DARK_MID_V, сохраняя соотношение каналов
        cur = max(r, g, b)
        if cur > 0:
            k = (DARK_MID_V * 255.0) / cur
            mid = (min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)))
    else:
        mid = (r, g, b)
    shadow = (int(mid[0] * SHADOW_MUL), int(mid[1] * SHADOW_MUL), int(mid[2] * SHADOW_MUL))
    hilight = tuple(int(c + (255 - c) * HILIGHT_MIX) for c in mid)
    return shadow, mid, hilight


def duotone(img: Image.Image, rgb) -> Image.Image:
    """Дуотон: hue берётся у металла, value - у исходного пикселя.

    Альфа копируется из исходника байт в байт - дуотон красит только RGB."""
    shadow, mid, hilight = calibrate(rgb)
    colorsys.rgb_to_hsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)

    out = img.convert("RGBA")
    src = img.convert("RGB").load()
    dst = out.load()
    w, hgt = out.size
    inv = 1.0 / 255.0
    for y in range(hgt):
        for x in range(w):
            r, g, b = src[x, y]
            _, _, v = colorsys.rgb_to_hsv(r * inv, g * inv, b * inv)
            if v < 0.5:
                t = v / 0.5
                c0, c1 = shadow, mid
            else:
                t = (v - 0.5) / 0.5
                c0, c1 = mid, hilight
            dst[x, y] = (
                int(c0[0] + (c1[0] - c0[0]) * t),
                int(c0[1] + (c1[1] - c0[1]) * t),
                int(c0[2] + (c1[2] - c0[2]) * t),
                out.getpixel((x, y))[3],
            )
    return out


def color_stats(img: Image.Image) -> dict:
    """Средняя хрома и размах светлоты по непрозрачным пикселям."""
    px = img.load()
    w, h = img.size
    chroma = 0
    vals = []
    n = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= 128:
                continue
            chroma += max(r, g, b) - min(r, g, b)
            vals.append(max(r, g, b) / 255.0)
            n += 1
    if not n:
        return {"chroma": 0.0, "luma_mean": 0.0, "luma_range": 0.0}
    return {
        "chroma": chroma / float(n),
        "luma_mean": sum(vals) / float(n),
        "luma_range": (max(vals) - min(vals)) if n else 0.0,
    }


def volume_ratio(stats_in: dict, stats_out: dict) -> float:
    """Размах светлоты выход/вход. 1.0 = объём сохранён, ниже = стал плоским."""
    if stats_in["luma_range"] <= 0.01:
        return 1.0
    return stats_out["luma_range"] / stats_in["luma_range"]


def alpha_of(img: Image.Image) -> bytes:
    return img.convert("RGBA").getchannel("A").tobytes()


def sha256_of_img(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return hashlib.sha256(buf.getvalue()).hexdigest()


def sha256_of_file(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()
