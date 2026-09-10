#!/usr/bin/env python3
"""
Slice tall terrain BMP strips into individual 64x32 tiles for Godot TileMap.
Each 32x448 BMP contains 14 tiles stacked vertically (448/32 = 14).
"""

import os
from PIL import Image

TILE_W = 64  # Godot tile width
TILE_H = 32  # Godot tile height
terrain_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\terrain"
output_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\terrain\tiles"

os.makedirs(output_dir, exist_ok=True)

count = 0

for filename in sorted(os.listdir(terrain_dir)):
    if not filename.endswith('.bmp') or '_rgb' in filename:
        continue
    
    filepath = os.path.join(terrain_dir, filename)
    img = Image.open(filepath)
    w, h = img.size
    
    # Each strip is 32px wide, we need 64px tiles
    # So combine 2 adjacent strips or stretch
    # Actually these are isometric tiles - each 32px slice is half a tile
    # We'll just resize to 64x32 for now
    
    num_tiles = h // TILE_H
    
    for i in range(num_tiles):
        y_start = i * TILE_H
        tile = img.crop((0, y_start, w, y_start + TILE_H))
        # Resize to 64x32
        tile = tile.resize((TILE_W, TILE_H), Image.LANCZOS)
        
        # Save as tile
        tile_name = filename.replace('.bmp', f'_{i:02d}.png')
        tile.save(os.path.join(output_dir, tile_name))
        count += 1

print(f"Sliced {count} tiles into: {output_dir}")
