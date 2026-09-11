#!/usr/bin/env python3
"""
Find the REAL tile data offset by maximizing spatial coherence.
Real terrain: adjacent tiles often share the same value (large regions).
"""
import struct
import os

def coherence_score(data, offset, width, height, bytes_per_tile, byte_idx):
    """Count how often horizontally+vertically adjacent tiles have equal byte value."""
    matches = 0
    total = 0
    for y in range(height):
        for x in range(width):
            i = y*width + x
            off = offset + i*bytes_per_tile + byte_idx
            if off >= len(data):
                return -1
            v = data[off]
            # right neighbor
            if x+1 < width:
                off2 = offset + (i+1)*bytes_per_tile + byte_idx
                total += 1
                if data[off2] == v:
                    matches += 1
            # down neighbor
            if y+1 < height:
                off2 = offset + (i+width)*bytes_per_tile + byte_idx
                total += 1
                if data[off2] == v:
                    matches += 1
    return matches / total if total else 0

def main():
    scenario_dir = r"D:\Games\Rage of Mages II\extracted\scenario"
    fp = os.path.join(scenario_dir, "84.alm")
    with open(fp, 'rb') as f:
        data = f.read()

    width = struct.unpack_from('<I', data, 0x28)[0]
    height = struct.unpack_from('<I', data, 0x2c)[0]
    print(f"Map {width}x{height}, file {len(data)} bytes")

    # Try many offsets and byte positions, find best coherence
    best = []
    for offset in range(0x100, 0x1000, 4):
        for bpt in [1, 2, 4]:
            for bi in range(bpt):
                score = coherence_score(data, offset, width, height, bpt, bi)
                if score > 0.5:
                    best.append((score, offset, bpt, bi))

    best.sort(reverse=True)
    print(f"\nTop coherent interpretations (score = fraction of matching neighbors):")
    for score, offset, bpt, bi in best[:15]:
        print(f"  score={score:.3f}  offset=0x{offset:04x}  bytes_per_tile={bpt}  byte_idx={bi}")

    # For the best, show value distribution
    if best:
        score, offset, bpt, bi = best[0]
        print(f"\nBest: offset=0x{offset:04x} bpt={bpt} byte={bi}")
        vals = {}
        for i in range(width*height):
            v = data[offset + i*bpt + bi]
            vals[v] = vals.get(v,0)+1
        top = sorted(vals.items(), key=lambda x:-x[1])[:12]
        print(f"  Value distribution: {top}")

if __name__ == '__main__':
    main()
