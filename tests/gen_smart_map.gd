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
var _terrain := PackedByteArray()

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
	# Try with sub numbers first (NW1, NW2, N1, N2 etc)
	for sub in ["1", "2"]:
		var key: String = "%d:%s%s:%d" % [type_a, dir, sub, type_b]
		var spec: Dictionary = _rules.get(key, {})
		if not spec.is_empty():
			return spec
	# Fallback to base direction
	return _rules.get("%d:%s:%d" % [type_a, dir, type_b], {})

# === Генерация ===

func _generate() -> void:
	var n: int = W * H
	_terrain.resize(n)
	_tiles.resize(n)
	_heights.resize(n)
	_obstacles.resize(n)
	_obstacles.fill(0)

	# Determine active terrain types from DB rules
	var active_types: Array = _detect_active_types()
	print("Active terrain types from DB: %s" % str(active_types))

	# 1. Noise → terrain (only active types)
	_place_terrain(n, active_types)

	# 2. Tiles with transitions from DB
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			_tiles[i] = _pick_tile(_terrain[i], x, y)

	# 3. Heights
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			_heights[i] = _pick_height(x, y, _terrain[i], rng)

func _detect_active_types() -> Array:
	# Find all terrain types that appear in rules
	var types := {}
	for key in _rules:
		var parts: Array = key.split(":")
		if parts.size() >= 3:
			var t: int = int(parts[0])
			types[t] = true
	# Always include types that appear as neighbors
	for key in _rules:
		var parts: Array = key.split(":")
		if parts.size() >= 3:
			var t: int = int(parts[2])
			types[t] = true
	return types.keys()

func _place_terrain(n: int, active_types: Array) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 48.0
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5

	var field := PackedFloat32Array()
	field.resize(n)
	for i in range(n):
		var x: float = float(i % W)
		var y: float = float(i / W)
		field[i] = clampf((noise.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)

	for _b in range(3):
		field = _box_blur(field)

	# Sort for thresholds
	var sorted: PackedFloat32Array = field.duplicate()
	sorted.sort()
	var n_cells: int = n

	if active_types.size() <= 1:
		# Single type — fill everything
		_terrain.fill(active_types[0] if active_types.size() > 0 else 0)
		return

	# Multiple types — distribute by noise thresholds
	# Sort types, use first as "low" (water-like), last as "high" (mountain-like)
	# Middle types fill the space between
	active_types.sort()
	var num_types: int = active_types.size()
	for i in range(n_cells):
		var v: float = field[i]
		var idx: int = clampi(int(v * num_types), 0, num_types - 1)
		_terrain[i] = active_types[idx]

func _pick_tile(t: int, x: int, y: int) -> int:
	var s: Dictionary = _sides(x, y)
	# Check all 8 directions for different neighbors
	var has_diff := false
	for d in ["N", "S", "E", "W", "NE", "NW", "SE", "SW"]:
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
	# Try A1-A6 interior variants from rules
	var a_variants: Array = []
	for iv in range(1, 7):
		var key: String = "%d:A%d:%d" % [t, iv, t]
		var spec: Dictionary = _rules.get(key, {})
		if not spec.is_empty():
			a_variants.append(spec)
	if a_variants.size() > 0:
		# Use a simple hash to vary across cells
		var idx: int = abs(t * 7919 + a_variants.size() * 104729) % a_variants.size()
		var spec: Dictionary = a_variants[idx]
		return AlmLoader.tile_from_spec(_spec_for_type(t, spec))

	# Fallback to interior dict
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
	# Collect all directions where neighbor differs
	var cardinal_diff: Array = []
	var diagonal_diff: Array = []
	for d in ["N", "S", "E", "W"]:
		if s[d] != -1 and s[d] != t:
			cardinal_diff.append(d)
	for d in ["NE", "NW", "SE", "SW"]:
		if s[d] != -1 and s[d] != t:
			diagonal_diff.append(d)

	# Try cardinal rules first
	for d in cardinal_diff:
		var neighbor: int = s[d]
		var spec: Dictionary = _get_rule(t, d, neighbor)
		if not spec.is_empty():
			return AlmLoader.tile_from_spec(_spec_for_type(t, spec))

	# Try diagonal rules
	for d in diagonal_diff:
		var neighbor: int = s[d]
		var spec: Dictionary = _get_rule(t, d, neighbor)
		if not spec.is_empty():
			return AlmLoader.tile_from_spec(_spec_for_type(t, spec))

	# No rule found — use interior
	return _interior_tile(t)

## file из правила -> file для кодировки типа A (.alm)
## Теперь palette хранит правильный file, remap не нужен.
func _spec_for_type(type_a: int, spec: Dictionary) -> Dictionary:
	var out := spec.duplicate(true)
	out["variant"] = int(spec.get("variant", 0))
	out["row"] = int(spec.get("row", 0))
	return out

func _pick_height(x: int, y: int, t: int, rng: RandomNumberGenerator) -> int:
	var base: float = 19.0
	match t:
		1: base = 35.0
		2: base = 6.0
		3: base = 17.0
		4: base = 12.0
		5: base = 8.0
		6: base = 10.0
	var variation := rng.randf_range(-0.3, 0.3)
	return int(round(clampf(base * (1.0 + variation), 0.0, 127.0)))

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
