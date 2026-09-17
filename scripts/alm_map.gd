extends Node2D
class_name AlmMap
## Карта разработчиков из .alm: рельефный меш с высотами и освещением от солнца
## (методика Allods16/repo jewalky): каждый тайл-квад поднят на высоту углов,
## текстура растягивается, яркость считается от нормали квада и угла солнца.
## Плюс: здания из секции id=4 (структуры) и препятствия из section id=3.

@export var alm_path: String = ""
@export var tile_size := 32   # свойство как у CustomMap (для миникарты и др.)

const TILE := 32
# Высота меша на 1 единицу высоты карты (оригинал рисует 1:1)
const HEIGHT_SCALE := 1.0

var map_width: int = 0
var map_height: int = 0
var _terrain: PackedByteArray   # byte[0] — вариант автайла
var _hflags: PackedByteArray    # byte[1] — тип terrain (файл-1: 0..3)
var _heights: PackedByteArray   # int8 — рельеф (0..127)
var _obstacles: PackedByteArray # uint8 — объекты (0=нет, >0=объект)
var _structures: Array = []     # секция id=4 — здания (или sidecar .structures.json)
var map_units: Array = []       # секция id=6 — юниты (или sidecar .npcs.json)
var _nowalk: Dictionary = {}    # клетки «Нельзя пройти» (ручная разметка в редакторе)
var _allowwalk: Dictionary = {} # клетки «Разрешить проход» — пускать сквозь препятствие
var solar_angle: float = 0.785398  # угол солнца из info (.alm), default 45°

# Вода: анимация кадрами-рядами вариантов tile3 (отдельный стрип + шейдер)
const WATER_ANIM_PERIOD := 0.18  # секунд на кадр воды
var _water_tex: ImageTexture = null
var _water_mat: ShaderMaterial = null
var _water_rows := 0             # кадров на вариант
var _water_total := 0            # всего рядов в стрипе
var _water_vidx := {}            # вариант -> индекс в стрипе
var _water_phase := 0.0

var mesh: MeshInstance2D
var _atlas: ImageTexture
var _cell_uv := {}              # "f{v}-r{row}" -> Rect4(u0,v0,u1,v1)
var _obstacle_db := {}          # .alm obstacle id -> {folder, w, h, cx, cy, phases}
var obstacles_root: Node2D      # слой препятствий (y-sort)
var buildings: Node2D           # слой зданий (y-sort)
var world_sort: Node2D          # общий y-sort: препятствия + здания (крона перекрывает фонтан)
var _structure_hits: Array = [] # хитбоксы зданий {x0,x1,y0,y1,picture,type_id}

## Единый слой с y-сортировкой для препятствий и зданий: южнее — поверх.
func _ensure_world_sort() -> Node2D:
	if world_sort == null:
		world_sort = Node2D.new()
		world_sort.name = "WorldSort"
		world_sort.y_sort_enabled = true
		add_child(world_sort)
	return world_sort

# Высотная сетка для движения (0/1: скала приподнята) — как раньше
var _height_grid: Array = []

const _DIRS_4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

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
	_structures = data.get("structures", [])
	map_units = data.get("units", [])
	_load_sidecars()
	var info: Dictionary = data.get("info", {})
	solar_angle = float(info.get("solar_angle", 0.785398))
	_load_obstacle_db()
	_build_height_grid()
	_build_atlas()
	_build_relief_mesh()
	_build_obstacles()
	_build_structures()
	print("AlmMap: %s %dx%d клеток, структур %d, солнце %s°" % [alm_path.get_file(), map_width, map_height, _structures.size(), str(rad_to_deg(solar_angle))])

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
		_ensure_world_sort().add_child(obstacles_root)
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
				int(spec.get("cx", 64)), int(spec.get("cy", 96)),
				int(spec.get("index", 0)))
			ob.place_at(Vector2i(x, y), TILE, relief_at_tile(x, y))
			obstacles_root.add_child(ob)

