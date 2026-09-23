extends SceneTree
## Умный генератор .alm на основе паттернов Beach.alm.
## Noise → terrain → переходы из transition_db → высоты → дороги → объекты.

const OUT_DIR := "res://assets/maps/gen/"
const DB_PATH := "res://assets/maps/transition_db.json"
const SHAPES_PATH := "res://assets/maps/shapes_db.json"
const W := 128
const H := 128
## Тип A -> tile-файл для .alm (в DB у песка/грязи file=1 — палитра tile1)
const TERRAIN_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7}
## 8-bit peer mask bit order — must match tests/analyze_shapes.gd
const SHAPE_DIRS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

var _tiles := PackedInt32Array()
var _heights := PackedByteArray()
var _obstacles := PackedByteArray()
var _terrain := PackedByteArray()

# Transition DB
var _rules: Dictionary = {}
var _interior: Dictionary = {}
# Shape table: "type:maskstr" -> {tiles: [{file,variant,row,w}...], total}
var _shapes: Dictionary = {}
# Interior base textures per type: "0" -> {tiles: [{file,variant,row,w}...], total}
var _base_int: Dictionary = {}
# Универсальный «краевой» row на тип (самый частый среди border-масок).
var _edge_rows := {}
# Шум для интерьера (пер-клеточный, без жёстких worley-чанков).
var _interior_noise: FastNoiseLite
var _interior_hi: FastNoiseLite
# Сдвиг домена шума на тип, чтобы типы не копировали друг друга.
const _NOISE_OFFSETS := {0: 1234, 1: 5678, 2: 9012, 3: 3456, 4: 7890, 5: 2345, 6: 6789}
var _stat_exact := 0
var _stat_subset := 0
var _stat_rules := 0

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
	var sf := FileAccess.open(SHAPES_PATH, FileAccess.READ)
	if sf != null:
		var sjson: Variant = JSON.parse_string(sf.get_as_text())
		sf.close()
		if sjson is Dictionary:
			_shapes = sjson.get("shapes", {})
			_base_int = sjson.get("interior", {})
	print("SHAPES: %d entries, base textures for %d types" % [_shapes.size(), _base_int.size()])
	_compute_edge_rows()

## «Краевой» row на тип: самый частотный row среди форм с >=1 кардинальным
## битом (N/E/S/W) и >= MIN_CELLS клеток. Для травы/гор это «универсальный
## край» (row 4 в анализе pvm-карт), для воды/дороги — свои краевые rows.
func _compute_edge_rows() -> void:
	const MIN_CELLS := 20
	var cardinal_bits := 0x55  # биты N, E, S, W (0,2,4,6)
	var rows_by_type := {}  # t -> {row: total_weight}
	for key in _shapes:
		var parts: Array = String(key).split(":")
		if parts.size() < 2:
			continue
		var t: int = int(parts[0])
		if t < 0 or t > 6:
			continue
		var mask := _mask_from_str(parts[1])
		if mask == 0 or mask & cardinal_bits == 0:
			continue
		var entry: Dictionary = _shapes[key]
		var total: int = int(entry.get("total", 0))
		if total < MIN_CELLS:
			continue
		for ti in entry.get("tiles", []):
			var r: int = int(ti.get("row", -1))
			var w: int = int(ti.get("w", 0))
			if r < 0:
				continue
			if not rows_by_type.has(t):
				rows_by_type[t] = {}
			rows_by_type[t][r] = int(rows_by_type[t].get(r, 0)) + w
	_edge_rows.clear()
	for t in rows_by_type:
		var best_row := -1
		var best_w := 0
		for r in rows_by_type[t]:
			if int(rows_by_type[t][r]) > best_w:
				best_w = int(rows_by_type[t][r])
				best_row = int(r)
		if best_row >= 0:
			_edge_rows[t] = best_row
	print("EDGE_ROWS: %s" % str(_edge_rows))

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

	# 1b. Дороги-коридоры (связные ленты шириной 2 клетки, огибают воду)
	_place_roads(rng_from_seed(4242))

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

