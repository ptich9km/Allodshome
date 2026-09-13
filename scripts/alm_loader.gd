class_name AlmLoader
## Парсер карт Allods 2 (.alm). Читает бинарный формат напрямую.
## Структура: 2 байта на тайл, ДВА слоя.
## Layer A: byte[0] = вариант автайла (младший ниббл -> файл tileN-XX, старший -> ряд),
##          byte[1] = ТИП terrain (0-3 -> tile1-4; 16-40=вода; >40=барьер).
## Layer B: объекты/декор.

const MAGIC := 0x4D375200  # "M7R\0"

# Флаги проходимости
enum TileFlag { GROUND, HILL, HIGH2, WATER, BARRIER }

static func _u32le(data: PackedByteArray, off: int) -> int:
	return data[off] | (data[off+1] << 8) | (data[off+2] << 16) | (data[off+3] << 24)

## Найти offset Layer A (максимум пространственной связности byte[1]).
static func _find_tile_offset(data: PackedByteArray, width: int, height: int) -> int:
	var best_off := 0x2c0
	var best_score := -1.0
	var n := width * height
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

## Тип terrain из byte[1]: 0-3 = tile1-4, -1 = вода (16-40), -2 = барьер.
static func terrain_type(hf: int) -> int:
	if hf >= 0 and hf <= 3:
		return hf
	elif hf >= 16 and hf <= 40:
		return -1
	return -2

## Проходимы: тип 0 (трава/tile1) и тип 1 (земля/tile2). Вода и скала — нет.
static func is_walkable_type(t: int) -> bool:
	return t >= 0 and t <= 1

static func classify(hf: int) -> int:
	var t := terrain_type(hf)
	if t == -1:
		return TileFlag.WATER
	elif t == -2:
		return TileFlag.BARRIER
	elif t == 3:
		return TileFlag.HILL  # скала — приподнята визуально
	elif t == 2:
		return TileFlag.WATER  # tile3 = вода
	return TileFlag.GROUND

## Высота для визуала: скала (тип 3) приподнята на 1 уровень.
static func height_level(hf: int) -> int:
	if classify(hf) == TileFlag.HILL:
		return 1
	return 0

static func is_walkable(hf: int) -> bool:
	return is_walkable_type(terrain_type(hf))

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

	var terrain := PackedByteArray()  # byte[0] — вариант автайла
	var hflags := PackedByteArray()   # byte[1] — тип terrain
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