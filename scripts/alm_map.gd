extends Node2D
class_name AlmMap
## Карта из .alm: секции info/tiles/heights/obstacles + structures (здания).
## Тайлы — tile id (uint16): файл tile{1-4}-XX.bmp, кадр = tile&0xF.
## Здания (секция id=4) — кадры house-NNN.png из assets/structures/<папка>/.
## Дороги (tile4) дают ускорение; горы (tile2) и вода (tile3) — барьер.

@export var alm_path: String = ""
@export var tile_px := 32

var map_width: int = 0
var map_height: int = 0
var _tiles: PackedInt32Array = PackedInt32Array()
var _heights: PackedByteArray = PackedByteArray()
var _obstacles: PackedByteArray = PackedByteArray()
var _structures: Array = []
var _height_grid: Array = []
var tilemap: TileMapLayer
var buildings: Node2D          # слой зданий (спрайты)
var obstacles_root: Node2D     # слой препятствий (деревья/камни/ограды)
var _max_rows: Dictionary = {} # sid -> число рядов в атласе тайла
var barrier_cells := {}        # клетки, заблокированные зданиями/растительностью
var _structure_hits: Array = [] # хитбоксы зданий {x0,x1,y0,y1,picture,type_id}

## Множитель скорости: дорога (tile4) = 1.5, обычная = 1.0.
const ROAD_SPEED := 1.5

## Совместимость с CustomMap: размер клетки в пикселях.
func tile_size() -> int:
	return tile_px

func _ready() -> void:
	add_to_group("alm_map")
	_build()

## Путь к карте: явный alm_path, либо последняя карта, открытая в редакторе
## (user://last_alm_path.txt), либо kids3.alm по умолчанию.
func _effective_alm_path() -> String:
	if not alm_path.is_empty():
		return alm_path
	var p := "user://last_alm_path.txt"
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null:
			var saved := f.get_as_text().strip_edges()
			f.close()
			if saved != "" and FileAccess.file_exists(saved):
				return saved
	return "res://assets/maps/kids3.alm"

func _build() -> void:
	var path := _effective_alm_path()
	var data := AlmLoader.load_map(path)
	if data.is_empty():
		return
	map_width = data["width"]
	map_height = data["height"]
	_tiles = data["tiles"]
	_heights = data.get("heights", PackedByteArray())
	_obstacles = data.get("obstacles", PackedByteArray())
	_structures = data.get("structures", [])
	_build_height_grid()
	_collect_barriers()
	_build_tilemap()
	_build_structures()
	_build_obstacles()
	print("AlmMap: %s %dx%d, структур %d" % [path.get_file(), map_width, map_height, _structures.size()])

## Высоты (int8 signed).
func _build_height_grid() -> void:
	_height_grid = []
	if _heights.size() != map_width * map_height:
		return
	for y in range(map_height):
		var row: Array = []
		row.resize(map_width)
		for x in range(map_width):
			var v := _heights[y * map_width + x]
			row[x] = v if v < 128 else v - 256
		_height_grid.append(row)

## Заблокированные клетки: растительность (obstacles>0) + площадь зданий.
func _collect_barriers() -> void:
	barrier_cells = {}
	var n := map_width * map_height
	if _obstacles.size() == n:
		for i in range(n):
			if _obstacles[i] > 0:
				barrier_cells[Vector2i(i % map_width, i / map_width)] = true

func _build_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMap"
	add_child(tilemap)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)
	ts.tile_layout = TileSet.TILE_LAYOUT_STACKED

	# Источники: файл 0..51 -> tile{(n>>4)+1}-{(n&0xF):02}.bmp, внутри — ряды-кадры
	for n in range(52):
		var path := "res://assets/terrain/tile%d-%02d.bmp" % [n / 16 + 1, n % 16]
		var tex: Variant = load(path)
		if tex == null:
			continue
		var nrows: int = tex.get_height() / tile_px
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(tile_px, tile_px)
		for r in range(nrows):
			src.create_tile(Vector2i(0, r))
		ts.add_source(src, n)
		_max_rows[n] = nrows

	tilemap.tile_set = ts

	for y in range(map_height):
		for x in range(map_width):
			var tile := _tiles[y * map_width + x] if _tiles.size() > 0 else 0
			var n := AlmLoader.tile_file(tile)
			if not _max_rows.has(n):
				continue
			var maxr: int = _max_rows[n]
			var frame := clampi(AlmLoader.tile_frame(tile), 0, maxr - 1)
			tilemap.set_cell(Vector2i(x, y), n, Vector2i(0, frame))