func rng_from_seed(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

# === Дороги-коридоры ===
## Рисует 1–2 связных коридора дороги шириной 2 клетки по земле (0/1),
## огибая воду (2). Якоря лежат на противоположных краях карты, но с отступом
## от самой кромки — как в оригинальных .alm (edgeC=0).
func _place_roads(rng: RandomNumberGenerator) -> void:
	var land: Array = _largest_land()
	var count: int = 1 + (1 if rng.randf() < 0.35 else 0)
	for r in range(count):
		_carve_road(land, rng)

func _carve_road(land: Array, rng: RandomNumberGenerator) -> void:
	# Крупнейший связный «материк» суши: внутри него гарантированно существует путь.
	if land.size() < 40:
		return
	# Якоря: клетки материка у противоположных краёв, с отступом от кромки
	var min_x := W
	var max_x := -1
	var min_y := H
	var max_y := -1
	for c in land:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)
	var horiz: bool = rng.randf() < 0.5
	var a: Vector2i = Vector2i.ZERO
	var b: Vector2i = Vector2i.ZERO
	if horiz:
		a = _anchor_in(land, Vector2i(min_x + 1, min_y), Vector2i(min_x + 3, max_y))
		b = _anchor_in(land, Vector2i(max_x - 3, min_y), Vector2i(max_x - 1, max_y))
	else:
		a = _anchor_in(land, Vector2i(min_x, min_y + 1), Vector2i(max_x, min_y + 3))
		b = _anchor_in(land, Vector2i(min_x, max_y - 3), Vector2i(max_x, max_y - 1))
	if a == Vector2i.ZERO or b == Vector2i.ZERO or a == b:
		return
	# A* по суше: гарантирует СВЯЗНУЮ дорогу (компоненты не рвутся у воды).
	var path: Array = _a_star(a, b, rng)
	if path.is_empty():
		return
	for i in range(path.size()):
		var p: Vector2i = path[i]
		# Направление сегмента для перпендикулярной полосы ширины 2
		var seg := Vector2i(0, 0)
		if i + 1 < path.size():
			seg = Vector2i(path[i + 1]) - p
		elif i > 0:
			seg = p - Vector2i(path[i - 1])
		var lane := Vector2i(-seg.y, seg.x) if seg != Vector2i.ZERO else Vector2i(1, 0)
		if lane.x + lane.y < 0:
			lane = -lane
		_set_land_road(p)
		_set_land_road(p + lane)

func _a_star(start: Vector2i, goal: Vector2i, rng: RandomNumberGenerator) -> Array:
	var came: Dictionary = {}
	var gscore: Dictionary = {}
	var fscore: Dictionary = {}
	var gk := start.y * W + start.x
	var gk2 := goal.y * W + goal.x
	gscore[gk] = 0
	fscore[gk] = _astar_h(start, goal)
	var open: Array = [gk]
	while not open.is_empty():
		# выбираем минимальный fscore
		var best_i := 0
		var best_f := -1
		for i in range(open.size()):
			var f := int(fscore.get(open[i], 1 << 30))
			if best_f < 0 or f < best_f:
				best_f = f
				best_i = i
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if cur == gk2:
			# восстанавливаем путь
			var out: Array = []
			var c := cur
			while c != gk:
				var cc: Vector2i = Vector2i(c % W, c / W)
				out.push_front(cc)
				c = int(came.get(c, gk))
			out.push_front(start)
			return out
		var cp: Vector2i = Vector2i(cur % W, cur / W)
		# Направление, с которого пришли (для штрафа за поворот)
		var dir_from_prev := Vector2i(0, 0)
		if came.has(cur):
			var prev_p: Vector2i = Vector2i(int(came[cur]) % W, int(came[cur]) / W)
			dir_from_prev = cp - prev_p
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = cp + d
			if not _is_road_cell(np.x, np.y):
				continue
			var nk: int = np.y * W + np.x
			# Базовая цена шага + штраф за горы (дорога любит траву)
			var stepcost := 10
			if _terrain[nk] == 1:
				stepcost = 18
			# Лёгкое отталкивание от воды: в оригиналах дорога почти не примыкает
			# к воде (adj 0–9%), держимся на расстоянии 1 клетки.
			var near_water_cost := 0
			for wd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var wn: Vector2i = np + wd
				if wn.x >= 0 and wn.y >= 0 and wn.x < W and wn.y < H and _terrain[wn.y * W + wn.x] == 2:
					near_water_cost = 3
					break
			var penalty := 0
			if dir_from_prev != Vector2i.ZERO and dir_from_prev != d:
				penalty = 6
			# детерминированный шум клетки для извилистости трассы
			var jitter: int = (abs(cp.x * 7919 + cp.y * 104729) % 9) - 4
			var tentative: int = int(gscore.get(cur, 1 << 30)) + stepcost + penalty + near_water_cost + jitter
			if tentative < int(gscore.get(nk, 1 << 30)):
				came[nk] = cur
				gscore[nk] = tentative
				fscore[nk] = tentative + _astar_h(np, goal)
				if not open.has(nk):
					open.append(nk)
	return []

