extends Node2D
class_name AlmMap
## Строит игровую карту из .alm файла: TileMap (terrain) + коллизии (вода/барьеры)
## + сетка высот для замедления на подъёме и изменения обзора.

@export var alm_path: String = ""
@export var tile_width: int = 64
@export var tile_height: int = 32

var map_width: int = 0
var map_height: int = 0
var _terrain: PackedByteArray
var _hflags: PackedByteArray
var _height_grid: Array = []   # [y][x] = уровень высоты 0..3

@onready var tilemap: TileMapLayer = $TileMap

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
	_build_tileset()
	_fill_tiles()
	print("AlmMap: карта %dx%d построена" % [map_width, map_height])

func _build_height_grid() -> void:
	_height_grid.clear()
	for y in range(map_height):
		var row := []
		row.resize(map_width)
		for x in range(map_width):
			row[x] = AlmLoader.height_level(_hflags[y * map_width + x])
		_height_grid.append(row)

func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_width, tile_height)
	ts.tile_layout = TileSet.TILE_LAYOUT_STACKED
	ts.add_physics_layer()

	# 4 тайлсета × 4 варианта = 16 тайлов земли (когерентные регионы)
	# tileset = terrain_byte // 32, variant = terrain_byte % 4
	var sets := 4
	var variants := 4
	for s in range(sets):
		for v in range(variants):
			var path := "res://assets/terrain/tiles/tile%d-%02d_00.png" % [s + 1, v]
			var src := TileSetAtlasSource.new()
			src.texture = _load_tex(path)
			src.texture_region_size = Vector2i(tile_width, tile_height)
			src.create_tile(Vector2i(0, 0))
			ts.add_source(src, s * variants + v)

	# Вода (16) и барьер (17) — с коллизией
	var water_tex := _make_color_tex(Color(0.12, 0.3, 0.6, 1.0))
	var barrier_tex := _make_color_tex(Color(0.32, 0.28, 0.24, 1.0))
	for i in range(2):
		var src := TileSetAtlasSource.new()
		src.texture = water_tex if i == 0 else barrier_tex
		src.texture_region_size = Vector2i(tile_width, tile_height)
		src.create_tile(Vector2i(0, 0))
		var td := src.get_tile_data(Vector2i(0, 0), 0)
		var poly := PackedVector2Array([
			Vector2(0, 0), Vector2(tile_width, 0),
			Vector2(tile_width, tile_height), Vector2(0, tile_height)
		])
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, poly)
		ts.add_source(src, sets * variants + i)

	tilemap.tile_set = ts

func _fill_tiles() -> void:
	var sets := 4
	var variants := 4
	var ground_count := sets * variants  # 16
	# 8 типов terrain (byte[0]//32) -> 4 тайлсета. Доминирующие типы -> разные тайлсеты.
	var type_to_set := [2, 2, 3, 0, 0, 1, 1, 3]
	for y in range(map_height):
		for x in range(map_width):
			var i := y * map_width + x
			var hf := _hflags[i]
			var flag := AlmLoader.classify(hf)
			var tile_id: int
			match flag:
				AlmLoader.TileFlag.WATER:
					tile_id = ground_count      # 16
				AlmLoader.TileFlag.BARRIER:
					tile_id = ground_count + 1  # 17
				_:
					# Когерентный terrain: тип по //32 (связные регионы),
					# вариант по переходному значению (плавные края)
					var t := int(_terrain[i])
					var ttype := (t / 32) % 8
					var tileset := type_to_set[ttype]
					var variant := (t % 32) / 8
					tile_id = tileset * variants + variant
			tilemap.set_cell(Vector2i(x, y), tile_id, Vector2i(0, 0))

## Уровень высоты тайла (0..3) для замедления/обзора.
func height_at_tile(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 0
	return _height_grid[ty][tx]

## Уровень высоты по мировой позиции.
func height_at_world(pos: Vector2) -> int:
	var tx := int(pos.x) / tile_width
	var ty := int(pos.y) / tile_height
	return height_at_tile(tx, ty)

func is_walkable_world(pos: Vector2) -> bool:
	var tx := int(pos.x) / tile_width
	var ty := int(pos.y) / tile_height
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return false
	return AlmLoader.is_walkable(_hflags[ty * map_width + tx])

## В пределах ли карты мировая позиция (с отступом на радиус персонажа).
func is_within_bounds(pos: Vector2, margin: float = 16.0) -> bool:
	var min_x := margin
	var min_y := margin
	var max_x := map_width * tile_width - margin
	var max_y := map_height * tile_height - margin
	return pos.x >= min_x and pos.y >= min_y and pos.x <= max_x and pos.y <= max_y

func _load_tex(path: String) -> Texture2D:
	var t := load(path)
	if t:
		return t
	return _make_color_tex(Color(0.2, 0.55, 0.15, 1.0))

func _make_color_tex(color: Color) -> Texture2D:
	var img := Image.create(tile_width, tile_height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