## Здания из секции id=4: спрайты assets/structures/<папка>/house-NNN.png.
## Сетка кадров 32x32: fw=TileWidth, fh=FullHeight; верхние (fh-th) рядов — выше земли.
func _build_structures() -> void:
	buildings = Node2D.new()
	buildings.name = "Buildings"
	buildings.y_sort_enabled = true
	buildings.z_index = 5
	add_child(buildings)

	var placed := 0
	var missing := 0
	for st in _structures:
		var type_id := int(st.get("type_id", 0))
		var x: float = st.get("x", 0.0)
		var y: float = st.get("y", 0.0)
		if type_id <= 0:
			continue
		var fj := _structure_frame_job(type_id, st)
		if fj.is_empty():
			missing += 1
			continue
		var node := _make_structure(fj)
		if node == null:
			missing += 1
			continue
		# Позиция: клетка (X, Y) = левый-нижний угол корпуса; верх поднят на (fh-th) клеток
		var dir := int(fj.get("fh", 1)) - int(fj.get("th", 1))
		node.position = Vector2(x * tile_px, (y - dir) * tile_px)
		buildings.add_child(node)
		placed += 1
		# Хитбокс здания в клетках (корпус th рядов + верхние (fh-th) визуальные ряды)
		var fw := int(fj.get("fw", 1))
		var th := int(fj.get("th", 1))
		var fh := int(fj.get("fh", th))
		_structure_hits.append({
			"x0": int(x), "x1": int(x) + fw - 1,
			"y0": int(y) - (fh - th), "y1": int(y) + th - 1,
			"picture": str(fj.get("picture", "")),
			"type_id": type_id,
		})
	print("AlmMap: зданий создано %d, пропущено %d" % [placed, missing])

## Растительность и декорации из секции id=3 (obstacles): байт на клетку = тип
## объекта (+1). Спавним анимированные MapObject из assets/map-objects.
func _build_obstacles() -> void:
	obstacles_root = Node2D.new()
	obstacles_root.name = "Obstacles"
	obstacles_root.y_sort_enabled = true
	obstacles_root.z_index = 4
	add_child(obstacles_root)

	if _obstacles.size() != map_width * map_height:
		return
	_load_object_registry()
	var placed := 0
	var missing := 0
	for i in range(_obstacles.size()):
		var b := _obstacles[i]
		if b <= 0:
			continue
		var tid := b - 1  # в .alm ID объекта записан со сдвигом +1
		var folder := str(_obstacle_folders.get(tid, ""))
		if folder.is_empty() or not ObjectDB.has(folder):
			missing += 1
			continue
		var cell := Vector2i(i % map_width, i / map_width)
		var o := ObjectDB.get_obj(folder)
		var anchor := Vector2(int(o.get("cx", 0)), int(o.get("cy", 0)))
		var mo := MapObject.new()
		mo.setup(folder, cell, tile_px, anchor)
		mo.position = Vector2(cell.x * tile_px + tile_px / 2, cell.y * tile_px + tile_px)
		obstacles_root.add_child(mo)
		placed += 1
	print("AlmMap: препятствий создано %d, пропущено %d" % [placed, missing])

