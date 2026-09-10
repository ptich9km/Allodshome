#!/usr/bin/env python3
"""Convert spell icons from RGBA to RGB with black background."""
from PIL import Image
import os

spell_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\spells"

for filename in os.listdir(spell_dir):
    if filename.startswith('spell_') and filename.endswith('.png'):
        filepath = os.path.join(spell_dir, filename)
        img = Image.open(filepath)
        
        if img.mode == 'RGBA':
            # Create black background and paste image on top
            bg = Image.new('RGB', img.size, (0, 0, 0))
            bg.paste(img, mask=img.split()[3])  # Use alpha as mask
            bg.save(filepath)
            print(f"Converted {filename}: RGBA -> RGB (black bg)")

print("Done!")
