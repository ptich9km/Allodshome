class_name CustomMap
extends Node2D
## Карта, созданная в редакторе: JSON, каждая клетка = тип terrain (1:1).
## У каждого типа — НАБОР текстур {file, variant, row}. Клетка хранит тип и
## индекс текстуры в наборе (tex_ids), -1 = первая в наборе.

const TILE := 32
const TYPE_NAMES := ["Трава", "Земля", "Песок", "Вода", "Скала", "Строение", "НПЦ", "Спавн"]
const TYPE_WALKABLE := [true, true, true, false, false, false, true, true]
# Текстуры заливки по умолчанию: {file: tileN, variant: XX, row: ряд}; file=0 -> цвет
const DEFAULT_TEX := {
	0: {"file": 1, "variant": 4, "row": 1},   # трава
	1: {"file": 2, "variant": 4, "row": 1},   # земля
	2: {"file": 1, "variant": 0, "row": 11},  # песок (тёплая строка tile1)
	3: {"file": 3, "variant": 1, "row": 5},   # вода
	4: {"file": 4, "variant": 1, "row": 3},   # скала (tile4 имеет 00-03)
	5: {"file": 0, "color": "8b5a2b"},        # строение (плейсхолдер-цвет)
	6: {"file": 0, "color": "7ec8e3"},        # НПЦ (плейсхолдер-цвет)
	7: {"file": 0, "color": "ffd700"},        # спавн героя (плейсхолдер-цвет)
}

var map_width := 0
var map_height := 0
var tiles: PackedInt32Array    # тип на клетку, -1 = пусто
var tex_ids: PackedInt32Array  # индекс текстуры в наборе типа, -1 = первая
var under_tiles: PackedInt32Array  # земля ПОД объектом (0-4) или -1: объект "стоит" на ней
var texture_sets := {}         # тип -> Array[{file, variant, row}]
var text_spec := {}            # тип -> {file, variant, row} (первая в наборе)
var tilemap: TileMapLayer      # слой земли (типы 0-4)
var object_layer: TileMapLayer # слой объектов (типы 5-7) поверх земли
var objects_root: Node2D       # слой анимированных спрайтов объектов (y-sort)
var map_objects := {}          # клетка (Vector2i) -> MapObject
var spawn_cell := Vector2i(-1, -1)   # клетка спавна героя (тип 7)

# (тип, индекс в наборе) -> source_id в TileSet
var _src_for := {}

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
	_load_tex_ids(json)
	_load_under_tiles(json)
	if json.has("texture_sets"):
		texture_sets = _normalize_sets(json["texture_sets"])
	else:
		texture_sets = _default_sets()
	_sync_text_spec()
	_refresh_spawn()
	_build_tilemap()
	print("CustomMap: %s %dx%d загружена" % [path.get_file(), map_width, map_height])
	return true

func _load_tex_ids(json: Dictionary) -> void:
	tex_ids = PackedInt32Array()
	tex_ids.resize(map_width * map_height)
	tex_ids.fill(-1)
	var raw: Variant = json.get("tex_ids", null)
	if raw is Array and raw.size() == map_width * map_height:
		for i in range(raw.size()):
			tex_ids[i] = int(raw[i])

## Земля под объектами (типы 5-7). У старых карт поля нет — всё -1.
func _load_under_tiles(json: Dictionary) -> void:
	under_tiles = PackedInt32Array()
	under_tiles.resize(map_width * map_height)
	under_tiles.fill(-1)
	var raw: Variant = json.get("under_tiles", null)
	if raw is Array and raw.size() == map_width * map_height:
		for i in range(raw.size()):
			under_tiles[i] = int(raw[i])

func new_map(w: int, h: int) -> void:
	map_width = w
	map_height = h
	tiles = PackedInt32Array()
	tiles.resize(w * h)
	tiles.fill(-1)
	tex_ids = PackedInt32Array()
	tex_ids.resize(w * h)
	tex_ids.fill(-1)
	under_tiles = PackedInt32Array()
	under_tiles.resize(w * h)
	under_tiles.fill(-1)
	texture_sets = _default_sets()
	_sync_text_spec()
	_refresh_spawn()
	_build_tilemap()