## Реестр объектов из assets/map-objects/objects.txt: obstacle typeId -> папка.
var _obstacle_folders := {}
var _object_registry_loaded := false
func _load_object_registry() -> void:
	if _object_registry_loaded:
		return
	_object_registry_loaded = true
	var f := FileAccess.open("res://assets/map-objects/objects.txt", FileAccess.READ)
	if f == null:
		push_warning("AlmMap: не открыть objects.txt")
		return
	var txt := f.get_as_text()
	f.close()

	var files := {}
	# object Files { string File0 = "папка\\sprites" ... }
	var files_match := RegEx.new()
	files_match.compile("object\\s+Files\\s*\\{([^}]*)\\}")
	var fm := files_match.search(txt)
	if fm:
		var file_lines := fm.get_string(1).split("\n")
		for line in file_lines:
			var t: String = line.strip_edges()
			var parts := t.split("=", true, 1)
			if parts.size() < 2 or not parts[0].strip_edges().begins_with("string File"):
				continue
			var idx_str := parts[0].strip_edges().trim_prefix("string File")
			var idx := int(idx_str.strip_edges())
			var dir_path := parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
			files[idx] = dir_path.split("\\")[0]  # "pine1\sprites" -> "pine1"

	# object ObjectN { int ID = X, int File = Y, ... } — связываем ID с File
	var obj_re := RegEx.new()
	obj_re.compile("object\\s+Object\\d+\\s*\\{([^}]*)\\}")
	for om_ in obj_re.search_all(txt):
		var body := om_.get_string(1)
		var id_v := -1
		var file_v := -1
		for line in body.split("\n"):
			var t: String = line.strip_edges()
			if not t.contains("="):
				continue
			var parts := t.split("=", true, 1)
			var key := parts[0].strip_edges()
			var key_last := key.split(" ", false)[-1]
			var val := parts[1].strip_edges()
			if key_last == "ID":
				id_v = int(val)
			elif key_last == "File":
				file_v = int(val)
		if id_v >= 0 and files.has(file_v):
			_obstacle_folders[id_v] = files[file_v]
	print("AlmMap: реестр объектов: %d файлов, %d связей ID->папка" % [files.size(), _obstacle_folders.size()])

## Собрать Node2D-здание из кадров house-001.. под TypeID.
func _make_structure(job: Dictionary) -> Node2D:
	var node := Node2D.new()
	var fw := int(job["fw"])
	var fh := int(job["fh"])
	var dir_name := str(job["dir"])
	var prefix := str(job.get("prefix", "house"))
	for ly in range(fh):
		for lx in range(fw):
			var idx := fw * ly + lx
			var path := "res://assets/structures/%s/%s-%03d.png" % [dir_name, prefix, idx + 1]
			var tex: Variant = load(path)
			if tex == null:
				continue
			var s := Sprite2D.new()
			s.texture = tex
			s.position = Vector2(lx * tile_px, ly * tile_px)
			node.add_child(s)
	return node

## Описание здания: папка/префикс кадров, сетка fw x fh (из structures.txt).
var _structure_jobs := {}
func _structure_frame_job(type_id: int, st: Dictionary) -> Dictionary:
	if _structure_jobs.has(type_id):
		var cached: Dictionary = _structure_jobs[type_id]
		return cached
	var def := _structure_def(type_id)
	if def.is_empty():
		_structure_jobs[type_id] = {}
		return {}
	var parts := str(def.get("file", "")).split("\\")
	var dir_name := (parts[0] if parts.size() > 0 else "").to_lower()
	if dir_name.is_empty():
		_structure_jobs[type_id] = {}
		return {}
	# File = "hut1\\house" — двойной backslash (экранирование reg); префикс = последний элемент
	var prefix := parts[parts.size() - 1] if parts.size() > 1 else "house"
	if prefix.is_empty():
		prefix = "house"
	var fw := int(def.get("tile_width", 1))
	var th := int(def.get("tile_height", 1))
	var fh := int(def.get("full_height", th))
	var job := {
		"dir": dir_name, "prefix": prefix, "fw": fw, "th": th, "fh": fh,
		"picture": str(def.get("picture", "")),
	}
	_structure_jobs[type_id] = job
	return job

## Здание под курсором (клетка cell) — для ховера; возвращает Dictionary или {}.
func structure_at(cell: Vector2i) -> Dictionary:
	for h in _structure_hits:
		if cell.x >= int(h["x0"]) and cell.x <= int(h["x1"]) \
				and cell.y >= int(h["y0"]) and cell.y <= int(h["y1"]):
			return h
	return {}

## Данные структуры из structures.txt по TypeID (кэш).
var _structure_defs := {}
func _structure_def(type_id: int) -> Dictionary:
	if _structure_defs.has(type_id):
		return _structure_defs[type_id]
	var f := FileAccess.open("res://assets/structures/structures.txt", FileAccess.READ)
	if f == null:
		push_warning("AlmMap: не открыть structures.txt")
		return {}
	var txt := f.get_as_text()
	f.close()
	var def := _parse_def_for_id(txt, type_id)
	_structure_defs[type_id] = def
	return def

