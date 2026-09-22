extends SceneTree
## Процедурный генератор .alm карт — строго по текстурам PVM разработчиков.
## Только 4 типа: grass(tile1), mountain(tile2), water(tile3), road(tile4).
## Autotile-aware tile selection с variational interior.

const OUT_DIR := "res://assets/maps/gen/"
const DB_PATH := "res://assets/maps/transition_db.json"
const W := 64
const H := 64

# Tile file for each terrain type (type 0 = tile1, type 1 = tile2, etc.)
const TERRAIN_FILES := {0: 1, 1: 2, 2: 3, 3: 4}

var _tiles := PackedInt32Array()
var _heights := PackedByteArray()
var _obstacles := PackedByteArray()
var _terrain := PackedByteArray()
var _field := PackedFloat32Array()
var _rules: Dictionary = {}
var _interior_rules: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = int(Time.get_ticks_msec())
	_load_db()
	_generate()
	_save()
	print("OK: %dx%d grid generated" % [W, H])
	quit(0)

# === Load transition database ===

func _load_db() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		print("WARN: transition_db.json not found")
		return
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Dictionary:
		_rules = json.get("rules", {})
		_interior_rules = json.get("interior", {})
	print("DB loaded: %d rules, %d interior" % [_rules.size(), _interior_rules.size()])

func _get_rule(type_a: int, dir: String, type_b: int) -> Dictionary:
	return _rules.get("%d:%s:%d" % [type_a, dir, type_b], {"file":0,"variant":0,"row":0})

# === Terrain generation ===

