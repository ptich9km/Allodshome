"""Проставляет сопротивления стихиям в assets/units/units_db.json.

Сопротивление — ПРОЦЕНТ магического урона, который не проходит (0..95).
Так в оригинале (main.txt: «Resistance… shows the percentage of the magical
effects of this particular sphere which will not affect the character»).
Раньше в enemy.gd было max_hp/60 — плоское вычитание, которое ломалось:
у босса с большим HP сопротивление росло до неуязвимости к одной стихии.

Таблица семейств задана здесь явно, чтобы её можно было читать и править.
Запуск: python tests/gen_unit_resists.py
"""
import json
import os
import re

DB = os.path.join(os.path.dirname(__file__), "..", "assets", "units", "units_db.json")

SPHERES = ["fire", "water", "air", "earth", "astral"]


def family_resists(name: str):
    n = name.lower()
    if re.search(r"skeleton|zombie|ghost|necro", n):
        # Нежить: гниёт и мёртвая — холод держит, огонь жечь может быстро
        return {"fire": 5, "water": 45, "air": 40, "earth": 35, "astral": 40}
    if "dragon" in n:
        return {"fire": 55, "water": 25, "air": 25, "earth": 20, "astral": 10}
    if "succubus" in n:
        return {"fire": 40, "water": 20, "air": 30, "earth": 10, "astral": 20}
    if re.search(r"orc|goblin|troll|ogre", n):
        return {"fire": 25, "water": 8, "air": 12, "earth": 20, "astral": 8}
    if re.search(r"turtle|bee|spider|bat|squirrel|wolf|dino|legg|sheep", n):
        return {"fire": 12, "water": 12, "air": 18, "earth": 20, "astral": 12}
    if "druid" in n:
        return {"fire": 12, "water": 25, "air": 20, "earth": 35, "astral": 20}
    # Люди и герои: небольшой ровный резист
    return {"fire": 10, "water": 10, "air": 10, "earth": 10, "astral": 10}


def main():
    with open(DB, "r", encoding="utf-8") as f:
        data = json.load(f)

    changed = 0
    for name, entry in data.items():
        want = family_resists(name)
        if entry.get("resist") != want:
            entry["resist"] = want
            changed += 1

    # Отступ 1 пробел — как в исходном файле, иначе диff на весь файл
    with open(DB, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("unit resists: sets=%d updated=%d" % (len(data), changed))


if __name__ == "__main__":
    main()
