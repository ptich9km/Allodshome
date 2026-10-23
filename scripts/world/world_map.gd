# ============================================================================
# WorldMap — статическая топология мира 4x3 (12 секторов).
#
# БЕЗ autoload и БЕЗ class_name: файл читается load()-по-пути, как world_state.gd
# (headless-canon: глобальный кеш классов в autoload не резолвится).
#
# Данные — assets/world/world_map.json. Здесь только вычисления:
# соседи по стороне, тир, размер, основа/рельеф, сид сектора.
# ============================================================================

const DATA_PATH := "res://assets/world/world_map.json"

static var _data: Dictionary = {}

static func reset_cache() -> void:
	_data = {}

static func _load() -> Dictionary:
	if not _data.is_empty():
		return _data
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("WorldMap: нет %s" % DATA_PATH)
		_data = {"sectors": {}, "start": "", "center": ""}
		return _data
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("WorldMap: %s не читается как JSON" % DATA_PATH)
		_data = {"sectors": {}, "start": "", "center": ""}
		return _data
	_data = parsed as Dictionary
	return _data

static func sectors() -> Dictionary:
	return _load().get("sectors", {}) as Dictionary

static func ids() -> Array:
	var out: Array = []
	for id in sectors().keys():
		out.append(str(id))
	out.sort_custom(func(a: String, b: String) -> bool:
		var sa: Dictionary = sector(a)
		var sb: Dictionary = sector(b)
		if int(sa.get("row", 0)) != int(sb.get("row", 0)):
			return int(sa.get("row", 0)) < int(sb.get("row", 0))
		return int(sa.get("col", 0)) < int(sb.get("col", 0))
	)
	return out

static func has(id: String) -> bool:
	return sectors().has(id)

static func sector(id: String) -> Dictionary:
	return sectors().get(id, {}) as Dictionary

static func start_id() -> String:
	return str(_load().get("start", "s41"))

static func center_id() -> String:
	return str(_load().get("center", "s22"))

static func tier_of(id: String) -> String:
	return str(sector(id).get("tier", "hard"))

static func size_of(id: String) -> int:
	return int(sector(id).get("size", 192))

static func base_of(id: String) -> String:
	return str(sector(id).get("base", "soil"))

static func relief_of(id: String) -> String:
	return str(sector(id).get("relief", "plains"))

static func is_capital(id: String) -> bool:
	return bool(sector(id).get("capital", false))

static func capital_ids() -> Array:
	var out: Array = []
	for id in ids():
		if is_capital(str(id)):
			out.append(str(id))
	return out

## id соседа по стороне: N/S/E/W. Пустая строка, если клетки нет.
static func neighbor_at(id: String, dir: String) -> String:
	var s := sector(id)
	if s.is_empty():
		return ""
	var col := int(s.get("col", 0))
	var row := int(s.get("row", 0))
	match dir:
		"N": row -= 1
		"S": row += 1
		"W": col -= 1
		"E": col += 1
		_: return ""
	for other in sectors().keys():
		var o: Dictionary = sector(str(other))
		if int(o.get("col", 0)) == col and int(o.get("row", 0)) == row:
			return str(other)
	return ""

## Соседи только по сторонам, стабильный порядок N,E,S,W.
static func neighbors(id: String) -> Array:
	var out: Array = []
	for dir in ["N", "E", "S", "W"]:
		var n := neighbor_at(id, dir)
		if n != "":
			out.append(n)
	return out

## Направление от одного сектора к соседнему. Пусто, если не соседи по стороне.
static func dir_of(from_id: String, to_id: String) -> String:
	for dir in ["N", "E", "S", "W"]:
		if neighbor_at(from_id, dir) == to_id:
			return dir
	return ""

## Детерминированный сид сектора. FNV-1a по строке "world|id": не зависит от
## порядка вызовов и не использует глобальный RNG.
static func seed_of(world_seed: int, id: String) -> int:
	var h: int = 2166136261
	var text := "%d|%s" % [world_seed, id]
	for i in range(text.length()):
		h = h ^ text.unicode_at(i)
		h = (h * 16777619) & 0x7FFFFFFF
	if h == 0:
		h = 1
	return h

## Сектор по тиру для старых вызовов (start/mid/hard/faction).
static func sector_for_tier(tier: String) -> String:
	if tier == "start":
		return start_id()
	for id in ids():
		if tier_of(str(id)) == tier:
			return str(id)
	return start_id()

static func all_capital_or_error() -> Array:
	var caps := capital_ids()
	if caps.size() != 4:
		push_error("WorldMap: столиц %d, ожидалось 4" % caps.size())
	return caps
