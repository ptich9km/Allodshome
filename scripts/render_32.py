#!/usr/bin/env python3
"""Render full 32.alm at 100% with best hypothesis: fill variant + correct row."""
import struct, os, collections
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
tile_dir = r"D:\Games\Rage of Mages II\extracted\graphics\terrain"
VMAX = {1:16, 2:16, 3:16, 4:4}
cache = {}
def tile_img(t, variant, row):
    v = min(VMAX.get(t,16)-1, max(0, variant))
    key = (t, v, row)
    if key in cache:
        return cache[key]
    p = os.path.join(tile_dir, f"tile{t}-{v:02d}.bmp")
    if os.path.exists(p):
        full = Image.open(p).convert("RGB")
        nrows = full.size[1] // 32
        r = min(nrows-1, max(0, row))
        cache[key] = full.crop((0, r*32, 32, r*32+32))
    else:
        cache[key] = Image.new("RGB", (32,32), (255,0,255))
    return cache[key]

def get_cell(x, y):
    i = y*width+x
    return data[layerA+i*2], data[layerA+i*2+1]

def terrain_of(hf):
    if 0 <= hf <= 3: return hf + 1
    return 3 if 16 <= hf <= 40 else 4

# Measure: for dominant variant per type, row distribution
rows_for = {}
for i in range(width*height):
    hf = data[layerA+i*2+1]
    if not (0 <= hf <= 3): continue
    b0 = data[layerA+i*2]
    t = hf+1
    v = b0 & 0xF
    r = b0 >> 4
    rows_for.setdefault((t,v), collections.Counter())[r] += 1
print("Fill variant rows (dominant variant per type):")
vmax_measured = {}
for (t,v), cnt in sorted(rows_for.items()):
    if v == 4 or v == 1 or v == 0:
        top = cnt.most_common(4)
        print(f"  tile{t} variant {v}: {top}")

# HYPOTHESIS: interior (all 4 neighbors same) => dominant variant + dominant row; edges => data variant/row
def neighbors_mask(x,y):
    _, cur = get_cell(x,y)
    m = 0
    if y>0 and get_cell(x,y-1)[1]==cur: m|=1
    if x+1<width and get_cell(x+1,y)[1]==cur: m|=2
    if y+1<height and get_cell(x,y+1)[1]==cur: m|=4
    if x>0 and get_cell(x-1,y)[1]==cur: m|=8
    return m

# Determine per-type dominant (variant, row)
dom = {}
for i in range(width*height):
    hf = data[layerA+i*2+1]
    if 0 <= hf <= 3:
        t = hf+1
        vr = (data[layerA+i*2]&0xF, data[layerA+i*2]>>4)
        dom.setdefault(t, collections.Counter())[vr] += 1
FILL = {t: c.most_common(1)[0][0] for t, c in dom.items()}
print("\nFill (variant,row) per type:", FILL)

def select_fill_edge(x, y):
    b0, hf = get_cell(x,y)
    t = terrain_of(hf)
    m = neighbors_mask(x,y)
    if m == 15:
        vr = FILL.get(t, (b0&0xF, b0>>4))
        return t, vr[0], vr[1]
    return t, b0 & 0xF, b0 >> 4

def select_data(x, y):
    b0, hf = get_cell(x,y)
    t = terrain_of(hf)
    return t, b0 & 0xF, b0 >> 4

for name, sel in [("32_full_data", select_data), ("32_full_fill", select_fill_edge)]:
    img = Image.new("RGB", (width*32, height*32))
    for y in range(height):
        for x in range(width):
            t, v, r = sel(x, y)
            img.paste(tile_img(t, v, r), (x*32, y*32, x*32+32, y*32+32))
    img.save(rf"D:\Work\UnityProjects\Allodshome_Godot\{name}.png")
    print("saved", name+".png", img.size)