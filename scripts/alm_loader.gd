class_name AlmLoader
## Парсер карт Allods 2 (.alm) — формат секций по Allods16/UnityAllods.
## 20-байтный заголовок: magic "M7R\0", headersize=0x14, junk, sectioncount, junk.
## Секции: [8 байт junk][size u32][id u32][4 байта junk][данные size].
## id: 0=info 1=tiles(uint16) 2=heights(int8) 3=obstacles(uint8) 4=structures
##     5=players 6=units 7=logic 8=sacks 9=effects 10=groups 11=options 12=music.

const MAGIC := 0x0052374D
const HEADER_SIZE := 0x14

enum TileFlag { GROUND, HILL, HIGH2, WATER, BARRIER }

static func _u32(data: PackedByteArray, off: int) -> int:
	return data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24)

static func _i16(data: PackedByteArray, off: int) -> int:
	var v := data[off] | (data[off + 1] << 8)
	if v >= 0x8000:
		v -= 0x10000
	return v

static func _i32(data: PackedByteArray, off: int) -> int:
	var v := _u32(data, off)
	if v >= 0x80000000:
		v -= 0x100000000
	return v

static func _cstr(data: PackedByteArray, off: int, max_len: int) -> String:
	var end := off
	while end < off + max_len and end < data.size() and data[end] != 0:
		end += 1
	# Строки в .alm — однобайтовая кодировка (cp1251). Имена карт ASCII;
	# читаем как ASCII, чтобы не ловить ошибки UTF-8 от кириллицы.
	return data.slice(off, end).get_string_from_ascii()

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
	if _u32(data, 0) != MAGIC:
		push_error("AlmLoader: неверная магия %08x" % _u32(data, 0))
		return {}

	var section_count := _u32(data, 0x0c)
	if section_count < 3:
		push_error("AlmLoader: секций слишком мало: %d" % section_count)
		return {}

	var result := {}
	var width := 0
	var height := 0
	var info_ok := false
	result["raw"] = data
	result["tiles_off"] = -1

	var off := HEADER_SIZE
	for i in range(section_count):
		if off + 20 > data.size():
			break
		var sec_size := _u32(data, off + 8)
		var sec_id := _u32(data, off + 12)
		var ds := off + 20
		if ds + sec_size > data.size():
			push_warning("AlmLoader: секция %d выходит за файл (size=%d)" % [sec_id, sec_size])
			break
		match sec_id:
			0:
				width = _u32(data, ds)
				height = _u32(data, ds + 4)
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

	if not (result.has("tiles") and result.has("structures")):
		push_error("AlmLoader: карта без тайлов/структур")
		return {}
	print("AlmLoader: %s -> %dx%d, секций %d, структур %d" % [
		path.get_file(), width, height, section_count, int(result.get("structures", []).size())])
	return result

## Секция structures: X(4) Y(4) TypeID(4) Health(2) Player(4) ID(2); мост +W(4) H(4).
static func _read_structures(data: PackedByteArray, ds: int, size: int) -> Array:
	var out: Array = []
	var o := ds
	var end := ds + size
	while o + 20 <= end:
		var xraw := _u32(data, o)
		var yraw := _u32(data, o + 4)
		var tid := _u32(data, o + 8)
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
			# Мост: ширина/высота в клетках (после ID)
			rec["bw"] = _u32(data, o)
			rec["bh"] = _u32(data, o + 4)
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
		var xraw := _u32(data, o)
		var yraw := _u32(data, o + 4)
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

## --- Запись тайлов обратно в .alm ---

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

## --- Классификация тайлов по tile id (uint16) ---

## Номер файла тайла (0..51): tile{(n>>4)+1}-{(n&0xF):02}.bmp; 0x20..0x2F = вода (tile3).
static func tile_file(tile: int) -> int:
	return (tile & 0xFF0) >> 4

## Тип terrain 0..3: 0=tile1(трава) 1=tile2(горы) 2=tile3(вода) 3=tile4(дорога).
static func terrain_type(tile: int) -> int:
	return (tile & 0xFF0) >> 8  # tile_file() / 16

## Кадр внутри атласа тайла (0..15, вода анимируется).
static func tile_frame(tile: int) -> int:
	return tile & 0xF

## Проходимость: трава (tile1) и дорога (tile4) — проход; горы/вода — барьер.
static func is_walkable_type(t: int) -> bool:
	return t == 0 or t == 3

static func classify(tile: int) -> int:
	var t := terrain_type(tile)
	if t == 2:
		return TileFlag.WATER
	elif t == 1:
		return TileFlag.HILL  # горы — непроходимый рельеф
	elif t == 3:
		return TileFlag.GROUND  # дорога
	return TileFlag.GROUND