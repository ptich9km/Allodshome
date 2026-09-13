extends Node2D
class_name AlmMap
## Карта из .alm: TileMapLayer 32x32 клетки, текстуры terrain из исходников
## (tile1-4 × варианты × ряды). byte[1]=тип, byte[0]=вариант(ниббл)+ряд(>>4).
## Движение блокируется логикой (_can_move_to), не физикой TileMap.

@export var alm_path: String = ""
@export var tile_size := 32

var map_width: int = 0
var map_height: int = 0
var _terrain: PackedByteArray
var _hflags: PackedByteArray
var _height_grid: Array = []
var tilemap: TileMapLayer
var _max_rows: Dictionary = {}   # sid -> число рядов в источнике

func _ready() -> void:
	add_to_group("alm_map")
	if alm_path.is_empty():
		push_warning("AlmMap: alm_path не задан")
		return
	var data := AlmLoader.load_map(alm_path)
	if data.is_empty():
		return
	map_width = data["width"]
	map_height = data["height"]
	_terrain = data["terrain"]
	_hflags = data["hflags"]
	_build_height_grid()
	_build_tilemap()
	print("AlmMap: %s %dx%d клеток %dpx" % [alm_path.get_file(), map_width, map_height, tile_size])

func _build_height_grid() -> void:
	_height_grid.clear()
	for y in range(map_height):
		var row := []
		row.resize(map_width)
		for x in range(map_width):
			# Скалы (тип 3) — уровень 1 (для будущего объёма/замедления)
			row[x] = 1 if AlmLoader.terrain_type(_hflags[y * map_width + x]) == 3 else 0
		_height_grid.append(row)

func _build_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMap"
	add_child(tilemap)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	ts.tile_layout = TileSet.TILE_LAYOUT_STACKED

	# Источники: тип 0-3 -> tile1-4, вариант 0-15 -> файл tileN-XX, каждый файл = атлас рядов
	# Число рядов берём из реальной высоты файла (tile3 короче — 8 рядов)
	for t in range(4):
		var vmax := 16
		if t == 3:
			vmax = 4  # tile4 имеет только 00-03
		for v in range(vmax):
			var path := "res://assets/terrain/tile%d-%02d.bmp" % [t + 1, v]
			var tex: Variant = load(path)
			if tex == null:
				continue
			var nrows: int = tex.get_height() / tile_size
			var src := TileSetAtlasSource.new()
			src.texture = tex
			src.texture_region_size = Vector2i(tile_size, tile_size)
			for r in range(nrows):
				src.create_tile(Vector2i(0, r))
			ts.add_source(src, t * 16 + v)
			_max_rows[t * 16 + v] = nrows

	tilemap.tile_set = ts

	for y in range(map_height):
		for x in range(map_width):
			var i := y * map_width + x
			var tt := AlmLoader.terrain_type(_hflags[i])
			var t := clampi(tt, 0, 3)
			var vmax := 16 if t < 3 else 4
			var variant := clampi(int(_terrain[i]) & 0xF, 0, vmax - 1)
			var sid := t * 16 + variant
			var maxr: int = _max_rows.get(sid, 14)
			var row := clampi(int(_terrain[i]) >> 4, 0, maxr - 1)
			tilemap.set_cell(Vector2i(x, y), sid, Vector2i(0, row))

## --- Запросы для движения и миникарты ---

func height_at_tile(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 0
	return _height_grid[ty][tx]

func height_at_world(pos: Vector2) -> int:
	return height_at_tile(int(pos.x) / tile_size, int(pos.y) / tile_size)

func flag_at_world(pos: Vector2) -> int:
	var tx := int(pos.x) / tile_size
	var ty := int(pos.y) / tile_size
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return AlmLoader.TileFlag.BARRIER
	return AlmLoader.classify(_hflags[ty * map_width + tx])

func is_walkable_world(pos: Vector2) -> bool:
	var tx := int(pos.x) / tile_size
	var ty := int(pos.y) / tile_size
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return false
	return AlmLoader.is_walkable(_hflags[ty * map_width + tx])

func is_within_bounds(pos: Vector2, margin: float = 12.0) -> bool:
	var min_x := margin
	var min_y := margin
	var max_x := map_width * tile_size - margin
	var max_y := map_height * tile_size - margin
	return pos.x >= min_x and pos.y >= min_y and pos.x <= max_x and pos.y <= max_y