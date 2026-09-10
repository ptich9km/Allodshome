#!/usr/bin/env python3
"""Analyze .alm (Allods map) binary file format"""

import struct
import sys

def analyze_alm(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    print(f"File size: {len(data)} bytes ({len(data)/1024:.1f} KB)")
    print()

    # Magic header
    magic = data[0:4]
    print(f"Magic: {magic} ('{magic.decode('ascii', errors='replace')}')")
    
    # Extract all readable ASCII strings (4+ chars)
    print("\n=== Readable strings ===")
    current = b""
    for i, byte in enumerate(data):
        if 32 <= byte < 127:
            current += bytes([byte])
        else:
            if len(current) >= 4:
                try:
                    s = current.decode('ascii')
                    print(f"  [{i-len(current):06x}] {s}")
                except:
                    pass
            current = b""
    
    # Parse header fields
    print("\n=== Header fields (little-endian uint32) ===")
    offsets = [0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20]
    labels = ["field_04", "field_08", "field_0C", "field_10", 
              "field_14", "field_18", "field_1C", "field_20"]
    for off, label in zip(offsets, labels):
        val = struct.unpack_from('<I', data, off)[0]
        print(f"  {label}: 0x{val:08X} ({val})")

    # Check for grid/tile data pattern
    # Look for repeated byte patterns
    print("\n=== Tile data analysis ===")
    # Check if there's a section with repeated single bytes (tile IDs)
    for start_off in range(0x100, min(0x2000, len(data)), 0x100):
        # Check if this looks like tile index data (lots of repeated bytes)
        chunk = data[start_off:start_off+256]
        unique = len(set(chunk))
        if unique < 20:  # Very repetitive = likely tile data
            most_common = max(set(chunk), key=chunk.count)
            print(f"  Offset 0x{start_off:04x}: {unique} unique bytes, most common=0x{most_common:02x}")

    # Look for potential texture/asset references
    print("\n=== Potential asset paths ===")
    import re
    # Look for patterns like *.tex, *.bmp, *.png, *.wav, *.tga
    for m in re.finditer(rb'[\x20-\x7e]*\.(tex|bmp|png|tga|wav|ogg|mp3|dat|pak)[\x00\x20-\x7e]*', data):
        print(f"  0x{m.start():06x}: {m.group().decode('ascii', errors='replace')}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python analyze_alm.py <file.alm>")
        sys.exit(1)
    analyze_alm(sys.argv[1])
