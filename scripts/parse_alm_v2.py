#!/usr/bin/env python3
"""
Correct .alm parser: 2 bytes per tile.
byte[0] = terrain texture, byte[1] = height + flags.
Two layers (A and B) = 4 bytes total per tile position.
"""
import struct
import os
from PIL import Image

def parse_alm(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    width = struct.unpack_from('<I', data, 0x28)[0]
    height = struct.unpack_from('<I', data, 0x2c)[0]

    # Find best offset: maximize coherence of byte1 with 2 bytes/tile
    def coherence(offset, bi):
        m = t = 0
        for y in range(height):
            for x in range(width):
                i = y*width+x
                off = offset + i*2 + bi
                if off+2 >= len(data): return -1
                v = data[off]
                if x+1<width:
                    t+=1
                    if data[offset+(i+1)*2+bi]==v: m+=1
                if y+1<height:
                    t+=1
                    if data[offset+(i+width)*2+bi]==v: m+=1
        return m/t if t else 0

    best_off, best_sc = 0, 0
    for off in range(0x100, 0x800, 2):
        sc = coherence(off, 1)
        if sc > best_sc:
            best_sc, best_off = sc, off

    return data, width, height, best_off

def render(data, width, height, offset, out_prefix):
    n = width*height
    # Layer A: bytes at offset + i*2
    terrain = Image.new('RGB', (width, height))
    heightmap = Image.new('L', (width, height))
    tp, hp = terrain.load(), heightmap.load()

    hvals = {}
    for y in range(height):
        for x in range(width):
            i = y*width+x
            b0 = data[offset + i*2 + 0]   # terrain texture
            b1 = data[offset + i*2 + 1]   # height/flags
            hvals[b1] = hvals.get(b1,0)+1
            # terrain color: use a fixed palette by index mod
            tp[x,y] = ((b0*53)%256, (b0*97)%256, (b0*151)%256)
            hp[x,y] = min(255, b1*8)

    terrain.save(out_prefix+'_terrain.png')
    heightmap.save(out_prefix+'_height.png')

    # Height value analysis
    print(f"  byte[1] (height/flags) values:")
    for v in sorted(hvals):
        print(f"    {v:3d} (0b{v:08b}): {hvals[v]:5d}")

    # Walkability mask: 0,1 = walkable ground; higher = elevated/water/barrier
    mask = Image.new('RGB', (width, height))
    mp = mask.load()
    for y in range(height):
        for x in range(width):
            i = y*width+x
            b1 = data[offset + i*2 + 1]
            if b1 == 0:
                mp[x,y] = (60,160,60)      # flat walkable
            elif b1 == 1:
                mp[x,y] = (120,200,80)     # elevated walkable (hill)
            elif b1 >= 16:
                mp[x,y] = (40,90,220)      # water (impassable, flyable)
            else:
                mp[x,y] = (200,120,40)     # barrier (wall/mountain)
    mask.save(out_prefix+'_walkmask.png')

def main():
    scenario_dir = r"D:\Games\Rage of Mages II\extracted\scenario"
    out_dir = r"D:\Work\UnityProjects\Allodshome_Godot\assets\map_analysis"
    os.makedirs(out_dir, exist_ok=True)

    for name in ["84.alm", "10.alm", "93.alm"]:
        fp = os.path.join(scenario_dir, name)
        if not os.path.exists(fp): continue
        data, w, h, off = parse_alm(fp)
        print(f"\n{name}: {w}x{h}, tile data @0x{off:04x}")
        render(data, w, h, off, os.path.join(out_dir, 'v2_'+name.replace('.alm','')))

if __name__ == '__main__':
    main()
