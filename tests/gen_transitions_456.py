#!/usr/bin/env python3
"""Генерация переходов для типов 4/5/6 (почва/песок/грязь).
Типы 4/5/6 используют tile1 (как трава), поэтому копируем правила типа 0.
Результат записывается в transition_db.json (секция rules)."""

import json
import sys

DB_PATH = "assets/maps/transition_db.json"

# Типы, для которых генерируем правила
NEW_TYPES = [4, 5, 6]

# Направления (8 кардинальных)
DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# Существующие соседи типа 0 (трава)
EXISTING_NEIGHBORS = [0, 1, 2, 3]

def main():
    with open(DB_PATH, "r", encoding="utf-8") as f:
        db = json.load(f)
    
    rules = db.get("rules", {})
    interior = db.get("interior", {})
    
    added = 0
    
    for new_type in NEW_TYPES:
        # 1. Добавить directional rules: новый_тип -> любой_существующий_тип
        for neighbor in EXISTING_NEIGHBORS:
            if neighbor == new_type:
                continue
            for d in DIRS:
                key = f"{new_type}:{d}:{neighbor}"
                if key not in rules:
                    # Копируем из правила типа 0 -> neighbor
                    src_key = f"0:{d}:{neighbor}"
                    if src_key in rules:
                        rules[key] = rules[src_key].copy()
                        added += 1
        
        # 2. Добавить directional rules: существующий_тип -> новый_тип
        for neighbor in EXISTING_NEIGHBORS:
            if neighbor == new_type:
                continue
            for d in DIRS:
                key = f"{neighbor}:{d}:{new_type}"
                if key not in rules:
                    # Копируем из правила neighbor -> типа 0
                    src_key = f"{neighbor}:{d}:0"
                    if src_key in rules:
                        rules[key] = rules[src_key].copy()
                        added += 1
        
        # 3. Добавить interior rules (если нет)
        for iv in range(1, 7):
            key = f"{new_type}:A{iv}:{new_type}"
            if key not in rules:
                # Копируем из interior типа 0
                src_key = f"0:A{iv}:0"
                if src_key in rules:
                    rules[key] = rules[src_key].copy()
                    added += 1
        
        # 4. Добавить interior в словарь interior
        if str(new_type) not in interior:
            src = interior.get("0", {})
            if src:
                interior[str(new_type)] = src.copy()
                added += 1
    
    # 5. Добавить правила между новыми типами (4↔5, 4↔6, 5↔6)
    for t1 in NEW_TYPES:
        for t2 in NEW_TYPES:
            if t1 >= t2:
                continue
            for d in DIRS:
                # t1 -> t2
                key1 = f"{t1}:{d}:{t2}"
                if key1 not in rules:
                    src = f"0:{d}:0"
                    if src in rules:
                        rules[key1] = rules[src].copy()
                        added += 1
                # t2 -> t1
                key2 = f"{t2}:{d}:{t1}"
                if key2 not in rules:
                    src = f"0:{d}:0"
                    if src in rules:
                        rules[key2] = rules[src].copy()
                        added += 1
    
    # 6. Добавить правила 0↔4/5/6 (трава ↔ почва/песок/грязь)
    # Используем правила 0->1 (трава→горы) как шаблон для 0->4/5/6
    # Для new_type -> 0: берём из 0->1 и инвертируем (source file=1 будет пересчитан)
    for new_type in NEW_TYPES:
        for d in DIRS:
            # 0 -> new_type: берём из 0->1
            key1 = f"0:{d}:{new_type}"
            src = f"0:{d}:1"
            if src in rules:
                rules[key1] = rules[src].copy()
                added += 1
            # new_type -> 0: берём из 0->1 (инвертируем направление)
            key2 = f"{new_type}:{d}:0"
            src = f"0:{d}:1"
            if src in rules:
                rules[key2] = rules[src].copy()
                added += 1
    
    db["rules"] = rules
    db["interior"] = interior
    
    with open(DB_PATH, "w", encoding="utf-8") as f:
        json.dump(db, f, indent=2, ensure_ascii=False)
    
    print(f"Добавлено {added} правил для типов 4/5/6")
    print(f"Всего правил: {len(rules)}")
    print(f"Interior типов: {sorted(interior.keys())}")

if __name__ == "__main__":
    main()
