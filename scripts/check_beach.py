#!/usr/bin/env python3
"""Check Beach.alm parsing with our decoder."""
import struct, os

def coherence(data, offset, width, height, bi, bpt=2):
    m=t=0
    n=width*height
    for i in range(0,n,3):
        x=i%width; y=i//width
        o=offset+i*bpt+bi
        if o+bpt>=len(data): return -1
        v=data[o]
        if x+1<width:
            t+=1
            if data[offset+(i+1)*bpt+bi]==v: m+=1
        if y+1<height:
            t+=1
            if data[offset+(i+width)*bpt+bi]==v: m+=1
    return m/t if t else 0

for name in ["Beach.alm", "84.alm"]:
    fp = os.path.join(r"D:\Games\Rage of Mages II", name)
    data = open(fp,'rb').read()
    width = struct.unpack_from('<I',data,0x28)[0]
    height = struct.unpack_from('<I',data,0x2c)[0]
    # find layer A
    bestA=(0,-1)
    for off in range(0x100,0x800,2):
        sc = coherence(data,off,width,height,1)
        if sc>bestA[1]: bestA=(off,sc)
    layerA = bestA[0]
    print(f"{name}: {width}x{height}, {len(data)}b, layerA@0x{layerA:04x} coh={bestA[1]:.3f}")
    # height values
    hf_vals = {}
    for i in range(width*height):
        o = layerA+i*2+1
        if o<len(data):
            v = data[o]
            hf_vals[v]=hf_vals.get(v,0)+1
    top = sorted(hf_vals.items(), key=lambda x:-x[1])[:8]
    print(f"  byte[1] (height/flags) top: {top}")
    # terrain values
    t_vals = {}
    for i in range(width*height):
        o = layerA+i*2
        if o<len(data):
            v = data[o]
            t_vals[v]=t_vals.get(v,0)+1
    top_t = sorted(t_vals.items(), key=lambda x:-x[1])[:8]
    print(f"  byte[0] (terrain) top: {top_t}")