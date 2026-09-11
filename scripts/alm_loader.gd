class_name AlmLoader
## Парсер карт Allods 2 (.alm). Читает бинарный формат напрямую.
## Формат: M7R magic, width@0x28, height@0x2c, тайлы по 2 байта
## (byte0=terrain, byte1=высота+флаги). Offset данных ищется по связности.

const MAGIC := 0x4D375200  # "M7R\0" little-endian

# Флаги высоты/проходимости (byte1)
enum TileFlag { GROUND, HILL, HIGH2, HIGH3, WATER, BARRIER }

static func _u32le(data: PackedByteArray, off: int) -> int:
	return data[off] | (data[off+1] << 8) | (data[off+2] << 16) | (data[off+3] << 24)

## Найти offset тайловых данных: максимум пространственной связности byte1.
static func _find_tile_offset(data: PackedByteArray, width: int, height: int) -> int:
	var best_off := 0x2c0
	var best_score := -1.0
	var n := width * height
	# Сэмплируем каждый 3-й тайл для скорости
	for off in range(0x100, 0x400, 2):
		var matches := 0
		var total := 0
		for i in range(0, n, 3):
			var x := i % width
			var y := i / width
			var o := off + i * 2 + 1
			if o + 2 >= data.size():
				break
			var v := data[o]
			if x + 1 < width:
				total += 1
				if data[off + (i+1)*2 + 1] == v:
					matches += 1
			if y + 1 < height:
				total += 1
				if data[off + (i+width)*2 + 1] == v:
					matches += 1
		if total > 0:
			var score := float(matches) / float(total)
			if score > best_score:
				best_score = score
				best_off = off
	return best_off

## Классифицировать byte1 в флаг проходимости/высоты.
static func classify(hf: int) -> int:
	if hf == 0:
		return TileFlag.GROUND
	elif hf == 1:
		return TileFlag.HILL
	elif hf == 2:
		return TileFlag.HIGH2
	elif hf == 3:
		return TileFlag.HIGH3
	elif hf >= 16 and hf <= 40:
		return TileFlag.WATER
	else:
		return TileFlag.BARRIER

## Высота в "уровнях" для замедления/обзора (0..3).
static func height_level(hf: int) -> int:
	match classify(hf):
		TileFlag.GROUND: return 0
		TileFlag.HILL: return 1
		TileFlag.HIGH2: return 2
		TileFlag.HIGH3: return 3
		_: return 0

static func is_walkable(hf: int) -> bool:
	var c := classify(hf)
	return c != TileFlag.WATER and c != TileFlag.BARRIER

## Загрузить карту. Возвращает Dictionary или {} при ошибке.
static func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("AlmLoader: файл не найден: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("AlmLoader: не удалось открыть: " + path)
		return {}
	var data := f.get_buffer(f.get_length())
	f.close()

	if data.size() < 0x40:
		push_error("AlmLoader: файл слишком мал")
		return {}

	var width := _u32le(data, 0x28)
	var height := _u32le(data, 0x2c)
	if width < 4 or height < 4 or width > 512 or height > 512:
		push_error("AlmLoader: некорректные размеры %dx%d" % [width, height])
		return {}

	var offset := _find_tile_offset(data, width, height)
	var n := width * height

	var terrain := PackedByteArray()
	var hflags := PackedByteArray()
	terrain.resize(n)
	hflags.resize(n)
	for i in range(n):
		var o := offset + i * 2
		if o + 1 < data.size():
			terrain[i] = data[o]
			hflags[i] = data[o + 1]

	print("AlmLoader: %s -> %dx%d, data@0x%x" % [path.get_file(), width, height, offset])
	return {
		"width": width,
		"height": height,
		"terrain": terrain,
		"hflags": hflags,
		"offset": offset,
	}
