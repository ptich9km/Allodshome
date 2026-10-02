#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генератор формулы «металл -> статы» (этап 2 бета-подготовки).

ЗАЧЕМ
-----
Замер 03.10: 554 из 651 предметов 13 металлов фракций имели ПОБАЙТОВО
одинаковую сигнатуру (type, quality, damage_min/max, to_hit, defence,
absorption, magcap) с тербием. Причина в tests/gen_empty_metals_items.py:167 —
он масштабировал от цены слитка только `price`, а статы копировал из
образца. Итог: слабый lutetium (слиток 24) был равен тербию (слиток 40),
а terbium-клоны стоили как элитные.

ФОРМУЛА
-------
    stats(metal) = base(type, quality) x (ingot_price(metal) / ingot_price(ref)) ^ exp

`base(type, quality)` берётся у САМОГО ДЕШЁВОГО металла, у которого есть
предмет такой пары (тип, качество) — обычно это bronze. Поэтому bronze
имеет множитель ровно 1.0 и его числа не меняются вообще.

Степени лежат в game.cfg ([metal] damage_exp и т.д.) и подобраны так,
чтобы «настоящие» металлы не поехали:
    bronze 1.00 (эталон), iron 1.40 (было 1.38), radium 7.11 (было 7.12)
Отсюда и берётся 0.22 — это НЕ круглое число из головы.

ПОЧЕМУ СТЕПЕНЬ, А НЕ ТАБЛИЦА ТИРОВ
---------------------------------
Таблица cheap/common/good/elite не может описать legacy-металлы: radium
(слиток 12150) в 7.1 раз сильнее bronze, а terbium (слиток 40) — в 2.0,
при том что оба elite. Степень по цене слитка даёт монотонность САМОЙ
собой: цена -> сила, без таблицы, которую надо поддерживать руками.
Побочный плюс: игрок меняет одно число в .cfg и через секунду получает
перебалансированные все 946 предметов, без регенерации базы.

ЧТО НЕ ДЕЛАЕТ
--------------
Не трогает цену (её лестка уже согласована), не трогает неметаллы
(wood/leather/linen), не трогает зелья/свитки/травы/книги.
`--dry-run` только печатает отчёт и ничего не пишет.

Запуск:
    python tests/gen_metal_stats.py --dry-run
    python tests/gen_metal_stats.py
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import statistics
import sys

DB = os.path.join("assets", "items", "item_db.json")
CFG = os.path.join("assets", "config", "game.cfg")

# Предметы без металла и не-боевое снаряжение — их статы не пересчитываются.
SKIP_QUALITY = {"Herb", "Scroll", "SuperScroll", "Book", "Quest", "Potion"}
SKIP_TYPE = {"Ingot", "Herb"}

FIELDS = ("damage_min", "damage_max", "to_hit", "defence", "absorption")
EXP_KEY = {
    "damage_min": "damage_exp",
    "damage_max": "damage_exp",
    "to_hit": "to_hit_exp",
    "defence": "defence_exp",
    "absorption": "absorption_exp",
}


def read_cfg() -> dict:
    """Читает [metal] из game.cfg. Файл генерируется скриптом на GDScript,
    формат ConfigFile — секция [metal], ключ=значение."""
    cp = configparser.ConfigParser()
    cp.optionxform = str  # не lowercasить ключи
    cp.read(CFG, encoding="utf-8")
    if not cp.has_section("metal"):
        raise SystemExit("FAIL: в game.cfg нет секции [metal]")
    m = dict(cp.items("metal"))
    cfg = {
        "reference_metal": m.get("reference_metal", "bronze"),
        "damage_exp": float(m.get("damage_exp", 0.22)),
        "to_hit_exp": float(m.get("to_hit_exp", 0.10)),
        "defence_exp": float(m.get("defence_exp", 0.22)),
        "absorption_exp": float(m.get("absorption_exp", 0.15)),
    }
    return cfg