func _generate() -> void:
	var n: int = W * H
	_terrain.resize(n)
	_tiles.resize(n)
	_heights.resize(n)
	_obstacles.resize(n)
	_field.resize(n)

	# Three independent noise layers — exactly as PVM maps work
	var noise_grass := FastNoiseLite.new()
	noise_grass.seed = 42
	noise_grass.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_grass.frequency = 1.0 / float(W)
	noise_grass.fractal_octaves = 5
	noise_grass.fractal_gain = 0.5

	var noise_water := FastNoiseLite.new()
	noise_water.seed = 137
	noise_water.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_water.frequency = 1.0 / float(W)
	noise_water.fractal_octaves = 4
	noise_water.fractal_gain = 0.4

	var noise_mountains := FastNoiseLite.new()
	noise_mountains.seed = 256
	noise_mountains.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_mountains.frequency = 3.0 / float(W)
	noise_mountains.fractal_octaves = 6
	noise_mountains.fractal_gain = 0.55

	for i in range(n):
		var x: float = float(i % W)
		var y: float = float(i / W)
		var g: float = clampf((noise_grass.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
		var wv: float = clampf((noise_water.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
		var mv: float = clampf((noise_mountains.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
		mv = pow(mv, 1.8)  # Sharpen peaks for mountains
		_field[i] = g
		# Store wv and mv in a structured way for later access
		_store_extra(i, wv, mv)

	# Assign terrain by percentile-based multi-noise blend (4 types only)
	_assign_terrain_percentiles(noise_water, noise_mountains)

	# Place roads
	_place_roads()

	# Assign tiles with autotile-aware selection AND variability
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			var t: int = _terrain[i]
			_tiles[i] = _pick_tile_autotile(t, x, y)
			_heights[i] = _pick_height(t, x, y)

	_count_terrains()

func _store_extra(idx: int, wv: float, mv: float) -> void:
	# Use unused slots in _field — overwrite after first pass
	pass

# === Percentile-based terrain classification (4 types) ===

func _assign_terrain_percentiles(noise_water: FastNoiseLite, noise_mountains: FastNoiseLite) -> void:
	var n: int = W * H

	# Assign TERRAIN TYPE by noise threshold
	for i in range(n):
		var x: float = float(i % W)
		var y: float = float(i / W)
		var w_val: float = clampf((noise_water.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
		var m_val: float = clampf((noise_mountains.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
		m_val = pow(m_val, 1.3)  # Mild sharpening
		
		if w_val > 0.68:
			_terrain[i] = 2      # water (tile3)
		elif m_val > 0.48:
			_terrain[i] = 1      # mountain (tile2)
		else:
			_terrain[i] = 0      # tile1 — contains sub-biomes below

	# Light smoothing to reduce noise but preserve features
	for _b in range(2):
		_terrain = _smooth_terrain(_terrain)

	# Now ASSIGN sub-biome variant for each tile1 cell
	_sub_biom_assign()

func _sub_biom_assign() -> void:
	"""Assign sub-biome variation info to each tile1 cell.
	Variant ranges within tile1 define biomes:
	    variants [0-5]: Grass-like (~40%)
	    variants [6-10]: Mud-like (~17%)
	    variants [11-14]: Sand-like (~27%)
	    variant 15: Hills (~16%)
	"""
	var noise_sub := FastNoiseLite.new()
	noise_sub.seed = 999
	noise_sub.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_sub.frequency = 1.0 / float(W)
	noise_sub.fractal_octaves = 4
	noise_sub.fractal_gain = 0.45
	
	for i in range(W * H):
		if _terrain[i] != 0:
			continue
		var x: float = float(i % W)
		var y: float = float(i / W)
		var sv: float = clampf((noise_sub.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
		
		# Assign variant based on sub-biome noise threshold
		if sv < 0.38:
			_field[i] = float(_rng.randi_range(0, 5))    # Grass-like
		elif sv < 0.55:
			_field[i] = float(_rng.randi_range(11, 14))   # Sand-like
		elif sv < 0.72:
			_field[i] = float(_rng.randi_range(6, 10))    # Mud-like
		else:
			_field[i] = 15.0                               # Hills

func _smooth_terrain(terrain: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = terrain.duplicate()
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			var votes := {0: 0, 1: 0, 2: 0}
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and nx < W and ny >= 0 and ny < H:
						var nt: int = terrain[ny * W + nx]
						votes[nt] = votes.get(nt, 0) + 1
			# Majority vote
			var best_type: int = 0
			var best_count: int = 0
			for t in votes:
				if votes[t] > best_count:
					best_count = votes[t]
					best_type = t
			out[i] = best_type
	return out

# === Road carving ===

func _place_roads() -> void:
	var pts: Array[Vector2i] = []
	for _i in range(3):
		pts.append(Vector2i(_rng.randi_range(10, W - 11), _rng.randi_range(10, H - 11)))

	var connected: Array[Vector2i] = [pts[0]]
	var remaining: Array[Vector2i] = [pts[1], pts[2]]

	while not remaining.is_empty():
		var best_dist := 999999
		var best_from: Vector2i = Vector2i.ZERO
		var best_to: Vector2i = Vector2i.ZERO
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

		_carve_road(best_from, best_to)
		connected.append(best_to)
		remaining.remove_at(best_ri)

func _carve_road(from_pt: Vector2i, to_pt: Vector2i) -> void:
	var p: Vector2i = from_pt
	var steps: int = 0
	while p != to_pt and steps < 500:
		steps += 1
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cx: int = p.x + dx
				var cy: int = p.y + dy
				if cx >= 0 and cx < W and cy >= 0 and cy < H:
					var idx: int = cy * W + cx
					if _terrain[idx] != 2:
						_terrain[idx] = 3
		var diff: Vector2i = to_pt - p
		var sx: int = signi(diff.x)
		var sy: int = signi(diff.y)
		if _rng.randf() < 0.3:
			if absi(diff.x) > absi(diff.y):
				sy = _rng.randi_range(-1, 1)
			else:
				sx = _rng.randi_range(-1, 1)
		p.x = clampi(p.x + sx, 0, W - 1)
		p.y = clampi(p.y + sy, 0, H - 1)

# === Autotile-aware tile selection ===

func _get_neighbors(x: int, y: int) -> Dictionary:
	return {
		"N": -1 if y == 0 else _terrain[(y-1)*W+x],
		"S": -1 if y == H-1 else _terrain[(y+1)*W+x],
		"E": -1 if x == W-1 else _terrain[y*W+x+1],
		"W": -1 if x == 0 else _terrain[y*W+x-1],
		"NE": -1 if y==0 or x==W-1 else _terrain[(y-1)*W+x+1],
		"NW": -1 if y==0 or x==0 else _terrain[(y-1)*W+x-1],
		"SE": -1 if y==H-1 or x==W-1 else _terrain[(y+1)*W+x+1],
		"SW": -1 if y==H-1 or x==0 else _terrain[(y+1)*W+x-1],
	}

func _get_neighbor_type_counts(s: Dictionary) -> Dictionary:
	var result := {}
	for dir_key in s:
		var nt: int = s[dir_key]
		if nt >= 0:
			result[nt] = result.get(nt, 0) + 1
	return result

func _pick_tile_autotile(t: int, x: int, y: int) -> int:
	var s: Dictionary = _get_neighbors(x, y)
	var diff_types: Dictionary = _get_neighbor_type_counts(s)

	if diff_types.is_empty():
		# Pure interior — pick tile using sub-biome from _field[x+y*W]
		var idx: int = y * W + x
		var sub_variant: float = _field[idx]
		
		# Deterministic row based on sub-biome + position (not random!)
		var noise_row := FastNoiseLite.new()
		noise_row.seed = t * 1000 + int(sub_variant)
		noise_row.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise_row.frequency = 0.5 / float(W)
		var row_val: float = clampf((noise_row.get_noise_2d(float(x), float(y)) + 1.0) * 0.5, 0.0, 1.0)
		
		# Pick row from appropriate range based on sub-biome
		var biomes: Dictionary = {0: [0,5], 6: [6,10], 11: [11,14], 15: [15]} # Grass-like, Mud-like, Sand-like, Hills
		var var_int := int(sub_variant)
		var row_range: Array = biomes.get(var_int, [0, 5])
		var row: int = row_range[0] + int(row_val * float(row_range[1] - row_range[0]))
		
		return AlmLoader.tile_from_spec({"file": TERRAIN_FILES[t], "variant": int(sub_variant), "row": row})

	# Cardinal and diagonal edges with their neighbor types
	var card_dirs: Array[String] = []
	for d in ["N", "S", "E", "W"]:
		if s[d] != -1 and s[d] != t:
			card_dirs.append(d)

	var diag_dirs: Array[String] = []
	for d in ["NE", "NW", "SE", "SW"]:
		if s[d] != -1 and s[d] != t:
			diag_dirs.append(d)

	var num_unique_types: int = diff_types.size()

	if card_dirs.size() > 0:
		return _pick_edge(t, s, card_dirs, diag_dirs, num_unique_types)
	elif diag_dirs.size() > 0:
		return _pick_diag_edge(t, s, diag_dirs, num_unique_types)

	# Fallback interior
	return _pick_interior_varied(t)

func _pick_interior_varied(t: int) -> int:
	"""Pick interior tile with random variation from known patterns."""
	var key: String = str(t)
	
	# Define interior pattern pools per terrain type
	var patterns: Dictionary = {
		0: [{"file": 1, "variant": 3, "row": 5},    # grass interior base
		    {"file": 1, "variant": 1, "row": 1},     # grass var 2
		    {"file": 1, "variant": 3, "row": 0}],    # grass var 3
		1: [{"file": 2, "variant": 15, "row": 3},   # mountain interior base
		    {"file": 2, "variant": 13, "row": 5},    # mountain var 2
		    {"file": 2, "variant": 11, "row": 1}],   # mountain var 3
		2: [{"file": 3, "variant": 3, "row": 0},    # water interior base
		    {"file": 3, "variant": 5, "row": 1},     # water var 2
		    {"file": 3, "variant": 1, "row": 2}],    # water var 3
		3: [{"file": 4, "variant": 3, "row": 0},    # road interior base
		    {"file": 4, "variant": 1, "row": 2}],    # road var 2
	}
	
	if patterns.has(t):
		var pool: Array = patterns[t]
		var chosen: Dictionary = pool[_rng.randi_range(0, pool.size()-1)]
		return AlmLoader.tile_from_spec(chosen)
	
	# Fallback
	return _pick_default_interior(t)

func _pick_default_interior(t: int) -> int:
	match t:
		0: return AlmLoader.tile_from_spec({"file": 1, "variant": 3, "row": 5})
		1: return AlmLoader.tile_from_spec({"file": 2, "variant": 15, "row": 3})
		2: return AlmLoader.tile_from_spec({"file": 3, "variant": 3, "row": 0})
		3: return AlmLoader.tile_from_spec({"file": 4, "variant": 3, "row": 0})
	return AlmLoader.tile_from_spec({"file": 1, "variant": 0, "row": 0})

func _pick_edge(center_t: int, neighbors: Dictionary, card_dirs: Array[String], diag_dirs: Array[String], unique_types: int) -> int:
	"""Pick edge tile - use first matching direction but select row by context."""
	
	# Try each direction until we find a valid rule for THIS terrain
	var base_spec: Dictionary = {}
	var found_dir := ""
	
	for d in (card_dirs + diag_dirs):
		var nt: int = neighbors[d]
		# Look up center->neighbor FIRST
		var spec := _get_rule(center_t, d, nt)
		if not spec.is_empty():
			base_spec = spec
			found_dir = d
			break
	
	# Fallback: reverse lookup center←neighbor
	if base_spec.is_empty():
		for d in (card_dirs + diag_dirs):
			var nt: int = neighbors[d]
			var rev := _get_rule(nt, d, center_t)
			if not rev.is_empty():
				base_spec = rev
				found_dir = d
				break
	
	if base_spec.is_empty():
		return _pick_interior_varied(center_t)
	
	# Select ROW based on autotile cluster — row encodes neighbor CONFIGURATION
	var row: int = int(base_spec.get("row", 4))
	if unique_types == 1:
		# Clean boundary: keep DB row (typically 4)
		row = max(0, min(row, 5))
	elif unique_types == 2:
		# Mixed: pick from r8 cluster
		row = 6 + int(_rng.randf() * 4.0)
	else:
		# Complex multi-directional: pick from r12 cluster  
		row = 10 + int(_rng.randf() * 4.0)
	
	base_spec["variant"] = float(int(base_spec.get("variant", 0)))
	base_spec["row"] = float(row)
	return AlmLoader.tile_from_spec(base_spec)

func _pick_diag_edge(center_t: int, neighbors: Dictionary, diag_dirs: Array[String], unique_types: int) -> int:
	"""Diagonal-only edges use center→neighbor lookup."""
	var base_spec: Dictionary = {}
	
	if diag_dirs.size() > 0:
		base_spec = _get_rule(center_t, diag_dirs[0], neighbors[diag_dirs[0]])
	
	if base_spec.is_empty():
		for d in diag_dirs:
			var nt: int = neighbors[d]
			var rev := _get_rule(nt, d, center_t)
			if not rev.is_empty():
				base_spec = rev
				break
	
	if base_spec.is_empty():
		return _pick_interior_varied(center_t)
	
	# Select ROW based on autotile cluster
	var row: int = int(base_spec.get("row", 4))
	if unique_types == 1:
		row = max(0, min(row, 5))
	elif unique_types == 2:
		row = 6 + int(_rng.randf() * 4.0)
	else:
		row = 10 + int(_rng.randf() * 4.0)
	
	base_spec["variant"] = float(int(base_spec.get("variant", 0)))
	base_spec["row"] = float(row)
	return AlmLoader.tile_from_spec(base_spec)

func _rule_exists(rules: Array[Dictionary], rule: Dictionary) -> bool:
	var rf: int = int(rule.get("file", 0))
	var rv: int = int(rule.get("variant", 0))
	var rr: int = int(rule.get("row", 0))
	for r in rules:
		if int(r.get("file", 0)) == rf and int(r.get("variant", 0)) == rv and int(r.get("row", 0)) == rr:
			return true
	return false

func _spec_for_type(type_a: int, spec: Dictionary) -> Dictionary:
	var out := spec.duplicate(true)
	match type_a:
		0: out["file"] = 1  # grass -> tile1
		1: out["file"] = 2  # mountain -> tile2
		2: out["file"] = 3  # water -> tile3
		3: out["file"] = 4  # road -> tile4
	out["variant"] = int(spec.get("variant", 0))
	out["row"] = int(spec.get("row", 0))
	return out

func _pick_height(t: int, x: int, y: int) -> int:
	match t:
		2: return 20  # water: low
		1: return 80 + _rng.randi_range(0, 47)  # mountain: high
		_: return 40 + (x * 7 + y * 13) % 30  # others: medium

func _count_terrains() -> void:
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for t in _terrain:
		counts[t] = counts.get(t, 0) + 1
	var total: int = W * H
	print("Terrain: grass=%d (%.1f%%), mountain=%d (%.1f%%), water=%d (%.1f%%), road=%d (%.1f%%)" % [
		counts.get(0,0), 100.0*counts.get(0,0)/total,
		counts.get(1,0), 100.0*counts.get(1,0)/total,
		counts.get(2,0), 100.0*counts.get(2,0)/total,
		counts.get(3,0), 100.0*counts.get(3,0)/total])

# === Save .alm file ===

func _save() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path: String = OUT_DIR + "gen_procedural_v3.alm"
	var data: PackedByteArray = _write_alm()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("ERROR writing: " + path)
		return
	f.store_buffer(data)
	f.close()
	
	var m := AlmLoader.load_map(path)
	if not m.is_empty():
		print("Loaded OK: %dx%d, tiles=%d" % [m["width"], m["height"], m["tiles"].size()])
		print("Map saved to: " + path)
	else:
		print("FAIL: couldn't load back map")

func _write_alm() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(0x14)
	_write_u32(data, 0, 0x0052374D)
	_write_u32(data, 4, 0x14)
	_write_u32(data, 0x0c, 4)

	# Section 0: info
	var sec0: PackedByteArray = PackedByteArray()
	sec0.resize(20 + 660)
	_write_u32(sec0, 8, 660)
	_write_u32(sec0, 12, 0)
	data.append_array(sec0)
	var ds: int = 0x14 + 20
	_write_u32(data, ds, W)
	_write_u32(data, ds + 4, H)
	_write_name(data, ds + 68, "gen_procedural_v3")

	# Section 1: tiles
	var n: int = W * H
	var sec1: PackedByteArray = PackedByteArray()
	sec1.resize(20 + n * 2)
	_write_u32(sec1, 8, n * 2)
	_write_u32(sec1, 12, 1)
	data.append_array(sec1)
	var tds: int = ds + 660 + 20
	for i in range(n):
		_write_u16(data, tds + i * 2, _tiles[i])

	# Section 2: heights
	var sec2: PackedByteArray = PackedByteArray()
	sec2.resize(20 + n)
	_write_u32(sec2, 8, n)
	_write_u32(sec2, 12, 2)
	data.append_array(sec2)
	var hds: int = tds + n * 2 + 20
	for i in range(n):
		data[hds + i] = _heights[i]

	# Section 3: obstacles
	var sec3: PackedByteArray = PackedByteArray()
	sec3.resize(20 + n)
	_write_u32(sec3, 8, n)
	_write_u32(sec3, 12, 3)
	data.append_array(sec3)
	var ods: int = hds + n + 20
	for i in range(n):
		data[ods + i] = _obstacles[i]

	return data

func _write_u32(d: PackedByteArray, off: int, v: int) -> void:
	d[off] = v & 0xFF; d[off + 1] = (v >> 8) & 0xFF; d[off + 2] = (v >> 16) & 0xFF; d[off + 3] = (v >> 24) & 0xFF

func _write_u16(d: PackedByteArray, off: int, v: int) -> void:
	d[off] = v & 0xFF; d[off + 1] = (v >> 8) & 0xFF

func _write_name(d: PackedByteArray, off: int, s: String) -> void:
	for i in range(mini(0x40, s.length())):
		d[off + i] = s.unicode_at(i) & 0xFF