## Здания из секции id=4 (structures): спрайты assets/structures/<папка>/house-NNN.png.
## Сетка кадров 32x32: fw=TileWidth, fh=FullHeight; верхние (fh-th) рядов — выше земли.
## Тень (houseb) и анимация фаз (Phases>1) — через StructureNode / StructureDB.
func _build_structures() -> void:
	if _structures.is_empty():
		return
	if buildings == null:
		buildings = Node2D.new()
		buildings.name = "Buildings"
		buildings.y_sort_enabled = true
		_ensure_world_sort().add_child(buildings)
	var placed := 0
	var missing := 0
	for st in _structures:
		var type_id := int(st.get("type_id", 0))
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
		var x: float = st.get("x", 0.0)
		var y: float = st.get("y", 0.0)
		var dir := int(fj.get("fh", 1)) - int(fj.get("th", 1))
		node.position = Vector2(x * TILE, (y - dir) * TILE)
		buildings.add_child(node)
		placed += 1
		# Хитбокс здания в клетках: база — Selection-бокс (пиксели структуры),
		# иначе корпус th рядов (+верхние (fh-th) визуальные ряды).
		var fw := int(fj.get("fw", 1))
		var th := int(fj.get("th", 1))
		var fh := int(fj.get("fh", th))
		var sel: Rect2i = fj.get("sel", Rect2i())
		if sel.size.x > 0 and sel.size.y > 0:
			# Selection в пикселях исходного спрайта (fw*fh*32): переводим в клетки
			var tw := int(fj.get("fw", 1)) * 32
			var thh := int(fj.get("fh", th)) * 32
			var sx := int(x) + sel.position.x * fw / tw
			var sy := int(y) - (fh - th) + (sel.position.y * fh / thh)
			var sw := maxi(1, int(ceil(sel.size.x * fw / float(tw))))
			var sh := maxi(1, int(ceil(sel.size.y * fh / float(thh))))
			_structure_hits.append({
				"x0": sx, "x1": sx + sw - 1,
				"y0": sy, "y1": sy + sh - 1,
				"picture": str(fj.get("picture", "")),
				"type_id": type_id,
				"ax": int(x), "ay": int(y),
			})
		else:
			_structure_hits.append({
				"x0": int(x), "x1": int(x) + fw - 1,
				"y0": int(y) - (fh - th), "y1": int(y) + th - 1,
				"picture": str(fj.get("picture", "")),
				"type_id": type_id,
				"ax": int(x), "ay": int(y),
			})
	print("AlmMap: зданий создано %d, пропущено %d" % [placed, missing])

## Собрать Node2D-здание: сетка house-NNN + тень houseb + анимация фаз.
func _make_structure(job: Dictionary) -> Node2D:
	var node := StructureNode.new()
	node.folder = str(job["dir"])
	node.fw = int(job["fw"])
	node.th = int(job["th"])
	node.fh = int(job["fh"])
	var anim_times: Array = job.get("anim_times", [])
	node.set_anim_times(anim_times)
	node.use_anim = int(job.get("phases", 1)) > 1
	node.build()
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
	var dir_name := str(def.get("folder", "")).to_lower()
	if dir_name.is_empty():
		_structure_jobs[type_id] = {}
		return {}
	var prefix := str(def.get("prefix", "house"))
	if prefix.is_empty():
		prefix = "house"
	var fw := int(def.get("tile_width", 1))
	var th := int(def.get("tile_height", 1))
	var fh := int(def.get("full_height", th))
	var sel := Rect2i(0, 0, 0, 0)
	if def.has("sel") and (def["sel"] as Array).size() == 4:
		var s: Array = def["sel"]
		sel = Rect2i(int(s[0]), int(s[2]), int(s[1]) - int(s[0]), int(s[3]) - int(s[2]))
	var job := {
		"dir": dir_name, "prefix": prefix, "fw": fw, "th": th, "fh": fh,
		"picture": str(def.get("picture", "")),
		"phases": int(def.get("phases", 1)),
		"anim_times": StructureDB.anim_time(dir_name, int(def.get("phases", 1))),
		"sel": sel,
	}
	_structure_jobs[type_id] = job
	return job

