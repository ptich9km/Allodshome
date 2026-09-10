#!/usr/bin/env python3
"""
Convert .256 files treating them as RGB0 packed data (every 4th byte is 0x00 separator).
"""

from PIL import Image
import os
import math

def convert_rgb0_to_png(filepath, output_path=None):
    """
    Convert .256 file where data is packed as R,G,B,0,R,G,B,0...
    """
    if output_path is None:
        output_path = filepath.replace('.256', '.png')
    
    with open(filepath, 'rb') as f:
        data = f.read()
    
    # Check if first 768 bytes could be a palette
    # Actually let's test both: with and without palette skip
    
    # Try WITHOUT skipping palette first
    pixel_data_start = 768  # Skip potential palette
    actual_data = data[pixel_data_start:]
    
    # Extract RGB bytes (skip every 4th byte which is 0x00)
    rgb_bytes = bytearray()
    for i in range(0, len(actual_data), 4):
        if i+3 < len(actual_data) and actual_data[i+3] == 0:
            rgb_bytes.extend(actual_data[i:i+3])
        else:
            # Not following R,G,B,0 pattern
            break
    
    if len(rgb_bytes) == 0:
        print(f"  Not R,G,B,0 format, trying alternative...")
        return False
    
    print(f"  Extracted {len(rgb_bytes)} RGB bytes from {len(actual_data)} bytes of data")
    
    # Try to determine dimensions
    num_pixels = len(rgb_bytes) // 3
    
    # Find reasonable width/height
    best_dims = None
    for width in [32, 48, 64, 96, 128, 160, 192, 256]:
        if num_pixels % width == 0:
            height = num_pixels // width
            if 10 < height < 500:
                best_dims = (width, height)
                break
    
    if not best_dims:
        # Try square-ish
        side = int(math.sqrt(num_pixels))
        if side * side == num_pixels:
            best_dims = (side, side)
        else:
            print(f"  Cannot determine dimensions for {num_pixels} pixels")
            return False
    
    width, height = best_dims
    print(f"  Dimensions: {width}x{height}")
    
    # Create RGB image
    img = Image.frombytes('RGB', (width, height), bytes(rgb_bytes))
    img.save(output_path)
    
    print(f"  Saved: {output_path}")
    return True

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
        print(f"File: {os.path.basename(filepath)}")
        
        success = convert_rgb0_to_png(filepath)
        
        if success:
            print(f"  ✓ Converted successfully!")
        else:
            print(f"  ✗ Failed")

if __name__ == '__main__':
    main()