## Применить наборы текстур (из настроек редактора или из JSON карты).
func set_texture_sets(sets: Dictionary) -> void:
	texture_sets = _normalize_sets(sets)
	_sync_text_spec()
	# Индексы за пределами новых наборов — сбрасываем на первую текстуру
	for i in range(tex_ids.size()):
		var t := tiles[i]
		if t >= 0 and t < 8 and tex_ids[i] >= 0:
			if tex_ids[i] > _set_size(t) - 1:
				tex_ids[i] = -1
	_build_tilemap()

func _sync_text_spec() -> void:
	text_spec = {}
	for t in range(8):
		var set: Array = texture_sets.get(t, [])
		if set.size() > 0:
			var first: Dictionary = set[0]
			text_spec[t] = first.duplicate(true)
		else:
			var def: Dictionary = DEFAULT_TEX[t]
			text_spec[t] = def.duplicate(true)

func _default_sets() -> Dictionary:
	var sets := {}
	for t in range(8):
		var def: Dictionary = DEFAULT_TEX[t]
		sets[t] = [def.duplicate(true)]
	return sets

func _normalize_sets(sets: Dictionary) -> Dictionary:
	var out := {}
	for t in range(8):
		# JSON превращает int-ключи словаря в строки ("0".."4")
		var arr: Array = []
		if sets.has(t):
			arr = sets[t]
		elif sets.has(str(t)):
			arr = sets[str(t)]
		var clean: Array = []
		for item in arr:
			if item is Dictionary:
				var spec := {}
				spec["file"] = int(item.get("file", 1))
				spec["variant"] = int(item.get("variant", 0))
				spec["row"] = int(item.get("row", 0))
				if item.has("kind"):
					spec["kind"] = str(item["kind"])
				if item.has("obj"):
					spec["obj"] = str(item["obj"])
				if item.has("path"):
					spec["path"] = str(item["path"])
				if item.has("color"):
					spec["color"] = str(item["color"])
				clean.append(spec)
		if clean.is_empty():
			var def: Dictionary = DEFAULT_TEX[t]
			clean.append(def.duplicate(true))
		out[t] = clean
	return out

func _set_size(t: int) -> int:
	var set: Array = texture_sets.get(t, [])
	return set.size()

func tile_id_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return -1
	return tiles[cell.y * map_width + cell.x]

func texture_spec_at(cell: Vector2i) -> Dictionary:
	var t := tile_id_at(cell)
	if t < 0:
		return {}
	var set: Array = texture_sets.get(t, [])
	if set.is_empty():
		return {}
	var idx := -1
	if cell.x >= 0 and cell.y >= 0 and cell.x < map_width and cell.y < map_height:
		idx = tex_ids[cell.y * map_width + cell.x]
	idx = clampi(idx, 0, set.size() - 1)
	return set[idx]

func set_tile(cell: Vector2i, type_id: int, tex_idx: int = -1) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return
	var i := cell.y * map_width + cell.x
	if type_id == -1:
		# Ластик: снять объект -> вернуть землю из-под него; иначе пусто
		if tiles[i] >= 5 and under_tiles[i] >= 0:
			tiles[i] = under_tiles[i]
			under_tiles[i] = -1
			tex_ids[i] = -1
		else:
			tiles[i] = -1
			tex_ids[i] = -1
			under_tiles[i] = -1
	elif type_id >= 5:
		# Объект: запомнить землю под ним (если клетка была землёй)
		if tiles[i] >= 0 and tiles[i] < 5:
			under_tiles[i] = tiles[i]
		else:
			under_tiles[i] = -1
		tiles[i] = type_id
		tex_ids[i] = tex_idx
	else:
		# Земля (0-4): закрашивает всё, включая объект
		tiles[i] = type_id
		tex_ids[i] = tex_idx
		under_tiles[i] = -1
	if type_id == 7:
		spawn_cell = cell
	elif spawn_cell == cell:
		spawn_cell = Vector2i(-1, -1)
	if tilemap:
		_refresh_cell(cell)

