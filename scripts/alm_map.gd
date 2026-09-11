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

	# Три типа тайлов: 0=трава(проходима), 1=вода(блок), 2=барьер(блок)
	var grass_tex := _load_tex("res://assets/terrain/tiles/tile1-00_00.png")
	var water_tex := _make_color_tex(Color(0.15, 0.35, 0.7, 1.0))
	var barrier_tex := _make_color_tex(Color(0.35, 0.3, 0.25, 1.0))

	# Физический слой для коллизий
	ts.add_physics_layer()

	var textures := [grass_tex, water_tex, barrier_tex]
	for i in range(3):
		var src := TileSetAtlasSource.new()
		src.texture = textures[i]
		src.texture_region_size = Vector2i(tile_width, tile_height)
		src.create_tile(Vector2i(0, 0))
		# Вода и барьер — непроходимы
		if i >= 1:
			var td := src.get_tile_data(Vector2i(0, 0), 0)
			var poly := PackedVector2Array([
				Vector2(0, 0), Vector2(tile_width, 0),
				Vector2(tile_width, tile_height), Vector2(0, tile_height)
			])
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, poly)
		ts.add_source(src, i)

	tilemap.tile_set = ts

func _fill_tiles() -> void:
	for y in range(map_height):
		for x in range(map_width):
			var hf := _hflags[y * map_width + x]
			var flag := AlmLoader.classify(hf)
			var tile_id := 0  # трава
			match flag:
				AlmLoader.TileFlag.WATER:
					tile_id = 1
				AlmLoader.TileFlag.BARRIER:
					tile_id = 2
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

func _load_tex(path: String) -> Texture2D:
	var t := load(path)
	if t:
		return t
	return _make_color_tex(Color(0.2, 0.55, 0.15, 1.0))

func _make_color_tex(color: Color) -> Texture2D:
	var img := Image.create(tile_width, tile_height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