## Данные структуры по TypeID: из структурированной БД (structure_db.json).
var _structure_defs := {}
func _structure_def(type_id: int) -> Dictionary:
	if _structure_defs.has(type_id):
		return _structure_defs[type_id]
	var def := StructureDB.get_by_id(type_id)
	_structure_defs[type_id] = def
	return def

## Здание под курсором (клетка cell) — для ховера; возвращает Dictionary или {}.
func structure_at(cell: Vector2i) -> Dictionary:
	for h in _structure_hits:
		if cell.x >= int(h["x0"]) and cell.x <= int(h["x1"]) \
				and cell.y >= int(h["y0"]) and cell.y <= int(h["y1"]):
			return h
	return {}

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
	_build_water_strip(used)

## Вода (tile3) анимируется кадрами-рядами варианта. Собираем отдельный стрип:
## колонка 32px, варианты воды — друг под другом, ряды внутри варианта — кадры.
func _build_water_strip(used: Dictionary) -> void:
	_water_tex = null
	_water_rows = 0
	_water_total = 0
	_water_vidx.clear()
	var variants_used: Array = []
	for key in used:
		if str(key).begins_with("f3-v"):
			var v := int(str(key).split("-")[1].trim_prefix("v").split("-")[0])
			if not variants_used.has(v):
				variants_used.append(v)
	variants_used.sort()
	if variants_used.is_empty():
		return
	var rows := 0
	var first_tex: Texture2D = null
	for v in variants_used:
		var tex: Texture2D = load("res://assets/terrain/tile3-%02d.bmp" % v)
		if tex == null:
			continue
		first_tex = tex
		var img: Image = tex.get_image()
		rows = maxi(1, img.get_height() / TILE)
		break
	if first_tex == null:
		return
	_water_rows = rows
	_water_total = rows * variants_used.size()
	var strip := Image.create(TILE, _water_total * TILE, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0, 0, 0, 0))
	for vi in range(variants_used.size()):
		var v: int = variants_used[vi]
		_water_vidx[v] = vi
		var tex: Texture2D = load("res://assets/terrain/tile3-%02d.bmp" % v)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var nrows := maxi(1, img.get_height() / TILE)
		for r in range(nrows):
			var cell_img := img.get_region(Rect2i(0, min(r, rows - 1) * TILE, TILE, TILE))
			strip.blit_rect(cell_img, Rect2i(0, 0, TILE, TILE),
				Vector2i(0, (vi * rows + r) * TILE))
	_water_tex = ImageTexture.create_from_image(strip)
	print("AlmMap: вода %d варианта(ов) x %d кадров" % [variants_used.size(), rows])

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

	var st_water: SurfaceTool = null
	if _water_tex != null and _water_total > 0:
		st_water = SurfaceTool.new()
		st_water.begin(Mesh.PRIMITIVE_TRIANGLES)

	var sun := _sun_dir()
	for y in range(map_height):
		for x in range(map_width):
			var i := y * map_width + x
			var file_n := (_hflags[i] & 0xF) + 1
			var vmax := 4 if file_n == 4 else 16
			var variant := clampi((_terrain[i] >> 4) & 0xF, 0, vmax - 1)
			var row := _terrain[i] & 0xF
			var is_water := file_n == 3 and st_water != null
			var uv := Vector4(0, 0, 0, 0) if is_water else _uv_for_cell(file_n, variant, row)
			if not is_water and uv == Vector4(0, 0, 0, 0):
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
			if is_water:
				# Вода: UV в стрипе — колонка 32px (u 0..1), ряд = кадр варианта
				var vi: int = int(_water_vidx.get(variant, 0))
				u0 = 0.0
				u1 = 1.0
				v0 = float(vi * _water_rows + row) / float(_water_total)
				v1 = v0 + 1.0 / float(_water_total)
			var target := st_water if is_water else st
			# Треугольник 1: p00 (u0,v0), p10 (u1,v0), p01 (u0,v1)
			_add_vert(target, p00, u0, v0, c)
			_add_vert(target, p10, u1, v0, c)
			_add_vert(target, p01, u0, v1, c)
			# Треугольник 2: p10 (u1,v0), p11 (u1,v1), p01 (u0,v1)
			_add_vert(target, p10, u1, v0, c)
			_add_vert(target, p11, u1, v1, c)
			_add_vert(target, p01, u0, v1, c)

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

	# Вторая поверхность: вода со своей текстурой-стрипом и анимацией рядов
	if st_water != null:
		var warr: Array = st_water.commit_to_arrays()
		amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warr)
		var wshader := Shader.new()
		wshader.code = """
shader_type canvas_item;
uniform sampler2D u_water;
uniform float u_phase = 0.0;
uniform float u_rows = 16.0;
uniform float u_total = 16.0;
void fragment() {
	float idx = UV.y * u_total;
	float base = floor(idx / u_rows) * u_rows;
	float row = mod(idx + u_phase * u_rows, u_rows);
	vec2 wuv = vec2(UV.x, (base + row) / u_total);
	COLOR = texture(u_water, wuv) * COLOR;
}
"""
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = wshader
		_water_mat.set_shader_parameter("u_water", _water_tex)
		_water_mat.set_shader_parameter("u_rows", float(_water_rows))
		_water_mat.set_shader_parameter("u_total", float(_water_total))
		amesh.surface_set_material(1, _water_mat)