## Применить клетку: земля (0-4) внизу, объект (5-7) поверх.
## Объекты с kind=object рендерятся анимированными спрайтами (map_objects).
func _refresh_cell(cell: Vector2i) -> void:
	var i := cell.y * map_width + cell.x
	var t := tiles[i]

	if t >= 0 and t < 5:
		if tilemap:
			tilemap.set_cell(cell, _source_id_for(t, tex_ids[i]), Vector2i(0, 0))
		if object_layer:
			object_layer.erase_cell(cell)
		_remove_map_object(cell)
	elif t >= 5:
		var spec := texture_spec_at(cell)
		var obj_name := ObjectDB.object_name_from_spec(spec)
		if obj_name != "":
			# Объект с анимацией: спрайт поверх, земля из-под него остаётся
			if under_tiles[i] >= 0:
				tilemap.set_cell(cell, _source_id_for(under_tiles[i], -1), Vector2i(0, 0))
			else:
				tilemap.erase_cell(cell)
			object_layer.erase_cell(cell)
			_ensure_map_object(cell, obj_name)
		else:
			# Цветовой плейсхолдер — обычный тайл
			if under_tiles[i] >= 0:
				tilemap.set_cell(cell, _source_id_for(under_tiles[i], -1), Vector2i(0, 0))
			else:
				tilemap.erase_cell(cell)
			object_layer.set_cell(cell, _source_id_for(t, tex_ids[i]), Vector2i(0, 0))
			_remove_map_object(cell)
	else:
		if tilemap:
			tilemap.erase_cell(cell)
		if object_layer:
			object_layer.erase_cell(cell)
		_remove_map_object(cell)

func _source_id_for(type_id: int, tex_idx: int) -> int:
	if type_id < 0 or type_id >= 8:
		return -1
	var idx := clampi(tex_idx, 0, _set_size(type_id) - 1)
	return int(_src_for.get(Vector2i(type_id, idx), -1))

func _build_tilemap() -> void:
	if tilemap == null:
		tilemap = TileMapLayer.new()
		tilemap.name = "TileMap"
		add_child(tilemap)
	if object_layer == null:
		object_layer = TileMapLayer.new()
		object_layer.name = "Objects"
		# Объекты поверх земли
		object_layer.z_index = 5
		add_child(object_layer)
	if objects_root == null:
		objects_root = Node2D.new()
		objects_root.name = "MapObjects"
		objects_root.y_sort_enabled = true
		objects_root.z_index = 6
		add_child(objects_root)

	# Удалить старые спрайты объектов при перестройке
	for cell_key in map_objects.keys():
		var mo: MapObject = map_objects[cell_key]
		if is_instance_valid(mo):
			mo.queue_free()
	map_objects.clear()

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	_src_for = {}
	var src_id := 0
	for t in range(8):
		var set: Array = texture_sets.get(t, [])
		for idx in range(set.size()):
			var spec: Dictionary = set[idx]
			var img := _load_spec_image(spec)
			var src := TileSetAtlasSource.new()
			src.texture = ImageTexture.create_from_image(img)
			src.texture_region_size = Vector2i(TILE, TILE)
			src.create_tile(Vector2i(0, 0))
			ts.add_source(src, src_id)
			_src_for[Vector2i(t, idx)] = src_id
			src_id += 1
	tilemap.tile_set = ts
	object_layer.tile_set = ts

	tilemap.clear()
	object_layer.clear()
	for y in range(map_height):
		for x in range(map_width):
			_refresh_cell(Vector2i(x, y))

## Создать (или обновить) спрайт объекта на клетке.
func _ensure_map_object(cell: Vector2i, obj_name: String) -> void:
	var existing: MapObject = map_objects.get(cell)
	if existing != null and is_instance_valid(existing) and existing.obj_name == obj_name:
		return
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	var mo := MapObject.new()
	var anchor := Vector2.ZERO
	var o := ObjectDB.get_obj(obj_name)
	if not o.is_empty():
		anchor = Vector2(int(o.get("cx", 0)), int(o.get("cy", 0)))
	mo.setup(obj_name, cell, TILE, anchor)
	# Точка якоря (cx,cy) спрайта = центр-низ клетки (объект "стоит" на клетке)
	mo.position = Vector2(cell.x * TILE + TILE / 2, cell.y * TILE + TILE)
	objects_root.add_child(mo)
	map_objects[cell] = mo

