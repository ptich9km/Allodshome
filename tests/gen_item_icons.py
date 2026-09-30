"""Привязывает каждому предмету item_db.json иконку из faction/ и faction_w/.

БЫЛО: все 1029 предметов ссылались на 508 уникальных иконок в
assets/inventory/ - это старые иконки Аллодов, а сами фракционные ассеты
(342 брони + 247 оружия = 589 файлов) в игру не попадали.

СТАЛО: металлический предмет берёт фракционную иконку по своему металлу,
остальное - заглушку по типу. Иконка слитка уже живёт в данных.

ПОЧЕМУ ИМЕННО ТАК. Материал - это ключ, по которому ищется файл:
  броня  faction/{group}/{metal}_{light|heavy}_{slot}_{tier}.png
  оружие faction_w/{group}/{metal}_{type}_{tier}.png
Регистр имени файла = регистр материала (нижний), и это совпадение
проверяется, а не предполагается.

СЛОТ -> АТЛАС. В атласе брони 9 колонок и 9 игровых слотов, но слоты в
item_db шире: Chain Helm/Full Helm/Plate Helm -> head (все три), Scale
Gauntlets/Chain Gauntlets/Bracers/Plate Bracers -> hands, Chain Mail/Scale
Mail/Cuirass/Plate Cuirass -> body, Chain Boots/Plate Boots -> feet. Несколько
типов делят одну картинку - это нормально, иначе на 9 картинках пришлось бы
рисовать 20 разных доспехов.

ЗАПАСНОЕ ПРАВИЛО. В атласе 13 типов оружия, в игре 21 (_WEAPON_TYPES) плюс
4 щита (_SHIELD_TYPES). Шесть игровых типов своего арта не имеют и получают
ближайший (решение игрока):
  Bastard Sword   -> greatsword
  Spiked Club     -> one_handed_mace
  Club            -> one_handed_mace
  Halberd         -> two_handed_spear
  Staff           -> one_handed_spear
  Shaman Staff    -> one_handed_spear
  Buckler         -> shield

ЗАГЛУШКИ. Предметы без готового арта (кожа, дерево, книги, зелья, свитки)
не могут получить фракционную иконку: металла у них нет, а фатальная ошибка
их убрать нельзя - кузнец их не берёт, но они остаются в игре. Поэтому
генерируются честные заглушки: рамка + подпись типа, отдельным каталогом,
чтобы потом заменить одной папкой.

Запуск:
    python tests/gen_item_icons.py --report
    python tests/gen_item_icons.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "assets", "items", "item_db.json")
PALETTE = os.path.join(ROOT, "assets", "items", "faction_palette.json")
PLACEHOLDER_DIR = os.path.join(ROOT, "assets", "items", "placeholder")

# Слот -> (set, слот в атласе). В атласе 9 колонок: head, chest, bracers,
# gloves, legs, ring, amulet, shirt, cloak.
ARMOR_SLOT = {
    # голова: три разных шлема делят одну картинку "head"
    "Helm":          ("heavy", "head"),
    "Full Helm":     ("heavy", "head"),
    "Plate Helm":    ("heavy", "head"),
    "Chain Helm":    ("heavy", "head"),
    "Cap":           ("light", "head"),
    "Hat":           ("light", "head"),
    "Low Hat":       ("light", "head"),
    # тело: кираса, латная кираса, кольчуга, чешуйчатый доспех, роба, платье
    "Cuirass":       ("heavy", "chest"),
    "Plate Cuirass": ("heavy", "chest"),
    "Chain Mail":    ("heavy", "chest"),
    "Scale Mail":    ("heavy", "chest"),
    "Robe":          ("light", "shirt"),
    "Dress":         ("light", "shirt"),
    # руки: наручи и все перчатки - одна колонка "bracers" и одна "gloves"
    "Bracers":       ("light", "bracers"),
    "Plate Bracers": ("heavy", "bracers"),
    "Gauntlets":     ("light", "gloves"),
    "Plate Gauntlets":   ("heavy", "bracers"),
    "Scale Gauntlets":   ("heavy", "gloves"),
    "Chain Gauntlets":   ("heavy", "gloves"),
    "Gloves":        ("light", "gloves"),
    # ноги
    "Boots":         ("light", "legs"),
    "Shoes":         ("light", "legs"),
    "Plate Boots":   ("heavy", "legs"),
    "Chain Boots":   ("heavy", "legs"),
    # аксессуары
    "Ring":          ("heavy", "ring"),
    "Amulet":        ("heavy", "amulet"),
    # Плащ и накидка - ТРЯПКИ (материал Linen), не металл. Арт лежит в base/:
    # faction/*_cloak_* - перекраска тех же текстур в цвета металлов, и для
    # льна она не используется. Разные наборы, иначе оба типа выглядели бы
    # одинаково на складе и на кукле.
    "Cloak":         ("light", "cloak"),
    "Cape":          ("heavy", "cloak"),
}

# Тряпки: арт лежит в base/, а не в faction/, потому что перекраска в цвет
# металла для них бессмысленна (см. gen_cloak_items.py).
CLOTH_MATERIALS = {"Linen", "Linen "}

# quality в базе -> тир в имени файла. У металлов качество = тир напрямую,
# но у тряпок качество ("Cheap"/"Common") приходит как слово, а файл называется
# по тиру ("cheap"/"common").
QUALITY_TO_TIER = {
    "Cheap": "cheap", "Common": "common", "Good": "good", "Elite": "elite",
}

# Тип оружия -> файл в faction_w. Ключи совпадают с именами в base_w/.
WEAPON_ICON = {
    "Dagger":             "dagger",
    "Short Sword":        "one_handed_sword",
    "Long Sword":         "one_handed_sword",
    "Bastard Sword":      "greatsword",            # запасное правило
    "Two Handed Sword":   "greatsword",
    "Axe":                "one_handed_axe",
    "Two Handed Axe":     "two_handed_axe",
    "Mace":               "one_handed_mace",
    "Morning Star":       "one_handed_mace",
    "Pick Hammer":        "two_handed_mace",
    "War Hammer":         "two_handed_mace",
    "Spiked Club":        "one_handed_mace",       # запасное правило
    "Club":               "one_handed_mace",       # запасное правило
    "Pike":               "one_handed_spear",
    "Lance":              "two_handed_spear",
    "Halberd":            "two_handed_spear",      # запасное правило
    "Staff":              "one_handed_spear",      # запасное правило
    "Shaman Staff":       "one_handed_spear",      # запасное правило
    "Short Bow":          "bow",
    "Long Bow":           "bow",
    "Crossbow":           "crossbow",
}

# Типы щитов: один атласный щит на все четыре игровых (запасное правило).
SHIELD_ICON = {
    "Buckler": "shield",
    "Small Shield": "shield",
    "Large Shield": "shield",
    "Tower Shield": "shield",
}

# Запасная иконка оружия для металлов, которых нет в атласе (saber не
# соответствует ни одному игровому типу, но файлы на диске есть).
SABER = "saber"

# Подпись на заглушке. Сначала смотрим ТИП предмета, и только если его нет -
# материал. Порядок важен: тип "Air" (книга сфер) не должен брать подпись
# материала, а тип "Herb" не должен превращаться в "Трава" по материалу None.
PH_TYPE_LABEL = {
    "Book": "Книга", "Potion": "Зелье", "Scroll": "Свиток",
    "SuperScroll": "Свиток", "Quest": "Квест", "Herb": "Трава",
    "Ingredient": "Ингр.", "Map": "Карта", "Treasure": "Клад",
    "Documents": "Док.", "Banner": "Флаг", "Stone": "Камень",
    "Shield": "Щит", "Crown1": "Корона", "Crown12": "Корона",
    "Crown13": "Корона", "Head": "Голова", "RuneA": "Руна", "RuneE": "Руна",
    "RuneF": "Руна", "RuneW": "Руна", "Meta1": "Мета", "Meta2": "Мета",
    "Meta3": "Мета", "Meta4": "Мета",
    # одежда без материала (47 предметов material=None, их удаляет игрок)
    "Dress": "Платье", "Robe": "Роба", "Cap": "Шапка", "Hat": "Шляпа",
    "Low Hat": "Шляпа", "Cloak": "Плащ", "Cape": "Накидка",
    "Gloves": "Перчатки", "Shoes": "Башмаки", "Amulet": "Амулет",
    "Ring": "Кольцо",
    # броня из неметаллов
    "Mail": "Кольчуга", "Helm": "Шлем", "Bracers": "Наручи",
    "Gauntlets": "Перчатки", "Boots": "Сапоги",
    "Small Shield": "Щит", "Large Shield": "Щит", "Tower Shield": "Щит",
}

# Неметаллы: подпись по материалу, когда тип не опознан.
PH_MAT_LABEL = {
    "Leather": "Кожа", "Hard Leather": "Кожа", "Dragon Leather": "Кожа",
    "Wood": "Дерево", "Magic Wood": "Дерево",
}

PH_SIZE = 64


def load_metal_index(pal: dict) -> dict:
    """metal -> (group, tier, is_base).

    is_base - сталь: она помечена в палитре как «не перекрашивать», её файлы
    лежат прямо в base/ и base_w/. Если не учесть это, на 108 предметов стали
    получится ссылка на faction/*/steel_*.png, которых там нет и быть не должно
    (перекраска is_base-тиров пропускается генераторами намеренно).
    """
    out = {}
    for g, gd in pal["groups"].items():
        for m in gd["metals"]:
            out[m["metal"]] = (g, m["tier"], bool(m.get("is_base")))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    with open(DB, encoding="utf-8") as fh:
        items = json.load(fh)
    with open(PALETTE, encoding="utf-8") as fh:
        pal = json.load(fh)
    metals = load_metal_index(pal)

    stats = {"faction": 0, "faction_w": 0, "base": 0, "ingot": 0, "placeholder": 0}
    problems = []
    assigned = {}
    new_ph = set()

    for it in items:
        mat = str(it.get("material", ""))
        typ = str(it.get("type", ""))
        icon = ""

        if typ == "Ingot":
            icon = "res://assets/professions/blacksmith/%s_ingot.png" % mat
            stats["ingot"] += 1

        elif mat in metals:
            group, tier, is_base = metals[mat]
            # У стали (is_base) в имени файла нет префикса металла: base/ и
            # base_w/ - это сам базовый набор, названный по тиру. У остальных
            # металлов префикс {metal}_ есть, иначе из 20 металлов в одной папке
            # получился бы один набор на всех.
            mpre = "" if is_base else mat + "_"
            froot = "base" if is_base else "faction/%s" % group
            wroot = "base_w" if is_base else "faction_w/%s" % group
            if typ in WEAPON_ICON:
                icon = "res://assets/items/%s/%s%s_%s.png" % (
                    wroot, mpre, WEAPON_ICON[typ], tier)
                stats["faction_w"] += 1
            elif typ in SHIELD_ICON:
                icon = "res://assets/items/%s/%s%s_%s.png" % (
                    wroot, mpre, SHIELD_ICON[typ], tier)
                stats["faction_w"] += 1
            elif typ in ARMOR_SLOT:
                a_set, a_slot = ARMOR_SLOT[typ]
                icon = "res://assets/items/%s/%s%s_%s_%s.png" % (
                    froot, mpre, a_set, a_slot, tier)
                stats["faction"] += 1
            else:
                problems.append("металл, но тип без иконки: %s / %s" % (typ, mat))
        elif typ in ARMOR_SLOT and mat in CLOTH_MATERIALS:
            # Тряпка (лён): арт есть в base/ - те же текстуры, из которых
            # faction/*_cloak_* делалась перекраска в металл. Лён не металл,
            # поэтому берём неокрашенный base, а не заглушку.
            a_set, a_slot = ARMOR_SLOT[typ]
            tier = QUALITY_TO_TIER.get(str(it.get("quality", "")), "common")
            icon = "res://assets/items/base/%s_%s_%s.png" % (a_set, a_slot, tier)
            stats["base"] += 1
        else:
            label = PH_TYPE_LABEL.get(typ) or PH_MAT_LABEL.get(mat) or "?"
            slug = slugify(typ or mat or "item")
            icon = "res://assets/items/placeholder/%s.png" % slug
            stats["placeholder"] += 1
            new_ph.add((slug, label))

        it["icon"] = icon
        assigned[icon] = assigned.get(icon, 0) + 1

    total = len(items)
    print("ПРЕДМЕТОВ: %d" % total)
    for k, v in stats.items():
        print("  %-12s %5d" % (k, v))
    print("УНИКАЛЬНЫХ ИКОНОК: %d" % len(assigned))

    # Заглушки рисуются ДО проверки существования: иначе скрипт всегда
    # сообщал бы о 91 отсутствующем файле - о собственных заглушках.
    os.makedirs(PLACEHOLDER_DIR, exist_ok=True)
    for slug, label in sorted(new_ph):
        make_placeholder(os.path.join(PLACEHOLDER_DIR, "%s.png" % slug), label)
    print("ЗАГЛУШЕК: %d файлов в %s"
          % (len(new_ph), PLACEHOLDER_DIR.replace("\\", "/")))

    # инвариант: каждый путь обязан существовать на диске
    missing = []
    for icon in sorted(assigned):
        rel = icon.replace("res://", "").replace("/", os.sep)
        if not os.path.exists(os.path.join(ROOT, rel)):
            missing.append(icon)
    print("НЕТ ФАЙЛА НА ДИСКЕ: %d" % len(missing))
    for m in missing[:10]:
        print("   ! %s" % m)
    if missing:
        problems.append("иконок нет на диске: %d" % len(missing))

    if problems:
        print("ПРОБЛЕМЫ: %d" % len(problems))
        for p in problems[:10]:
            print("   ! %s" % p)
    else:
        print("ПРОВЕРКА: все %d иконок есть на диске" % len(assigned))

    if args.report:
        print("REPORT: item_db.json не записан")
        return 1 if problems else 0

    if problems:
        return 1

    with open(DB, "w", encoding="utf-8") as fh:
        json.dump(items, fh, ensure_ascii=False, indent=1)
    print("ГОТОВО: %s" % DB)
    return 0


def slugify(s: str) -> str:
    out = "".join(ch if ch.isalnum() else "_" for ch in s).strip("_").lower()
    return out or "item"


def make_placeholder(path: str, label: str) -> None:
    """Заглушка: рамка + подпись типа. Сознательно НЕ имитация вещи.

    Лучше честная пустая рамка с подписью, чем фальшивая картинка: игрок увидит
    в инвентаре «Зелье» и поймёт, что это не готовая иконка, а не решит, что
    это какая-то необычная вещь.
    """
    img = Image.new("RGBA", (PH_SIZE, PH_SIZE), (38, 40, 48, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, PH_SIZE - 1, PH_SIZE - 1], outline=(94, 98, 112, 255), width=2)
    d.rectangle([4, 4, PH_SIZE - 5, PH_SIZE - 5], outline=(58, 62, 74, 255), width=1)
    if label:
        bb = d.textbbox((0, 0), label)
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        d.text(((PH_SIZE - w) / 2 - bb[0], (PH_SIZE - h) / 2 - bb[1]),
               label, fill=(150, 156, 170, 255))
    img.save(path)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
