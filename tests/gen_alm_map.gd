extends SceneTree
## Генератор .alm с DIRECTIONAL transitions из transition_db.json.
## База правил заполняется через визуальный редактор в map_editor.

const OUT_DIR := "res://assets/maps/gen/"
const DB_PATH := "res://assets/maps/transition_db.json"
const W := 48
const H := 48
## Тип A -> tile-файл для .alm. В transition_db у песка/грязи file=1 (палитра tile1),
## при генерации пересчитываем по типу, variant/row берём из правила.
const TERRAIN_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7}

var _tiles := PackedInt32Array()
var _heights := PackedByteArray()
var _obstacles := PackedByteArray()
var _terrain := PackedByteArray()
var _transition_db: Dictionary = {}  # transition_db.json
var _rules: Dictionary = {}          # "typeA:dir:typeB" -> {file, variant, row}
var _interior_rules: Dictionary = {} # "type" -> {file, variant, row}

func _init() -> void:
	_load_db()
	_generate()
	_save()
	quit(0)

func _load_db() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		print("WARN: transition_db.json not found, using fallback tiles")
		return
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Dictionary:
		_transition_db = json
		_rules = _transition_db.get("rules", {})
		_interior_rules = _transition_db.get("interior", {})
	print("Loaded transition DB: %d rules, %d interior" % [_rules.size(), _interior_rules.size()])

func _get_rule(type_a: int, dir: String, type_b: int) -> Dictionary:
	return _rules.get("%d:%s:%d" % [type_a, dir, type_b], {})

func _generate() -> void:
	var n: int = W * H
	_terrain.resize(n)
	_tiles.resize(n)
	_heights.resize(n)
	_obstacles.resize(n)

	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 48.0
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5

	var field := PackedFloat32Array()
	field.resize(n)
	for i in range(n):
		field[i] = clampf((noise.get_noise_2d(float(i % W), float(i / W)) + 1.0) * 0.5, 0.0, 1.0)
	for _b in range(2):
		field = _box_blur(field)

	var sorted: PackedFloat32Array = field.duplicate()
	sorted.sort()
	var water_thr: float = sorted[clampi(int(0.35 * n), 0, n - 1)]
	var mountain_thr: float = sorted[clampi(n - 1 - int(0.30 * n), 0, n - 1)]

	for i in range(n):
		var v: float = field[i]
		if v <= water_thr:
			_terrain[i] = 2
		elif v >= mountain_thr:
			_terrain[i] = 1
		else:
			_terrain[i] = 0

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	_place_roads(rng)

	# Directional tiles
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			var t: int = _terrain[i]
			_tiles[i] = _pick_tile(t, x, y)
			_heights[i] = _pick_height(field[i], t, water_thr, mountain_thr)

## Определить какие стороны имеют соседей другого типа
## Возвращает dictionary с ключами N/S/E/W/NE/NW/SE/SW = тип соседа или -1
func _sides(x: int, y: int) -> Dictionary:
	var t: int = _terrain[y * W + x]
	var r := {"N": -1, "S": -1, "E": -1, "W": -1,
			  "NE": -1, "NW": -1, "SE": -1, "SW": -1}
	if y > 0:
		r["N"] = _terrain[(y - 1) * W + x]
	if y < H - 1:
		r["S"] = _terrain[(y + 1) * W + x]
	if x < W - 1:
		r["E"] = _terrain[y * W + x + 1]
	if x > 0:
		r["W"] = _terrain[y * W + x - 1]
	# Диагонали
	if y > 0 and x < W - 1:
		r["NE"] = _terrain[(y - 1) * W + x + 1]
	if y > 0 and x > 0:
		r["NW"] = _terrain[(y - 1) * W + x - 1]
	if y < H - 1 and x < W - 1:
		r["SE"] = _terrain[(y + 1) * W + x + 1]
	if y < H - 1 and x > 0:
		r["SW"] = _terrain[(y + 1) * W + x - 1]
	return r

func _pick_tile(t: int, x: int, y: int) -> int:
	var s: Dictionary = _sides(x, y)
	var has_diff := false
	for d in ["N", "S", "E", "W"]:
		if s[d] != -1 and s[d] != t:
			has_diff = true
			break
	if not has_diff:
		return _interior(t, x, y)
	return _edge(t, s, x, y)

