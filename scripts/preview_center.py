#!/usr/bin/env python3
"""Center-crop previews of terrain hypotheses (no missing texture magenta)."""
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
tile_dir = r"D:\Games\Rage of Mages II\extracted\graphics\terrain"

# max variants per type: tile1-4 = 16,16,16,4
VMAX = {1:16, 2:16, 3:16, 4:4}
img_cache = {}
def tile_img(t, variant, row):
    vmax = VMAX.get(t, 16)
    v = min(vmax-1, max(0, variant))
    key = (t, v, row)
    if key in img_cache:
        return img_cache[key]
    fname = f"tile{t}-{v:02d}.bmp"
    p = os.path.join(tile_dir, fname)
    if os.path.exists(p):
        full = Image.open(p).convert("RGB")
        nrows = full.size[1] // 32
        r = min(nrows-1, max(0, row))
        img_cache[key] = full.crop((0, r*32, 32, r*32+32))
    else:
        img_cache[key] = Image.new("RGB", (32,32), (200,0,200))
    return img_cache[key]

def get_cell(x, y):
    i = y*width+x
    return data[layerA+i*2], data[layerA+i*2+1]

def terrain_of(hf):
    if 0 <= hf <= 3: return hf + 1  # 1..4
    return 3 if 16 <= hf <= 40 else 4  # вода->tile3, барьер->tile4

def neighbors_mask(x, y):
    _, cur = get_cell(x,y)
    mask = 0
    if y>0 and get_cell(x,y-1)[1]==cur: mask |= 1
    if x+1<width and get_cell(x+1,y)[1]==cur: mask |= 2
    if y+1<height and get_cell(x,y+1)[1]==cur: mask |= 4
    if x>0 and get_cell(x-1,y)[1]==cur: mask |= 8
    return mask

FILL_ROW = {1:11, 2:3, 3:5, 4:1}  # dominant rows per type

def h1(x,y):
    b0, hf = get_cell(x,y)
    t = terrain_of(hf)
    return t, b0 & 0xF, b0 >> 4

def h2(x,y):
    b0, hf = get_cell(x,y)
    t = terrain_of(hf)
    m = neighbors_mask(x,y)
    if m == 15:
        return t, b0 & 0xF, FILL_ROW.get(t, 0)
    return t, m & 0xF, b0 >> 4

def h4(x,y):
    b0, hf = get_cell(x,y)
    t = terrain_of(hf)
    return t, 0, FILL_ROW.get(t, 0)

# center crop: 64x64 tiles around map center, render at 8px per tile = 512x512
cx0, cy0 = width//2 - 32, height//2 - 32
SCALE = 8
outdir = r"D:\Work\UnityProjects\Allodshome_Godot"
for name, func in [("center_h1", h1), ("center_h2", h2), ("center_h4", h4)]:
    img = Image.new("RGB", (64*SCALE, 64*SCALE))
    for yy in range(64):
        for xx in range(64):
            x, y = cx0+xx, cy0+yy
            t, v, r = func(x, y)
            tile = tile_img(t, v, r).resize((SCALE, SCALE), Image.BOX)
            img.paste(tile, (xx*SCALE, yy*SCALE, xx*SCALE+SCALE, yy*SCALE+SCALE))
    img.save(os.path.join(outdir, f"{name}.png"))
    print("saved", name+".png")