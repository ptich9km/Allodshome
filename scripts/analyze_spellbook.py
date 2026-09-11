#!/usr/bin/env python3
"""Find exact icon cell boundaries in spellbook.bmp by dark separators."""
from PIL import Image

img = Image.open(r"D:\Work\UnityProjects\Allodshome_Godot\assets\interface\spellbook.bmp")
gray = img.convert('L')
w, h = gray.size
px = gray.load()

def col_mean(x):
    return sum(px[x, y] for y in range(h)) / h

# Find dark columns (separators)
dark_cols = []
run = None
for x in range(w):
    m = col_mean(x)
    if m < 32:
        if run is None:
            run = [x, x]
        else:
            run[1] = x
    else:
        if run:
            dark_cols.append(tuple(run))
            run = None
if run:
    dark_cols.append(tuple(run))

print("Dark column runs (separators):")
for a, b in dark_cols:
    print(f"  x={a}..{b} (width {b-a+1})")

# Derive cell boundaries
bounds = [0]
for a, b in dark_cols:
    mid = (a + b) // 2
    bounds.append(mid)
bounds.append(w)

print(f"\nDerived cells ({len(bounds)-1}):")
for i in range(len(bounds)-1):
    print(f"  cell {i}: x={bounds[i]}..{bounds[i+1]} (width {bounds[i+1]-bounds[i]})")

# Row analysis: dark rows
def row_mean(y):
    return sum(px[x, y] for x in range(w)) / w

dark_rows = []
run = None
for y in range(h):
    m = row_mean(y)
    if m < 32:
        if run is None:
            run = [y, y]
        else:
            run[1] = y
    else:
        if run:
            dark_rows.append(tuple(run))
            run = None
if run:
    dark_rows.append(tuple(run))

print("\nDark row runs:")
for a, b in dark_rows:
    print(f"  y={a}..{b}")
