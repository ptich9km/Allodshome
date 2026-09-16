#!/usr/bin/env python3
"""Correlate inventory icon files with itemserv.txt lines (first hypothesis) and
show a sample for user verification against their manual catalog."""
import os, json

icon_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\inventory"
icons = sorted(f for f in os.listdir(icon_dir) if f.endswith(".png"))

with open(r"D:\Games\Rage of Mages II\extracted\main\text\itemserv.txt", encoding="cp1251", errors="replace") as f:
    lines = [l.strip() for l in f if l.strip()]

cat_path = r"D:\Work\UnityProjects\Allodshome_Godot\assets\maps\inventory_catalog.json"
user_cat = {}
if os.path.exists(cat_path):
    with open(cat_path, encoding="utf-8") as f:
        user_cat = json.load(f)

print(f"Иконок: {len(icons)}, строк itemserv: {len(lines)}")

# Гипотеза A: сортированный порядок иконок == порядок строк itemserv
print("\n=== Гипотеза A: порядковое соответствие (иконка i -> itemserv[i]) ===")
for i in range(10):
    icon = icons[i]
    item = lines[i] if i < len(lines) else "?"
    q, m, t = "?", "?", "?"
    parts = item.split()
    if len(parts) >= 3:
        q, m = parts[0], parts[1]
        t = " ".join(parts[2:])
    uc = user_cat.get(icon, {})
    print(f"{icon:16s} -> [{q}][{m}][{t}]   (твой каталог: {uc})")

# Гипотеза B: id иконки как число — посмотреть диапазоны первых цифр
print("\n=== Распределение по первым 2 цифрам id иконки ===")
from collections import Counter
pref = Counter(icon[:2] for icon in icons)
print(sorted(pref.items(), key=lambda x: x[0])[:30])