func _remove_map_object(cell: Vector2i) -> void:
	var mo: MapObject = map_objects.get(cell)
	if mo == null:
		return
	map_objects.erase(cell)
	if is_instance_valid(mo):
		mo.queue_free()

## Урон по объектам в радиусе от точки (world coords).
func damage_area(world_pos: Vector2, radius: float, dmg: int) -> void:
	for cell_key in map_objects.keys():
		var mo: MapObject = map_objects[cell_key]
		if is_instance_valid(mo) and mo.position.distance_to(world_pos) <= radius:
			mo.take_damage(dmg)

func _load_spec_image(spec: Dictionary) -> Image:
	# Объект карты (map-objects): спрайт вписывается в клетку 32x32
	if str(spec.get("kind", "")) == "object":
		var obj_name := ObjectDB.object_name_from_spec(spec)
		if obj_name != "":
			var path := ObjectDB.frame_path(obj_name, 1)
			var tex: Variant = load(path)
			if tex != null:
				var img: Image = tex.get_image()
				img.convert(Image.FORMAT_RGBA8)
				return _fit_in_cell(img)
	return _load_tile_region(
		int(spec.get("file", 1)), int(spec.get("variant", 0)), int(spec.get("row", 0)),
		str(spec.get("color", "")))

## Вписать спрайт в клетку 32x32 с сохранением пропорций (по центру, прозрачный фон).
func _fit_in_cell(img: Image) -> Image:
	var sw := img.get_width()
	var sh := img.get_height()
	if sw <= 0 or sh <= 0:
		return img
	var scale := minf(float(TILE) / float(sw), float(TILE) / float(sh))
	var nw := maxi(1, int(round(float(sw) * scale)))
	var nh := maxi(1, int(round(float(sh) * scale)))
	var resized: Image = img.duplicate()
	resized.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	var out := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(resized, Rect2i(0, 0, nw, nh), Vector2i((TILE - nw) / 2, TILE - nh))
	return out

func _load_tile_region(file_idx: int, variant: int, row: int, color_hex: String = "") -> Image:
	var file_n := clampi(file_idx, 0, 4)
	if file_n == 0:
		# Плейсхолдер-цвет для строений/НПЦ/спавна
		var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		var c := Color("#8b5a2b")
		if color_hex != "":
			c = Color(color_hex)
		img.fill(c)
		return img
	var vmax := 4 if file_n == 4 else 16  # tile4 имеет только 00-03
	var v := clampi(variant, 0, vmax - 1)
	var path := "res://assets/terrain/tile%d-%02d.bmp" % [file_n, v]
	var tex: Variant = load(path)
	if tex == null:
		var fallback := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		return fallback
	var img2: Image = tex.get_image()
	var nrows: int = img2.get_height() / 32
	var r := clampi(row, 0, nrows - 1)
	var cell: Image = img2.get_region(Rect2i(0, r * 32, 32, 32))
	cell.convert(Image.FORMAT_RGBA8)
	return cell

## Мировая позиция спавна героя (тип 7) или центр карты если не задан.
func get_spawn_pos() -> Vector2:
	if spawn_cell.x >= 0:
		return Vector2(spawn_cell.x * TILE + TILE / 2, spawn_cell.y * TILE + TILE / 2)
	return Vector2(map_width * TILE / 2, map_height * TILE / 2)

## Найти клетку спавна (тип 7) — первая встреченная.
func _refresh_spawn() -> void:
	spawn_cell = Vector2i(-1, -1)
	for i in range(tiles.size()):
		if tiles[i] == 7:
			spawn_cell = Vector2i(i % map_width, i / map_width)
			break

func save_map(path: String) -> bool:
	if map_width == 0:
		return false
	var data := {
		"width": map_width,
		"height": map_height,
		"tiles": Array(tiles),
		"tex_ids": Array(tex_ids),
		"under_tiles": Array(under_tiles),
		"texture_sets": texture_sets,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

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