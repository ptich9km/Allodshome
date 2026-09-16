class_name AlmLoader
## Парсер карт Allods 2 (.alm). Читает бинарный формат напрямую.
## Формат (Allods16/UnityAllods): заголовок 0x14: magic "M7R\0", headersize,
## junk, sectioncount, junk. Далее секции: [8 байт junk][size u32][id u32]
## [4 junk][данные size].
##   id: 0=info 1=tiles(uint16) 2=heights(int8) 3=obstacles(uint8)
##       4=structures 5=players 6=units 7=logic ...
## Тайл uint16: биты 4-11 = индекс картинки (0x00..0x33 — tile1-4 × 32 варианта
## с рядами-кадрами; tile4 имеет 4 варианта), биты 12-15 = 0; byte[0] =
## вариант<<4 | ряд, byte[1] = (индекс>>4)&0xF = файл-1 (0..3).
## load_map() отдаёт ОБА представления: byte-виды (terrain/hflags — для
## рельефного меша AlmMap) и tile id (tiles — для редактора/custom_map).

const MAGIC := 0x0052374D  # "M7R\0" (little-endian)
const HEADER_SIZE := 0x14

# Флаги проходимости
enum TileFlag { GROUND, HILL, HIGH2, WATER, BARRIER }

static func _u32le(data: PackedByteArray, off: int) -> int:
	return data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24)

static func _i16(data: PackedByteArray, off: int) -> int:
	var v := data[off] | (data[off + 1] << 8)
	if v >= 0x8000:
		v -= 0x10000
	return v

static func _i32(data: PackedByteArray, off: int) -> int:
	var v := _u32le(data, off)
	if v >= 0x80000000:
		v -= 0x100000000
	return v

static func _f32le(data: PackedByteArray, off: int) -> float:
	if off + 4 > data.size():
		return 0.0
	var b := data
	var bytes := PackedByteArray([b[off], b[off + 1], b[off + 2], b[off + 3]])
	return bytes.decode_float(0)

## Строка в .alm — однобайтовая кодировка (cp1251). Имена карт ASCII;
## читаем как ASCII, чтобы не ловить ошибки UTF-8 от кириллицы.
static func _cstr(data: PackedByteArray, off: int, max_len: int) -> String:
	var end := off
	while end < off + max_len and end < data.size() and data[end] != 0:
		end += 1
	return data.slice(off, end).get_string_from_ascii()

# --- Классификация тайлов ---

## Тип terrain из byte[1] тайла: 0=трава (tile1), 1=ГОРЫ (tile2), 2=вода (tile3),
## 3=ДОРОГИ/мостовая (tile4). Спец-значения 16..40 на картах Nival — вода (-1),
## остальное — барьер (-2). (Эвристика по Beach/Kids3.)
static func terrain_type(hf: int) -> int:
	if hf >= 0 and hf <= 3:
		return hf
	elif hf >= 16 and hf <= 40:
		return -1
	return -2

## Тип terrain 0..3 из ПОЛНОГО tile id (uint16): файл-1 = (tile & 0xFF0) >> 8.
## Отдельное имя — не конфликтует с terrain_type(hf) для byte[1].
static func tile_type(tile: int) -> int:
	return (tile & 0xFF0) >> 8

## Номер файла тайла (0..51): tile{(n>>4)+1}-{(n&0xF):02}.bmp.
static func tile_file(tile: int) -> int:
	return (tile & 0xFF0) >> 4

## Кадр внутри атласа тайла (0..15, вода анимируется).
static func tile_frame(tile: int) -> int:
	return tile & 0xF

## Проходимы: тип 0 (трава/tile1) и тип 3 (дорога/tile4, по ней ходят быстрее).
## Горы (тип 1) и вода (тип 2) — нет.
static func is_walkable_type(t: int) -> bool:
	return t == 0 or t == 3

## Скорость по типу клетки: дорога (3) быстрее травы (0). Остальное 1.0.
static func speed_factor_type(t: int) -> float:
	if t == 3:
		return 1.4
	return 1.0

static func classify(hf: int) -> int:
	var t := terrain_type(hf)
	if t == 2:
		return TileFlag.WATER
	elif t == 1:
		return TileFlag.HILL  # горы (tile2) — визуально приподняты
	elif t == 3:
		return TileFlag.GROUND  # дорога
	return TileFlag.GROUND

## Высота для визуала: горы (тип 1) приподняты на 1 уровень.
static func height_level(hf: int) -> int:
	if classify(hf) == TileFlag.HILL:
		return 1
	return 0

