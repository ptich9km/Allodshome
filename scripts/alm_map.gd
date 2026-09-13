extends Node2D
class_name AlmMap
## Строит карту из .alm: terrain по ТИПУ (byte[1]) с правильными текстурами
## из исходников (tile1-4), вода (tile3), скалы (tile4, непроходимые), обрывы.

@export var alm_path: String = ""
@export var tile_width: int = 64
@export var tile_height: int = 32
@export var cliff_height: int = 22

const MAX_HEIGHT := 1
const TERRAIN_DIR := "res://assets/terrain/tiles/"

var map_width: int = 0
var map_height: int = 0
var _terrain: PackedByteArray   # byte[0] — вариант автайла
var _hflags: PackedByteArray    # byte[1] — тип terrain
var _height_grid: Array = []    # [y][x] — 0/1 (скалы приподняты)

# Кэш текстур: key = "type_variant_row" -> Image 64x32
var _tile_cache: Dictionary = {}

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
	_bake_map()
	print("AlmMap: %s %dx%d построена" % [alm_path.get_file(), map_width, map_height])

func _build_height_grid() -> void:
	_height_grid.clear()
	for y in range(map_height):
		var row := []
		row.resize(map_width)
		for x in range(map_width):
			row[x] = AlmLoader.height_level(_hflags[y * map_width + x])
		_height_grid.append(row)

## Получить текстуру тайла 64x32: тип -> tileN-XX.bmp, ряд из byte[0]>>4.
func _tile_image_for(x: int, y: int) -> Image:
	var i := y * map_width + x
	var t := AlmLoader.terrain_type(_hflags[i])
	if t == -1:
		t = 2  # вода
	elif t == -2:
		t = 3  # барьер -> скала
	var variant := int(_terrain[i]) & 0xF
	var row := int(_terrain[i]) >> 4
	var key := "%d_%d_%d" % [t, variant, row]
	if _tile_cache.has(key):
		return _tile_cache[key]
	var img := _load_tile(t, variant, row)
	_tile_cache[key] = img
	return img

## Загрузить tile{d}-{variant:02d}.bmp и вырезать ряд row (32x32 -> 64x32).
## Тип 0->tile1, 1->tile2, 2->tile3(вода), 3->tile4(скала).
func _load_tile(t: int, variant: int, row: int) -> Image:
	var file_idx := clampi(t + 1, 1, 4)
	var v := clampi(variant, 0, 15)
	var file := "res://assets/terrain/tile%d-%02d.bmp" % [file_idx, v]
	var img := _tex_to_image(file)
	var rows := img.get_height() / 32
	var r := clampi(row, 0, rows - 1)
	var cell := img.get_region(Rect2i(0, r * 32, 32, 32))
	cell.resize(64, 32, Image.INTERPOLATE_NEAREST)
	return cell

## Выпекание: terrain + обрывы скал (там где тип 3 выше следующего ряда).
func _bake_map() -> void:
	var top_margin := MAX_HEIGHT * cliff_height
	var img_w := map_width * tile_width
	var img_h := map_height * tile_height + top_margin
	var canvas := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.05, 0.05, 0.06, 1.0))

	for y in range(map_height):
		for x in range(map_width):
			var h: int = _height_grid[y][x]
			var px := x * tile_width
			var ground_y := top_margin + y * tile_height
			var top_y := ground_y - h * cliff_height
			var tile_img := _tile_image_for(x, y)

			# Обрыв под скалой: виден где следующий ряд ниже
			var cliff_face := 0
			if y + 1 < map_height:
				var h_next: int = _height_grid[y + 1][x]
				if h > h_next:
					var next_top := top_margin + (y + 1) * tile_height - h_next * cliff_height
					cliff_face = (top_y + tile_height) - next_top
			if cliff_face > 0:
				var cliff := Image.create(64, cliff_face, false, Image.FORMAT_RGBA8)
				var rock := _rock_color_for(tile_img)
				cliff.fill(rock)
				canvas.blit_rect(cliff, Rect2i(0, 0, 64, cliff_face), Vector2i(px, top_y + tile_height - cliff_face))

			canvas.blit_rect(tile_img, Rect2i(0, 0, tile_width, tile_height), Vector2i(px, top_y))

	var tex := ImageTexture.create_from_image(canvas)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = Vector2(0, -top_margin)
	add_child(sprite)

func _rock_color_for(tile_img: Image) -> Color:
	var y := tile_img.get_height() - 1
	var r := 0.0; var g := 0.0; var b := 0.0
	var step: int = maxi(1, tile_img.get_width() / 8)
	var cnt := 0
	for x in range(0, tile_img.get_width(), step):
		var c: Color = tile_img.get_pixel(x, y)
		r += c.r; g += c.g; b += c.b; cnt += 1
	if cnt > 0:
		r /= cnt; g /= cnt; b /= cnt
	return Color(r * 0.45, g * 0.45, b * 0.45, 1.0)

func _tex_to_image(path: String) -> Image:
	var t := load(path)
	if t:
		return t.get_image()
	return Image.create_empty(32, 448, false, Image.FORMAT_RGBA8)

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