## Анимация воды: сдвиг фазы в шейдере (пауза останавливает).
func _process(delta: float) -> void:
	if _water_mat == null or _water_total <= 0:
		return
	if Game.is_paused:
		return
	_water_phase = fmod(_water_phase + delta / WATER_ANIM_PERIOD, 1.0)
	_water_mat.set_shader_parameter("u_phase", _water_phase)

func _add_vert(st: SurfaceTool, p: Vector3, u: float, v: float, c: Color) -> void:
	st.set_uv(Vector2(u, v))
	st.set_color(c)
	st.add_vertex(p)

## Мировая позиция спавна: из файла-якоря "<имя>.spawn.json" рядом с .alm
## (ставится в редакторе карт) или центр карты (game.gd сам ищет проходимый тайл).
func get_spawn_pos() -> Vector2:
	var anchor := _load_spawn_anchor()
	if anchor.x >= 0:
		return Vector2(anchor.x * TILE + TILE / 2, anchor.y * TILE + TILE / 2)
	return Vector2(map_width * TILE / 2, map_height * TILE / 2)

## Клетка спавна из файла-якоря рядом с .alm, или (-1,-1).
func _load_spawn_anchor() -> Vector2i:
	if alm_path.is_empty():
		return Vector2i(-1, -1)
	var anchor_path := alm_path.get_basename() + ".spawn.json"
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

## Sidecar-файлы рядом с .alm — редактор сохраняет в них полное состояние
## структур и НПЦ (сам .alm не перезаписывается):
##   "<имя>.structures.json" — {"structures": [{x, y, type_id}]}
##   "<имя>.npcs.json"       — {"npcs": [{x, y, set}]}
## Если sidecar существует — он ПЕРЕКРЫВАЕТ секции 4/6 .alm (редактор копирует
## их туда при первом открытии); иначе работают оригинальные секции.
func _load_sidecars() -> void:
	if alm_path.is_empty():
		return
	var base := alm_path.get_basename()
	var s: Variant = _read_sidecar(base + ".structures.json")
	if s != null and s is Array:
		_structures = s
	var u: Variant = _read_sidecar(base + ".npcs.json")
	if u != null and u is Array:
		map_units = u
	# Ручная разметка «Нельзя пройти» — редактор пишет её рядом с .alm
	var n: Variant = _read_sidecar(base + ".nowalk.json")
	_nowalk.clear()
	if n != null and n is Array:
		for pair in n:
			if pair is Array and pair.size() >= 2:
				_nowalk[Vector2i(int(pair[0]), int(pair[1]))] = true
	# Ручная разметка «Разрешить проход» — пускать сквозь препятствие (дерево/камень)
	var a: Variant = _read_sidecar(base + ".allowwalk.json")
	_allowwalk.clear()
	if a != null and a is Array:
		for pair in a:
			if pair is Array and pair.size() >= 2:
				_allowwalk[Vector2i(int(pair[0]), int(pair[1]))] = true

