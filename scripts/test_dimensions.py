#!/usr/bin/env python3
"""
Test different dimensions for a single .256 file to find correct sprite layout.
"""

import os
from PIL import Image

def load_palette_from_256(filepath):
    """Extract 256-color palette from .256 file (first 768 bytes)."""
    with open(filepath, 'rb') as f:
        data = f.read(768)
    
    palette = []
    for i in range(0, 768, 3):
        r, g, b = data[i], data[i+1], data[i+2]
        palette.append((r, g, b))
    
    return palette

def convert_with_size(filepath, palette, width, height, output_path):
    """Convert .256 to PNG with explicit dimensions."""
    with open(filepath, 'rb') as f:
        f.seek(768)  # Skip palette
        pixel_data = f.read()
    
    needed = width * height
    if len(pixel_data) < needed:
        return False, f"Not enough data ({len(pixel_data)} < {needed})"
    
    # Create image
    img = Image.new('P', (width, height))
    
    # Set palette
    flat_palette = []
    for r, g, b in palette:
        flat_palette.extend([r, g, b])
    while len(flat_palette) < 768:
        flat_palette.append(0)
    
    img.putpalette(flat_palette)
    img.putdata(list(pixel_data[:needed]))
    img.save(output_path, transparency=0)
    
    return True, f"OK ({width}x{height})"

def main():
    # Test file
    filepath = r"D:\Work\UnityProjects\Allodshome_Godot\assets\units\monsters\orc\sprites.256"
    palette = load_palette_from_256(filepath)
    
    # Get pixel data size
    file_size = os.path.getsize(filepath)
    pixel_size = file_size - 768
    
    print(f"File: {filepath}")
    print(f"Total size: {file_size} bytes")
    print(f"Pixel data: {pixel_size} bytes")
    print(f"\nTrying different dimensions:\n")
    
    # Try various width/height combinations
    test_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\_test_converts"
    os.makedirs(test_dir, exist_ok=True)
    
    results = []
    
    # Common sprite widths for isometric games
    for width in [32, 48, 64, 96, 128, 160, 192, 256]:
        if pixel_size % width == 0:
            height = pixel_size // width
            output = os.path.join(test_dir, f"orc_{width}x{height}.png")
            success, msg = convert_with_size(filepath, palette, width, height, output)
            results.append((width, height, success, msg))
            print(f"  {width:3d} x {height:4d} = {pixel_size:6d} bytes -> {msg}")
    
    print(f"\n✓ Generated {len(results)} test images in: {test_dir}")
    print("\nOpen these PNGs and tell me which one looks correct!")

if __name__ == '__main__':
    main()
