#!/usr/bin/env python3
"""Разновидности Серых по тирам: сдвиг тона с сохранением светлоты.

Зачем. Тиров у Серых нет ни одного: пул `GRAY_POOL_TEST` даёт семь видов без
градации, а задумано 4-5 тиров (`AGENTS.md` §13, пакет C). Генерировать каждую
разновидность отдельно дорого: набор - это 12 кадров, то есть 4 полосы, то есть
примерно $0.24 за вид. Перекраска ничего не стоит.

Почему не `faction_tint.duotone`. Он раскладывает картинку на две яркости от
одного заданного цвета - так сделана броня, где фактура металла и должна быть
одноцветной. У зверя оттенок сам carries вид: серый волк, зелёная оса, бурый
динозавр. Сведение к двум тонам убивает различие между видами, ради которого
пул и существует.

Поэтому здесь сдвиг ТОНА при сохранении светлоты и насыщенности: силуэт,
светотный рисунок и все детали остаются попиксельно теми же, меняется только
цвет. Это и есть «разновидность», а не «другой зверь».

Проверки, без которых перекраска не годится:
- альфа не меняется ни на один пиксель (иначе кадр поедет по земле);
- средняя светлота сохраняется (иначе тирный зверь станет темнее оригинала и
  будет читаться иначе при том же свете);
- объём силуэта не меняется.

Запуск:
    python tests/gen_grey_tiers.py --preview wolf          # 4 варианта в C:\\Temp
    python tests/gen_grey_tiers.py --build wolf            # записать в assets
    python tests/gen_grey_tiers.py --build --all           # все виды пула
    python tests/gen_grey_tiers.py --build wolf --check     # только проверить
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC_ROOT = REPO / "assets" / "units" / "monsters"

_UNITS: dict | None = None

# Тир 1 - сам зверь без перекраски, его палитра не трогается.
#
# Сдвиг ТОЛЬКО относительный не годится, и это измерено (см. журнал): сдвиг
# считается от палитры исходника, поэтому тиры разных видов попадали в разные
# цвета - тир 5 волка фиолетовый (230°), тир 5 призрака жёлтый (49°), тир 4
# дракона маджента (255°). Игрок не смог бы опознать тир по цвету.
#
# Поэтому у каждого тира есть ЦЕЛЕВОЙ тон, и тон существа переносится к нему
# с сохранением разброса оттенков ВНУТРИ спрайта: медведь останется медведем со
# своим рисунком шерсти, но станет цвета своего тира.
#
# Цели подобраны так, чтобы ряд читался от тёплого к холодному и обратно к
# «элитному» фиолету. Что означает каждый тир, решает игрок.
#
# ТИР 2 отличается от остальных намеренно (решение игрока). Тон его цели 25°
# совпадает с нативным тоном ЧЕТЫРЁХ видов из семи: bee 20.6, dino 25.9,
# squirrel 13.1, wolf 18.1. Отличие 1-12°, то есть на глаз тир 2 у них не
# отличим от оригинала - это измерено на хрома-взвешенном среднем тоне
# (вес = насыщенность; у серых пикселей HSV Hue не информативен).
#
# Поэтому тир 2 различает НЕ тон, а насыщенность и светлота: x1.55 по
# насыщенности и x0.72 по светлоте. Насыщенность в HSV не может сделать
# янтарный янтарнее, а вот потемнение и подсыщение превращают рыжего волка в
# тёмного янтарного - это читается как «другой зверь» без смены оттенка.
TIERS = [
    #      цель   сила  насыщ.  светл.
    (2, 25.0, 0.55, 1.55, 0.72),  # тёмный насыщенный янтарь
    (3, 95.0, 0.55, 1.06, 1.00),  # зелёный
    (4, 205.0, 0.60, 1.12, 1.00),  # ледяной синий
    (5, 285.0, 0.65, 1.20, 1.00),  # элитный фиолет
]

ALPHA_TOL = 0
# Допуск к ОТНОШЕНИЮ светлоты l1/l0 против заданного val_mul. Широкий не нужен:
# отношение проверяет намерение, а не «примерно похоже».
LIGHT_TOL = 0.035

# Лестница имён (решение игрока). Ключ — имя папки вида, значение — тройка
# (именительный, родительный, род). Виды в НИЖНЕМ регистре: прилагательное
# стоит перед видом, и «Свирепый Летучая мышь» — это регистровая ошибка.
# Заглавная буква поднимается один раз, на готовом имени.
#
# Род обязателен, а не украшение: прилагательное согласуется с видом, иначе
# выходит «Свирепый пчела». Родительный падеж нужен тиру 5 — «Владыка белок»,
# а не «Владыка белка».
SPECIES_RU = {
    "wolf": ("волк", "волков", "m"),
    "dino": ("динозавр", "динозавров", "m"),
    "squirrel": ("белка", "белок", "f"),
    "bee": ("пчела", "пчёл", "f"),
    "bat": ("летучая мышь", "летучих мышей", "f"),
    "ghost": ("призрак", "призраков", "m"),
    "dragon": ("дракон", "драконов", "m"),
    # 17.10: два новых вида по просьбе игрока. Оба двуногие, поэтому прилагательные
    # стоят в мужском роде.
    "cannibal": ("людоед", "людоедов", "m"),
    "troll": ("тролль", "троллей", "m"),
    # 17.10: суккуб добавлен в пул по решению игрока. Без фазы удара
    # (`attack: 0`), поэтому копии — перекраска, как у остальных.
    "succubus": ("суккуб", "суккубов", "f"),
}

# Прилагательные по тирам, формы (муж., жен.). Среднего рода в пуле нет.
TIER_ADJ = {
    2: ("Свирепый", "Свирепая"),
    3: ("Древний", "Древняя"),
    4: ("Легендарный", "Легендарная"),
}


def tier_name(name: str, tier: int) -> str:
    """Русское имя набора по виду и тиру (решение игрока).

    Лестница прилагательных: тир 1 — обычное название вида, дальше Свирепый →
    Древний → Легендарный → Владыка. Прилагательное согласуется с родом вида
    («Свирепая пчела»), а тир 5 стоит в родительном падеже («Владыка пчёл»).

    Имя нужно потому, что тултип берёт подпись из поля `name_ru`; без него
    игрок видел бы английский `desc` вида «Monster wolf, Gemini Nano Banana
    strips…».
    """
    nominative, genitive, gender = SPECIES_RU[name]
    if tier == 1:
        out = nominative
    elif tier == 5:
        out = f"Владыка {genitive}"
    else:
        adj = TIER_ADJ[tier][0 if gender == "m" else 1]
        out = f"{adj} {nominative}"
    return out[0].upper() + out[1:]


def shift_hue(img: Image.Image, target_deg: float, spread_keep: float,
               sat_mul: float, val_mul: float = 1.0) -> Image.Image:
    """Перенести тон спрайта к целевому, сохранив разброс оттенков внутри.

    Формула: `h' = target + (h - base) * spread_keep`.

    Именно центрирование, а НЕ «притяжение к цели». Притяжение ломается, когда
    тон существа почти противоположен цели: у динозавра база 26°, цель тира 4
    205°, разница 179°, и притяжение с силой 0.60 давало 133° - зелёный вместо
    синего, то есть тир 4 у динозавра не совпадал с тиром 4 у пчелы. Здесь база
    всегда садится ровно на цель, а разброс оттенков ВНУТРИ спрайта (шерсть,
    чешуя, блики) сохраняется в долю `spread_keep`, и существо остаётся собой.

    Альфа не трогается ни на один бит. Светлота (канал V) сохраняется по
    умолчанию, но `val_mul` затемняет её - этого нужно тиру 2, у которого
    нативный тон зверя почти совпадает с целью (см. TIERS).
    """
    out = img.copy()
    alpha = np.asarray(img)[..., 3].copy()
    hsv = img.convert("RGB").convert("HSV")
    h, s, v = hsv.split()
    ha = np.asarray(h, dtype=np.float32)
    sa = np.asarray(s, dtype=np.float32)
    va = np.asarray(v, dtype=np.float32)

    a = np.asarray(alpha)
    sel = a > 32
    if not sel.any():
        return out
    # Опорный тон спрайта - круговое среднее по видимым пикселям, а не
    # арифметическое: 350° и 10° это один красный, а среднее арифметическое
    # дало бы 180° - зелёный из красного.
    ang = ha[sel] * (2.0 * np.pi / 256.0)
    base = float(np.arctan2(np.sin(ang).mean(), np.cos(ang).mean()))

    # Градусы -> радианы. Именно pi/180: умножение на 2*pi/180 удваивало цель
    # (25° -> 50°, 95° -> 190°, 205° -> 50°, 285° -> 210°), из-за чего тир 2 и
    # тир 4 выходили одним цветом. Поймано синтетикой: равномерный спрайт 30°
    # при цели 25° давал 47.8° вместо 25°.
    target = target_deg * (np.pi / 180.0)
    rel = ha * (2.0 * np.pi / 256.0) - base
    # Разница углов по КРУГУ. Без этого пиксель с тоном 10° при базе 350° даёт
    # -340° вместо +20°, и результат заворачивается: тир 4 выходил тем же
    # цветом, что тир 2 (измерено: 50° против 51°).
    rel = np.mod(rel + np.pi, 2.0 * np.pi) - np.pi
    ha = np.mod(target + rel * spread_keep, 2.0 * np.pi) * (256.0 / (2.0 * np.pi))
    sa = np.clip(sa * sat_mul, 0, 255)
    va = np.clip(va * val_mul, 0, 255)

    hsv2 = Image.merge("HSV", (Image.fromarray(ha.astype(np.uint8)),
                               Image.fromarray(sa.astype(np.uint8)),
                               Image.fromarray(va.astype(np.uint8))))
    out.paste(hsv2.convert("RGB"), (0, 0))
    out.putalpha(Image.fromarray(alpha))
    return out


def mean_light(img: Image.Image) -> float:
    a = np.asarray(img)[..., 3]
    if not (a > 32).any():
        return 0.0
    v = np.asarray(img.convert("RGB").convert("HSV"), dtype=np.float32)[..., 2]
    return float(v[a > 32].mean() / 255.0)


def alpha_bytes(img: Image.Image) -> bytes:
    return np.asarray(img)[..., 3].tobytes()


def build_set(name: str, check_only: bool) -> list[str]:
    """Сделать тирные копии набора. Возвращает список строк отчёта."""
    src = SRC_ROOT / name
    frames = sorted(src.glob("sprites-*.png"))
    if not frames:
        return [f"{name}: нет кадров в {src}"]
    lines = []
    for tier, target, strength, sat, val in TIERS:
        dst = SRC_ROOT / f"{name}_t{tier}"
        problems = []
        for p in frames:
            img = Image.open(p).convert("RGBA")
            new = shift_hue(img, target, strength, sat, val)
            if alpha_bytes(new) != alpha_bytes(img):
                problems.append(f"{p.name}: альфа изменилась")
            l0, l1 = mean_light(img), mean_light(new)
            # Светлота проверяется ОТНОШЕНИЕМ l1/l0, а не «почти не изменилась».
            # Тир 2 затемняется намеренно, и вольный допуск 0.32 пропустил бы
            # любую проваленную яркость; отношение к заданному `val_mul` -
            # настоящий инвариант: ловит и просадку от сдвига тона, и то, что
            # затемнение применилось ровно настолько, насколько заказано.
            if l0 > 0.0:
                ratio = l1 / l0
                if abs(ratio - val) > LIGHT_TOL:
                    problems.append(f"{p.name}: светлота {l0:.3f} -> {l1:.3f} "
                                    f"(x{ratio:.3f}, ждём x{val:.2f})")
            if check_only:
                continue
            dst.mkdir(parents=True, exist_ok=True)
            new.save(dst / p.name)
        entry = json_entry(name, tier, len(frames))
        if not check_only:
            (dst / "_entry.json").write_text(
                json.dumps(entry, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        verdict = "БРАК" if problems else "ок"
        lines.append(f"  {verdict} {name}_t{tier} (цель {target:.0f}°, сила {strength:.2f}, "
                     f"насыщ. x{sat:.2f}, светл. x{val:.2f}), кадров {len(frames)}")
        for pr in problems[:4]:
            lines.append(f"       {pr}")
    return lines


def _base_units() -> dict:
    """Записи тира 1 из units_db.json — источник истины по нехудожественным полям.

    Нужно ради поля `z`: у bat/bee/ghost/dragon оно есть, и без него тирная
    копия перестаёт летать, то есть враг не обходит воду и горы
    (`enemy.gd` проверяет `fly_z > 0`). Константа в этом файле была бы
    второй копией и разъехалась бы с базой.
    """
    global _UNITS
    if _UNITS is None:
        raw = (REPO / "assets" / "units" / "units_db.json").read_text(encoding="utf-8")
        _UNITS = json.loads(raw)
    return _UNITS


def json_entry(name: str, tier: int, frames: int) -> dict:
    # Контрактные поля (сколько фаз у удара/смерти, размеры холста, полёт) НЕ
    # задаются здесь константами: они копируются из `_entry.json` базового
    # набора. Иначе тирная копия расходится с оригиналом по контракту — так
    # и вышло с суккубом: у него `attack: 0` и 9 кадров, а зашитое в генераторе
    # `attack: 3` молча обещало бы анимацию удара, которой нет.
    base_entry = json.loads(
        (SRC_ROOT / name / "_entry.json").read_text(encoding="utf-8"))
    entry = {
        "name_ru": tier_name(name, tier),
        "tier": tier,
        "desc": f"Monster {name} tier {tier}, recoloured variant, three-quarter east "
                f"view + mirror, idle1+move4"
                + ("+attack3" if int(base_entry.get("attack", 0)) > 0 else "")
                + "+dying4",
    }
    for key in ("dirs", "idle_phases", "move", "move_begin", "attack", "dying",
                "decay", "cast", "idle", "move_f", "move_t", "attack_f",
                "attack_t", "die_f", "dying_t", "w", "h", "cx", "cy", "tile",
                "projectile", "palette", "blocks", "resist", "z"):
        if key in base_entry:
            entry[key] = base_entry[key]
    entry["folder"] = f"monsters/{name}_t{tier}"
    entry["frames"] = frames
    entry["prefix"] = base_entry.get("prefix", "sprites")
    return entry


def preview(name: str) -> Path:
    """Контактный лист: исходник + четыре тира, в игровом масштабе x3."""
    src = SRC_ROOT / name
    frames = sorted(src.glob("sprites-*.png"))
    cols, z = 5, 3
    cell = 64 * z
    ladder = [(1, 0.0, 0.0, 1.0, 1.0)] + TIERS
    sheet = Image.new("RGBA", (cols * cell, len(ladder) * cell), (34, 34, 38, 255))
    px = sheet.load()
    for y in range(len(ladder) * cell):
        for x in range(cols * cell):
            px[x, y] = (74, 74, 80, 255) if ((x // 16) + (y // 16)) % 2 else (50, 50, 54, 255)
    for row, (tier, target, strength, sat, val) in enumerate(ladder):
        for i, p in enumerate(frames):
            img = Image.open(p).convert("RGBA")
            if tier > 1:
                img = shift_hue(img, target, strength, sat, val)
            sheet.alpha_composite(img.resize((cell, cell), Image.NEAREST),
                                 (i * cell, row * cell))
    out = Path(r"C:\Temp\opencode") / f"tiers_{name}.png"
    sheet.save(out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("name", nargs="?", default="")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--build", action="store_true", help="записать в assets")
    ap.add_argument("--check", action="store_true", help="только проверить, не писать")
    ap.add_argument("--preview", default="", help="контактный лист в C:/Temp")
    args = ap.parse_args()

    if args.preview:
        p = preview(args.preview)
        print(f"контактный лист: {p}")
        print("ряды сверху вниз: тир 1 (оригинал), тиры 2, 3, 4, 5")
        return 0

    names = sorted(d.name for d in SRC_ROOT.iterdir()
                   if d.is_dir() and not d.name.startswith("_")
                   and not any(ch.isdigit() for ch in d.name[-2:]))
    if args.all:
        chosen = names
    elif args.name:
        chosen = [args.name]
    else:
        print("укажи вид или --all")
        return 1
    print("виды:", ", ".join(chosen))
    bad = 0
    for n in chosen:
        for line in build_set(n, check_only=args.check or not args.build):
            print(line)
            if line.strip().startswith("БРАК"):
                bad += 1
    print(f"\n{'ПРОВЕРКА' if not args.build else 'ЗАПИСАНО'}: проблем {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