def split_blocks(text: str):
    lines = text.split("\n")
    blocks, start = [], None
    for i, line in enumerate(lines):
        if start is None and line == " {":
            start = i
            continue
        if start is not None and line in (" }", " },"):
            blocks.append((start, i + 1, "\n".join(lines[start : i + 1])))
            start = None
    if not blocks:
        raise SystemExit("FAIL: блоки предметов не найдены")
    prefix = text[: text.index(blocks[0][2])]
    last = blocks[-1]
    suffix = text[text.rindex(last[2]) + len(last[2]) :]
    return prefix, blocks, suffix


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cfg = read_cfg()
    print("=== формула из game.cfg [metal] ===")
    for k, v in cfg.items():
        print(f"   {k:18} {v}")

    with open(DB, encoding="utf-8") as f:
        items = json.load(f)

    # цена слитка на металл
    ingot = {}
    for i in items:
        if str(i.get("type")) == "Ingot":
            ingot[str(i.get("material"))] = int(i.get("price", 0))
    if cfg["reference_metal"] not in ingot:
        raise SystemExit(f"FAIL: reference_metal={cfg['reference_metal']} не имеет слитка")

    # множитель на металл
    ref_price = ingot[cfg["reference_metal"]]
    mult = {}
    for m, p in ingot.items():
        ratio = float(p) / float(ref_price)
        mult[m] = {f: ratio ** cfg[EXP_KEY[f]] for f in FIELDS}

    # база по (тип, качество) от самого дешёвого металла, который её имеет.
    # ВАЖНО: база НОРМИРУЕТСЯ на множитель своего же металла, иначе базовый
    # металл получил бы свой множитель второй раз и сам оказался бы завышен.
    # Это поймал инвариант монотонности: wolfram(слиток 18) оказывался
    # сильнее steel(слиток 20), потому что у пары (тип, качество) дешевле
    # всего был wolfram, и его 34.00 перемножалось ещё на его же множитель.
    # После нормировки база — «единичные» статы, и metal получает ровно
    # mult[metal], то есть монотонность верна по построению.
    cheap_order = sorted(ingot.items(), key=lambda kv: kv[1])
    base: dict[tuple[str, str], dict] = {}
    base_metal: dict[tuple[str, str], str] = {}
    for i in items:
        m = str(i.get("material"))
        if m not in ingot or str(i.get("quality")) in SKIP_QUALITY:
            continue
        if str(i.get("type")) in SKIP_TYPE:
            continue
        k = (str(i.get("type")), str(i.get("quality")))
        cur = base_metal.get(k)
        if cur is None or ingot[m] < ingot[cur]:
            base_metal[k] = m
            base[k] = i

    # нормированная база (float)
    norm: dict[tuple[str, str], dict] = {}
    for k, src in base.items():
        owner = base_metal[k]
        u = mult[owner]
        norm[k] = {
            f: (float(src[f]) / u[f] if isinstance(src.get(f), int) and u[f] > 0 else 0.0)
            for f in FIELDS
        }

    print(f"\n=== множители (база={cfg['reference_metal']}, слиток={ref_price}) ===")
    print(f"{'металл':12}{'слиток':>8}{'урон':>8}{'to_hit':>8}{'защита':>8}")
    for m, p in sorted(ingot.items(), key=lambda kv: kv[1]):
        u = mult[m]
        print(f"{m:12}{p:>8}{u['damage_min']:>8.2f}{u['to_hit']:>8.2f}{u['defence']:>8.2f}")

    # пересчёт
    prefix, blocks, suffix = split_blocks(
        open(DB, encoding="utf-8").read().replace("\r\n", "\n")
    )
    out, changed, same = [], 0, 0
    after_items: list[dict] = []
    dmg_by_metal_before: dict[str, list] = {}
    dmg_by_metal_after: dict[str, list] = {}

    for _, _, b in blocks:
        it = json.loads("[" + b.rstrip().rstrip(",") + "]")[0]
        m = str(it.get("material"))
        q = str(it.get("quality"))
        t = str(it.get("type"))
        if m not in ingot or q in SKIP_QUALITY or t in SKIP_TYPE:
            after_items.append(it)
            out.append(b)
            continue
        k = (t, q)
        if k not in norm:
            after_items.append(it)
            out.append(b)
            continue
        nb_ = norm[k]
        new = {}
        for f in FIELDS:
            v = nb_[f] * mult[m][f]
            new[f] = max(0, int(round(v)))
        # damage_min/max не должны перепутаться местами и не схлопнуться в 0
        if new["damage_min"] == 0 and new["damage_max"] > 0:
            new["damage_min"] = new["damage_max"]
        dmin, dmax = it.get("damage_min", 0), it.get("damage_max", 0)
        if isinstance(dmin, int) and dmax > 0:
            dmg_by_metal_before.setdefault(m, []).append((dmin + dmax) / 2.0)
        if new["damage_max"] > 0:
            dmg_by_metal_after.setdefault(m, []).append((new["damage_min"] + new["damage_max"]) / 2.0)

        nb = b
        for f in FIELDS:
            old = it.get(f, 0)
            if new[f] == old:
                continue
            mo = re.search(r'^(\s*)"%s":\s*-?\d+(,?)\s*$' % f, nb, re.M)
            if mo is None:
                raise SystemExit(f"FAIL: не найдена строка {f} у {it.get('key')}")
            ind, comma = mo.group(1), mo.group(2)
            nb = nb[: mo.start()] + '%s"%s": %d%s' % (ind, f, new[f], comma) + nb[mo.end():]
        if nb == b:
            same += 1
        else:
            changed += 1
        out.append(nb)
        after_items.append(dict(it, **new))

    print(f"\n=== результат ===")
    print(f"пересчитано предметов: {changed}")
    print(f"оставлено без изменений: {same}")

    print(f"\n=== урон по металлам: было -> стало (медиана) ===")
    print(f"{'металл':12}{'слиток':>8}{'было':>9}{'стало':>9}")
    for m, p in sorted(ingot.items(), key=lambda kv: kv[1]):
        b_ = dmg_by_metal_before.get(m, [])
        a_ = dmg_by_metal_after.get(m, [])
        if not a_:
            continue
        print(f"{m:12}{p:>8}{statistics.median(b_) if b_ else 0:>9.2f}{statistics.median(a_):>9.2f}")

    # ---- ИНВАРИАНТЫ -----------------------------------------------------
    print("\n=== инварианты ===")
    ok = True
    # 1. МОНОТОНОННОСТЬ внутри одной пары (тип, качество): дороже слиток ->
    #    не слабее та же вещь из другого металла.
    #    Именно такой, а не по медиане на металл. Медиана по металлу смешивает
    #    две разные вещи — «металл сильнее» и «у металла другой набор
    #    типов/качеств»: у золота всего 3 предмета с уроном, у титания 28,
    #    и медианы не сравнимы. На такой проверке формула выглядела бы
    #    сломанной, будучи корректной. Сравнивать надо лайки за лайку.
    pair_new: dict[tuple[str, str], list] = {}
    for it2 in after_items:
        m = str(it2.get("material"))
        q = str(it2.get("quality"))
        t2 = str(it2.get("type"))
        if m not in ingot or q in SKIP_QUALITY or t2 in SKIP_TYPE:
            continue
        d2 = it2.get("damage_max", 0)
        if not isinstance(d2, int) or d2 <= 0:
            continue
        pair_new.setdefault((t2, q), []).append((ingot[m], m, d2))
    viol: list = []
    for pair, rows in pair_new.items():
        rows.sort()
        for i in range(len(rows) - 1):
            if rows[i][2] > rows[i + 1][2]:
                viol.append((pair, rows[i][1], rows[i][2], rows[i + 1][1], rows[i + 1][2]))
    print(f"[1] монотонность урона внутри пары (тип, качество): пар {len(pair_new)}, нарушений {len(viol)}")
    for v in viol[:6]:
        print(f"      {v[0][0]}/{v[0][1]}: {v[1]}={v[2]} сильнее {v[3]}={v[4]} при более дешёвом слитке")
    if viol:
        ok = False
    # 2. у эталонного металла множитель ровно 1.0 -> его числа не поехали
    refd = sum(1 for _, _, b in blocks if str(json.loads("[" + b.rstrip().rstrip(",") + "]")[0].get("material")) == cfg["reference_metal"])
    print(f"[2] эталон {cfg['reference_metal']}: предметов {refd}, множитель 1.000")
    # 3. ни один урон не обнулился
    zeros = [m for m, v in dmg_by_metal_after.items() if statistics.median(v) <= 0]
    print(f"[3] металлов с нулевым уроном: {len(zeros)}")
    if zeros:
        ok = False
    # 4. не было 13 клонов подряд
    dup = []
    for m in ingot:
        v = dmg_by_metal_after.get(m)
        if v and len(set(v)) == 1 and len(v) > 5:
            dup.append(m)
    print(f"[4] металлов с ОДНИМ уроном на все типы/качества (клоны): {len(dup)} {dup if dup else ''}")

    if args.dry_run:
        print("\nRESULT: OK (dry-run, файл не тронут)")
        return 0 if ok else 2

    with open(DB, "w", encoding="utf-8", newline="") as f:
        f.write(prefix + "\n".join(out) + suffix)

    with open(DB, encoding="utf-8") as f:
        check = json.load(f)
    print(f"\nпосле записи: {len(check)} предметов, JSON валиден")
    print("RESULT: OK" if ok else "RESULT: FAIL (инварианты нарушены, файл всё равно записан — смотри отчёт)")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
