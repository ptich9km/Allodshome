extends SceneTree
## Прототип генератора биома: воспроизводит распределение terrain (трава/горы/
## вода/дорога) и среднюю высоту профиля биома (по анализатору карт Nival pvm/).
## Цель: подобрать параметры noise -> чтобы факт совпал с профилем биома.

const PROFILES := {
	"greenlnd": {"grass": 33, "mountain": 30, "water": 35, "road": 2, "havg": 18, "freq": 1.0 / 48.0},
	"tropic":   {"grass": 27, "mountain": 9,  "water": 60, "road": 4, "havg": 10, "freq": 1.0 / 48.0},
	"canyon":   {"grass": 56, "mountain": 29, "water": 7,  "road": 7, "havg": 39, "freq": 1.0 / 40.0},
	"orcish":   {"grass": 62, "mountain": 21, "water": 10, "road": 7, "havg": 39, "freq": 1.0 / 44.0},
	"gothic":   {"grass": 47, "mountain": 31, "water": 18, "road": 5, "havg": 42, "freq": 1.0 / 40.0},
	"som":      {"grass": 41, "mountain": 46, "water": 4,  "road": 9, "havg": 74, "freq": 1.0 / 32.0},
	"nord":     {"grass": 36, "mountain": 38, "water": 17, "road": 9, "havg": 37, "freq": 1.0 / 40.0},
	"islands":  {"grass": 33, "mountain": 18, "water": 35, "road": 14, "havg": 64, "freq": 1.0 / 24.0},
}

const W := 144
const H := 144

func _init() -> void:
	var out_dir := "C:/Temp/opencode/preview"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for name in PROFILES:
		var p: Dictionary = PROFILES[name]
		var res := _gen(p, name.hash())
		_report(name, p, res)
		_render_png(out_dir + "/" + name + ".png", res.get("tiles"), res.get("heights"))
	quit(0)

func _report(name: String, p: Dictionary, res: Dictionary) -> void:
	var txt := "%-9s цель [тр %2d|г %2d|в %2d|дор %2d|h %3d]  факт [тр %5.1f|г %5.1f|в %5.1f|дор %5.1f|h %3d]" % [
		name,
		int(p.get("grass")), int(p.get("mountain")), int(p.get("water")), int(p.get("road")), int(p.get("havg")),
		float(res.get("grass")), float(res.get("mountain")), float(res.get("water")), float(res.get("road")),
		int(res.get("havg")),
	]
	print(txt)
	var lakes: int = res.get("lakes", 0)
	if lakes > 1:
		print("  -> вода разбита на %d регионов (цель: связная масса воды)" % lakes)

## Цветовая карта превью: 0=трава, 1=горы(серое), 2=вода(синее), 3=дорога(жёлтая)
func _render_png(path: String, tiles: Array, heights: Array) -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var cols := {
		0: Color(0.35, 0.55, 0.28),  # трава
		1: Color(0.52, 0.49, 0.45),  # горы
		2: Color(0.25, 0.45, 0.75),  # вода
		3: Color(0.75, 0.68, 0.35),  # дорога
	}
	for y in range(H):
		for x in range(W):
			var i := y * W + x
			var t: int = tiles[i]
			var h: int = heights[i]
			var c: Color = cols[t]
			var light: float = 0.6 + float(h) / 127.0 * 0.5
			img.set_pixel(x, y, Color(c.r * light, c.g * light, c.b * light))
	img.save_png(path)

func _gen(p: Dictionary, seedv: int) -> Dictionary:
	var n := FastNoiseLite.new()
	n.seed = seedv
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = float(p.get("freq"))
	n.fractal_octaves = 4
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0

	# Поле высот в 0..1 + сглаживание (массы воды/гор связные, без шумовой ряби)
	var field := _noise_field(n, W, H)
	for _blur in range(2):
		field = _box_blur(field)

	# Пороги по квантилям: вода = самые низкие, горы = самые высокие
	var field_sorted := field.duplicate()
	field_sorted.sort()
	var water_q: float = float(p.get("water")) / 100.0
	var mountain_q: float = float(p.get("mountain")) / 100.0
	var n_cells := W * H
	var w_idx: int = clampi(int(water_q * n_cells), 0, n_cells - 1)
	var m_idx: int = clampi(n_cells - 1 - int(mountain_q * n_cells), 0, n_cells - 1)
	var water_thr: float = field_sorted[w_idx]
	var mountain_thr: float = field_sorted[m_idx]

	# Классификация тайлов (0=трава, 1=горы, 2=вода, 3=дорога)
	var tiles := PackedInt32Array()
	tiles.resize(n_cells)
	for i in range(n_cells):
		var v: float = field[i]
		if v <= water_thr:
			tiles[i] = 2
		elif v >= mountain_thr:
			tiles[i] = 1
		else:
			tiles[i] = 0

	# Дороги: 1-2 тракта между противоположными краями, ширина 1-2
	_place_roads(tiles, int(p.get("road")))

	var grass := 0
	var mountain := 0
	var water := 0
	var road := 0
	for i in range(n_cells):
		match tiles[i]:
			0:
				grass += 1
			1:
				mountain += 1
			2:
				water += 1
			3:
				road += 1

	var visited := {}
	var lakes := 0
	for y in range(H):
		for x in range(W):
			var key := y * W + x
			if tiles[key] == 2 and not visited.has(key):
				lakes += 1
				_flood(visited, tiles, x, y)

	var total := float(n_cells)
	return {
		"grass": grass * 100.0 / total,
		"mountain": mountain * 100.0 / total,
		"water": water * 100.0 / total,
		"road": road * 100.0 / total,
		"havg": _height_avg(field, water_thr, mountain_thr, int(p.get("havg")), n_cells),
		"lakes": lakes,
	}