## Интерьер — из transition_db.json (file пересчитываем по типу)
func _interior(t: int, x: int, y: int) -> int:
	var key := str(t)
	if _interior_rules.has(key):
		return AlmLoader.tile_from_spec(_spec_for_type(t, _interior_rules[key]))
	match t:
		0: return AlmLoader.tile_from_spec({"file": 1, "variant": 1, "row": 1})
		1: return AlmLoader.tile_from_spec({"file": 2, "variant": 15, "row": 3})
		2: return AlmLoader.tile_from_spec({"file": 3, "variant": 3, "row": 0})
		3: return AlmLoader.tile_from_spec({"file": 4, "variant": 3, "row": 0})
	return 0

## Edge — ищет правило в transition_db.json
func _edge(t: int, s: Dictionary, x: int, y: int) -> int:
	var diff_cardinals: Array = []
	for d in ["N", "S", "E", "W"]:
		if s[d] != -1 and s[d] != t:
			diff_cardinals.append(d)
	for d in diff_cardinals:
		var spec: Dictionary = _get_rule(t, d, s[d])
		if not spec.is_empty():
			return AlmLoader.tile_from_spec(_spec_for_type(t, spec))
	var diff_diags: Array = []
	for d in ["NE", "NW", "SE", "SW"]:
		if s[d] != -1 and s[d] != t:
			diff_diags.append(d)
	for d in diff_diags:
		var spec: Dictionary = _get_rule(t, d, s[d])
		if not spec.is_empty():
			return AlmLoader.tile_from_spec(_spec_for_type(t, spec))
	return _interior(t, x, y)

## file из правила -> file для кодировки типа A (.alm)
func _spec_for_type(type_a: int, spec: Dictionary) -> Dictionary:
	var out := spec.duplicate(true)
	out["file"] = int(TERRAIN_FILE.get(type_a, int(spec.get("file", 1))))
	out["variant"] = int(spec.get("variant", 0))
	out["row"] = int(spec.get("row", 0))
	return out

func _pick_height(v: float, t: int, water_thr: float, mountain_thr: float) -> int:
	var hval: float
	if t == 2:
		hval = v * 0.5
	elif t == 1:
		hval = 0.6 + v * 0.4
	else:
		hval = 0.35 + v * 0.35
	return int(round(clampf(hval, 0.0, 1.0) * 127.0))

func _place_roads(rng: RandomNumberGenerator) -> void:
	var points: Array = []
	for _i in range(4):
		points.append(Vector2i(rng.randi_range(5, W - 6), rng.randi_range(5, H - 6)))
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
	while p != to and steps < 300:
		steps += 1
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cx: int = p.x + dx
				var cy: int = p.y + dy
				if cx >= 0 and cy >= 0 and cx < W and cy < H:
					var i: int = cy * W + cx
					if _terrain[i] != 2:
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

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path: String = OUT_DIR + "gen_biome_01.alm"
	var data: PackedByteArray = _write_alm()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("ОШИБКА: " + path)
		return
	f.store_buffer(data)
	f.close()
	var m: Dictionary = AlmLoader.load_map(path)
	if not m.is_empty():
		print("OK: %dx%d, tiles=%d, heights=%d" % [
			int(m["width"]), int(m["height"]),
			int(m["tiles"].size()), int(m["heights"].size()),
		])
	else:
		print("ОШИБКА load_map")
	print("Сохранено: " + path)

func _write_alm() -> PackedByteArray:
	var data := PackedByteArray()
	var n: int = W * H
	data.resize(0x14)
	_write_u32(data, 0, 0x0052374D)
	_write_u32(data, 4, 0x14)
	_write_u32(data, 0x0c, 4)

	var sec0 := PackedByteArray()
	sec0.resize(20 + 660)
	_write_u32(sec0, 8, 660)
	_write_u32(sec0, 12, 0)
	data.append_array(sec0)
	var ds: int = 0x14 + 20
	_write_u32(data, ds, W)
	_write_u32(data, ds + 4, H)
	_write_name(data, ds + 68, "gen_biome_01")

	var sec1 := PackedByteArray()
	sec1.resize(20 + n * 2)
	_write_u32(sec1, 8, n * 2)
	_write_u32(sec1, 12, 1)
	data.append_array(sec1)
	var tds: int = ds + 660 + 20
	for i in range(n):
		_write_u16(data, tds + i * 2, _tiles[i])

	var sec2 := PackedByteArray()
	sec2.resize(20 + n)
	_write_u32(sec2, 8, n)
	_write_u32(sec2, 12, 2)
	data.append_array(sec2)
	var hds: int = tds + n * 2 + 20
	for i in range(n):
		data[hds + i] = _heights[i]

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
