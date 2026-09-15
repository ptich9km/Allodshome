#!/usr/bin/env python3
"""Extract data.bin by known offsets and dump its structure."""
import os

buf = open(r"D:\Games\Rage of Mages II\world.res", "rb").read()
out = r"D:\Games\Rage of Mages II\world_extracted"
os.makedirs(out, exist_ok=True)
files = {
    "ai.reg": (24, 180 - 24),
    "data.bin": (180, 150151 - 180),
    "itemname.bin": (150151, 982),
    "itemname.pkt": (151133, 7763),
    "map.reg": (158896, 160108 - 158896),
}
for n, (o, s) in files.items():
    with open(os.path.join(out, n), "wb") as f:
        f.write(buf[o:o+s])
    print(f"{n}: {s} bytes saved")

d = buf[180:180 + 149971]
print("\ndata.bin первые 400 байт (latin1):")
print(repr(d[:400]))
print("\nНачало как текст:")
try:
    print(d[:400].decode("cp1251", errors="replace"))
except Exception as e:
    print("decode err", e)