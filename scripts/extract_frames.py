#!/usr/bin/env python3
"""
Try to extract individual sprite frames from .256 file.
Assume the file contains multiple frames/sprites concatenated.
"""

from PIL import Image
import os

def try_extract_sprites(filepath, palette, test_widths=[32, 48, 64, 96, 128]):
    """Try to extract multiple sprites from .256 file."""
    
    with open(filepath, 'rb') as f:
        f.seek(768)  # Skip palette
        data = f.read()
    
    output_dir = filepath.replace('.256', '_frames')
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"\nTrying to extract frames from: {os.path.basename(filepath)}")
    print(f"Total pixel data: {len(data)} bytes")
    
    frame_num = 0
    offset = 0
    
    while offset < len(data):
        remaining = len(data) - offset
        
        # Try each test width
        best_frame = None
        
        for width in test_widths:
            # Reasonable heights for isometric sprites
            for height in [32, 48, 64, 96, 128, 160, 192, 256]:
                needed = width * height
                if offset + needed <= len(data):
                    # Extract this frame
                    frame_data = data[offset:offset+needed]
                    
                    # Check if frame has variety (not all same color)
                    unique = len(set(frame_data[:100]))
                    if unique > 5:  # Has some variety
                        # Create image
                        img = Image.new('P', (width, height))
                        flat_palette = []
                        for r, g, b in palette:
                            flat_palette.extend([r, g, b])
                        while len(flat_palette) < 768:
                            flat_palette.append(0)
                        img.putpalette(flat_palette)
                        img.putdata(list(frame_data))
                        
                        out_path = os.path.join(output_dir, f"frame_{frame_num:03d}_{width}x{height}.png")
                        img.save(out_path, transparency=0)
                        
                        if not best_frame:
                            best_frame = (width, height, out_path)
                            frame_num += 1
                            offset += needed
                            break
            
            if best_frame:
                break
        
        if not best_frame:
            # Couldn't find a good frame, skip rest
            break
    
    print(f"Extracted {frame_num} frames to: {output_dir}")
    return frame_num

def main():
    # Test files
    test_files = [
        r"D:\Work\UnityProjects\Allodshome_Godot\assets\units\monsters\orc\sprites.256",
        r"D:\Work\UnityProjects\Allodshome_Godot\assets\structures\bhut1\house.256",
        r"D:\Work\UnityProjects\Allodshome_Godot\assets\map-objects\bush1\sprites.256",
    ]
    
    for filepath in test_files:
        if not os.path.exists(filepath):
            continue
            
        print(f"\n{'='*60}")
        print(f"File: {filepath}")
        
        # Load palette
        with open(filepath, 'rb') as f:
            palette_data = f.read(768)
        
        palette = []
        for i in range(0, 768, 3):
            r, g, b = palette_data[i], palette_data[i+1], palette_data[i+2]
            palette.append((r, g, b))
        
        try_extract_sprites(filepath, palette)

if __name__ == '__main__':
    main()
