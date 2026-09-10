import os

files = [
    r'D:\Work\UnityProjects\Allodshome_Godot\assets\units\monsters\orc\sprites.256',
    r'D:\Work\UnityProjects\Allodshome_Godot\assets\structures\bhut1\house.256',
    r'D:\Work\UnityProjects\Allodshome_Godot\assets\map-objects\bush1\sprites.256',
]

for f in files:
    size = os.path.getsize(f)
    print(f"\n{os.path.basename(f)}: {size} bytes")
    
    for skip in [0, 768]:
        remaining = size - skip
        if remaining % 4 == 0:
            pixels = remaining // 4
            for w in [32, 48, 64, 96, 128, 160, 192, 256]:
                if pixels % w == 0:
                    h = pixels // w
                    if 10 < h < 500:
                        print(f"  skip={skip}: {pixels} pixels = {w}x{h}")
                        break
