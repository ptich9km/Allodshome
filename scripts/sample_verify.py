#!/usr/bin/env python3
"""Sample 10 icons by ID prefix with user catalog info for visual verification."""
import json

cat_path = r"D:\Work\UnityProjects\Allodshome_Godot\assets\maps\inventory_catalog.json"
with open(cat_path, encoding="utf-8") as f:
    cat = json.load(f)

samples = ["0101002", "0102001", "0105002", "0201102", "0501202", "0606208",
           "0712330", "1012028", "1506003", "0014001", "0001002", "1412330"]

print("Иконка      | По ID-префиксу ожидаю        | Твой каталог")
print("-" * 70)
for sid in samples:
    fname = sid + "-000.png"
    info = cat.get(fname, {})
    pref = sid[:2]
    expect = {
        "01": "бронза", "02": "сталь", "03": "сталь-кольца", "04": "золото",
        "05": "мифрил", "06": "адамант", "07": "метеорит", "08": "дерево/маг",
        "09": "маг.оружие", "10": "кожа", "11": "толстая кожа", "12": "драконья кожа",
        "14": "кристалл", "15": "маг.ткань", "00": "железо/свитки/квест",
    }.get(pref, "?")
    print(f"{fname:14s} | {expect:22s} | {info}")