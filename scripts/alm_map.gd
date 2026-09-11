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

	# 16 вариантов травы (ряд 00 каждого) + вода + барьер
	var grass_variants := 16
	for i in range(grass_variants):
		var path := "res://assets/terrain/tiles/tile1-%02d_00.png" % i
		var src := TileSetAtlasSource.new()
		src.texture = _load_tex(path)
		src.texture_region_size = Vector2i(tile_width, tile_height)
		src.create_tile(Vector2i(0, 0))
		ts.add_source(src, i)

	# Вода (индекс 16) и барьер (индекс 17) — с коллизией
	var water_tex := _make_color_tex(Color(0.15, 0.35, 0.7, 1.0))
	var barrier_tex := _make_color_tex(Color(0.35, 0.3, 0.25, 1.0))
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
		ts.add_source(src, grass_variants + i)

	tilemap.tile_set = ts

func _fill_tiles() -> void:
	var grass_variants := 16
	for y in range(map_height):
		for x in range(map_width):
			var i := y * map_width + x
			var hf := _hflags[i]
			var flag := AlmLoader.classify(hf)
			var tile_id := int(_terrain[i]) % grass_variants  # вариант травы
			match flag:
				AlmLoader.TileFlag.WATER:
					tile_id = grass_variants      # 16
				AlmLoader.TileFlag.BARRIER:
					tile_id = grass_variants + 1  # 17
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

## В пределах ли карты мировая позиция.
func is_within_bounds(pos: Vector2) -> bool:
	var tx := int(pos.x) / tile_width
	var ty := int(pos.y) / tile_height
	return tx >= 0 and ty >= 0 and tx < map_width and ty < map_height

func _load_tex(path: String) -> Texture2D:
	var t := load(path)
	if t:
		return t
	return _make_color_tex(Color(0.2, 0.55, 0.15, 1.0))

func _make_color_tex(color: Color) -> Texture2D:
	var img := Image.create(tile_width, tile_height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
