extends Node2D
class_name AlmMap
## Строит игровую карту из .alm: выпекает terrain + высоту + обрывы (объём гор)
## в одну текстуру. Коллизии (вода/барьеры/границы) — через логику движения.

@export var alm_path: String = ""
@export var tile_width: int = 64
@export var tile_height: int = 32
@export var cliff_height: int = 22  # пикселей на уровень высоты

const MAX_HEIGHT := 3

var map_width: int = 0
var map_height: int = 0
var _terrain: PackedByteArray
var _hflags: PackedByteArray
var _height_grid: Array = []   # [y][x] = 0..3

var _ground_images: Array = []  # 16 тайлов земли как Image
var _water_img: Image
var _barrier_img: Image

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
	_load_tile_images()
	_bake_map()
	print("AlmMap: карта %dx%d с объёмом построена" % [map_width, map_height])

func _build_height_grid() -> void:
	_height_grid.clear()
	for y in range(map_height):
		var row := []
		row.resize(map_width)
		for x in range(map_width):
			row[x] = AlmLoader.height_level(_hflags[y * map_width + x])
		_height_grid.append(row)

func _load_tile_images() -> void:
	_ground_images.clear()
	var sets := 4
	var variants := 4
	for s in range(sets):
		for v in range(variants):
			var path := "res://assets/terrain/tiles/tile%d-%02d_00.png" % [s + 1, v]
			_ground_images.append(_tex_to_image(path))
	_water_img = _color_image(Color(0.12, 0.3, 0.6, 1.0))
	_barrier_img = _color_image(Color(0.4, 0.36, 0.3, 1.0))

func _tex_to_image(path: String) -> Image:
	var t := load(path)
	if t:
		return t.get_image()
	return _color_image(Color(0.2, 0.55, 0.15, 1.0))

func _color_image(c: Color) -> Image:
	var img := Image.create(tile_width, tile_height, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img

## Выбрать Image тайла для тайла карты.
func _tile_image_for(x: int, y: int) -> Image:
	var i := y * map_width + x
	var flag := AlmLoader.classify(_hflags[i])
	match flag:
		AlmLoader.TileFlag.WATER:
			return _water_img
		AlmLoader.TileFlag.BARRIER:
			return _barrier_img
		_:
			var t := int(_terrain[i])
			var type_to_set := [2, 2, 3, 0, 0, 1, 1, 3]
			var ttype: int = (t / 32) % 8
			var tileset: int = int(type_to_set[ttype])
			var variant: int = (t % 32) / 8
			return _ground_images[tileset * 4 + variant]

## Выпекание карты: terrain + высота (тайлы выше) + обрывы (скалы снизу).
func _bake_map() -> void:
	var top_margin := MAX_HEIGHT * cliff_height
	var img_w := map_width * tile_width
	var img_h := map_height * tile_height + top_margin
	var canvas := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.05, 0.05, 0.06, 1.0))

	# Сзади наперёд (y возрастает) — передние тайлы перекрывают обрывы задних
	for y in range(map_height):
		for x in range(map_width):
			var h: int = _height_grid[y][x]
			var px := x * tile_width
			var ground_y := top_margin + y * tile_height
			var top_y := ground_y - h * cliff_height
			var tile_img := _tile_image_for(x, y)

			# Обрыв (скала) под возвышенным тайлом
			if h > 0:
				var cliff := Image.create(tile_width, h * cliff_height, false, Image.FORMAT_RGBA8)
				var rock := _rock_color_for(tile_img)
				cliff.fill(rock)
				canvas.blit_rect(cliff, Rect2i(0, 0, tile_width, cliff.get_height()), Vector2i(px, top_y + tile_height))

			# Сам тайл (возвышенный)
			canvas.blit_rect(tile_img, Rect2i(0, 0, tile_width, tile_height), Vector2i(px, top_y))

	var tex := ImageTexture.create_from_image(canvas)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	add_child(sprite)

func _rock_color_for(tile_img: Image) -> Color:
	# Тёмный оттенок нижней строки тайла — цвет скалы
	var y := tile_img.get_height() - 1
	var r := 0.0; var g := 0.0; var b := 0.0
	var step := max(1, tile_img.get_width() / 8)
	var cnt := 0
	for x in range(0, tile_img.get_width(), step):
		var c := tile_img.get_pixel(x, y)
		r += c.r; g += c.g; b += c.b; cnt += 1
	if cnt > 0:
		r /= cnt; g /= cnt; b /= cnt
	return Color(r * 0.5, g * 0.5, b * 0.5, 1.0)

## --- Запросы для движения и миникарты ---

func height_at_tile(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 0
	return _height_grid[ty][tx]

func height_at_world(pos: Vector2) -> int:
	return height_at_tile(int(pos.x) / tile_width, int(pos.y) / tile_height)

func flag_at_world(pos: Vector2) -> int:
	var tx := int(pos.x) / tile_width
	var ty := int(pos.y) / tile_height
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return AlmLoader.TileFlag.BARRIER
	return AlmLoader.classify(_hflags[ty * map_width + tx])

func is_walkable_world(pos: Vector2) -> bool:
	var tx := int(pos.x) / tile_width
	var ty := int(pos.y) / tile_height
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return false
	return AlmLoader.is_walkable(_hflags[ty * map_width + tx])

func is_within_bounds(pos: Vector2, margin: float = 16.0) -> bool:
	var min_x := margin
	var min_y := margin
	var max_x := map_width * tile_width - margin
	var max_y := map_height * tile_height - margin
	return pos.x >= min_x and pos.y >= min_y and pos.x <= max_x and pos.y <= max_y
