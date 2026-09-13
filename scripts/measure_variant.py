#!/usr/bin/env python3
"""Measure variant (byte0&0xF) and row (byte0>>4) distributions per terrain type."""
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
n = width*height

# variant and row distribution per terrain type (byte1)
import collections
per_type = collections.defaultdict(lambda: [collections.Counter(), collections.Counter(), 0])
for i in range(n):
    hf = data[layerA+i*2+1]
    if not (0 <= hf <= 3):
        continue
    b0 = data[layerA+i*2]
    per_type[hf][0][b0 & 0xF] += 1
    per_type[hf][1][b0 >> 4] += 1
    per_type[hf][2] += 1

names = {0:"tile1(трава)", 1:"tile2(земля)", 2:"tile3(вода)", 3:"tile4(скала)"}
for t in sorted(per_type):
    var_c, row_c, cnt = per_type[t]
    total = cnt
    variants = var_c.most_common()
    rows = row_c.most_common()
    # percentage of top variant & top row
    topv = variants[0] if variants else (None,0)
    topr = rows[0] if rows else (None,0)
    print(f"\nТип {t} ({names.get(t,'?')}) тайлов: {total}")
    print(f"  вариантов в byte0&0xF: {len(variants)}; ТОП: {topv[1]*100//total}% тайлов используют вариант {topv[0]}")
    print(f"  рядов в byte0>>4: {len(rows)}; ТОП: {topr[1]*100//total}% тайлов используют ряд {topr[0]}")
    print(f"  топ варианты: {variants[:6]}")
    print(f"  топ ряды: {rows[:6]}")