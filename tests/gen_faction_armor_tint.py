#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Фракционные варианты одежды: перекраска base-текстур в цвет металла.

Вход:  assets/items/base/{light,heavy}_{slot}_{quality}.png  (108 файлов, из них
       красится только light_* и heavy_* = 72; magic_* по решению игрока не
       трогаем - магическая одежда своя, с оттенком фракции она не вяжется).
Палитра: assets/items/faction_palette.json (источник правды).
Выход: assets/items/faction/{group}/{metal}_{set}_{slot}_{quality}.png

Метод - дуотон по светлоте: тон исходника заменяется на цвет металла, а
светлота и внутренние блики берутся из исходного пикселя. Так сохраняется
объём и детализация, а предмет читается как «сделан из этого металла».

Почему не зональная перекраска («только металл, кожу оставить»): замер
assets/items/base показал, что зоны по цвету неразделимы. Синяя рубашка
light_shirt_common даёт 52% насыщенных пикселей, золотое кольцо
heavy_ring_elite - 61%, то есть «самоцвет» и «ткань» выглядят одинаково.
Классификатор зон давал бы случайные результаты и требовал бы ручной правки
каждого предмета.

Почему именно рампа тень->свет, а не multiply цветом: multiply гасит светлые
участки (светлая рубашка уходила бы в грязь) и не даёт металлического блика.

Запуск:
    python tests/gen_faction_armor_tint.py --report   # только отчёт
    python tests/gen_faction_armor_tint.py            # перекрасить всё
    python tests/gen_faction_armor_tint.py --sheet    # + контактные листы
    python tests/gen_faction_armor_tint.py --check    # сверить SHA256 с диском
