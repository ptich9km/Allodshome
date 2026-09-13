#!/usr/bin/env python3
"""Measure coherence of terrain TYPE (byte>>4) on Beach.alm vs per-tile byte."""
import struct, os

fp = r"D:\Games\Rage of Mages II\Beach.alm"
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
print(f"layerA=0x{layerA:04x}")

def region_coherence(keyfunc, name):
    """Coherence of a derived key (type) across adjacent tiles."""
    m=t=0
    for y in range(height):
        for x in range(width):
            i=y*width+x
            k = keyfunc(data[layerA+i*2], data[layerA+i*2+1])
            if x+1<width:
                t+=1
                if k == keyfunc(data[layerA+(i+1)*2], data[layerA+(i+1)*2+1]): m+=1
            if y+1<height:
                t+=1
                if k == keyfunc(data[layerA+(i+width)*2], data[layerA+(i+width)*2+1]): m+=1
    print(f"{name}: coherence={m/t:.3f}")

region_coherence(lambda b,_: b, "raw byte0")
region_coherence(lambda b,_: b>>4, "type (byte>>4)")
region_coherence(lambda b,_: b&0xF, "variant (byte&0xF)")

# type distribution
types = {}
for i in range(width*height):
    t = data[layerA+i*2]>>4
    types[t]=types.get(t,0)+1
print("type distribution:", sorted(types.items(), key=lambda x:-x[1]))

# for water tiles (byte1 16-40), what type?
wtypes = {}
for i in range(width*height):
    hf = data[layerA+i*2+1]
    if 16<=hf<=40:
        t = data[layerA+i*2]>>4
        wtypes[t]=wtypes.get(t,0)+1
print("water-tile types:", sorted(wtypes.items(), key=lambda x:-x[1]))
print("water count:", sum(wtypes.values()))