func _parse_def_for_id(txt: String, type_id: int) -> Dictionary:
	var lines := txt.split("\n")
	var in_block := false
	var depth := 0
	var block: Array = []
	for line in lines:
		var t: String = line.strip_edges()
		if t.begins_with("object Structure"):
			if not in_block:
				in_block = true
				depth = 0
				block = [line]
				continue  # строка-заголовок: скобки считаем со следующей строки
		if in_block:
			block.append(line)
			depth += line.count("{") - line.count("}")
			if depth <= 0:
				# Конец блока: проверить ID
				var id_val := -1
				for bl in block:
					var b: String = bl.strip_edges()
					if b.begins_with("int ID"):
						id_val = int(b.split("=")[1].strip_edges())
				if id_val == type_id:
					return _parse_block(block)
				in_block = false
	return {}

func _parse_block(block: Array) -> Dictionary:
	var def := {}
	for line in block:
		var t: String = line.strip_edges()
		if not t.contains("="):
			continue
		var parts := t.split("=", true, 1)
		if parts.size() < 2:
			continue
		var key: String = parts[0].strip_edges()
		var val: String = parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		var k: String = key.split(" ", false)[-1]
		match k:
			"File": def["file"] = val
			"TileWidth": def["tile_width"] = int(val)
			"TileHeight": def["tile_height"] = int(val)
			"FullHeight": def["full_height"] = int(val)
			"Picture": def["picture"] = val
	return def

## --- Запросы для движения и миникарты ---

func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x) / tile_px, int(pos.y) / tile_px)

func height_at_tile(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 0
	if ty >= _height_grid.size():
		return 0
	return _height_grid[ty][tx]

func height_at_world(pos: Vector2) -> int:
	return height_at_tile(int(pos.x) / tile_px, int(pos.y) / tile_px)

func flag_at_world(pos: Vector2) -> int:
	var c := _cell_of(pos)
	if c.x < 0 or c.y < 0 or c.x >= map_width or c.y >= map_height:
		return AlmLoader.TileFlag.BARRIER
	return AlmLoader.classify(_tiles[c.y * map_width + c.x])

## Тип тайла (0..3) для миникарты, по клетке.
func cell_type_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 0
	return AlmLoader.terrain_type(_tiles[ty * map_width + tx])

## Проходимость: не вода/горы, нет растительности и зданий на клетке.
func is_walkable_world(pos: Vector2) -> bool:
	var c := _cell_of(pos)
	if c.x < 0 or c.y < 0 or c.x >= map_width or c.y >= map_height:
		return false
	var tile := _tiles[c.y * map_width + c.x]
	if not AlmLoader.is_walkable_type(AlmLoader.terrain_type(tile)):
		return false
	if barrier_cells.has(c):
		return false
	return true

## Множитель скорости на клетке: дорога (tile4) ускоряет.
func speed_factor_at_world(pos: Vector2) -> float:
	var c := _cell_of(pos)
	if c.x < 0 or c.y < 0 or c.x >= map_width or c.y >= map_height:
		return 1.0
	var t := AlmLoader.terrain_type(_tiles[c.y * map_width + c.x])
	return ROAD_SPEED if t == 3 else 1.0

func is_within_bounds(pos: Vector2, margin: float = 12.0) -> bool:
	var min_x := margin
	var min_y := margin
	var max_x := map_width * tile_px - margin
	var max_y := map_height * tile_px - margin
	return pos.x >= min_x and pos.y >= min_y and pos.x <= max_x and pos.y <= max_y

## Точка спавна: если рядом с .alm есть файл-якорь "<имя>.spawn.json" (ставится в
## редакторе карт), берём его клетку; иначе центр карты (game.gd найдёт рядом).
func get_spawn_pos() -> Vector2:
	var anchor := _load_spawn_anchor()
	if anchor.x >= 0:
		return Vector2(anchor.x * tile_px + tile_px / 2, anchor.y * tile_px + tile_px / 2)
	return Vector2(map_width * tile_px / 2, map_height * tile_px / 2)

## Клетка спавна из файла-якоря рядом с .alm, или (-1,-1).
func _load_spawn_anchor() -> Vector2i:
	var anchor_path := _effective_alm_path().get_basename() + ".spawn.json"
	if not FileAccess.file_exists(anchor_path):
		return Vector2i(-1, -1)
	var f := FileAccess.open(anchor_path, FileAccess.READ)
	if f == null:
		return Vector2i(-1, -1)
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is not Dictionary:
		return Vector2i(-1, -1)
	return Vector2i(int(json.get("x", -1)), int(json.get("y", -1)))

## .alm-карта содержит только здания — урон по ним не реализован (заглушка).
func damage_area(_world_pos: Vector2, _radius: float, _dmg: int) -> void:
	pass