#!/usr/bin/env python3
"""
Deep analysis of Allods 2 .alm map format.
Goal: understand tile grid, height levels, water, barriers.
"""
import struct
import os

def analyze_alm(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    print(f"\n{'='*70}")
    print(f"File: {os.path.basename(filepath)} ({len(data)} bytes)")
    print(f"{'='*70}")

    # Magic + header
    magic = data[0:4]
    print(f"Magic: {magic} ({magic.decode('ascii', errors='replace')})")

    # Read header fields (little-endian uint32)
    print("\nHeader fields (uint32 LE):")
    for off in range(4, 64, 4):
        val = struct.unpack_from('<I', data, off)[0]
        fval = struct.unpack_from('<f', data, off)[0]
        print(f"  [{off:02x}] int={val:10d}  float={fval:.4f}")

    # Find map name string
    print("\nStrings in header area:")
    for i in range(0, min(512, len(data))):
        if data[i] == 0x4d and i+4 < len(data):  # 'M'
            s = data[i:i+32].split(b'\x00')[0]
            if len(s) > 3 and all(32 <= b < 127 for b in s):
                print(f"  [{i:04x}] '{s.decode('ascii')}'")

    # Look for the tile data section - search for patterns after header
    # The header seems to end around 0x100 based on earlier analysis
    # Let's examine the structure after the name/author strings

    # Find where readable strings end and binary data begins
    print("\nSearching for data sections...")

    # Look for repeated byte patterns that indicate tile grids
    # Check bytes 0x100-0x400 region
    print("\nByte analysis at key offsets:")
    for off in [0x100, 0x140, 0x180, 0x1C0, 0x200, 0x240, 0x280]:
        if off + 32 <= len(data):
            chunk = data[off:off+32]
            hexs = ' '.join(f'{b:02x}' for b in chunk[:16])
            # Count unique values
            uniq = len(set(chunk))
            print(f"  [{off:04x}] {hexs}  (uniq={uniq})")

    # Try to find map dimensions
    # Common approach: look for width/height as uint16 or uint32 pairs
    print("\nPotential dimension pairs (uint16 LE) in header:")
    for off in range(4, 128, 2):
        w = struct.unpack_from('<H', data, off)[0]
        h = struct.unpack_from('<H', data, off+2)[0]
        if 10 < w < 500 and 10 < h < 500 and abs(w-h) < 200:
            print(f"  [{off:02x}] {w} x {h}")

    return data

def main():
    # Analyze a few scenario maps of different sizes
    scenario_dir = r"D:\Games\Rage of Mages II\extracted\scenario"
    maps = sorted([f for f in os.listdir(scenario_dir) if f.endswith('.alm')])

    # Pick small, medium, large
    sizes = []
    for m in maps:
        sz = os.path.getsize(os.path.join(scenario_dir, m))
        sizes.append((sz, m))
    sizes.sort()

    print(f"Total maps: {len(maps)}")
    print(f"Smallest: {sizes[0]}")
    print(f"Largest: {sizes[-1]}")

    # Analyze smallest and a medium one
    for sz, name in [sizes[0], sizes[len(sizes)//2]]:
        analyze_alm(os.path.join(scenario_dir, name))

if __name__ == '__main__':
    main()
