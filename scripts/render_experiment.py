#!/usr/bin/env python3
"""Experiment: render Beach.alm with row=type hypothesis."""
import struct, os
from PIL import Image

fp = r"D:\Games\Rage of Mages II\Beach.alm"
data = open(fp, 'rb').read()
width = struct.unpack_from('<I', data, 0x28)[0]
height = struct.unpack_from('<I', data, 0x2c)[0]

def coherence(data, offset, width, height, bi):
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

layerA=0; best=-1
for off in range(0x100,0x800,2):
    sc=coherence(data,off,width,height,1)
    if sc>best: best, layerA = sc, off

# Load terrain files: tile{N}-{XX}.bmp, row = type
terrain_dir = r"D:\Games\Rage of Mages II\extracted\graphics\terrain"
tile_cache = {}
def get_tile_row(ttype, variant, row):
    # clamp variant to 0-15
    v = min(15, max(0, variant))
    key = (ttype, v)
    if key not in tile_cache:
        name = f"tile{ttype}-{v:02d}.bmp"
        p = os.path.join(terrain_dir, name)
        if os.path.exists(p):
            tile_cache[key] = Image.open(p).convert("RGB")
        else:
            tile_cache[key] = None
    img = tile_cache[key]
    if img is None:
        return Image.new("RGB", (32,32), (200,0,200))
    r = min(img.size[1]//32-1, max(0, row))
    return img.crop((0, r*32, 32, r*32+32))

def water_tile():
    name = "tile3-00.bmp"
    p = os.path.join(terrain_dir, name)
    if os.path.exists(p):
        img = Image.open(p).convert("RGB")
        return img.crop((0, 0, 32, 32))
    return Image.new("RGB", (32,32), (0,0,200))

# Render 256x256 map at 1px per 32x32 tile (too big) -> downsample: render 128x128 view
out = Image.new("RGB", (width, height))
op = out.load()
water_flag_lo, water_flag_hi = 16, 40
for y in range(height):
    for x in range(width):
        i = y*width+x
        code = data[layerA+i*2]
        hf = data[layerA+i*2+1]
        if 16 <= hf <= 40:
            # water -> use water tiles
            op[x,y] = (30, 60, 180)
        else:
            ttype = (code >> 4) & 0xF
            variant = code & 0xF
            row = ttype  # hypothesis: row = type
            # map type to file: try file=tile{type}
            if not os.path.exists(os.path.join(terrain_dir, f"tile{ttype}-{variant:02d}.bmp")):
                # fallback: use tile1 variation for unknown types
                ttype = 1
            tile = get_tile_row(ttype, variant, row)
            px = tile.load()
            op[x,y] = px[16,16]  # sample center pixel
out.save(r"D:\Work\UnityProjects\Allodshome_Godot\tmp_terrain_rows\beach_experiment.png")
print("saved beach_experiment.png", out.size)
print("layerA", hex(layerA))