"""

from __future__ import annotations

import argparse
import colorsys
import hashlib
import json
import os
import sys

from PIL import Image, ImageDraw

PALETTE = os.path.join("assets", "items", "faction_palette.json")
BASE_DIR = os.path.join("assets", "items", "base")
OUT_ROOT = os.path.join("assets", "items", "faction")

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

TIERS = ["cheap", "common", "good", "elite"]


def load_palette() -> dict:
    with open(PALETTE, encoding="utf-8") as fh:
        return json.load(fh)


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
    """Дуотон: hue берётся у металла, value - у исходного пикселя."""
    shadow, mid, hilight = calibrate(rgb)
    h, s, _ = colorsys.rgb_to_hsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)

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


def sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def build() -> list[dict]:
    """Собирает список заданий {src, dst, metal, group, tier, set, slot, quality}."""
    pal = load_palette()
    jobs = []
    for group, gdata in pal["groups"].items():
        for m in gdata["metals"]:
            if m.get("is_base"):
                continue  # сталь = сами base-файлы, не дублируем
            metal, tier = m["metal"], m["tier"]
            for s in pal["sets"]:
                for slot in pal["slots"]:
                    # КАЧЕСТВО = ТИР МЕТАЛЛА, поэтому вход и выход берут ОДИН и тот
                    # же уровень quality, а не все четыре. Раньше здесь был цикл по
                    # всем TIERS, и на каждый металл выдавалось 4 файла (1368 вместо
                    # 342) - четыре копии одного тира с разной детализацией рисунка.
                    src = os.path.join(BASE_DIR, "%s_%s_%s.png" % (s, slot, tier))
                    if not os.path.exists(src):
                        continue
                    dst = os.path.join(OUT_ROOT, group, "%s_%s_%s_%s.png" % (metal, s, slot, tier))
                    jobs.append({
                        "src": src, "dst": dst, "metal": metal, "group": group,
                        "tier": tier, "set": s, "slot": slot, "quality": tier,
                        "color": tuple(m["color"]),
                    })
    return jobs


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Перекраска base-брони в цвета металлов фракций")
    ap.add_argument("--report", action="store_true", help="только отчёт, ничего не писать")
    ap.add_argument("--sheet", action="store_true", help="собрать контактные листы")
    ap.add_argument("--check", action="store_true", help="сверить SHA256 с диском")
    args = ap.parse_args()

    if not os.path.exists(PALETTE):
        print("НЕТ ПАЛИТРЫ: %s" % PALETTE)
        return 1
    if not os.path.isdir(BASE_DIR):
        print("НЕТ КАТАЛОГА BASE: %s (сначала tests/extract_chatgpt_armor.py)" % BASE_DIR)
        return 1

    pal = load_palette()
    jobs = build()
    total = sum(len(g["metals"]) for g in pal["groups"].values())
    base_tiers = sum(1 for g in pal["groups"].values() for m in g["metals"] if m.get("is_base"))
    print("ГРУПП: %d, МЕТАЛЛОВ: %d (из них base-тиров без перекраски: %d)"
          % (len(pal["groups"]), total, base_tiers))
    print("ЗАДАЧ: %d" % len(jobs))
    if not jobs:
        print("НЕТ ЗАДАЧ - проверь пути base")
        return 1

    for group in sorted(set(j["group"] for j in jobs)):
        n = sum(1 for j in jobs if j["group"] == group)
        metals = [m["metal"] for m in pal["groups"][group]["metals"] if not m.get("is_base")]
        print("  %-14s %3d файлов, металлы: %s" % (group, n, ", ".join(metals)))

    if args.check:
        bad = [j for j in jobs if not os.path.exists(j["dst"])]
        if bad:
            print("НЕТ ФАЙЛОВ: %d (например %s)" % (len(bad), os.path.basename(bad[0]["dst"])))
            return 1
        # перекрашиваем в память и сравниваем хеш с файлом на диске
        mism = []
        for j in jobs:
            got = Image.open(j["dst"]).convert("RGBA")
            want = duotone(Image.open(j["src"]), j["color"])
            if sha256_of_img(got) != sha256_of_img(want):
                mism.append(os.path.basename(j["dst"]))
        if mism:
            print("НЕСОВПАДЕНИЕ: %d файлов, например %s" % (len(mism), ", ".join(mism[:5])))
            return 1
        print("SHA256: все %d файлов совпадают с перегенерацией" % len(jobs))
        return 0

    if args.report:
        return 0

    # страховка: снимок цветовых метрик ДО перекраски, чтобы потом доказать,
    # что порча (если будет) пришла от дуотона, а не от входа
    for j in jobs:
        j["stats_in"] = color_stats(Image.open(j["src"]).convert("RGBA"))

    for j in jobs:
        img = duotone(Image.open(j["src"]), j["color"])
        os.makedirs(os.path.dirname(j["dst"]), exist_ok=True)
        img.save(j["dst"])
    print("ЗАПИСАНО: %d файлов в %s/" % (len(jobs), OUT_ROOT.replace("\\", "/")))

    # Сканер «схлопывания». Важно: портит структуру НЕ хрома, а размах
    # светлоты. Хрома падает у любого нейтрального металла by design: у железа
    # (120,120,125) собственная хрома = 5, поэтому и выход почти серый, и это
    # правильно. Первая версия сканера брала хрому и завалила бы 34 файла из
    # 342, выглядя очень правдоподобно и показывая ровно то, что починить не надо.
    # Правильный признак - размах светлоты упал, то есть объём стал плоским.
    for j in jobs:
        j["stats_out"] = color_stats(Image.open(j["dst"]).convert("RGBA"))
    worst = []
    for j in jobs:
        si, so = j["stats_in"], j["stats_out"]
        ratio = (so["luma_range"] / si["luma_range"]) if si["luma_range"] > 0.01 else 1.0
        j["luma_ratio"] = ratio
        worst.append((ratio, j))
    worst.sort(key=lambda p: p[0])
    print("ОБЪЁМ (размах светлоты выход/вход, меньше = хуже), худшие 8:")
    for ratio, j in worst[:8]:
        print("   %.3f  %-44s размах %.3f -> %.3f, хрома %.1f -> %.1f" % (
            ratio, os.path.basename(j["dst"]),
            j["stats_in"]["luma_range"], j["stats_out"]["luma_range"],
            j["stats_in"]["chroma"], j["stats_out"]["chroma"]))
    flat = [j for r, j in worst if r < 0.75]
    print("ОБЪЁМ ПОТЕРЯН (размах светлоты упал ниже 0.75): %d из %d"
          % (len(flat), len(jobs)))
    for j in flat[:8]:
        print("   ! %s" % os.path.basename(j["dst"]))

    # альфа обязана совпасть с входом байт в байт: дуотон красит только RGB
    bad_alpha = [j for j in jobs
                 if Image.open(j["src"]).convert("RGBA").getchannel("A").tobytes()
                 != Image.open(j["dst"]).getchannel("A").tobytes()]
    print("АЛЬФА РАСХОДИТСЯ: %d (должно быть 0)" % len(bad_alpha))
    if bad_alpha:
        return 1

    if args.sheet:
        for group in sorted(set(j["group"] for j in jobs)):
            make_sheet(pal, group)
        print("КОНТАКТНЫЕ ЛИСТЫ: %s/*/_contact_sheet.png" % OUT_ROOT.replace("\\", "/"))
    return 0


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


def sha256_of_img(img: Image.Image) -> str:
    import io
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return hashlib.sha256(buf.getvalue()).hexdigest()


def make_sheet(pal: dict, group: str) -> None:
    """Лист группы: строки = тиры, колонки = слоты, оба сета рядом."""
    gdata = pal["groups"][group]
    metals = [m for m in gdata["metals"] if not m.get("is_base")]
    slots = pal["slots"]
    sets = pal["sets"]
    cell = 104
    cols = len(slots) * len(sets)
    rows = len(metals)
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 18)), (24, 26, 32, 255))
    d = ImageDraw.Draw(sheet)
    for y in range(0, sheet.size[1], 8):
        for x in range(0, sheet.size[0], 8):
            if ((x // 8) + (y // 8)) % 2 == 0:
                d.rectangle([x, y, x + 7, y + 7], fill=(48, 50, 58, 255))
    for ri, m in enumerate(metals):
        y0 = ri * (cell + 18)
        d.text((4, y0 + cell + 2), "%s %s %s" % (m["metal"], m["tier"], m["color"]),
               fill=(225, 228, 235, 255))
        for si, s in enumerate(sets):
            for li, slot in enumerate(slots):
                name = "%s_%s_%s_%s.png" % (m["metal"], s, slot, m["tier"])
                p = os.path.join(OUT_ROOT, group, name)
                if not os.path.exists(p):
                    continue
                im = Image.open(p).convert("RGBA")
                k = (cell - 10) / float(max(im.size))
                im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))),
                               Image.LANCZOS)
                x0 = (li * len(sets) + si) * cell
                sheet.alpha_composite(im, (x0 + (cell - im.size[0]) // 2,
                                           y0 + (cell - im.size[1]) // 2))
    sheet.save(os.path.join(OUT_ROOT, group, "_contact_sheet.png"))


if __name__ == "__main__":
    sys.exit(main())