## Прочитать sidecar: null — файла нет (использовать секции .alm),
## иначе массив записей (пустой — сущностей нет).
func _read_sidecar(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		if parsed.has("structures") and parsed["structures"] is Array:
			return parsed["structures"]
		if parsed.has("npcs") and parsed["npcs"] is Array:
			return parsed["npcs"]
		if parsed.has("nowalk") and parsed["nowalk"] is Array:
			return parsed["nowalk"]
		if parsed.has("allowwalk") and parsed["allowwalk"] is Array:
			return parsed["allowwalk"]
		return []
	if parsed is Array:
		return parsed
	return []

## Список юнитов карты для спавна: секция id=6 (.alm) или sidecar .npcs.json.
## Записи: {x, y — клетки, type_id | set, player, hp_max}.
func get_units() -> Array:
	return map_units

## --- Запросы для движения и миникарты ---

func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x) / TILE, int(pos.y) / TILE)

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
	return AlmLoader.classify(_hflags[ty * map_width + tx])

func is_walkable_world(pos: Vector2) -> bool:
	var tx := int(pos.x) / TILE
	var ty := int(pos.y) / TILE
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return false
	# Ручная разметка «Нельзя пройти» (редактор) — приоритет над автоматикой
	if _nowalk.has(Vector2i(tx, ty)):
		return false
	var i := ty * map_width + tx
	var hf := _hflags[i]
	# Спец-значения Nival (16..40 — вода/барьер в byte[1]) — всегда непроходимы
	if hf >= 16 and hf <= 40:
		return false
	var file_n := (hf & 0xF) + 1
	var variant := clampi((_terrain[i] >> 4) & 0xF, 0, 15)
	# Таблица «цены прохода по текстуре» (WalkTable): вода (tile3) и
	# переопределённые варианты с ценой 0 — непроходимы; горы/песок — проходимы
	if not WalkTable.walkable(file_n, variant):
		return false
	var allow := _allowwalk.has(Vector2i(tx, ty))
	# Объект (дерево/камень из obstacles) — непроходимо (кроме allowwalk-разметки)
	if not allow and _obstacles.size() > i and _obstacles[i] > 0:
		return false
	# Здания (секция id=4) — непроходимы (кроме allowwalk-разметки)
	if not allow and not structure_at(Vector2i(tx, ty)).is_empty():
		return false
	return true

## Множитель скорости по текстуре клетки (WalkTable, как у разработчиков:
## скорость = 8 / цена прохода). Дорога быстрее травы, песок/горы медленнее.
func speed_factor_at_world(pos: Vector2) -> float:
	var tx := int(pos.x) / TILE
	var ty := int(pos.y) / TILE
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 1.0
	return WalkTable.speed_at(_hflags[ty * map_width + tx], _terrain[ty * map_width + tx])

