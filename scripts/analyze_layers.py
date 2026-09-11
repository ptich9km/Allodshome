#!/usr/bin/env python3
"""Examine both 2-byte layers of the .alm tile block."""
import struct, os
from PIL import Image

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

def main():
    fp = r"D:\Games\Rage of Mages II\extracted\scenario\84.alm"
    data = open(fp,'rb').read()
    width = struct.unpack_from('<I',data,0x28)[0]
    height = struct.unpack_from('<I',data,0x2c)[0]
    block_size = struct.unpack_from('<I',data,0x08)[0]
    n = width*height
    print(f"Map {width}x{height}, block_size={block_size}, tiles*2={n*2}, two_layers={n*4}")

    # Find layer A start (byte1 coherent)
    bestA=(0,-1)
    for off in range(0x100,0x500,2):
        sc=coherence(data,off,width,height,1)
        if sc>bestA[1]: bestA=(off,sc)
    layerA = bestA[0]
    layerB = layerA + n*2
    print(f"Layer A @0x{layerA:04x} (byte1 coh={bestA[1]:.3f})")
    print(f"Layer B @0x{layerB:04x}")

    # Analyze coherence of each byte in each layer
    for name, off in [("A",layerA),("B",layerB)]:
        print(f"\nLayer {name} @0x{off:04x}:")
        for bi in range(2):
            sc = coherence(data,off,width,height,bi)
            # value distribution
            vals={}
            for i in range(n):
                o=off+i*2+bi
                if o<len(data): vals[data[o]]=vals.get(data[o],0)+1
            top=sorted(vals.items(),key=lambda x:-x[1])[:6]
            print(f"  byte[{bi}] coherence={sc:.3f}  uniq={len(vals)}  top={top}")

    # Render layer B byte0 and byte1 as images
    out = r"D:\Work\UnityProjects\Allodshome_Godot\assets\map_analysis"
    for bi, label in [(0,'b0'),(1,'b1')]:
        img=Image.new('RGB',(width,height)); p=img.load()
        for y in range(height):
            for x in range(width):
                i=y*width+x
                v=data[layerB+i*2+bi]
                p[x,y]=((v*53)%256,(v*97)%256,(v*151)%256)
        img.save(f"{out}/layerB_{label}.png")
    print(f"\nRendered layerB -> {out}/layerB_b0.png, layerB_b1.png")

if __name__=='__main__':
    main()
