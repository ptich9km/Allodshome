#!/usr/bin/env python3
"""
Parse .alm tile data: find section start, decode 4 bytes per tile.
Extract terrain type, height, water, barrier flags.
"""
import struct
import os

def find_data_start(data, width, height):
    """Find where the tile grid data begins (first large non-zero block)."""
    expected_tiles = width * height
    # Scan for a region of ~expected_tiles*4 bytes with varied data
    for start in range(0x100, min(0x2000, len(data)), 4):
        block = data[start:start + expected_tiles * 4]
        if len(block) < expected_tiles * 4:
            continue
        # A tile grid should have variety but also structure
        uniq = len(set(block[:400]))
        nonzero = sum(1 for b in block[:400] if b != 0)
        if uniq > 20 and nonzero > 100:
            return start
    return -1

def analyze_tile_bytes(data, start, width, height):
    """Decode the 4-byte-per-tile structure."""
    print(f"\nTile data starts at 0x{start:04x}")
    print(f"Map: {width}x{height} = {width*height} tiles")

    # Show first 20 tiles raw
    print("\nFirst 20 tiles (4 bytes each):")
    for i in range(min(20, width*height)):
        off = start + i*4
        b = data[off:off+4]
        if len(b) == 4:
            # Interpret as different ways
            as_u32 = struct.unpack('<I', b)[0]
            as_4u8 = tuple(b)
            print(f"  tile[{i:3d}] bytes={as_4u8}  u32={as_u32}")

    # Analyze byte-by-byte meaning across all tiles
    print("\nByte position analysis (which byte carries which info):")
    for bytepos in range(4):
        values = {}
        for i in range(width*height):
            off = start + i*4 + bytepos
            if off < len(data):
                v = data[off]
                values[v] = values.get(v, 0) + 1
        top = sorted(values.items(), key=lambda x: -x[1])[:8]
        print(f"  byte[{bytepos}]: {len(values)} unique, top: {top}")

def main():
    scenario_dir = r"D:\Games\Rage of Mages II\extracted\scenario"

    # Use 84.alm (80x80, smallest)
    filepath = os.path.join(scenario_dir, "84.alm")
    with open(filepath, 'rb') as f:
        data = f.read()

    width = struct.unpack_from('<I', data, 0x28)[0]
    height = struct.unpack_from('<I', data, 0x2c)[0]
    print(f"Map dimensions: {width}x{height}")

    start = find_data_start(data, width, height)
    if start < 0:
        print("Could not find tile data start!")
        return

    analyze_tile_bytes(data, start, width, height)

if __name__ == '__main__':
    main()