static func is_walkable(hf: int) -> bool:
	var t := terrain_type(hf)
	return t == 0 or t == 3

## Найти offset Layer A (фолбэк для файлов без распознанных секций).
## Основной способ — формальный: заголовок секции тайлов это
## [skip8][size=W*H*2][id=1][skip4], тело начинается сразу после.
static func _find_tile_offset(data: PackedByteArray, width: int, height: int) -> int:
	var n := width * height
	var want := n * 2
	for off in range(0x14, maxi(0x14, data.size() - want - 64)):
		if off + 24 + want > data.size():
			break
		var sz := _u32le(data, off + 8)
		var sid := _u32le(data, off + 12)
		if sid == 1 and sz == want:
			return off + 20
	return -1

## --- Секции structures/units/players ---

## Секция structures: X(4) Y(4) TypeID(4) Health(2) Player(4) ID(2); мост +W(4) H(4).
static func _read_structures(data: PackedByteArray, ds: int, size: int) -> Array:
	var out: Array = []
	var o := ds
	var end := ds + size
	while o + 20 <= end:
		var xraw := _u32le(data, o)
		var yraw := _u32le(data, o + 4)
		var tid := _u32le(data, o + 8)
		var health := _i16(data, o + 12)
		var player := _i32(data, o + 14)
		var sid := _i16(data, o + 18)
		var is_bridge := (tid & 0x01000000) != 0
		tid &= 0xFFFF
		var rec := {
			"x": ((xraw & 0xFF00) >> 8) + float(xraw & 0xFF) / 256.0,
			"y": ((yraw & 0xFF00) >> 8) + float(yraw & 0xFF) / 256.0,
			"type_id": tid,
			"health": health,
			"player": player,
			"id": sid,
			"is_bridge": is_bridge,
		}
		o += 20
		if is_bridge:
			rec["bw"] = _u32le(data, o)
			rec["bh"] = _u32le(data, o + 4)
			o += 8
		out.append(rec)
	return out

## Юниты: X(4) Y(4) TypeID(2) Face(2) Flags(4) Flags2(4) Server(4) Player(4)
##        Sack(4) Angle(4) HP(2) HPMax(2) ID(4) Group(4) = 48 байт.
static func _read_units(data: PackedByteArray, ds: int, size: int) -> Array:
	var out: Array = []
	var o := ds
	var end := ds + size
	while o + 48 <= end:
		var xraw := _u32le(data, o)
		var yraw := _u32le(data, o + 4)
		out.append({
			"x": ((xraw & 0xFF00) >> 8) + float(xraw & 0xFF) / 256.0,
			"y": ((yraw & 0xFF00) >> 8) + float(yraw & 0xFF) / 256.0,
			"type_id": data[o + 8] | (data[o + 9] << 8),
			"player": _i32(data, o + 24),
			"hp_max": _i16(data, o + 38),
			"group": _i32(data, o + 44),
		})
		o += 48
	return out

static func _read_players(data: PackedByteArray, ds: int, size: int) -> Array:
	var out: Array = []
	var o := ds
	var end := ds + size
	while o + 60 <= end:
		out.append({"color": _i32(data, o), "money": _i32(data, o + 8), "name": _cstr(data, o + 12, 0x20)})
		o += 60
	return out

