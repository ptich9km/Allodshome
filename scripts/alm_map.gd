extends Node2D
class_name AlmMap
## Карта разработчиков из .alm: рельефный меш с высотами и освещением от солнца
## (методика Allods16/repo jewalky): каждый тайл-квад поднят на высоту углов,
## текстура растягивается, яркость считается от нормали квада и угла солнца.

@export var alm_path: String = ""
@export var tile_px := 32

const TILE := 32
# Высота меша на 1 единицу высоты карты (оригинал рисует 1:1)
const HEIGHT_SCALE := 1.0

var map_width: int = 0
var map_height: int = 0
var _terrain: PackedByteArray   # byte[0] — вариант автайла
var _hflags: PackedByteArray    # byte[1] — тип terrain (файл-1: 0..3)
var _heights: PackedByteArray   # int8 — рельеф (0..127)
var _obstacles: PackedByteArray # uint8 — объекты (0=нет, >0=объект)
var solar_angle: float = 0.785398  # угол солнца из info (.alm), default 45°

var mesh: MeshInstance2D
var _atlas: ImageTexture
var _cell_uv := {}              # "f{v}-r{row}" -> Rect4(u0,v0,u1,v1)
var _obstacle_db := {}          # .alm obstacle id -> {folder, w, h, cx, cy, phases}
var obstacles_root: Node2D      # слой препятствий (y-sort)

# Высотная сетка для движения (0/1: скала приподнята) — как раньше
var _height_grid: Array = []

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
	_heights = data["heights"]
	_obstacles = data["obstacles"]
	var info: Dictionary = data.get("info", {})
	solar_angle = float(info.get("solar_angle", 0.785398))
	_load_obstacle_db()
	_build_height_grid()
	_build_atlas()
	_build_relief_mesh()
	_build_obstacles()
	print("AlmMap: %s %dx%d клеток, солнце %s°" % [alm_path.get_file(), map_width, map_height, str(rad_to_deg(solar_angle))])

## Таблица препятствий: .alm obstacle id -> параметры спрайта (из objects.txt/obj.reg).
func _load_obstacle_db() -> void:
	var f := FileAccess.open("res://assets/map-objects/alm_objects.json", FileAccess.READ)
	if f == null:
		push_warning("AlmMap: нет alm_objects.json — препятствия не будут показаны")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_obstacle_db = parsed

## Препятствия (.alm obstacles): дерево/камень/статуя на клетках с id > 0.
func _build_obstacles() -> void:
	if obstacles_root == null:
		obstacles_root = Node2D.new()
		obstacles_root.name = "Obstacles"
		obstacles_root.y_sort_enabled = true
		obstacles_root.z_index = 1
		add_child(obstacles_root)
	for y in range(map_height):
		for x in range(map_width):
			var oid := _obstacles[y * map_width + x]
			if oid == 0:
				continue
			var spec: Dictionary = _obstacle_db.get(str(oid), {})
			if spec.is_empty():
				continue
			var folder := str(spec.get("folder", ""))
			if folder.is_empty():
				continue
			var ob := AlmObstacle.new()
			ob.setup(folder, int(spec.get("phases", 1)),
				int(spec.get("w", 128)), int(spec.get("h", 128)),
				int(spec.get("cx", 64)), int(spec.get("cy", 96)))
			ob.place_at(Vector2i(x, y), TILE, relief_at_tile(x, y))
			obstacles_root.add_child(ob)

## Высотная сетка для движения (как раньше): скала = 1, остальное 0.
func _build_height_grid() -> void:
	_height_grid = []
	if _heights.size() != map_width * map_height:
		return
	for y in range(map_height):
		var row: Array = []
		row.resize(map_width)
		for x in range(map_width):
			row[x] = 1 if AlmLoader.terrain_type(_hflags[y * map_width + x]) == 3 else 0
		_height_grid.append(row)

