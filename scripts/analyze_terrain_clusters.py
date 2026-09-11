#!/usr/bin/env python3
"""Analyze terrain byte[0] clusters + render banded map to see connected regions."""
import struct, os
from PIL import Image

def main():
    fp = r"D:\Games\Rage of Mages II\extracted\scenario\84.alm"
    data = open(fp,'rb').read()
    width = struct.unpack_from('<I',data,0x28)[0]
    height = struct.unpack_from('<I',data,0x2c)[0]
    n = width*height
    # Layer A start (byte1 coherent) ~0x1c2
    off = 0x1c2
    terrain = [data[off+i*2] for i in range(n)]

    # Histogram
    hist = {}
    for v in terrain: hist[v]=hist.get(v,0)+1
    top = sorted(hist.items(), key=lambda x:-x[1])
    print("Top 25 terrain byte[0] values:")
    for v,c in top[:25]:
        print(f"  {v:3d}: {c:5d}")
    print(f"  ... total distinct: {len(hist)}")

    out = r"D:\Work\UnityProjects\Allodshome_Godot\assets\map_analysis"

    # Render 1: band by value//64 (4 terrain bands)
    band_colors = [(60,160,60),(200,180,90),(180,140,80),(120,120,120)]
    img = Image.new('RGB',(width,height)); p=img.load()
    for y in range(height):
        for x in range(width):
            v = terrain[y*width+x]
            p[x,y] = band_colors[(v//64)%4]
    img.save(f"{out}/terrain_bands.png")

    # Render 2: dominant value=green, its transitions=yellow, else=by band
    dom = top[0][0]
    img2 = Image.new('RGB',(width,height)); p2=img2.load()
    for y in range(height):
        for x in range(width):
            v = terrain[y*width+x]
            if v == dom: p2[x,y]=(60,160,60)
            elif abs(v-dom)<=8: p2[x,y]=(220,220,60)
            else: p2[x,y]=band_colors[(v//64)%4]
    img2.save(f"{out}/terrain_dom.png")
    print(f"\nDominant terrain value: {dom}")
    print(f"Rendered -> terrain_bands.png, terrain_dom.png")

if __name__=='__main__':
    main()
