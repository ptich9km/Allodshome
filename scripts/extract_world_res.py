#!/usr/bin/env python3
"""Extract files from world.res using the tail-index parser (res.exe crashes on it).
Index entries at end of file: [u32 flag][u32 offset][u32 size][u32 ?][u16 name...]
Known entries (from prior research): ai.reg@24, data.bin@180, itemname.bin@150151,
itemname.pkt@151133, map.reg@158896. File size ~160108.
"""
import struct, os

SRC = r"D:\Games\Rage of Mages II\world.res"
OUT = r"D:\Games\Rage of Mages II\world_extracted"
os.makedirs(OUT, exist_ok=True)

data = open(SRC, "rb").read()
print(f"world.res size: {len(data)}")

# Посмотрим хвост файла — индекс
tail = data[-256:]
print("Хвост (последние 128 байт как hex):")
for i in range(0, 128, 16):
    print(f"  {len(data)-128+i:06x}: {' '.join(f'{b:02x}' for b in tail[i:i+16])}")

# Парсим индекс: ищем 12-байтовые записи + имя
# Записи: [u32 = ?0][u32 offset][u32 size][u32 = ?0][name up to 16 bytes]
pos = len(data)
entries = []
# Индекс идёт с конца; формат из исследования
buf = data
idx = len(buf) - 4
count = struct.unpack_from("<I", buf, idx)[0]
print(f"\nПоследние 4 байта (count?): {count} (0x{count:x})")

# Пробуем: записи индекса идут от (count) с конца
# Известно: data.bin@180, itemname.bin@150151, itemname.pkt@151133, map.reg@158896, ai.reg@24
# Порядок имён в индексе, вероятно: в обратном порядке файлов
# Попробуем пройтись по хвосту с конца: [u32][u32 offset][u32 size][u16/32 name]

# Метод: читаем с конца 4 байта за раз как (offset,size) пары, имя до этого
entries = []
p = len(buf)
# Первый блок индекса обычно: [u32 0][u32 offset][u32 size][u32 0]
for attempt in range(12):
    if p < 16:
        break
    # читаем запись из 3 u32
    a, off, sz = struct.unpack_from("<3I", buf, p - 12)
    if sz > 0 and sz < 200000 and off >= 0 and off < len(buf):
        # найдено: ищем имя перед записью
        name_start = p - 12
        # имя: строка перед (обычно до 16 байт)
        nm = ""
        for k in range(24, 0, -1):
            start = name_start - k
            if start < 0:
                continue
            chunk = buf[start:name_start]
            # имя — печатные символы
            if all(32 <= c < 127 for c in chunk) and b"\x00" not in chunk:
                nm = chunk.decode("ascii", errors="replace")
                break
        entries.append((nm, off, sz))
        print(f"  {nm or '?'}: offset={off}, size={sz}")
        p = name_start - (24 if nm else 12)
    else:
        p -= 4

print(f"\nВсего записей в индексе: {len(entries)}")
# Сохраняем найденные файлы
for name, off, sz in entries:
    if not name:
        continue
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(buf[off:off+sz])
    print(f"Сохранено: {name} ({sz} байт)")