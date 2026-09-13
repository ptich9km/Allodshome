#!/usr/bin/env python3
"""Analyze 32.alm terrain structure + render bottom-left corner at 100%."""
import struct, os
from PIL import Image

fp = r"D:\Games\Rage of Mages II\extracted\scenario\32.alm"
data = open(fp, 'rb').read()
width = struct.unpack_from('<I', data, 0x28)[0]
height = struct.unpack_from('<I', data, 0x2c)[0]

def find_layerA():
    def coherence(offset, bi):
        m=t=0
        n=width*height
        for i in range(0,n,3):
            x=i%width; y=i//width
            o=offset+i*2+bi
            if o+2>=len(data): return -1
            v=data[o]
            if x+1<width:
                t+=1
                if data[offset+(i+1)*2+bi]==v: m+=1
            if y+1<height:
                t+=1
                if data[offset+(i+width)*2+bi]==v: m+=1
        return m/t if t else 0
    bestA=(0,-1)
    for off in range(0x100,0x800,2):
        sc=coherence(off,1)
        if sc>bestA[1]: bestA=(off,sc)
    return bestA[0]

layerA = find_layerA()
print(f"32.alm {width}x{height}, layerA=0x{layerA:04x}")

# byte1 distribution (types)
import collections
types = collections.Counter()
for i in range(width*height):
    types[data[layerA+i*2+1]] += 1
print("byte[1] (type) distribution:", sorted(types.items(), key=lambda x:-x[1]))

# byte0 variants per type
per_t = collections.defaultdict(lambda: collections.Counter())
for i in range(width*height):
    hf = data[layerA+i*2+1]
    if 0 <= hf <= 3:
        per_t[hf][data[layerA+i*2] & 0xF] += 1
for t in sorted(per_t):
    print(f"  type {t}: варианты {per_t[t].most_common(8)}")

# Type map (low res) to see structure
def type_color(hf):
    t = hf if 0 <= hf <= 3 else (2 if 16 <= hf <= 40 else 3)
    return [(30,160,60),(180,140,80),(40,90,200),(150,150,150)][t]

tm = Image.new("RGB", (width, height))
tp = tm.load()
for y in range(height):
    for x in range(width):
        tp[x,y] = type_color(data[layerA+(y*width+x)*2+1])
tm.save(r"D:\Work\UnityProjects\Allodshome_Godot\prev_32_type.png")
print("saved prev_32_type.png")