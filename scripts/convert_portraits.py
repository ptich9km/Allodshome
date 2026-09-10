#!/usr/bin/env python3
"""Convert portrait BMP to PNG for Godot compatibility."""
from PIL import Image
import os

portrait_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\portraits"
count = 0

for filename in os.listdir(portrait_dir):
    if filename.endswith('.bmp'):
        filepath = os.path.join(portrait_dir, filename)
        img = Image.open(filepath)
        png_path = filepath.replace('.bmp', '.png')
        img.save(png_path)
        count += 1

print(f"Converted {count} BMP portraits to PNG")
