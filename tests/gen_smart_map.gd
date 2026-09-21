extends SceneTree
## Умный генератор .alm на основе паттернов Beach.alm.
## Noise → terrain → переходы из transition_db → высоты → дороги → объекты.

const OUT_DIR := "res://assets/maps/gen/"
const DB_PATH := "res://assets/maps/transition_db.json"
const W := 128
const H := 128
## Тип A -> tile-файл для .alm (в DB у песка/грязи file=1 — палитра tile1)
const TERRAIN_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7}

var _tiles := PackedInt32Array()
var _heights := PackedByteArray()
var _obstacles := PackedByteArray()
var _terrain := PackedByteArray()  # тип 0-3

# Паттерны из Beach.alm
var _biome := {
	"grass_pct": 0.50,
	"mountain_pct": 0.15,
	"water_pct": 0.33,
	"road_pct": 0.02,
	"h_grass": 19,
	"h_mountain": 35,
	"h_water": 6,
	"h_road": 17,
	"obj_on_grass": 0.13,
	"obj_on_mountain": 0.07,
}

# Transition DB
var _rules: Dictionary = {}
var _interior: Dictionary = {}

func _init() -> void:
	_load_db()
	_generate()
	_save()
	quit(0)

func _load_db() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		return
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Dictionary:
		_rules = json.get("rules", {})
		_interior = json.get("interior", {})
	print("DB: %d rules, %d interior" % [_rules.size(), _interior.size()])

func _get_rule(type_a: int, dir: String, type_b: int) -> Dictionary:
	return _rules.get("%d:%s:%d" % [type_a, dir, type_b], {})

# === Генерация ===

func _generate() -> void:
	var n: int = W * H
	_terrain.resize(n)
	_tiles.resize(n)
	_heights.resize(n)
	_obstacles.resize(n)
	_obstacles.fill(0)

	# 1. Noise → terrain
	_place_terrain(n)

	# 2. Roads
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	_place_roads(rng)

	# 3. Tiles с переходами из DB
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			_tiles[i] = _pick_tile(_terrain[i], x, y)

	# 4. Высоты
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			_heights[i] = _pick_height(x, y, _terrain[i], rng)

	# 5. Объекты (деревья/кусты) на траве и горах
	_place_objects(rng)