func _noise_field(n: FastNoiseLite, w: int, h: int) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(w * h)
	for y in range(h):
		for x in range(w):
			var v: float = (n.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			field[y * w + x] = clampf(v, 0.0, 1.0)
	return field

func _box_blur(field: PackedFloat32Array) -> PackedFloat32Array:
	var out := field.duplicate()
	for y in range(H):
		for x in range(W):
			var sum := 0.0
			var cnt := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					sum += field[ny * W + nx]
					cnt += 1
			out[y * W + x] = sum / float(cnt)
	return out

## Дороги: тракты между случайными точками противоположных краёв.
## Желаемая доля дорог (%): количество трактов подбираем по факту.
func _place_roads(tiles: PackedInt32Array, want_pct: int) -> void:
	var want_cells := W * H * want_pct / 100
	if want_cells <= 0:
		return
	var placed := 0
	var guard := 0
	while placed < want_cells and guard < 12:
		guard += 1
		# точки на противоположных краях
		var from: Vector2i
		var to: Vector2i
		if (guard % 2) == 0:
			from = Vector2i(2, rng().randi_range(2, H - 3))
			to = Vector2i(W - 3, rng().randi_range(2, H - 3))
		else:
			from = Vector2i(rng().randi_range(2, W - 3), 2)
			to = Vector2i(rng().randi_range(2, W - 3), H - 3)
		var p := from
		var steps := 0
		while p != to and steps < 600 and placed < want_cells:
			steps += 1
			var wc := 1 + int(rng().randi_range(0, 1))  # ширина 1-2
			for dx in range(-1, wc):
				var cell := p + Vector2i(dx, 0)
				if _set_road(tiles, cell):
					placed += 1
			# шаг к цели с случайным изгибом
			var to_vec := to - p
			var step := Vector2i(signi(to_vec.x), signi(to_vec.y))
			if rng().randf() < 0.3 and absi(to_vec.x) > 3:
				step.x += rng().randi_range(-1, 1)
			if rng().randf() < 0.3 and absi(to_vec.y) > 3:
				step.y += rng().randi_range(-1, 1)
			p += step
			p.x = clampi(p.x, 0, W - 1)
			p.y = clampi(p.y, 0, H - 1)

func _set_road(tiles: PackedInt32Array, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return false
	var i := cell.y * W + cell.x
	if tiles[i] == 2 or tiles[i] == 1:
		return false  # дороги по суше, а не по воде/горам
	if tiles[i] == 3:
		return false
	tiles[i] = 3
	return true

func rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = 12345
	return _rng

var _rng: RandomNumberGenerator

func _flood(visited: Dictionary, tiles: PackedInt32Array, x0: int, y0: int) -> void:
	var stack := []
	stack.append(Vector2i(x0, y0))
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var k := c.y * W + c.x
		if visited.has(k):
			continue
		if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
			continue
		if tiles[k] != 2:
			continue
		visited[k] = true
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))

func _height_avg(field: PackedFloat32Array, water_thr: float, mountain_thr: float, target: int, n_cells: int) -> int:
	# h = clamp(v*127 + shift, 0, 127). Подбираем shift, чтобы средняя = target.
	var lo := -200.0
	var hi := 200.0
	for _iter in range(40):
		var shift: float = (lo + hi) * 0.5
		var sum := 0.0
		for i in range(field.size()):
			sum += clampf(field[i] * 127.0 + shift, 0.0, 127.0)
		var avg: float = sum / float(n_cells)
		if avg < float(target):
			lo = shift
		else:
			hi = shift
	var shift: float = (lo + hi) * 0.5
	var sum := 0.0
	for i in range(field.size()):
		sum += clampf(field[i] * 127.0 + shift, 0.0, 127.0)
	return int(round(sum / float(n_cells)))