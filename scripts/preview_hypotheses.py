#!/usr/bin/env python3
"""Generate multiple terrain-rendering hypothesis previews for user to compare."""
import struct, os
from PIL import Image

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
terrain_dir = r"D:\Games\Rage of Mages II\extracted\graphics\terrain"

# cache of (file,row) -> 32x32 tile
img_cache = {}
def tile_img(t, variant, row):
    v = min(15, max(0, variant))
    key = (t, v, row)
    if key in img_cache:
        return img_cache[key]
    fname = f"tile{t}-{v:02d}.bmp"
    p = os.path.join(terrain_dir, fname)
    if os.path.exists(p):
        full = Image.open(p).convert("RGB")
        nrows = full.size[1] // 32
        r = min(nrows-1, max(0, row))
        img_cache[key] = full.crop((0, r*32, 32, r*32+32)).resize((2,2), Image.BOX)
    else:
        img_cache[key] = Image.new("RGB", (2,2), (200,0,200))
    return img_cache[key]

def get_cell(x, y):
    i = y*width+x
    return data[layerA+i*2], data[layerA+i*2+1]

def neighbors_same(x, y):
    """4-edge mask: neighbor type (byte1) == current."""
    _, cur = get_cell(x,y)
    mask = 0
    if y>0 and get_cell(x,y-1)[1]==cur: mask |= 1  # N
    if x+1<width and get_cell(x+1,y)[1]==cur: mask |= 2  # E
    if y+1<height and get_cell(x,y+1)[1]==cur: mask |= 4  # S
    if x>0 and get_cell(x-1,y)[1]==cur: mask |= 8  # W
    return mask

def render_hyp(name, select):
    """select(x,y) -> (t, variant, row). Returns Image of the map."""
    out = Image.new("RGB", (width*2, height*2))
    for y in range(height):
        for x in range(width):
            t, v, r = select(x, y)
            out.paste(tile_img(t, v, r), (x*2, y*2, x*2+2, y*2+2))
    out.save(os.path.join(r"D:\Work\UnityProjects\Allodshome_Godot", f"prev_{name}.png"))
    print("saved prev_"+name+".png")

# H1: current — variant=byte0&0xF, row=byte0>>4
def h1(x,y):
    b0, hf = get_cell(x,y)
    t = hf if 0<=hf<=3 else (2 if 16<=hf<=40 else 3)
    return t, b0&0xF, b0>>4

# H2: edge-aware — interior uses dominant fill per type, edges use byte0 variant
FILL_ROW = {0:11, 1:1, 2:5, 3:1}   # dominant rows per type from measurement
def h2(x,y):
    b0, hf = get_cell(x,y)
    t = hf if 0<=hf<=3 else (2 if 16<=hf<=40 else 3)
    mask = neighbors_same(x,y)
    if mask == 15:  # fully interior
        return t, b0&0xF, FILL_ROW.get(t, 0)
    return t, mask & 0xF, b0>>4

# H3: fully interior-fixed fill, edges via mask
def h3(x,y):
    b0, hf = get_cell(x,y)
    t = hf if 0<=hf<=3 else (2 if 16<=hf<=40 else 3)
    mask = neighbors_same(x,y)
    if mask == 15:
        return t, 0, FILL_ROW.get(t, 0)   # always tileN-00 fill
    return t, mask & 0xF, 0

# H4: uniform fill per type, ignore byte0 (pure type map)
def h4(x,y):
    b0, hf = get_cell(x,y)
    t = hf if 0<=hf<=3 else (2 if 16<=hf<=40 else 3)
    return t, 0, FILL_ROW.get(t, 0)

render_hyp("h1_current", h1)
render_hyp("h2_interior_fill", h2)
render_hyp("h3_fill_edges", h3)
render_hyp("h4_puretype", h4)
print("done")