func _astar_h(p: Vector2i, goal: Vector2i) -> int:
	return absi(goal.x - p.x) + absi(goal.y - p.y)

func _is_road_cell(x: int, y: int) -> bool:
	if x < 1 or y < 1 or x >= W - 1 or y >= H - 1:
		return false
	var t: int = _terrain[y * W + x]
	return t == 0 or t == 1 or t == 3

func _set_land_road(p: Vector2i) -> void:
	if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
		return
	var idx: int = p.y * W + p.x
	var t: int = _terrain[idx]
	if t == 2:
		return
	_terrain[idx] = 3

func _largest_land() -> Array:
	var seen := {}
	var best: Array = []
	for y in range(H):
		for x in range(W):
			var idx: int = y * W + x
			if seen.has(idx) or _terrain[idx] == 2:
				continue
			var comp: Array = []
			var st: Array = [Vector2i(x, y)]
			seen[idx] = true
			while not st.is_empty():
				var p: Vector2i = st.pop_back()
				comp.append(p)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = p + d
					if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
						continue
					var nk: int = n.y * W + n.x
					if seen.has(nk) or _terrain[nk] == 2:
						continue
					seen[nk] = true
					st.push_back(n)
			if comp.size() > best.size():
				best = comp
	return best

func _anchor_in(land: Array, from: Vector2i, to: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := 999999
	for c in land:
		if c.x < from.x or c.y < from.y or c.x > to.x or c.y > to.y:
			continue
		var cnt := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and _terrain[n.y * W + n.x] != 2:
				cnt += 1
		var d := -cnt
		if d < best_d:
			best_d = d
			best = c
	return best

func _to_land(p: Vector2i) -> Vector2i:
	var best := p
	var best_d := 999999
	for cy in range(maxi(0, p.y - 6), mini(H, p.y + 7)):
		for cx in range(maxi(0, p.x - 6), mini(W, p.x + 7)):
			var dist: int = absi(cx - p.x) + absi(cy - p.y)
			var t: int = _terrain[cy * W + cx]
			if dist < best_d and t != 2 and t != 3:
				best = Vector2i(cx, cy)
				best_d = dist
	return best

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
	# Умеренно-высокочастотная составляющая: делает берег извилистым,
	# как в оригинальных .alm (compactness ~1.5), не ломая связность воды/гор.
	var coastal := FastNoiseLite.new()
	coastal.seed = 7001
	coastal.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coastal.frequency = 1.0 / 16.0
	coastal.fractal_octaves = 4
	coastal.fractal_gain = 0.5
	# Тонкая «рябь» берега — мелкие бухты и мысы вдоль линии воды.
	var fine := FastNoiseLite.new()
	fine.seed = 7002
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.frequency = 1.0 / 7.0
	fine.fractal_octaves = 2
	fine.fractal_gain = 0.5

	# Поле высот 0..1 + лёгкое сглаживание, чтобы массы воды/гор были связными
	var field := PackedFloat32Array()
	field.resize(n)
	for i in range(n):
		var x: float = float(i % W)
		var y: float = float(i / W)
		var base: float = (noise.get_noise_2d(x, y) + 1.0) * 0.5
		var det: float = (coastal.get_noise_2d(x, y) + 1.0) * 0.5
		var ripple: float = (fine.get_noise_2d(x, y) + 1.0) * 0.5
		field[i] = clampf(base * 0.55 + det * 0.3 + ripple * 0.15, 0.0, 1.0)
	field = _box_blur(field)

	if active_types.size() <= 1:
		_terrain.fill(active_types[0] if active_types.size() > 0 else 0)
		return

	# Квантильные пороги по профилю (как в gen_biome.gd), а НЕ равные сегменты.
	# Это убирает перекос к горам/воде, когда поле скучено вокруг 0.5.
	var has_water: bool = active_types.has(2)
	var has_mountain: bool = active_types.has(1)
	# Роли для остальных типов: всё, что не вода/горы, занимает «середину».
	var sorted := field.duplicate()
	sorted.sort()
	var water_q := 0.32  # низкие значения
	var mountain_q := 0.20  # высокие значения
	if not has_water:
		water_q = 0.0
	if not has_mountain:
		mountain_q = 0.0
	var w_idx: int = clampi(int(water_q * n), 0, n - 1)
	var m_idx: int = clampi(n - 1 - int(mountain_q * n), 0, n - 1)
	var water_thr: float = sorted[w_idx]
	var mountain_thr: float = sorted[m_idx]

	# Список «серединных» типов (трава, почва, песок, грязь — что есть).
	# Дорога (3) НЕ входит: она рисуется отдельным проходом как связный коридор
	# шириной 2 клетки (в оригинале это одна лента, а не шумовые пятна).
	var mid_types: Array = []
	for t in active_types:
		if t != 2 and t != 1 and t != 3:
			mid_types.append(t)
	mid_types.sort()
	# Каждый серединный тип получает равный диапазон между (water_thr, mountain_thr)
	for i in range(n):
		var v: float = field[i]
		if has_water and v <= water_thr:
			_terrain[i] = 2
			continue
		if has_mountain and v >= mountain_thr:
			_terrain[i] = 1
			continue
		if mid_types.is_empty():
			_terrain[i] = 0
			continue
		# Серединный тип: нормализуем v в [water_thr, mountain_thr] -> индекс по типам
		var lo: float = water_thr if has_water else sorted[0]
		var hi: float = mountain_thr if has_mountain else sorted[n - 1]
		var span: float = maxf(0.0001, hi - lo)
		var u: float = clampf((v - lo) / span, 0.0, 1.0)
		var accu := 0.0
		for j in range(mid_types.size()):
			accu += 1.0 / float(mid_types.size())
			if u <= accu or j == mid_types.size() - 1:
				_terrain[i] = mid_types[j]
				break

func _pick_tile(t: int, x: int, y: int) -> int:
	var s: Dictionary = _sides(x, y)
	var mask := _mask_from_sides(s, t)
	if mask == 0:
		return _interior_tile(t, x, y)
	# 1. Exact shape from real-map audit (weighted top tiles)
	var spec := _shape_lookup(t, mask, x, y)
	if not spec.is_empty():
		_stat_exact += 1
		return AlmLoader.tile_from_spec(spec)
	# 2. Fallback: old directional rules (first matching direction)
	_stat_rules += 1
	return _edge_tile(t, s, x, y)

## Bit layout must match tests/analyze_shapes.gd: [N, NE, E, SE, S, SW, W, NW]
const CARDINAL_BITS := 0x55  # биты N(0), E(2), S(4), W(6)
## Варианты кромки травы, визуально почти идентичные (L1 4-20 тыс).
## v0/v2/v3 — «почвенные» (L1 26-46 тыс): на ровной кромке выглядят
## врезанными квадратами, сценаристы на простые границы их не ставили.
const GRASS_EDGE_VARIANTS := [1, 5, 9, 12, 13, 14]
func _mask_from_sides(s: Dictionary, t: int) -> int:
	var mask := 0
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for d in range(8):
		var n: int = s[dirs[d]]
		if n != -1 and n != t:
			mask |= (1 << d)
	return mask

func _mask_str(mask: int) -> String:
	var out := ""
	for d in range(8):
		out += "1" if (mask & (1 << (7 - d))) != 0 else "0"
	return out

## Exact shape -> hybrid (types 4-6 borrow grass topology) -> nearest mask.
## Returns {file, variant, row} or {} if nothing found.
func _shape_lookup(t: int, mask: int, x: int, y: int) -> Dictionary:
	var key := "%d:%s" % [t, _mask_str(mask)]
	if _shapes.has(key):
		return _shape_tile(t, _shapes[key], x, y, mask)
	# Hybrid: soil/sand/mud have no real art — borrow grass(0) shapes,
	# re-render into their own tile file via TERRAIN_FILE.
	if t >= 4:
		var tkey := "0:%s" % _mask_str(mask)
		if _shapes.has(tkey):
			return _shape_tile(t, _shapes[tkey], x, y, mask)
	# Nearest mask by Hamming distance for this type (or grass for 4-6)
	_stat_subset += 1
	var best_key := ""
	var best_dist := 99
	var best_total := -1
	var types: Array = [t] if t <= 3 else [t, 0]
	for tt in types:
		var prefix := "%d:" % tt
		for k in _shapes:
			var ks: String = str(k)
			if not ks.begins_with(prefix):
				continue
			var sm := _mask_from_str(ks.substr(prefix.length()))
			var dist := _popcount(sm ^ mask)
			var total: int = _shapes[k].get("total", 0)
			if dist < best_dist or (dist == best_dist and total > best_total):
				best_dist = dist
				best_key = ks
				best_total = total
	if best_key.is_empty():
		return {}
	return _shape_tile(t, _shapes[best_key], x, y, mask)

## Весовой выбор из формы. Для граничных клеток с кардинальной маской
## сужаем кандидатов до «краевого» row типа — иначе топ-тайл может быть
## внутренней текстурой и рвать ровную линию кромки.
func _shape_tile(t: int, entry: Dictionary, x: int, y: int, mask: int) -> Dictionary:
	var tiles: Array = entry.get("tiles", [])
	if tiles.is_empty():
		return {}
	var candidates: Array = tiles
	if mask & CARDINAL_BITS != 0:
		var art_t := t if t <= 3 else 0
		# Универсальный «край» есть только у травы (0) и гор (1) — один row на
		# любой кардинальный переход. Вода анимирована (rows 0..7), дорога имеет
		# свои краевые rows по соседям — им единый row навязывать нельзя.
		if (art_t == 0 or art_t == 1) and _edge_rows.has(art_t):
			var er: int = _edge_rows[art_t]
			var filtered: Array = []
			for ti in tiles:
				if int(ti.get("row", -1)) == er:
					# Кромка травы: только «зелёные» варианты. v0/v2/v3 — темнее,
					# выглядят «квадратами почвы» на ровной линии, их сценаристы
					# не ставили на простые кромки. Семейство v1/v5/v9/v12/v13/v14
					# пиксельно почти идентично (L1 4-20 тыс vs 26-46 тыс у v0/2/3).
					if art_t == 0 and int(ti.get("variant", -1)) in GRASS_EDGE_VARIANTS:
						filtered.append(ti)
					elif art_t != 0:
						filtered.append(ti)
			if filtered.is_empty():
				# Краевых кандидатов нет — пусть _pick_tile уйдёт в rules-fallback
				# (ровная кромка по типу соседа), а не возьмёт внутренние текстуры.
				return {}
			candidates = filtered
	var total := 0
	for ti in candidates:
		total += int(ti.get("w", 0))
	if total <= 0:
		return {}
	var h: int = hash(Vector2i(x, y))
	var r: int = abs(h) % total
	var acc := 0
	var picked: Dictionary = candidates[candidates.size() - 1]
	for ti in candidates:
		acc += int(ti.get("w", 0))
		if r < acc:
			picked = ti
			break
	var out := {
		"file": int(picked.get("file", 1)),
		"variant": int(picked.get("variant", 0)),
		"row": int(picked.get("row", 0)),
	}
	if t >= 4:
		out["file"] = int(TERRAIN_FILE.get(t, out["file"]))
	return out

func _mask_from_str(s: String) -> int:
	var m := 0
	for i in range(mini(8, s.length())):
		if s[i] == "1":
			m |= 1 << (7 - i)
	return m

func _popcount(v: int) -> int:
	var c := 0
	for i in range(8):
		if v & (1 << i):
			c += 1
	return c

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

func _interior_tile(t: int, x: int, y: int = -1) -> int:
	# 1. Base textures from real maps: low-frequency noise per cell -> one of
	#    top-6 tiles. Плавное поле даёт связные «поля» без жёстких worley-чанков.
	var base: Dictionary = _base_int.get(str(t), {})
	var tiles: Array = base.get("tiles", [])
	if not tiles.is_empty():
		var total := 0
		for ti in tiles:
			total += int(ti.get("w", 0))
		var val := _interior_value(x, y, t, total)
		var pick: Dictionary = tiles[tiles.size() - 1]
		if total > 0:
			var r: int = val
			var acc := 0
			for ti in tiles:
				acc += int(ti.get("w", 0))
				if r < acc:
					pick = ti
					break
		var spec := {
			"file": int(pick.get("file", 1)),
			"variant": int(pick.get("variant", 0)),
			"row": int(pick.get("row", 0)),
		}
		if t >= 4:
			spec["file"] = int(TERRAIN_FILE.get(t, spec["file"]))
		return AlmLoader.tile_from_spec(spec)

	# 2. A1-A6 interior variants from rules
	var a_variants: Array = []
	for iv in range(1, 7):
		var key: String = "%d:A%d:%d" % [t, iv, t]
		var spec: Dictionary = _rules.get(key, {})
		if not spec.is_empty():
			a_variants.append(spec)
	if a_variants.size() > 0:
		# Vary across cells via coordinates (constant hash was a bug:
		# same variant for the whole map).
		var hseed: int = 17
		if x >= 0 and y >= 0:
			hseed = abs(t * 73856093 + x * 19349663 + y * 83492791)
		var idx: int = hseed % a_variants.size()
		var spec: Dictionary = a_variants[idx]
		return AlmLoader.tile_from_spec(_spec_for_type(t, spec))

	# 3. Fallback to interior dict
	var key := str(t)
	if _interior.has(key):
		return AlmLoader.tile_from_spec(_spec_for_type(t, _interior[key]))
	match t:
		0: return AlmLoader.tile_from_spec({"file": 1, "variant": 1, "row": 1})
		1: return AlmLoader.tile_from_spec({"file": 2, "variant": 15, "row": 3})
		2: return AlmLoader.tile_from_spec({"file": 3, "variant": 3, "row": 0})
		3: return AlmLoader.tile_from_spec({"file": 4, "variant": 3, "row": 0})
	return 0

## Плавный низкочастотный шум (частота ~1/14) + лёгкий локальный компонент.
	## Возвращает индекс в диапазоне [0, total): соседние клетки коррелируют —
	## связные «поля» без жёстких 8x8-чанков и без «шахматки».
func _interior_value(x: int, y: int, t: int, total: int) -> int:
	if _interior_noise == null:
		_interior_noise = FastNoiseLite.new()
		_interior_noise.seed = 7
		_interior_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_interior_noise.frequency = 1.0 / 14.0
	if _interior_hi == null:
		_interior_hi = FastNoiseLite.new()
		_interior_hi.seed = 99
		_interior_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_interior_hi.frequency = 1.0 / 60.0
	_interior_noise.seed = 7 + t * 131
	_interior_hi.seed = 99 + t * 271
	var off: int = _NOISE_OFFSETS.get(t, 0)
	var f1: float = (_interior_noise.get_noise_2d(float(x) + off, float(y)) + 1.0) * 0.5
	var f2: float = (_interior_hi.get_noise_2d(float(x) * 2.0 + off, float(y) * 2.0) + 1.0) * 0.5
	var f: float = clampf(f1 * 0.8 + f2 * 0.2, 0.0, 1.0)
	return clampi(int(f * float(total)) % maxi(1, total), 0, maxi(0, total - 1))

func _edge_tile(t: int, s: Dictionary, x: int, y: int) -> int:
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
			# Правила для травы дают v0r4 («почва»). На кромке травы это
			# «врезанный квадрат» — нормализуем вариант до зелёного семейства.
			if t == 0 and int(spec.get("variant", -1)) in [0, 2, 3]:
				spec = {"file": 1, "variant": 13, "row": int(spec.get("row", 4))}
			return AlmLoader.tile_from_spec(_spec_for_type(t, spec))

	# Try diagonal rules
	for d in diagonal_diff:
		var neighbor: int = s[d]
		var spec: Dictionary = _get_rule(t, d, neighbor)
		if not spec.is_empty():
			return AlmLoader.tile_from_spec(_spec_for_type(t, spec))

	# No rule found — use interior
	return _interior_tile(t, x, y)

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
	# Лёгкое сглаживание (3×3): сохраняет извилистость берега, убирая только
	# одиночные пиксели-артефакты шума.
	var out: PackedFloat32Array = field.duplicate()
	for y in range(H):
		for x in range(W):
			var sum := 0.0
			var cnt := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
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
		print("Shapes: exact=%d subset=%d rules-fallback=%d" % [
			_stat_exact, _stat_subset, _stat_rules])
		_road_stats(tc.get(3, 0))
		var obj_count := 0
		for v in _obstacles:
			if v > 0:
				obj_count += 1
		print("Объектов: %d (%.1f%%)" % [obj_count, obj_count * 100.0 / total])
	else:
		print("ERROR load_map")
	print("Сохранено: " + path)

func _road_stats(road_cells: int) -> void:
	# Компоненты связности дороги (4-соседи)
	var seen := {}
	var comps: Array = []
	for y in range(H):
		for x in range(W):
			var idx: int = y * W + x
			if seen.has(idx) or _terrain[idx] != 3:
				continue
			var size := 0
			var st: Array = [Vector2i(x, y)]
			seen[idx] = true
			while not st.is_empty():
				var p: Vector2i = st.pop_back()
				size += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = p + d
					if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
						continue
					var nk: int = n.y * W + n.x
					if seen.has(nk) or _terrain[nk] != 3:
						continue
					seen[nk] = true
					st.push_back(n)
			comps.append(size)
	comps.sort()
	comps.reverse()
	# bbox главного компонента и ширина дороги
	var main_bbox := Rect2i()
	var main_flat := 0
	var width_cnt := {}
	var adj_cnt := {}
	if not comps.is_empty():
		var ms := 0
		for y in range(H):
			for x in range(W):
				var idx: int = y * W + x
				if _terrain[idx] != 3:
					continue
				if ms == 0:
					main_bbox = Rect2i(Vector2i(x, y), Vector2i(1, 1))
					ms = 1
				else:
					if x < main_bbox.position.x:
						main_bbox.position.x = x
					if y < main_bbox.position.y:
						main_bbox.position.y = y
					if x - main_bbox.position.x + 1 > main_bbox.size.x:
						main_bbox.size.x = x - main_bbox.position.x + 1
					if y - main_bbox.position.y + 1 > main_bbox.size.y:
						main_bbox.size.y = y - main_bbox.position.y + 1
		# ширина: сколько дорожных клеток в колонке bbox (гориз. маршрут) или строке
		for y in range(main_bbox.position.y, main_bbox.position.y + main_bbox.size.y):
			var cnt := 0
			for x in range(main_bbox.position.x, main_bbox.position.x + main_bbox.size.x):
				if _terrain[y * W + x] == 3:
					cnt += 1
			if cnt > 0:
				width_cnt[cnt] = width_cnt.get(cnt, 0) + 1
				main_flat += cnt
		# примыкание: доля соседей дороги по terrain
		for y in range(H):
			for x in range(W):
				var idx: int = y * W + x
				if _terrain[idx] != 3:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = Vector2i(x, y) + d
					if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
						continue
					var nt: int = _terrain[n.y * W + n.x]
					if nt != 3 and nt != -1:
						adj_cnt[nt] = adj_cnt.get(nt, 0) + 1
	print("ROAD: cells=%d comps=%s bbox=%s widths=%s adj=%s" % [
		road_cells, str(comps), str(main_bbox), str(width_cnt), str(adj_cnt)])

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