func _place_terrain(n: int) -> void:
	# Multi-octave noise для естественных форм
	var noise1 := FastNoiseLite.new()
	noise1.seed = 42
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise1.frequency = 1.0 / 48.0
	noise1.fractal_octaves = 4
	noise1.fractal_gain = 0.5

	var noise2 := FastNoiseLite.new()
	noise2.seed = 137
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 1.0 / 32.0
	noise2.fractal_octaves = 3

	# Отдельный шум для почвы/песка/грязи
	var noise3 := FastNoiseLite.new()
	noise3.seed = 999
	noise3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise3.frequency = 1.0 / 40.0
	noise3.fractal_octaves = 3

	var field := PackedFloat32Array()
	field.resize(n)
	var soil_field := PackedFloat32Array()
	soil_field.resize(n)
	for i in range(n):
		var x: float = float(i % W)
		var y: float = float(i / W)
		var v1: float = noise1.get_noise_2d(x, y)
		var v2: float = noise2.get_noise_2d(x, y)
		field[i] = clampf((v1 * 0.7 + v2 * 0.3 + 1.0) * 0.5, 0.0, 1.0)
		soil_field[i] = clampf((noise3.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)

	# Blur для плавных переходов
	for _b in range(3):
		field = _box_blur(field)
	for _b in range(2):
		soil_field = _box_blur(soil_field)

	# Пороги по биому
	var sorted: PackedFloat32Array = field.duplicate()
	sorted.sort()
	var n_cells: int = n
	var water_thr: float = sorted[clampi(int(_biome["water_pct"] * n_cells), 0, n_cells - 1)]
	var mountain_thr: float = sorted[clampi(n_cells - 1 - int(_biome["mountain_pct"] * n_cells), 0, n_cells - 1)]

	# Пороги почвы/песка/грязи (поверх травы)
	var soil_sorted: PackedFloat32Array = soil_field.duplicate()
	soil_sorted.sort()
	var soil_thr: float = soil_sorted[clampi(int(0.72 * n_cells), 0, n_cells - 1)]     # ~8% почва
	var sand_thr: float = soil_sorted[clampi(int(0.84 * n_cells), 0, n_cells - 1)]     # ~6% песок
	var mud_thr: float = soil_sorted[clampi(int(0.92 * n_cells), 0, n_cells - 1)]      # ~4% грязь

	for i in range(n):
		var v: float = field[i]
		if v <= water_thr:
			_terrain[i] = 2  # вода
		elif v >= mountain_thr:
			_terrain[i] = 1  # горы
		else:
			var sv: float = soil_field[i]
			if sv >= mud_thr:
				_terrain[i] = 6      # грязь
			elif sv >= sand_thr:
				_terrain[i] = 5      # песок
			elif sv >= soil_thr:
				_terrain[i] = 4      # почва
			else:
				_terrain[i] = 0      # трава

func _place_roads(rng: RandomNumberGenerator) -> void:
	# Соединяем центры карты случайными точками
	var points: Array = []
	var n_roads := maxi(3, int(W * H * _biome["road_pct"] / 100.0 / 50))
	for _i in range(n_roads):
		points.append(Vector2i(rng.randi_range(10, W - 11), rng.randi_range(10, H - 11)))

	var connected: Array = [points[0]]
	var remaining: Array = points.slice(1)
	while not remaining.is_empty():
		var best_dist := 999999
		var best_from := Vector2i.ZERO
		var best_to := Vector2i.ZERO
		var best_ri := 0
		for ri in range(remaining.size()):
			var p: Vector2i = remaining[ri]
			for c in connected:
				var d: int = absi(p.x - c.x) + absi(p.y - c.y)
				if d < best_dist:
					best_dist = d
					best_from = c
					best_to = p
					best_ri = ri
		_carve_road(best_from, best_to, rng)
		connected.append(best_to)
		remaining.remove_at(best_ri)

func _carve_road(from: Vector2i, to: Vector2i, rng: RandomNumberGenerator) -> void:
	var p: Vector2i = from
	var steps := 0
	while p != to and steps < 500:
		steps += 1
		# Ширина дороги 2 клетки
		for dx in range(-1, 3):
			for dy in range(-1, 2):
				var cx: int = p.x + dx
				var cy: int = p.y + dy
				if cx >= 0 and cy >= 0 and cx < W and cy < H:
					var i: int = cy * W + cx
					if _terrain[i] != 2:  # не по воде
						_terrain[i] = 3
		var diff: Vector2i = to - p
		var step := Vector2i(signi(diff.x), signi(diff.y))
		if rng.randf() < 0.3:
			if absi(diff.x) > absi(diff.y):
				step.y = rng.randi_range(-1, 1)
			else:
				step.x = rng.randi_range(-1, 1)
		p += step
		p.x = clampi(p.x, 0, W - 1)
		p.y = clampi(p.y, 0, H - 1)

func _pick_tile(t: int, x: int, y: int) -> int:
	var s: Dictionary = _sides(x, y)
	var has_diff := false
	for d in ["N", "S", "E", "W"]:
		if s[d] != -1 and s[d] != t:
			has_diff = true
			break
	if not has_diff:
		return _interior_tile(t)
	return _edge_tile(t, s)

func _sides(x: int, y: int) -> Dictionary:
	var t: int = _terrain[y * W + x]
	var r := {"N": -1, "S": -1, "E": -1, "W": -1,
			  "NE": -1, "NW": -1, "SE": -1, "SW": -1}
	if y > 0:     r["N"]  = _terrain[(y - 1) * W + x]
	if y < H - 1: r["S"]  = _terrain[(y + 1) * W + x]
	if x < W - 1: r["E"]  = _terrain[y * W + x + 1]
	if x > 0:     r["W"]  = _terrain[y * W + x - 1]
	if y > 0 and x < W - 1: r["NE"] = _terrain[(y - 1) * W + x + 1]
	if y > 0 and x > 0:     r["NW"] = _terrain[(y - 1) * W + x - 1]
	if y < H - 1 and x < W - 1: r["SE"] = _terrain[(y + 1) * W + x + 1]
	if y < H - 1 and x > 0:     r["SW"] = _terrain[(y + 1) * W + x - 1]
	return r

func _interior_tile(t: int) -> int:
	var key := str(t)
	if _interior.has(key):
		return AlmLoader.tile_from_spec(_spec_for_type(t, _interior[key]))
	match t:
		0: return AlmLoader.tile_from_spec({"file": 1, "variant": 1, "row": 1})
		1: return AlmLoader.tile_from_spec({"file": 2, "variant": 15, "row": 3})
		2: return AlmLoader.tile_from_spec({"file": 3, "variant": 3, "row": 0})
		3: return AlmLoader.tile_from_spec({"file": 4, "variant": 3, "row": 0})
	return 0

func _edge_tile(t: int, s: Dictionary) -> int:
	# Ищем cardinal правила из DB
	for d in ["N", "S", "E", "W"]:
		if s[d] != -1 and s[d] != t:
			var spec: Dictionary = _get_rule(t, d, s[d])
			if not spec.is_empty():
				return AlmLoader.tile_from_spec(_spec_for_type(t, spec))
	# Пробуем diagonal
	for d in ["NE", "NW", "SE", "SW"]:
		if s[d] != -1 and s[d] != t:
			var spec: Dictionary = _get_rule(t, d, s[d])
			if not spec.is_empty():
				return AlmLoader.tile_from_spec(_spec_for_type(t, spec))
	return _interior_tile(t)

## file из правила -> file для кодировки типа A (.alm)
func _spec_for_type(type_a: int, spec: Dictionary) -> Dictionary:
	var out := spec.duplicate(true)
	out["file"] = int(TERRAIN_FILE.get(type_a, int(spec.get("file", 1))))
	out["variant"] = int(spec.get("variant", 0))
	out["row"] = int(spec.get("row", 0))
	return out

func _pick_height(x: int, y: int, t: int, rng: RandomNumberGenerator) -> int:
	var base: float = float(_biome["h_grass"])
	match t:
		1: base = float(_biome["h_mountain"])
		2: base = float(_biome["h_water"])
		3: base = float(_biome["h_road"])
	# Variация ±30%
	var variation := rng.randf_range(-0.3, 0.3)
	return int(round(clampf(base * (1.0 + variation), 0.0, 127.0)))

func _place_objects(rng: RandomNumberGenerator) -> void:
	# Объекты на траве и горах (как в Beach.alm)
	for i in range(W * H):
		var t: int = _terrain[i]
		var chance := 0.0
		if t == 0:
			chance = _biome["obj_on_grass"]
		elif t == 1:
			chance = _biome["obj_on_mountain"]
		if chance > 0 and rng.randf() < chance:
			# obstacles[i] > 0 = объект есть (рид-only для генератора)
			_obstacles[i] = 1

func _box_blur(field: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = field.duplicate()
	for y in range(H):
		for x in range(W):
			var sum := 0.0
			var cnt := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					sum += field[ny * W + nx]
					cnt += 1
			out[y * W + x] = sum / float(cnt)
	return out

# === Сохранение ===

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path: String = OUT_DIR + "gen_smart_01.alm"
	var data: PackedByteArray = _write_alm()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("ERROR: " + path)
		return
	f.store_buffer(data)
	f.close()
	var m: Dictionary = AlmLoader.load_map(path)
	if not m.is_empty():
		print("OK: %dx%d, tiles=%d, heights=%d" % [
			int(m["width"]), int(m["height"]),
			int(m["tiles"].size()), int(m["heights"].size()),
		])
		# Статистика
		var tc := {}
		for i in range(W * H):
			var tt: int = _terrain[i]
			tc[tt] = tc.get(tt, 0) + 1
		var total: float = W * H
		print("Terrain: трава=%.1f%% горы=%.1f%% вода=%.1f%% дорога=%.1f%%" % [
			tc.get(0, 0) * 100.0 / total, tc.get(1, 0) * 100.0 / total,
			tc.get(2, 0) * 100.0 / total, tc.get(3, 0) * 100.0 / total])
		var obj_count := 0
		for v in _obstacles:
			if v > 0:
				obj_count += 1
		print("Объектов: %d (%.1f%%)" % [obj_count, obj_count * 100.0 / total])
	else:
		print("ERROR load_map")
	print("Сохранено: " + path)

func _write_alm() -> PackedByteArray:
	var data := PackedByteArray()
	var n: int = W * H
	data.resize(0x14)
	_write_u32(data, 0, 0x0052374D)
	_write_u32(data, 4, 0x14)
	_write_u32(data, 0x0c, 4)

	# Section 0: info (660 bytes)
	var sec0 := PackedByteArray()
	sec0.resize(20 + 660)
	_write_u32(sec0, 8, 660)
	_write_u32(sec0, 12, 0)
	data.append_array(sec0)
	var ds: int = 0x14 + 20
	_write_u32(data, ds, W)
	_write_u32(data, ds + 4, H)
	_write_name(data, ds + 68, "gen_smart_01")

	# Section 1: tiles (uint16 per cell)
	var sec1 := PackedByteArray()
	sec1.resize(20 + n * 2)
	_write_u32(sec1, 8, n * 2)
	_write_u32(sec1, 12, 1)
	data.append_array(sec1)
	var tds: int = ds + 660 + 20
	for i in range(n):
		_write_u16(data, tds + i * 2, _tiles[i])

	# Section 2: heights
	var sec2 := PackedByteArray()
	sec2.resize(20 + n)
	_write_u32(sec2, 8, n)
	_write_u32(sec2, 12, 2)
	data.append_array(sec2)
	var hds: int = tds + n * 2 + 20
	for i in range(n):
		data[hds + i] = _heights[i]

	# Section 3: obstacles
	var sec3 := PackedByteArray()
	sec3.resize(20 + n)
	_write_u32(sec3, 8, n)
	_write_u32(sec3, 12, 3)
	data.append_array(sec3)
	var ods: int = hds + n + 20
	for i in range(n):
		data[ods + i] = _obstacles[i]

	return data

func _write_u32(d: PackedByteArray, off: int, v: int) -> void:
	d[off] = v & 0xFF
	d[off + 1] = (v >> 8) & 0xFF
	d[off + 2] = (v >> 16) & 0xFF
	d[off + 3] = (v >> 24) & 0xFF

func _write_u16(d: PackedByteArray, off: int, v: int) -> void:
	d[off] = v & 0xFF
	d[off + 1] = (v >> 8) & 0xFF

func _write_name(d: PackedByteArray, off: int, s: String) -> void:
	for i in range(mini(0x40, s.length())):
		d[off + i] = s.unicode_at(i) & 0xFF
