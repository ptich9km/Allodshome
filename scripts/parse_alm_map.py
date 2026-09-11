#!/usr/bin/env python3
"""
Allods 2 .alm map parser + visualizer.
Renders: terrain type map, height map, water/barrier masks.
Tile = 4 bytes: [terrain_lo, height_flags, terrain_hi, height_flags2]
"""
import struct
import os
from PIL import Image

def parse_alm(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    width = struct.unpack_from('<I', data, 0x28)[0]
    height = struct.unpack_from('<I', data, 0x2c)[0]

    # Find tile data start (first large varied block)
    expected = width * height
    start = -1
    for s in range(0x100, min(0x3000, len(data)), 4):
        block = data[s:s + expected*4]
        if len(block) < expected*4:
            continue
        uniq = len(set(block[:400]))
        nz = sum(1 for b in block[:400] if b != 0)
        if uniq > 20 and nz > 100:
            start = s
            break

    if start < 0:
        return None

    tiles = []
    for i in range(expected):
        off = start + i*4
        b = data[off:off+4]
        if len(b) < 4:
            b = b + b'\x00'*(4-len(b))
        terrain = b[0]          # terrain texture index
        hf = b[1]               # height + flags byte
        tiles.append((terrain, hf, b[2], b[3]))

    return {'width': width, 'height': height, 'tiles': tiles, 'start': start}

def render_maps(parsed, out_prefix):
    w, h = parsed['width'], parsed['height']
    tiles = parsed['tiles']

    # 1. Terrain type map (color by terrain index)
    terrain_img = Image.new('RGB', (w, h))
    tp = terrain_img.load()
    for y in range(h):
        for x in range(w):
            t = tiles[y*w + x][0]
            # Map terrain index to a color (hash-based palette)
            r = (t * 37) % 256
            g = (t * 71) % 256
            b = (t * 113) % 256
            tp[x, y] = (r, g, b)
    terrain_img.save(out_prefix + '_terrain.png')

    # 2. Height map (byte[1] low bits = height)
    height_img = Image.new('L', (w, h))
    hp = height_img.load()
    heights = set()
    for y in range(h):
        for x in range(w):
            hf = tiles[y*w + x][1]
            heights.add(hf)
            # height likely in low nibble
            hval = hf & 0x0F
            hp[x, y] = hval * 16
    height_img.save(out_prefix + '_height.png')

    # 3. Analyze byte[1] bit structure
    print(f"\n  byte[1] distinct values ({len(heights)}):")
    for v in sorted(heights):
        count = sum(1 for t in tiles if t[1] == v)
        binary = f'{v:08b}'
        print(f"    {v:3d} (0b{binary}) : {count:5d} tiles")

    # 4. Water/barrier guess: high values of byte[1]
    # Render mask where byte[1] >= 16 (possible water/special)
    mask_img = Image.new('RGB', (w, h))
    mp = mask_img.load()
    for y in range(h):
        for x in range(w):
            hf = tiles[y*w + x][1]
            if hf >= 16:
                mp[x, y] = (0, 100, 255)   # blue = water/special
            elif hf >= 8:
                mp[x, y] = (255, 100, 0)   # orange = barrier?
            else:
                mp[x, y] = (50, 150, 50)   # green = walkable
    mask_img.save(out_prefix + '_walkmask.png')

    return w, h

def main():
    scenario_dir = r"D:\Games\Rage of Mages II\extracted\scenario"
    out_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\map_analysis"
    os.makedirs(out_dir, exist_ok=True)

    for name in ["84.alm", "93.alm", "10.alm"]:
        fp = os.path.join(scenario_dir, name)
        if not os.path.exists(fp):
            continue
        print(f"\n{'='*60}\n{name}")
        parsed = parse_alm(fp)
        if not parsed:
            print("  Failed to parse")
            continue
        print(f"  Map {parsed['width']}x{parsed['height']}, data@0x{parsed['start']:04x}")
        w, h = render_maps(parsed, os.path.join(out_dir, name.replace('.alm','')))
        print(f"  Rendered -> {out_dir}/{name.replace('.alm','')}_*.png")

if __name__ == '__main__':
    main()
