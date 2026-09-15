class_name AlmLoader
## Парсер карт Allods 2 (.alm). Читает бинарный формат напрямую.
## Структура: заголовок 0x14 + info-секция (размеры на 0x28/0x2c, солнце на 0x30),
## затем uint16-тайлы и uint16-высоты... Уточнено по картам Nival (Beach/Kids3):
##   tile uint16: биты 4-11 = индекс картинки (0x00..0x33, т.к. tile1-4 × 16 вариантов
##   с 16 рядами; tile4 имеет 4), биты 12-15 = 0; byte[0] = вариант<<4 | ряд,
##   byte[1] = (индекс>>4)&0xF = файл-1 (0-3).
## За тайлами: высоты (int8), затем препятствия/объекты (uint8).

const MAGIC := 0x4D375200  # "M7R\0"

# Флаги проходимости
enum TileFlag { GROUND, HILL, HIGH2, WATER, BARRIER }

static func _u32le(data: PackedByteArray, off: int) -> int:
	return data[off] | (data[off+1] << 8) | (data[off+2] << 16) | (data[off+3] << 24)

## Найти offset Layer A. Основной способ — формальный: заголовок секции тайлов
## это [skip8][size=W*H*2][id=1][skip4], само тело начинается сразу после.
## Фолбэк — валидность тайлов (биты 12-15 = 0, byte[1] = 0..3).
static func _find_tile_offset(data: PackedByteArray, width: int, height: int) -> int:
	var n := width * height
	var want := n * 2
	# 1) Формальный якорь: заголовок секции с id=1 и точным размером W*H*2
	for off in range(0x14, maxi(0x14, data.size() - want - 64)):
		if off + 24 + want > data.size():
			break
		var sz := _u32le(data, off + 8)
		var sid := _u32le(data, off + 12)
		if sid == 1 and sz == want:
			return off + 20
	# 2) Фолбэк: валидность тайлов
	var best_off := 0x2d8
	var best_score := -1.0
	var probe: int = mini(n, 4000)
	for off in range(0x100, 0x800, 2):
		if off + probe * 2 >= data.size():
			break
		var good := 0
		var total := 0
		for i in range(0, probe, 2):
			var o := off + i * 2
			var hi := data[o + 1]
			# byte[1] = 0..3 и биты 12-15 нулевые (file 1..4, у tile4 варианты 0-3)
			if hi <= 3:
				good += 1
			total += 1
		if total > 0:
			var score := float(good) / float(total)
			if score > best_score:
				best_score = score
				best_off = off
	return best_off

## Тип terrain из byte[1]: 0 = трава (tile1), 1 = ГОРЫ (tile2), -1 = вода (tile3),
## 3 = ДОРОГИ/мостовая (tile4), >40 = барьер.
static func terrain_type(hf: int) -> int:
	if hf >= 0 and hf <= 3:
		return hf
	elif hf >= 16 and hf <= 40:
		return -1
	return -2

## Проходимы: тип 0 (трава/tile1) и тип 3 (дорога/tile4, по ней ходят быстрее).
## Горы (тип 1, tile2) и вода (тип 2, tile3) — нет. Уточнено по картам Nival:
## например на Kids3 массивы типа 1 внизу = горные хребты, тип 3 в центре = деревня.
static func is_walkable_type(t: int) -> bool:
	return t == 0 or t == 3

## Скорость по типу клетки: дорога (3) быстрее травы (0). Остальное 1.0
## (воду/горы персонаж туда не заходит).
static func speed_factor_type(t: int) -> float:
	if t == 3:
		return 1.4
	return 1.0

static func classify(hf: int) -> int:
	var t := terrain_type(hf)
	if t == -1:
		return TileFlag.WATER
	elif t == -2:
		return TileFlag.BARRIER
	elif t == 1:
		return TileFlag.HILL  # горы (tile2) — визуально приподняты
	elif t == 2:
		return TileFlag.WATER  # tile3 = вода
	return TileFlag.GROUND

## Высота для визуала: горы (тип 1) приподняты на 1 уровень.
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

	# Рельеф: int8-сетка высот сразу после тайлов; препятствия (объекты) — после высот.
	var heights := PackedByteArray()
	var obstacles := PackedByteArray()
	heights.resize(n)
	obstacles.resize(n)
	heights.fill(0)
	obstacles.fill(0)
	var h_off := offset + n * 2
	if h_off + n <= data.size():
		for i in range(n):
			heights[i] = data[h_off + i]
	var o_off := h_off + n
	if o_off + n <= data.size():
		for i in range(n):
			obstacles[i] = data[o_off + i]

	print("AlmLoader: %s -> %dx%d, data@0x%x, h@0x%x, o@0x%x" % [path.get_file(), width, height, offset, h_off, o_off])
	return {
		"width": width,
		"height": height,
		"terrain": terrain,
		"hflags": hflags,
		"heights": heights,
		"obstacles": obstacles,
		"offset": offset,
		"info": {
			"solar_angle": _f32le(data, 0x30) if data.size() >= 0x34 else 0.0,
			"time_of_day": _u32le(data, 0x34) if data.size() >= 0x38 else 0,
			"darkness": _u32le(data, 0x38) if data.size() >= 0x3c else 0,
			"contrast": _u32le(data, 0x3c) if data.size() >= 0x40 else 0,
		},
	}

static func _f32le(data: PackedByteArray, off: int) -> float:
	if off + 4 > data.size():
		return 0.0
	var b := data
	var i: int = b[off] | (b[off+1] << 8) | (b[off+2] << 16) | (b[off+3] << 24)
	var bytes := PackedByteArray([b[off], b[off+1], b[off+2], b[off+3]])
	return bytes.decode_float(0)