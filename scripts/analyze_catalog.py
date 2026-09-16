#!/usr/bin/env python3
"""Analyze user's manual inventory catalog: what category does each icon ID prefix map to?"""
import json, os
from collections import Counter

cat_path = r"D:\Work\UnityProjects\Allodshome_Godot\assets\maps\inventory_catalog.json"
with open(cat_path, encoding="utf-8") as f:
    cat = json.load(f)

# Группировка по первым 2 цифрам id
by_prefix = {}
for fname, info in cat.items():
    pref = fname[:2]
    by_prefix.setdefault(pref, []).append(info)

print(f"Всего в каталоге: {len(cat)} предметов\n")
print(f"{'Преф':4s} {'Кол-во':5s}  Категории (топ)")
for pref in sorted(by_prefix):
    infos = by_prefix[pref]
    cats = Counter(i.get("cat", "?") for i in infos)
    qs = Counter(i.get("quality", 0) for i in infos)
    top_cats = ", ".join(f"{c}×{n}" for c, n in cats.most_common(3))
    top_q = ", ".join(f"q{q}×{n}" for q, n in qs.most_common(3))
    print(f"{pref:4s} {len(infos):5d}  {top_cats}   | качество: {top_q}")

# Пример: какие битые вещи в категории
print("\n=== Примеры по префиксам 00, 01, 05, 06, 15 ===")
for pref in ["00", "01", "05", "06", "15"]:
    if pref not in by_prefix:
        continue
    print(f"\n-- префикс {pref} --")
    for fname in sorted(by_prefix[pref])[:6]:
        print(f"   {fname}: {by_prefix[pref][fname]}")