## --- Загрузка карты ---

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
	if _u32le(data, 0) != MAGIC:
		push_error("AlmLoader: неверная магия %08x" % _u32le(data, 0))
		return {}

	var section_count := _u32le(data, 0x0c)
	if section_count < 3:
		push_error("AlmLoader: секций слишком мало: %d" % section_count)
		return {}

	var result := {}
	var width := 0
	var height := 0
	var info_ok := false
	var offset := -1
	result["raw"] = data
	result["tiles_off"] = -1

	var off: int = HEADER_SIZE
	for i in range(section_count):
		if off + 20 > data.size():
			break
		var sec_size := _u32le(data, off + 8)
		var sec_id := _u32le(data, off + 12)
		var ds := off + 20
		if ds + sec_size > data.size():
			push_warning("AlmLoader: секция %d выходит за файл (size=%d)" % [sec_id, sec_size])
			break
		match sec_id:
			0:
				width = _u32le(data, ds)
				height = _u32le(data, ds + 4)
				result["width"] = width
				result["height"] = height
				result["name"] = _cstr(data, ds + 68, 0x40)
				info_ok = true
			1:
				if not info_ok:
					break
				var tiles := PackedInt32Array()
				tiles.resize(width * height)
				for j in range(width * height):
					tiles[j] = data[ds + j * 2] | (data[ds + j * 2 + 1] << 8)
				result["tiles"] = tiles
				result["tiles_off"] = ds
				offset = ds
			2:
				result["heights"] = data.slice(ds, ds + width * height)
			3:
				result["obstacles"] = data.slice(ds, ds + width * height)
			4:
				result["structures"] = _read_structures(data, ds, sec_size)
			5:
				result["players"] = _read_players(data, ds, sec_size)
			6:
				result["units"] = _read_units(data, ds, sec_size)
		# Секция info: в заголовке size=644, но реально 660 байт (поля+Name+Rec/Junk+Author).
		# Иначе следующая секция reads съезжает на 16 байт (tiles начинается ровно на 0x2bc).
		if sec_id == 0:
			off = ds + 660
		else:
			off = ds + sec_size
		if off >= data.size():
			break

	if not info_ok or width < 4 or height < 4:
		push_error("AlmLoader: не удалось прочитать info %dx%d" % [width, height])
		return {}

	# Секции 2/3 могут отсутствовать — тогда фолбэк как раньше: сразу после тайлов
	var n := width * height
	if not result.has("heights"):
		var heights := PackedByteArray()
		heights.resize(n)
		heights.fill(0)
		var h_off := offset + n * 2
		if offset >= 0 and h_off + n <= data.size():
			for k in range(n):
				heights[k] = data[h_off + k]
		result["heights"] = heights
	if not result.has("obstacles"):
		var obstacles := PackedByteArray()
		obstacles.resize(n)
		obstacles.fill(0)
		var o_off := offset + n * 3
		if offset >= 0 and o_off + n <= data.size():
			for k in range(n):
				obstacles[k] = data[o_off + k]
		result["obstacles"] = obstacles
	if not result.has("structures"):
		result["structures"] = []
	if not result.has("tiles"):
		push_error("AlmLoader: карта без тайлов")
		return {}

	# Byte-виды для AlmMap: byte[0]=вариант|ряд, byte[1]=файл-1
	var tiles: PackedInt32Array = result["tiles"]
	var terrain := PackedByteArray()
	var hflags := PackedByteArray()
	terrain.resize(n)
	hflags.resize(n)
	for j in range(n):
		terrain[j] = tiles[j] & 0xFF
		hflags[j] = (tiles[j] >> 8) & 0xFF
	result["terrain"] = terrain
	result["hflags"] = hflags
	result["offset"] = offset
	result["info"] = {
		"solar_angle": _f32le(data, 0x30) if data.size() >= 0x34 else 0.0,
		"time_of_day": _u32le(data, 0x34) if data.size() >= 0x38 else 0,
		"darkness": _u32le(data, 0x38) if data.size() >= 0x3c else 0,
		"contrast": _u32le(data, 0x3c) if data.size() >= 0x40 else 0,
	}

	print("AlmLoader: %s -> %dx%d, секций %d, структур %d" % [
		path.get_file(), width, height, section_count, int(result["structures"].size())])
	return result

## --- Запись тайлов обратно в .alm (редактор карт) ---

## Перезаписать секцию tiles в существующем файле .alm (raw из load_map).
static func write_tiles(path: String, raw: PackedByteArray, tiles_off: int, tiles: PackedInt32Array) -> bool:
	if tiles_off < 0 or tiles.is_empty():
		push_error("AlmLoader: неверные параметры записи тайлов (off=%d, n=%d)" % [tiles_off, tiles.size()])
		return false
	if tiles_off + tiles.size() * 2 > raw.size():
		push_error("AlmLoader: тайлы выходят за файл")
		return false
	var data := raw.duplicate()
	for j in range(tiles.size()):
		var o := tiles_off + j * 2
		data[o] = tiles[j] & 0xFF
		data[o + 1] = (tiles[j] >> 8) & 0xFF
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("AlmLoader: не открыть для записи: " + path)
		return false
	f.store_buffer(data)
	f.close()
	return true

## Tile id из спеки текстур редактора {file 1-4, variant 0-15, row кадр}.
static func tile_from_spec(spec: Dictionary) -> int:
	var file_n := clampi(int(spec.get("file", 1)), 1, 4)
	var variant := clampi(int(spec.get("variant", 0)), 0, 15)
	var row := clampi(int(spec.get("row", 0)), 0, 15)
	var n := (file_n - 1) * 16 + variant
	return (n << 4) | row