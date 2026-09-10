import os, struct

# Cursor sprite
sample = r'D:\Games\Rage of Mages II\extracted\graphics\cursors\default.256'
with open(sample, 'rb') as f:
    data = f.read()
print(f'=== Cursor .256: default.256 ===')
print(f'Size: {len(data)} bytes')
print(f'First 32 bytes: {list(data[:32])}')
print(f'First 32 hex: {data[:32].hex()}')
print()

# Unit monster sprite
sample2 = r'D:\Games\Rage of Mages II\extracted\graphics\units\monsters\bat\sprites.256'
with open(sample2, 'rb') as f:
    data2 = f.read()
print(f'=== Unit .256: monsters/bat/sprites.256 ===')
print(f'Size: {len(data2)} bytes')
print(f'First 32 bytes: {list(data2[:32])}')
print(f'First 32 hex: {data2[:32].hex()}')
print()

# Structure sprite
sample3 = r'D:\Games\Rage of Mages II\extracted\graphics\structures\hut1\house.256'
with open(sample3, 'rb') as f:
    data3 = f.read()
print(f'=== Structure .256: structures/hut1/house.256 ===')
print(f'Size: {len(data3)} bytes')
print(f'First 32 bytes: {list(data3[:32])}')
print(f'First 32 hex: {data3[:32].hex()}')
print()

# Equipment sprite
sample4 = r'D:\Games\Rage of Mages II\extracted\graphics\equipment\ffighter\1.256'
with open(sample4, 'rb') as f:
    data4 = f.read()
print(f'=== Equipment .256: ffighter/1.256 ===')
print(f'Size: {len(data4)} bytes')
print(f'First 32 bytes: {list(data4[:32])}')
print(f'First 32 hex: {data4[:32].hex()}')