## Рельеф: настоящие высоты (для визуала и скорости движения).
func relief_at_tile(x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= map_width or y >= map_height:
		return 0.0
	return float(_heights[y * map_width + x]) * HEIGHT_SCALE

func relief_at_world(pos: Vector2) -> float:
	return relief_at_tile(int(pos.x) / TILE, int(pos.y) / TILE)

# --- Текстуры: атлас всех используемых (файл, вариант, ряд) ---

func _used_cells() -> Dictionary:
	## Ключ "f{file}-v{variant}-r{row}" -> true. file 1..4, variant 0..15, row 0..nrows-1
	var used := {}
	for i in range(map_width * map_height):
		var file_n := (_hflags[i] & 0xF) + 1
		var vmax := 4 if file_n == 4 else 16
		var variant := clampi((_terrain[i] >> 4) & 0xF, 0, vmax - 1)
		var row := _terrain[i] & 0xF
		# ряд может превышать реальную высоту файла — проверка позже в _build_atlas
		used["f%d-v%d-r%d" % [file_n, variant, row]] = true
	return used

func _build_atlas() -> void:
	var used := _used_cells()
	# Соберём фактические (файл, вариант, ряд) с реальным числом рядов в файле
	var cells: Array = []  # [key, Image32]
	var key_to_cell := {}
	var vmax_by_file := {1: 16, 2: 16, 3: 16, 4: 4}
	# Порядок: сначала все ряды файла 1, потом файла 2 ... (для обхода файлов)
	for file_n in [1, 2, 3, 4]:
		var vmax: int = vmax_by_file[file_n]
		for variant in range(vmax):
			var path := "res://assets/terrain/tile%d-%02d.bmp" % [file_n, variant]
			if not ResourceLoader.exists(path):
				continue
			var tex: Texture2D = load(path)
			var img: Image = tex.get_image()
			img.convert(Image.FORMAT_RGBA8)
			var nrows: int = img.get_height() / TILE
			for row in range(nrows):
				var key := "f%d-v%d-r%d" % [file_n, variant, row]
				if not used.has(key) and not key_to_cell.has(key):
					continue
				var cell_img: Image = img.get_region(Rect2i(0, row * TILE, TILE, TILE))
				cells.append([key, cell_img])
				key_to_cell[key] = cells.size() - 1

	# Собираем атлас 64x64 ячейки (до 4096)
	var atlas := Image.create(64 * TILE, 64 * TILE, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	_cell_uv.clear()
	for idx in range(cells.size()):
		var key: String = cells[idx][0]
		var cimg: Image = cells[idx][1]
		var cx := idx % 64
		var cy := idx / 64
		atlas.blit_rect(cimg, Rect2i(0, 0, TILE, TILE), Vector2i(cx * TILE, cy * TILE))
		var u0 := float(cx * TILE) / float(64 * TILE)
		var v0 := float(cy * TILE) / float(64 * TILE)
		var u1 := u0 + 1.0 / 64.0
		var v1 := v0 + 1.0 / 64.0
		_cell_uv[key] = Vector4(u0, v0, u1, v1)
	_atlas = ImageTexture.create_from_image(atlas)
	print("AlmMap: атлас %d ячеек" % cells.size())

## Для отладки: сама текстура атласа.
func get_atlas_texture() -> ImageTexture:
	return _atlas

func _uv_for_cell(file_n: int, variant: int, row: int) -> Vector4:
	var key := "f%d-v%d-r%d" % [file_n, variant, row]
	var r: Vector4 = _cell_uv.get(key, Vector4(0, 0, 0, 0))
	return r

# --- Рельефный меш с освещением ---

func _node_h(nx: int, ny: int) -> float:
	## Высота узла сетки (угла клетки), с клампом к границам карты.
	var cx := clampi(nx, 0, map_width - 1)
	var cy := clampi(ny, 0, map_height - 1)
	return float(_heights[cy * map_width + cx]) * HEIGHT_SCALE

func _cell_normal(x: int, y: int) -> Vector3:
	## Нормаль квада (Allods16): u=(32,0,uz), v=(0,32,vz),
	## где uz = h(x+1,y)-h(x,y), vz = h(x,y+1)-h(x,y). n = cross(u,v).
	var uz := _node_h(x + 1, y) - _node_h(x, y)
	var vz := _node_h(x, y + 1) - _node_h(x, y)
	# cross((32,0,uz),(0,32,vz)) = (-32*uz, -32*vz, 1024)
	var n := Vector3(-32.0 * uz, -32.0 * vz, 1024.0)
	return n.normalized()

func _sun_dir() -> Vector3:
	var a := solar_angle
	var s := Vector3(cos(a), sin(a), -0.75)
	return s.normalized()

func _brightness(x: int, y: int) -> float:
	## Яркость клетки: |n·sun|*64+96, затем контраст (как в Allods16).
	## В оригинале shade/4 — индекс яркостной палитры (0..64, 32 = норма),
	## поэтому нормируем на 128: плоский террейн ~1.0, склоны темнее.
	var n := _cell_normal(x, y)
	var sun := _sun_dir()
	var dot := absf(n.dot(sun))
	var b := dot * 64.0 + 96.0
	b = (b - 128.0) * 0.75 + 128.0
	return clampf(b / 128.0, 0.25, 1.0)

func _build_relief_mesh() -> void:
	if mesh == null:
		mesh = MeshInstance2D.new()
		mesh.name = "ReliefMesh"
		mesh.z_index = -1
		add_child(mesh)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var sun := _sun_dir()
	for y in range(map_height):
		for x in range(map_width):
			var i := y * map_width + x
			var file_n := (_hflags[i] & 0xF) + 1
			var vmax := 4 if file_n == 4 else 16
			var variant := clampi((_terrain[i] >> 4) & 0xF, 0, vmax - 1)
			var row := _terrain[i] & 0xF
			var uv := _uv_for_cell(file_n, variant, row)
			if uv == Vector4(0, 0, 0, 0):
				continue

			# Углы квада: (x,y) вверх-влево, (x+1,y) вправо, (x,y+1) вниз, (x+1,y+1)
			var h00 := _node_h(x, y)
			var h10 := _node_h(x + 1, y)
			var h01 := _node_h(x, y + 1)
			var h11 := _node_h(x + 1, y + 1)
			var p00 := Vector3(x * TILE, y * TILE - h00, 0)
			var p10 := Vector3((x + 1) * TILE, y * TILE - h10, 0)
			var p01 := Vector3(x * TILE, (y + 1) * TILE - h01, 0)
			var p11 := Vector3((x + 1) * TILE, (y + 1) * TILE - h11, 0)

			# Яркость: средняя из 4 угловых клеток (гладкий свет), по нормали самой клетки
			var br := _brightness(x, y)
			var c := Color(br, br, br, 1.0)

			var u0 := uv.x
			var v0 := uv.y
			var u1 := uv.z
			var v1 := uv.w
			# Треугольник 1: p00 (u0,v0), p10 (u1,v0), p01 (u0,v1)
			_add_vert(st, p00, u0, v0, c)
			_add_vert(st, p10, u1, v0, c)
			_add_vert(st, p01, u0, v1, c)
			# Треугольник 2: p10 (u1,v0), p11 (u1,v1), p01 (u0,v1)
			_add_vert(st, p10, u1, v0, c)
			_add_vert(st, p11, u1, v1, c)
			_add_vert(st, p01, u0, v1, c)

	var arr: Array = st.commit_to_arrays()
	var amesh := ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D u_atlas;
void fragment() {
	COLOR = texture(u_atlas, UV) * COLOR;
}
"""
	mat.shader = shader
	mat.set_shader_parameter("u_atlas", _atlas)
	mesh.mesh = amesh
	mesh.material = mat
	print("AlmMap: меш собран (%d клеток)" % (map_width * map_height))

func _add_vert(st: SurfaceTool, p: Vector3, u: float, v: float, c: Color) -> void:
	st.set_uv(Vector2(u, v))
	st.set_color(c)
	st.add_vertex(p)

## Мировая позиция спавна: центр карты (game.gd сам ищет проходимый тайл рядом).
func get_spawn_pos() -> Vector2:
	return Vector2(map_width * TILE / 2, map_height * TILE / 2)

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
	return height_at_tile(int(pos.x) / TILE, int(pos.y) / TILE)

func flag_at_world(pos: Vector2) -> int:
	var tx := int(pos.x) / TILE
	var ty := int(pos.y) / TILE
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return AlmLoader.TileFlag.BARRIER
	return AlmLoader.classify(_tiles[c.y * map_width + c.x])

func is_walkable_world(pos: Vector2) -> bool:
	var tx := int(pos.x) / TILE
	var ty := int(pos.y) / TILE
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 0
	return AlmLoader.terrain_type(_tiles[ty * map_width + tx])

## Проходимость: не вода/горы, нет растительности и зданий на клетке.
func is_walkable_world(pos: Vector2) -> bool:
	var c := _cell_of(pos)
	if c.x < 0 or c.y < 0 or c.x >= map_width or c.y >= map_height:
		return false
	var i := ty * map_width + tx
	if not AlmLoader.is_walkable(_hflags[i]):
		return false
	# Объект (дерево/камень из obstacles) — непроходимо
	if _obstacles[i] > 0:
		return false
	return true

## Множитель скорости по типу клетки: дороги (tile4) быстрее травы.
func speed_factor_at_world(pos: Vector2) -> float:
	var tx := int(pos.x) / TILE
	var ty := int(pos.y) / TILE
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 1.0
	return AlmLoader.speed_factor_type(AlmLoader.terrain_type(_hflags[ty * map_width + tx]))

func is_within_bounds(pos: Vector2, margin: float = 12.0) -> bool:
	var min_x := margin
	var min_y := margin
	var max_x := map_width * TILE - margin
	var max_y := map_height * TILE - margin
	return pos.x >= min_x and pos.y >= min_y and pos.x <= max_x and pos.y <= max_y

func tile_id_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return -1
	return _hflags[cell.y * map_width + cell.x]

func damage_area(_world_pos: Vector2, _radius: float, _dmg: int) -> void:
	pass