## Тип клетки 0..3 для миникарты: 0 трава, 1 горы, 2 вода/барьер, 3 дорога.
func cell_type_at(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map_width or ty >= map_height:
		return 0
	var t := AlmLoader.terrain_type(_hflags[ty * map_width + tx])
	if t == -1 or t == -2:
		return 2
	return t

## Причина непроходимости клетки («», если проходима) — для подсказки координат.
## «Трава» может быть занята деревом/камнем (obstacles), зданием или разметкой.
func blocked_reason(cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return "вне карты"
	if _nowalk.has(cell):
		return "запрет разметки"
	var i := cell.y * map_width + cell.x
	var hf := _hflags[i]
	if hf >= 16 and hf <= 40:
		return "барьер (спец-тайл)"
	var file_n := (hf & 0xF) + 1
	var variant := clampi((_terrain[i] >> 4) & 0xF, 0, 15)
	if not WalkTable.walkable(file_n, variant):
		if file_n == 3:
			return "вода (tile3)"
		return "непроходимая текстура (tile%d-%02d)" % [file_n, variant]
	if _obstacles.size() > i and _obstacles[i] > 0:
		return "дерево/камень"
	if not structure_at(cell).is_empty():
		return "здание"
	return ""

func is_within_bounds(pos: Vector2, margin: float = 12.0) -> bool:
	var min_x := margin
	var min_y := margin
	var max_x := map_width * TILE - margin
	var max_y := map_height * TILE - margin
	return pos.x >= min_x and pos.y >= min_y and pos.x <= max_x and pos.y <= max_y

## --- Путь (pathfinding): BFS по сетке проходимости, обход препятствий ---

## Путь от from_world до to_world в мировых точках (центры клеток), без первой
## клетки. Если цель непроходима — ищем путь к ближайшей проходимой рядом с ней
## (клик по дереву/воде подводит героя к самому краю). Пустой — пути нет.
func find_path(from_world: Vector2, to_world: Vector2) -> Array:
	var start := _cell_of(from_world)
	var goal := _cell_of(to_world)
	# Герой может стоять в клетке, которая по разметке непроходима (упёрся/склон):
	# путь начинаем от ближайшей ПРОХОДИМОЙ клетки рядом, иначе «нельзя вернуться».
	if not _cell_walkable(start):
		start = _nearest_walkable(start, 4)
		if start.x < 0:
			return []
	if not _cell_walkable(goal):
		# Цель непроходима: пробуем 4 соседей, берём ближайшего
		var best: Vector2i = goal
		var best_d := -1.0
		for d in _DIRS_4:
			var n := goal + d
			if _cell_walkable(n):
				var dist := from_world.distance_squared_to(Vector2(n.x * TILE + TILE / 2, n.y * TILE + TILE / 2))
				if best_d < 0.0 or dist < best_d:
					best_d = dist
					best = n
		if best_d < 0.0:
			return []
		goal = best

	# BFS по 4 соседям
	var prev := {}
	var queue: Array = [start]
	var seen := {start: true}
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			break
		for d in _DIRS_4:
			var n := cur + d
			if seen.has(n) or not _cell_walkable(n):
				continue
			seen[n] = true
			prev[n] = cur
			queue.append(n)
	if not seen.has(goal):
		return []

	# Восстановить путь и перевести в мировые точки (центры клеток)
	var cells: Array = []
	var c := goal
	while c != start:
		cells.append(c)
		c = prev[c]
	cells.reverse()
	var out: Array = []
	for cell in cells:
		out.append(Vector2(cell.x * TILE + TILE / 2, cell.y * TILE + TILE / 2))
	return out

func _cell_walkable(cell: Vector2i) -> bool:
	return is_walkable_world(Vector2(cell.x * TILE + TILE / 2, cell.y * TILE + TILE / 2))

## Ближайшая проходимая клетка (спираль радиуса r) или (-1,-1).
func _nearest_walkable(cell: Vector2i, r: int) -> Vector2i:
	if _cell_walkable(cell):
		return cell
	for radius in range(1, r + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if _cell_walkable(c):
					return c
	return Vector2i(-1, -1)

func tile_id_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return -1
	return _hflags[cell.y * map_width + cell.x]

func damage_area(_world_pos: Vector2, _radius: float, _dmg: int) -> void:
	pass