# -*- coding: utf-8 -*-
"""Юнит-тесты сборки промтов gen_hero_strip.py (21.10, запрос игрока).

Модель читает промт буквально: физически неисполнимые раскладки она
"решает" самовольно (2 ряда вместо одного), а пропущенные определения пола
заменяет стереотипами (грудь у "solid torso" мага). Оба дефекта ловятся
тут, на тексте, ДО платной генерации.

Запуск: python tests/test_prompts.py  (без pytest — plain assert)
"""
import importlib.util
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "gen_hero_strip", HERE / "gen_hero_strip.py")
ghs = importlib.util.module_from_spec(spec)
sys.argv = ["gen_hero_strip.py"]  # заглушка для argparse-поля module-level
spec.loader.exec_module(ghs)

FAILS = []


def check(name, cond, detail=""):
    if cond:
        print(f"  ок   {name}")
    else:
        FAILS.append(name)
        print(f"  ПРОВАЛ {name} {detail}")


def build_prompt(race, sex, anim="stand", mage=True):
    """Точная копия сборки main() для заданной расы/пола."""
    if mage:
        char_map = {"human": (ghs.CHARACTER_M, ghs.CHARACTER_M_F),
                    "orc": (ghs.CHARACTER_OM, ghs.CHARACTER_OM_F),
                    "undead": (ghs.CHARACTER_UM, ghs.CHARACTER_UM_F),
                    "druid": (ghs.CHARACTER_DM, ghs.CHARACTER_DM_F)}
        c, cf = char_map[race]
        if sex == "f":
            character, proportions, view = cf, ghs.PROPORTIONS_M_F, ghs.VIEW_F
        else:
            character, proportions, view = c, ghs.PROPORTIONS_M, ghs.VIEW
    else:
        table = {"human": (ghs.CHARACTER, ghs.CHARACTER_F),
                 "orc": (ghs.CHARACTER_O, ghs.CHARACTER_O_F),
                 "undead": (ghs.CHARACTER_U, ghs.CHARACTER_U_F),
                 "druid": (ghs.CHARACTER_D, ghs.CHARACTER_D_F)}
        c, cf = table[race]
        if sex == "f":
            character, proportions, view = cf, ghs.PROPORTIONS_F, ghs.VIEW_F
        else:
            character, proportions, view = c, ghs.PROPORTIONS, ghs.VIEW
    pose = ghs.ANIMS[anim]
    if sex == "f":
        pose = ghs.femaleize(pose)
    return " ".join((
        f"{character}\n\n{proportions}\n\n{view}\n\n{pose}\n\n{ghs.LAYOUT}"
    ).split())


# Раскладка не должна требовать неисполнимого (8 фигур на весь рост):
# именно это рождало 2 ряда. One row обязан быть, про "fills the image
# height" упоминания быть не должно.
layout = ghs.LAYOUT
check("layout: одна строка", "single horizontal row" in layout)
check("layout: запрет двух строк", "TWO ROWS IS A HARD ERROR" in layout)
check("layout: нет 'fills the image height'",
      "fills the image height" not in layout,
      "— неисполнимо при 8 фигурах, модель кладёт 2 ряда")

# Промт мага теперь = воинский ДОСЛОВНО (только одежда заменена):
# mage-надстройки («FLAT MALE CHEST», «EYES WIDE OPEN») убраны 21.10 —
# проверка «no breasts» неактуальна, лицо/телосложение приходят из
# воинского блока без изменений.
for race in ("human", "orc", "undead", "druid"):
    p = build_prompt(race, "m", mage=True)
    bad = re.findall(r"\bher\b|\bshe\b", p, re.I)
    check(f"mage m {race}: нет женских местоимений", not bad, str(bad[:5]))
    # муж. местоимения допустимы, но не должно быть "her/she"

for race in ("human", "orc", "undead", "druid"):
    p = build_prompt(race, "f", mage=True)
    male = re.findall(r"\b(?:he|his|him|himself)\b", p, re.I)
    check(f"mage f {race}: нет мужских местоимений", not male, str(male[:5]))

# Мантия до земли (ноги скрыты) — ключевое требование 21.10 для всех магов.
# Проверка по нормализованному тексту: перенос строки рвёт «ALL THE WAY DOWN».
for race in ("human", "orc", "undead", "druid"):
    for sex in ("m", "f"):
        p = build_prompt(race, sex, mage=True)
        check(f"mage {race}/{sex}: мантия до земли",
              "ALL THE WAY DOWN TO THE GROUND" in p)
        check(f"mage {race}/{sex}: ноги скрыты",
              "COMPLETELY HIDDEN" in p)

# Совпадение с воинским блоком: всё до блока одежды байт в байт.
def prefix_of(text):
    return " ".join(text.split("He wears")[0].split())
for race in ("human", "orc", "undead", "druid"):
    pw = build_prompt(race, "m", mage=False)
    pm = build_prompt(race, "m", mage=True)
    check(f"mage {race}/m: персонаж = воинский",
          prefix_of(pm) == prefix_of(pw))

# Воины не сломаны mage-правками: старые блоки на месте.
robe_colors = {"human": "deep blue", "orc": "deep red",
               "undead": "violet", "druid": "moss-green"}
for race, color in robe_colors.items():
    for sex in ("m", "f"):
        p = build_prompt(race, sex, mage=True)
        check(f"mage {race}/{sex}: цвет мантии '{color}'", color in p)

# Воины не сломаны mage-правками: старые блоки на месте.
p = build_prompt("human", "m", mage=False)
check("warrior human m: старый промт не пуст", len(p) > 500)
check("warrior human m: не мантия до земли",
      "ALL THE WAY DOWN" not in p)

print()
if FAILS:
    print(f"ПРОВАЛЕНО: {len(FAILS)}: {FAILS}")
    sys.exit(1)
print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
