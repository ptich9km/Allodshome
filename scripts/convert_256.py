#!/usr/bin/env python3
"""
Convert .256 sprite files from Allods 2 (Rage of Mages II) to PNG.

Allods 2 .256 format analysis:
- Some files start with palette (768 bytes = 256 colors * 3 RGB)
- Pixel data uses 8-bit palette indices
- Some files have 4-byte headers
- Shadow variants (.256b) may have transparent backgrounds
"""

import os
import struct
import sys
from PIL import Image

def extract_palette_from_file(data, offset=0):
    """Try to extract 256-color palette from file data."""
    if len(data) < offset + 768:
        return None, offset
    
    palette_bytes = data[offset:offset+768]
    
    # Check if this looks like a valid palette (values should be 0-255, not all same)
    unique_vals = len(set(palette_bytes))
    if unique_vals < 10:
        return None, offset
    
    palette = []
    for i in range(0, 768, 3):
        r, g, b = palette_bytes[i], palette_bytes[i+1], palette_bytes[i+2]
        palette.append((r, g, b))
    
    return palette, offset + 768

def analyze_256_file(filepath):
    """Analyze a .256 file structure and return info."""
    with open(filepath, 'rb') as f:
        data = f.read()
    
    info = {
        'file': filepath,
        'size': len(data),
        'first_32_bytes': data[:32].hex(),
        'has_palette': False,
        'palette': None,
        'pixel_data_offset': 0,
        'pixel_data_size': 0,
    }
    
    # Try to detect palette at start
    palette, pixel_offset = extract_palette_from_file(data, 0)
    
    if palette:
        info['has_palette'] = True
        info['palette'] = palette
        info['pixel_data_offset'] = pixel_offset
        info['pixel_data_size'] = len(data) - pixel_offset
    else:
        info['pixel_data_size'] = len(data)
    
    # Analyze pixel data patterns
    pixel_data = data[info['pixel_data_offset']:]
    
    # Check unique byte values in pixel data
    unique_bytes = set(pixel_data[:min(1000, len(pixel_data))])
    info['unique_byte_values'] = len(unique_bytes)
    info['sample_bytes'] = pixel_data[:64].hex()
    
    return info

def convert_256_with_palette(filepath, output_path, palette=None, width=None, height=None):
    """
    Convert .256 file to PNG using provided or embedded palette.
    
    Args:
        filepath: input .256 file
        output_path: output .png path
        palette: list of (R,G,B) tuples, or None to extract from file
        width: explicit width, or auto-detect
        height: explicit height, or auto-detect
    """
    with open(filepath, 'rb') as f:
        data = f.read()
    
    pixel_offset = 0
    
    # Extract palette if not provided
    if palette is None:
        palette, pixel_offset = extract_palette_from_file(data, 0)
        if palette is None:
            print(f"  WARNING: No palette found in {filepath}")
            return False
    
    # Get pixel data
    pixel_data = data[pixel_offset:]
    data_len = len(pixel_data)
    
    # Auto-detect dimensions if not provided
    if width is None or height is None:
        # Try common sprite sheet dimensions
        candidates = []
        
        # Common widths for Allods sprites
        for w in [32, 48, 64, 96, 128]:
            if data_len % w == 0:
                h = data_len // w
                if 0 < h <= 200:  # Reasonable height
                    candidates.append((w, h))
        
        if not candidates:
            # Try square-ish
            side = int(data_len ** 0.5)
            if side * side == data_len:
                candidates.append((side, side))
        
        if candidates:
            # Pick the one closest to square or common size
            width, height = candidates[0]
        else:
            print(f"  WARNING: Cannot determine dimensions for {data_len} bytes")
            return False
    
    # Check if we have enough data
    if len(pixel_data) < width * height:
        # Pad with zeros if needed
        pixel_data = pixel_data + b'\x00' * (width * height - len(pixel_data))
    
    # Create indexed image
    img = Image.new('P', (width, height))
    
    # Flatten palette for PIL
    flat_palette = []
    for r, g, b in palette:
        flat_palette.extend([r, g, b])
    # Pad to 768 bytes (256 colors * 3)
    while len(flat_palette) < 768:
        flat_palette.append(0)
    
    img.putpalette(flat_palette)
    
    # Set pixel data
    pixels = list(pixel_data[:width*height])
    img.putdata(pixels)
    
    # Save with transparency for index 0 (common in 8-bit games)
    # Check if index 0 is used as transparency
    img.save(output_path, transparency=0)
    
    return True

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python convert_256.py <file.256>          - analyze single file")
        print("  python convert_256.py <file.256> <out.png> - convert with auto-detect")
        print("  python convert_256.py test <directory>     - test convert a few files")
        sys.exit(1)
    
    if sys.argv[1] == 'test':
        # Test mode: analyze and convert a few sample files
        test_dir = sys.argv[2] if len(sys.argv) > 2 else '.'
        
        # Find some .256 files
        test_files = []
        for root, dirs, files in os.walk(test_dir):
            for f in files:
                if f.endswith('.256'):
                    test_files.append(os.path.join(root, f))
                    if len(test_files) >= 5:
                        break
            if len(test_files) >= 5:
                break
        
        print(f"Testing {len(test_files)} files...\n")
        
        for filepath in test_files:
            print(f"\n{'='*60}")
            print(f"File: {filepath}")
            
            info = analyze_256_file(filepath)
            print(f"  Size: {info['size']} bytes")
            print(f"  First 32 bytes: {info['first_32_bytes']}")
            print(f"  Has palette: {info['has_palette']}")
            print(f"  Pixel offset: {info['pixel_data_offset']}")
            print(f"  Pixel data size: {info['pixel_data_size']}")
            print(f"  Unique byte values (sample): {info['unique_byte_values']}")
            print(f"  Sample: {info['sample_bytes'][:32]}...")
            
            if info['has_palette'] and info['palette']:
                # Show first few palette colors
                print(f"  Palette sample:")
                for i in range(min(8, len(info['palette']))):
                    r, g, b = info['palette'][i]
                    print(f"    [{i}] RGB({r}, {g}, {b})")
            
            # Try to convert
            out_path = filepath.replace('.256', '_test.png')
            success = convert_256_with_palette(filepath, out_path)
            if success:
                print(f"  ✓ Converted to: {out_path}")
            else:
                print(f"  ✗ Conversion failed")
    
    else:
        # Single file mode
        filepath = sys.argv[1]
        output = sys.argv[2] if len(sys.argv) > 2 else filepath.replace('.256', '.png')
        
        print(f"Analyzing: {filepath}")
        info = analyze_256_file(filepath)
        
        print(f"Size: {info['size']} bytes")
        print(f"Has palette: {info['has_palette']}")
        print(f"Pixel offset: {info['pixel_data_offset']}")
        
        if info['has_palette'] and info['palette']:
            print(f"\nPalette colors (first 16):")
            for i in range(min(16, len(info['palette']))):
                r, g, b = info['palette'][i]
                print(f"  [{i:2d}] #{r:02X}{g:02X}{b:02X}  RGB({r:3d}, {g:3d}, {b:3d})")
        
        print(f"\nConverting to: {output}")
        success = convert_256_with_palette(filepath, output)
        
        if success:
            print(f"✓ Success!")
        else:
            print(f"✗ Failed")

if __name__ == '__main__':
    main()
