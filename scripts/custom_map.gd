class_name CustomMap
extends Node2D
## Карта, созданная в редакторе: JSON, каждая клетка = тип terrain (1:1).
## Никакого автайлинга — что нарисовано, то и отображается.

const TILE := 32
const TYPE_NAMES := ["Трава", "Земля", "Песок", "Вода", "Скала"]
const TYPE_WALKABLE := [true, true, true, false, false]
# Текстуры заливки по умолчанию: {file: tileN, variant: XX, row: ряд}
const DEFAULT_TEX := {
	0: {"file": 1, "variant": 4, "row": 1},   # трава
	1: {"file": 2, "variant": 4, "row": 1},   # земля
	2: {"file": 1, "variant": 0, "row": 11},  # песок (тёплая строка tile1)
	3: {"file": 3, "variant": 1, "row": 5},   # вода
	4: {"file": 4, "variant": 5, "row": 3},   # скала
}

var map_width := 0
var map_height := 0
var tiles: PackedInt32Array    # тип на клетку, -1 = пусто
var text_spec := {}            # тип -> {file, variant, row}
var tilemap: TileMapLayer

func _ready() -> void:
	add_to_group("alm_map")
	if map_file != "":
		load_map(map_file)

var map_file := ""

func load_map(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CustomMap: не открыть " + path)
		return false
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is not Dictionary:
		push_error("CustomMap: битый JSON")
		return false
	map_width = int(json.get("width", 0))
	map_height = int(json.get("height", 0))
	var raw: Array = json.get("tiles", [])
	if map_width <= 0 or map_height <= 0 or raw.size() != map_width * map_height:
		push_error("CustomMap: неверные размеры/данные")
		return false
	tiles = PackedInt32Array()
	tiles.resize(raw.size())
	for i in range(raw.size()):
		tiles[i] = int(raw[i])
	text_spec = json.get("textures", DEFAULT_TEX.duplicate(true))
	_build_tilemap()
	print("CustomMap: %s %dx%d загружена" % [path.get_file(), map_width, map_height])
	return true

func new_map(w: int, h: int) -> void:
	map_width = w
	map_height = h
	tiles = PackedInt32Array()
	tiles.resize(w * h)
	tiles.fill(-1)
	text_spec = DEFAULT_TEX.duplicate(true)
	_build_tilemap()

func save_map(path: String) -> bool:
	if map_width == 0:
		return false
	var data := {
		"width": map_width,
		"height": map_height,
		"tiles": Array(tiles),
		"textures": text_spec,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

func tile_id_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return -1
	return tiles[cell.y * map_width + cell.x]

func set_tile(cell: Vector2i, type_id: int) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return
	tiles[cell.y * map_width + cell.x] = type_id
	if tilemap:
		tilemap.set_cell(cell, _source_id(type_id), Vector2i(0, 0))

func _source_id(type_id: int) -> int:
	# -1 = нет источника (-1 в TileSetLayer = стереть)
	return type_id

func _build_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMap"
	add_child(tilemap)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	for t in range(5):
		var spec: Dictionary = text_spec.get(t, {})
		var file_idx: int = int(spec.get("file", DEFAULT_TEX.get(t, {}).get("file", 1)))
		var variant: int = int(spec.get("variant", 0))
		var row: int = int(spec.get("row", 0))
		var img := _load_tile_region(file_idx, variant, row)
		if img == null:
			continue
		var src := TileSetAtlasSource.new()
		src.texture = ImageTexture.create_from_image(img)
		src.texture_region_size = Vector2i(TILE, TILE)
		src.create_tile(Vector2i(0, 0))
		ts.add_source(src, t)
	tilemap.tile_set = ts

	for y in range(map_height):
		for x in range(map_width):
			var t := tiles[y * map_width + x]
			if t >= 0:
				tilemap.set_cell(Vector2i(x, y), t, Vector2i(0, 0))

func _load_tile_region(file_idx: int, variant: int, row: int) -> Image:
	var v := clampi(variant, 0, 15)
	var path := "res://assets/terrain/tile%d-%02d.bmp" % [clampi(file_idx, 1, 4), v]
	var tex: Variant = load(path)
	if tex == null:
		var fallback := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		return fallback
	var img: Image = tex.get_image()
	var nrows: int = img.get_height() / 32
	var r := clampi(row, 0, nrows - 1)
	var cell: Image = img.get_region(Rect2i(0, r * 32, 32, 32))
	cell.convert(Image.FORMAT_RGBA8)
	return cell

## --- Интерфейс для движения ---

func height_at_tile(tx: int, ty: int) -> int:
	return 0

func height_at_world(pos: Vector2) -> int:
	return 0

func flag_at_world(pos: Vector2) -> int:
	return AlmLoader.TileFlag.GROUND

func is_walkable_world(pos: Vector2) -> bool:
	var cell := Vector2i(int(pos.x) / TILE, int(pos.y) / TILE)
	var t := tile_id_at(cell)
	if t < 0 or t >= TYPE_WALKABLE.size():
		return false
	return TYPE_WALKABLE[t]

func tile_size() -> int:
	return TILE

func is_within_bounds(pos: Vector2, margin: float = 12.0) -> bool:
	var min_x := margin
	var min_y := margin
	var max_x := map_width * TILE - margin
	var max_y := map_height * TILE - margin
	return pos.x >= min_x and pos.y >= min_y and pos.x <= max_x and pos.y <= max_y