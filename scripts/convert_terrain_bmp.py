#!/usr/bin/env python3
"""Convert terrain BMP from palette mode to RGB - save as new files."""

import os
import shutil
from PIL import Image

terrain_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\terrain"
count = 0

for filename in os.listdir(terrain_dir):
    if filename.endswith('.bmp'):
        filepath = os.path.join(terrain_dir, filename)
        img = Image.open(filepath)
        
        if img.mode == 'P':
            # Convert palette to RGB and save as new file
            img_rgb = img.convert('RGB')
            new_path = filepath.replace('.bmp', '_rgb.bmp')
            img_rgb.save(new_path)
            print(f"Converted {filename} -> {filename.replace('.bmp', '_rgb.bmp')}: {img.size}")
            count += 1

print(f"\nConverted {count} BMP files to RGB")
print("Now deleting original palette BMPs...")

# Delete originals
for filename in os.listdir(terrain_dir):
    if filename.endswith('.bmp') and not filename.endswith('_rgb.bmp'):
        os.remove(os.path.join(terrain_dir, filename))
        print(f"  Deleted {filename}")

# Rename _rgb.bmp to .bmp
for filename in os.listdir(terrain_dir):
    if filename.endswith('_rgb.bmp'):
        old_path = os.path.join(terrain_dir, filename)
        new_path = old_path.replace('_rgb.bmp', '.bmp')
        os.rename(old_path, new_path)
        print(f"  Renamed {filename} -> {filename.replace('_rgb.bmp', '.bmp')}")

print("\nDone!")
