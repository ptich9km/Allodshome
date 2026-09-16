#!/usr/bin/env python3
"""Сравнить твой РУЧНОЙ каталог (истина) с ПОЗИЦИОННЫМ маппингом агента:
для каждой иконки агент говорит itemserv[i] = Quality Material Type,
а твой каталог даёт {cat, quality}. Считаем несовпадения по качеству."""
import json, os

icon_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\inventory"
icons = sorted(f.replace("-000.png", "") for f in os.listdir(icon_dir) if f.endswith("-000.png"))

with open(r"D:\Games\Rage of Mages II\extracted\main\text\itemserv.txt", encoding="cp1251", errors="replace") as f:
    itemserv = [l.strip() for l in f if l.strip()]

with open(r"D:\Work\UnityProjects\Allodshome_Godot\assets\maps\inventory_catalog.json", encoding="utf-8") as f:
    cat = json.load(f)

# Карта качества из itemserv -> числовой ранг (по тиру материалов, как пользователь)
quality_rank = {
    "Bad": 1, "Common": 1, "Elven": 2, "Good": 3, "Uncommon": 5, "Rare": 5, "Very Rare": 5,
}

print(f"Иконок: {len(icons)}, itemserv: {len(itemserv)}, в каталоге: {len(cat)}\n")
print("Сравниваем ПЕРВЫЕ 15 иконок (по позиции i):")

mismatch = 0
checked = 0
for i in range(len(icons)):
    icon = icons[i] + "-000.png"
    if icon not in cat:
        continue
    checked += 1
    key = itemserv[i] if i < len(itemserv) else "?"
    parts = key.split()
    q = parts[0] if parts else "?"
    user_q = cat[icon].get("quality", 0)
    rq = quality_rank.get(q, q)
    ok = (str(rq) == str(int(user_q)) or q in ("Book", "Potion", "Quest", "Scroll", "SuperScroll"))
    if not ok:
        mismatch += 1
    if i < 15:
        print(f"  {icon}: агент={q:<12s}({key}) твой_q={user_q} {'✅' if ok else '❌'}")

print(f"\nПроверено иконок с каталожной инфой: {checked}, НЕСОВПАДЕНИЙ по качеству: {mismatch}")
print("\nВывод: если несовпадений > 0 — позиционный маппинг агента НЕВЕРЕН для иконок.")