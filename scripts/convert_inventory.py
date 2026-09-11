#!/usr/bin/env python3
"""Convert all inventory .16a files to PNG using 16a_png.exe."""
import os
import subprocess

SRC = r"D:\Games\Rage of Mages II\extracted\graphics\inventory"
CONVERTER = r"D:\Games\Rage of Mages II\16a_png.exe"

files = [f for f in os.listdir(SRC) if f.endswith('.16a')]
print(f"Converting {len(files)} files...")

ok = 0
for i, f in enumerate(files):
    result = subprocess.run([CONVERTER, f], cwd=SRC, capture_output=True, text=True, timeout=30)
    if result.returncode == 0:
        ok += 1
    if (i+1) % 50 == 0:
        print(f"  {i+1}/{len(files)}...")

print(f"Done: {ok}/{len(files)} converted")

# Count PNGs
pngs = [f for f in os.listdir(SRC) if f.endswith('.png')]
print(f"PNG files in dir: {len(pngs)}")
