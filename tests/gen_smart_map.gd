extends SceneTree
## Умный генератор .alm на основе паттернов Beach.alm.
## Noise → terrain → переходы из transition_db → высоты → дороги → объекты.

const OUT_DIR := "res://assets/maps/gen/"
const DB_PATH := "res://assets/maps/transition_db.json"
const SHAPES_PATH := "res://assets/maps/shapes_db.json"
const W := 128
const H := 128
## Тип A -> tile-файл для .alm (песок/грязь/почва — свои BMP-файлы)
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
var _field := PackedFloat32Array()
var _water_thr: float = 0.0
var _mountain_thr: float = 0.0

# Спавн (структуры/npc sidecar-ами): зарезервированные клетки и выходные записи.
var _reserved := {}           # Vector2i -> true (здания, спавн, портал)
var _structures_out: Array = []   # {x, y, type_id}
var _npcs_out: Array = []         # {x, y, set, role, patrol, post, hp_max, damage}
var _herbs_out: Array = []        # {x, y, item, icon}
var _obj_noise: FastNoiseLite

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
	_reserved.clear()
	_structures_out.clear()
	_npcs_out.clear()
	_herbs_out.clear()

	# 1. Почва Voronoi (база, без гор/воды/дороги)
	_place_terrain(n)

	var rng := rng_from_seed(4242)

	# 2. Города: овалы ~11×11 дорогой (type 3), по профилю зоны
	_place_cities(rng)

	# 3. Дороги: MST по городам + A*-коридоры ширины 2
	_connect_cities(rng)

	# 4. Горы/вода поверх экстремумов рельефа, не перетирая дорогу (3)
	_place_mountains_water()

	# 5. Portal + Spawn маркеры (у города №0)
	_place_portal_spawn()

	# 6. City content: здания + НПЦ городов (после известных спавна/портала)
	_place_city_content(rng)

	# 7. Деревья/объекты (заполняют _obstacles, обходя города/дороги/спавн)
	_place_objects(rng)

	# 8. Травы: отдельные collectible-узлы, не препятствия
	_place_herbs(rng_from_seed(8642))

	# 9. Серые: кластеры у дорог и в лесу (только на не-занятых клетках)
	_place_greys(rng)

	# 10. Tiles with transitions from DB
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			_tiles[i] = _pick_tile(_terrain[i], x, y)

	# 11. Heights
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			_heights[i] = _pick_height(x, y, _terrain[i], _field[i])

func rng_from_seed(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

# === Профили зон: число городов по сложности ===
const ZONE := "mid"  # start | mid | hard | faction
const ZONE_CITY_COUNTS := {
	"start": [1, 1],
	"mid": [1, 3],
	"hard": [4, 5],
	"faction": [2, 3],
}

# Серые (монстры palette=5 — UnitDB.is_hostile) по зоне: кластеры у дорог и в лесах.
const GRAY_ZONE := {
	"start": {
		"count": [6, 10], "hp": [25, 45], "dmg": [4, 6],
		"pool": ["monsters/bat", "monsters/bee", "monsters/wolf", "monsters/squirrel"],
	},
	"mid": {
		"count": [10, 14], "hp": [45, 75], "dmg": [6, 9],
		"pool": ["monsters/orc", "monsters/goblin", "monsters/wolf", "monsters/spider", "monsters/squirrel"],
	},
	"hard": {
		"count": [14, 18], "hp": [70, 120], "dmg": [9, 14],
		"pool": ["monsters/troll", "monsters/ogre", "monsters/goblin", "monsters/orc", "monsters/ghost", "monsters/dino"],
	},
	"faction": {
		"count": [12, 16], "hp": [50, 95], "dmg": [7, 11],
		"pool": ["monsters/orc", "monsters/goblin", "monsters/wolf", "monsters/spider", "monsters/troll"],
	},
}

# Здания в городах: функциональные + жильё + декор (folder -> StructureDB).
const SHOP_FOLDERS := ["shop1", "shop2"]
const ALCHEMY_FOLDERS := ["druidshop1", "druidshop2", "druidshop3"]
const INN_FOLDERS := ["inn1", "inn2", "inn3"]
const TRAIN_FOLDERS := ["train1", "train2", "train3"]
const BLACKSMITH_FOLDERS := ["blacksmith1", "blacksmith2"]
const HOUSE_FOLDERS := ["shed1", "shed2", "shed3", "khut1", "khut2", "hut1", "hut4", "hut5", "bighouse1", "bighouse2"]
const DECOR_FOLDERS := ["well1", "well2", "well3", "campfire", "mill1", "mill2"]
const ZONE_HOUSES := {"start": 4, "mid": 5, "hard": 7, "faction": 6}

# НПЦ городов.
const GUARD_SETS := ["humans/swordsman", "humans/archer", "humans/pikeman_"]
const CITIZEN_SETS := ["humans/unarmed", "humans/clubman", "humans/axeman", "humans/mage_st"]
const CAPTAIN_SET := "heroes/swordsman"

# Объекты по биому: подходящие ID из alm_objects.json.
const TREE_GRASS := [1, 4, 7, 10, 16, 19, 25, 26, 27]
const TREE_SOIL := [41, 43, 53, 55, 47, 49, 51]
const TREE_SAND := [128, 132, 134, 98, 99]
const TREE_MUD := [7, 49, 51]
const HERB_ITEMS := [
	{"item": "Herb Green Leaf", "icon": "res://assets/professions/herbalism/green_leaf.png"},
	{"item": "Herb White Flower", "icon": "res://assets/professions/herbalism/white_flower.png"},
	{"item": "Herb Red Berry", "icon": "res://assets/professions/herbalism/red_berry.png"},
	{"item": "Herb Tall Grass", "icon": "res://assets/professions/herbalism/tall_grass.png"},
	{"item": "Herb Lavender", "icon": "res://assets/professions/herbalism/lavender.png"},
	{"item": "Herb Mint", "icon": "res://assets/professions/herbalism/mint.png"},
	{"item": "Herb Dandelion", "icon": "res://assets/professions/herbalism/dandelion.png"},
	{"item": "Herb Broad Leaf", "icon": "res://assets/professions/herbalism/broad_leaf.png"},
]
const HERB_TARGET_COUNTS := {"start": 20, "mid": 26, "hard": 30, "faction": 28}
const HERB_REGION_GRID := 4
const HERB_MIN_DISTANCE := 6

var _spawn_pos: Vector2i = Vector2i(-1, -1)
var _portal_pos: Vector2i = Vector2i(-1, -1)
var _cities: Array = []  # [{pos: Vector2i, faction: String}]

## Этап 2: города. Центры — на базовой земле, разнесённые (мин. дистанция),
## заливка овалом ~11×11 дорогой (type 3). Количество — из профиля зоны.
func _place_cities(rng: RandomNumberGenerator) -> void:
	_cities.clear()
	var range_arr: Array = ZONE_CITY_COUNTS.get(ZONE, [1, 3])
	var count: int = rng.randi_range(int(range_arr[0]), int(range_arr[1]))
	var min_city_dist := 20
	var attempts := 0
	while _cities.size() < count and attempts < 500:
		attempts += 1
		var cx: int = rng.randi_range(8, W - 9)
		var cy: int = rng.randi_range(8, H - 9)
		var p := Vector2i(cx, cy)
		# Центр города — только на базовой земле (0/4/5/6), не на воде/горах/дороге
		var t: int = _terrain[p.y * W + p.x]
		if t == 1 or t == 2 or t == 3:
			continue
		# Разнесение: не ближе min_city_dist к уже размещённым городам
		var far_enough := true
		for c in _cities:
			if p.distance_to(c["pos"]) < min_city_dist:
				far_enough = false
				break
		if not far_enough:
			continue
		_cities.append({"pos": p, "faction": _faction_for(_cities.size())})
		_fill_city_oval(p, 5, 5)
	print("CITIES: %d/%d (zone=%s)" % [_cities.size(), count, ZONE])

## Присвоение фракции городу (метка-данные; арта/маркеров пока нет).
## start — герою; faction — всем одна фракция; mid/hard — по кругу 4 фракции.
func _faction_for(i: int) -> String:
	match ZONE:
		"start": return "hero"
		"faction": return "f0"
		_: return "f%d" % (i % 4)

## Залитый овал дорогой (type 3), диаметр (2*rx+1)×(2*ry+1).
func _fill_city_oval(center: Vector2i, rx: int, ry: int) -> void:
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			var fx: float = float(dx) / float(rx)
			var fy: float = float(dy) / float(ry)
			if fx * fx + fy * fy > 1.0:
				continue
			var x: int = center.x + dx
			var y: int = center.y + dy
			if x < 1 or y < 1 or x >= W - 1 or y >= H - 1:
				continue
			_terrain[y * W + x] = 3

## Этап 3: дороги — MST по городам (Прим, ближайший сосед) + A*-коридоры ширины 2.
func _connect_cities(rng: RandomNumberGenerator) -> void:
	if _cities.size() < 2:
		return
	var in_tree := {}
	in_tree[0] = true
	var connected: Array = [0]
	while connected.size() < _cities.size():
		var best_i := -1
		var best_j := -1
		var best_d := 1 << 30
		for i in connected:
			for j in range(_cities.size()):
				if in_tree.has(j):
					continue
				var d: int = _cities[i]["pos"].distance_squared_to(_cities[j]["pos"])
				if d < best_d:
					best_d = d
					best_i = i
					best_j = j
		if best_j < 0:
			break
		_carve_road_between(_cities[best_i]["pos"], _cities[best_j]["pos"], rng)
		in_tree[best_j] = true
		connected.append(best_j)

## A* между двумя точками + лента ширины 2 (перпендикулярно сегменту).
func _carve_road_between(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var path: Array = _a_star(a, b, rng)
	if path.is_empty():
		path = _a_star(b, a, rng)
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

## Этап 4: горы/вода по экстремумам рельефа. Никогда не трогаем дорогу (3):
## города и дорожная сеть остаются проходимыми — «горы/вода защищают дороги».
func _place_mountains_water() -> void:
	for y in range(H):
		for x in range(W):
			var i: int = y * W + x
			if _terrain[i] == 3:
				continue
			var elev: float = _field[i]
			if elev < _water_thr:
				_terrain[i] = 2
			elif elev > _mountain_thr:
				_terrain[i] = 1

## Этап 5: спавн у города №0, портал на противоположном краю.
func _place_portal_spawn() -> void:
	if _cities.is_empty():
		return
	var city0: Vector2i = _cities[0]["pos"]
	_spawn_pos = _find_land_near(city0, 8)
	_portal_pos = _find_land_far(city0, 40)
	_save_spawn_json()
	_save_portal_json()
	if _spawn_pos.x >= 0:
		print("SPAWN: (%d, %d)" % [_spawn_pos.x, _spawn_pos.y])
	if _portal_pos.x >= 0:
		print("PORTAL: (%d, %d)" % [_portal_pos.x, _portal_pos.y])
	_reserved[_spawn_pos] = true
	_reserved[_portal_pos] = true

# === Спавн: здания + НПЦ городов, деревья, Серые ===

## Ближайшая базовая земля (0 трава, 4 почва, 5 песок, 6 грязь) рядом с origin.
func _find_land_near(origin: Vector2i, radius: int) -> Vector2i:
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var p := Vector2i(origin.x + dx, origin.y + dy)
				if p.x >= 1 and p.y >= 1 and p.x < W - 1 and p.y < H - 1:
					var t: int = _terrain[p.y * W + p.x]
					if t == 0 or t == 4 or t == 5 or t == 6:
						return p
	return Vector2i(-1, -1)

## Базовая земля далеко от origin, ближе к краю карты.
func _find_land_far(origin: Vector2i, min_dist: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -1
	for y in range(3, H - 3):
		for x in range(3, W - 3):
			var t: int = _terrain[y * W + x]
			if t != 0 and t != 4 and t != 5 and t != 6:
				continue
			var p := Vector2i(x, y)
			var dist: float = p.distance_to(origin)
			if dist < min_dist:
				continue
			# Оценка: дальше от origin + ближе к краю карты
			var edge_dist: float = mini(mini(x, W - 1 - x), mini(y, H - 1 - y))
			var score: int = int(dist * 2.0 - edge_dist * 3.0)
			if score > best_score:
				best_score = score
				best = p
	return best

# === Спавн: здания + НПЦ городов, деревья, Серые ===

## Спека здания по папке: {id, w, h} из structure_db.json или {}.
func _structure_spec(folder: String) -> Dictionary:
	if not StructureDB.has(folder):
		return {}
	var def := StructureDB.get_structure(folder)
	var tid := int(def.get("id", 0))
	if tid <= 0:
		return {}
	return {
		"id": tid,
		"w": int(def.get("tile_width", 1)),
		"h": int(def.get("tile_height", 1)),
	}

## Этап 6: здания + НПЦ для каждого города. Запись в sidecar-ы structures/npcs.
func _place_city_content(rng: RandomNumberGenerator) -> void:
	var houses_n: int = int(ZONE_HOUSES.get(ZONE, 5))
	for city_index in range(_cities.size()):
		var c: Dictionary = _cities[city_index]
		var center: Vector2i = c["pos"]
		# Сначала НПЦ — посты резервируются; здания ниже обходят их.
		_place_city_npcs(rng, center)
		var alchemy_rng := rng_from_seed(7300 + city_index)
		var alchemy_folder: String = str(_pick(alchemy_rng, ALCHEMY_FOLDERS))
		var plan: Array = [
			_pick(rng, SHOP_FOLDERS),
			_pick(rng, INN_FOLDERS),
			_pick(rng, BLACKSMITH_FOLDERS),
			_pick(rng, TRAIN_FOLDERS),
		]
		for i in range(houses_n):
			plan.append(_pick(rng, HOUSE_FOLDERS))
		plan.append(_pick(rng, DECOR_FOLDERS))
		var replaceable_index := -1
		for folder in plan:
			var spec := _structure_spec(folder)
			if spec.is_empty():
				continue
			if _place_city_building(center, spec) and (folder in HOUSE_FOLDERS or folder in DECOR_FOLDERS):
				replaceable_index = _structures_out.size() - 1
		var alchemy_spec := _structure_spec(alchemy_folder)
		if replaceable_index >= 0 and not alchemy_spec.is_empty():
			_structures_out[replaceable_index]["type_id"] = int(alchemy_spec["id"])
	print("STRUCTURES_COUNT: %d" % _structures_out.size())

## Поставить здание (spec) в кольцо вокруг центра города, не на площадь.
func _place_city_building(center: Vector2i, spec: Dictionary) -> bool:
	var w := int(spec["w"])
	var h := int(spec["h"])
	var rings: Array[int] = [2, 3, 4]
	for r in rings:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var tl := center + Vector2i(dx, dy)
				if not _footprint_fits(tl, w, h, center):
					continue
				_structures_out.append({"x": tl.x, "y": tl.y, "type_id": int(spec["id"])})
				for yy in range(h):
					for xx in range(w):
						_reserved[tl + Vector2i(xx, yy)] = true
				return true
	return false

## Футпринт здания помещается внутри овала города на дороге, не на площади,
## не пересекая спавн/портал/уже занятые клетки.
func _footprint_fits(tl: Vector2i, w: int, h: int, center: Vector2i) -> bool:
	for yy in range(h):
		for xx in range(w):
			var c := tl + Vector2i(xx, yy)
			if c.x < 1 or c.y < 1 or c.x >= W - 1 or c.y >= H - 1:
				return false
			if _terrain[c.y * W + c.x] != 3:
				return false
			if _reserved.has(c) or c == _spawn_pos or c == _portal_pos:
				return false
			var d := maxi(abs(c.x - center.x), abs(c.y - center.y))
			if d <= 1 or d > 4:
				return false
	return true

## НПЦ города: стражи (первые 2 патрульные, остальные на постах), капитан,
## жители у магазина/центра. Все стоят; патруль — только первые 2 стража.
func _place_city_npcs(rng: RandomNumberGenerator, center: Vector2i) -> void:
	var posts_taken := {}
	var guard_offsets: Array = [
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
		Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2),
	]
	var citizens_offsets: Array = [
		Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3),
		Vector2i(3, 3), Vector2i(-3, 3), Vector2i(3, -3), Vector2i(-3, -3),
		Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4),
	]
	var guards_n := rng.randi_range(3, 5)
	for i in range(guards_n):
		var post := _post_cell(center, guard_offsets, posts_taken)
		if post.x < 0:
			continue
		var set_name: String = _pick(rng, GUARD_SETS)
		var hp := rng.randi_range(60, 100)
		var dmg := rng.randi_range(6, 10)
		_npcs_out.append(_npc_rec(post, set_name, "guard", i < 2, hp, dmg))
	# Капитан у площади
	var cap := _post_cell(center, [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)], posts_taken)
	if cap.x >= 0:
		_npcs_out.append(_npc_rec(cap, CAPTAIN_SET, "guard", false, 120, 12))
	# Жители (стоят, не патрулируют) — кольца 3–4
	var cit_n := rng.randi_range(4, 10)
	for i in range(cit_n):
		var post := _post_cell(center, citizens_offsets, posts_taken)
		if post.x < 0:
			continue
		var set_name: String = _pick(rng, CITIZEN_SETS)
		_npcs_out.append(_npc_rec(post, set_name, "citizen", false, 30, 0))

## Свободный пост: клетка дороги в городе, не на площади, не занята.
func _post_cell(center: Vector2i, offsets: Array, taken: Dictionary) -> Vector2i:
	for off in offsets:
		var c: Vector2i = center + off
		if c.x < 1 or c.y < 1 or c.x >= W - 1 or c.y >= H - 1:
			continue
		if _terrain[c.y * W + c.x] != 3:
			continue
		if _reserved.has(c) or taken.has(c):
			continue
		if c == _spawn_pos or c == _portal_pos:
			continue
		taken[c] = true
		return c
	return Vector2i(-1, -1)

func _npc_rec(post: Vector2i, set_name: String, role: String, patrol: bool, hp: int, dmg: int) -> Dictionary:
	return {
		"x": post.x, "y": post.y, "set": set_name,
		"role": role, "patrol": patrol,
		"post": [post.x, post.y],
		"hp_max": hp, "damage": dmg,
	}

## Этап 7: деревья/объекты в _obstacles (ID из alm_objects.json). Кластерный
## шум по биому; не ставим на дорогу, у дорог, в городах и у спавна/портала.
func _place_objects(rng: RandomNumberGenerator) -> void:
	if _obj_noise == null:
		_obj_noise = FastNoiseLite.new()
		_obj_noise.seed = 777
		_obj_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_obj_noise.frequency = 1.0 / 16.0
		_obj_noise.fractal_octaves = 2
	var density: float = {"start": 0.06, "mid": 0.08, "hard": 0.10, "faction": 0.09}.get(ZONE, 0.08)
	for y in range(H):
		for x in range(W):
			var t := _terrain[y * W + x]
			if t != 0 and t != 4 and t != 5 and t != 6:
				continue
			var cell := Vector2i(x, y)
			if _reserved.has(cell) or _near_road(cell) or _near_city(cell, 6):
				continue
			if _near_point(cell, _spawn_pos, 3) or _near_point(cell, _portal_pos, 3):
				continue
			if _obj_noise.get_noise_2d(x, y) > 0.12 and rng.randf() < density:
				_obstacles[y * W + x] = _tree_id(rng, t)

## Сосед-дорога рядом? (клиренс: дерево не примыкает к дороге)
func _near_road(cell: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
			continue
		if _terrain[n.y * W + n.x] == 3:
			return true
	return false

func _near_city(cell: Vector2i, r: int) -> bool:
	for c in _cities:
		var cc: Vector2i = c["pos"]
		if maxi(abs(cell.x - cc.x), abs(cell.y - cc.y)) <= r:
			return true
	return false

func _near_point(cell: Vector2i, p: Vector2i, r: int) -> bool:
	if p.x < 0:
		return false
	return maxi(abs(cell.x - p.x), abs(cell.y - p.y)) <= r

func _tree_id(rng: RandomNumberGenerator, t: int) -> int:
	var pool: Array
	match t:
		4: pool = TREE_SOIL
		5: pool = TREE_SAND
		6: pool = TREE_MUD
		_: pool = TREE_GRASS
	return int(_pick(rng, pool))

func _place_herbs(rng: RandomNumberGenerator) -> void:
	var target_count: int = int(HERB_TARGET_COUNTS.get(ZONE, 26))
	var herb_index := rng.randi() % HERB_ITEMS.size()
	var regions_filled := 0
	var region_width := W / HERB_REGION_GRID
	var region_height := H / HERB_REGION_GRID
	for region_y in range(HERB_REGION_GRID):
		for region_x in range(HERB_REGION_GRID):
			var min_x := region_x * region_width + 2
			var max_x := mini((region_x + 1) * region_width - 3, W - 3)
			var min_y := region_y * region_height + 2
			var max_y := mini((region_y + 1) * region_height - 3, H - 3)
			for attempt in range(80):
				var cell := Vector2i(rng.randi_range(min_x, max_x), rng.randi_range(min_y, max_y))
				if not _herb_cell_ok(cell) or not _herb_spacing_ok(cell):
					continue
				herb_index = _append_herb(cell, herb_index)
				regions_filled += 1
				break
	var tries := 0
	while _herbs_out.size() < target_count and tries < 1200:
		tries += 1
		var cell := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if not _herb_cell_ok(cell) or not _herb_spacing_ok(cell):
			continue
		herb_index = _append_herb(cell, herb_index)
	print("HERBS: %d/%d regions=%d/%d min_distance=%d" % [
		_herbs_out.size(), target_count, regions_filled, HERB_REGION_GRID * HERB_REGION_GRID, HERB_MIN_DISTANCE])

func _append_herb(cell: Vector2i, herb_index: int) -> int:
	var herb: Dictionary = HERB_ITEMS[herb_index % HERB_ITEMS.size()]
	_herbs_out.append({
		"x": cell.x, "y": cell.y,
		"item": str(herb["item"]), "icon": str(herb["icon"]),
	})
	return herb_index + 1

func _herb_spacing_ok(cell: Vector2i) -> bool:
	for record in _herbs_out:
		var dx := absi(cell.x - int(record.get("x", -1)))
		var dy := absi(cell.y - int(record.get("y", -1)))
		if dx < HERB_MIN_DISTANCE and dy < HERB_MIN_DISTANCE:
			return false
	return true

func _herb_cell_ok(cell: Vector2i) -> bool:
	if cell.x < 2 or cell.y < 2 or cell.x >= W - 2 or cell.y >= H - 2:
		return false
	var terrain := _terrain[cell.y * W + cell.x]
	if terrain != 0 and terrain != 4:
		return false
	if _obstacles[cell.y * W + cell.x] != 0:
		return false
	if _reserved.has(cell) or _near_road(cell) or _near_city(cell, 6):
		return false
	if _near_point(cell, _spawn_pos, 8) or _near_point(cell, _portal_pos, 8):
		return false
	for record in _herbs_out:
		if int(record.get("x", -1)) == cell.x and int(record.get("y", -1)) == cell.y:
			return false
	return true

## Этап 9: Серые — кластеры у дорог (сбоку) и в лесных массивах. Только на
## свободных клетках, вне городов и не ближе 20 клеток к спавну.
func _place_greys(rng: RandomNumberGenerator) -> void:
	var cfg: Dictionary = GRAY_ZONE.get(ZONE, GRAY_ZONE["mid"])
	var count: int = rng.randi_range(int(cfg["count"][0]), int(cfg["count"][1]))
	var placed := 0
	var tries := 0
	while placed < count and tries < 800:
		tries += 1
		var anchor := Vector2i(-1, -1)
		if rng.randf() < 0.5:
			var road := _road_anchor(rng)
			if road.x >= 0:
				anchor = _side_road_cell(rng, road)
		else:
			anchor = _forest_anchor(rng)
		if anchor.x < 0:
			continue
		placed += _gray_cluster(rng, anchor, cfg)
	print("GRAY: %d/%d" % [placed, count])

## Случайная клетка дороги вне городов и подальше от спавна.
func _road_anchor(rng: RandomNumberGenerator) -> Vector2i:
	var tries := 0
	while tries < 400:
		tries += 1
		var x := rng.randi_range(2, W - 3)
		var y := rng.randi_range(2, H - 3)
		if _terrain[y * W + x] != 3:
			continue
		var c := Vector2i(x, y)
		if _near_city(c, 6) or _near_point(c, _spawn_pos, 24):
			continue
		return c
	return Vector2i(-1, -1)

## Сбоку от дороги (1–2 клетки в сторону, только проходимая земля).
func _side_road_cell(rng: RandomNumberGenerator, road: Vector2i) -> Vector2i:
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for step in range(1, 3):
		for attempt in range(8):
			var dir: Vector2i = dirs[rng.randi() % dirs.size()]
			var c: Vector2i = road + dir * step
			if _gray_cell_ok(c):
				return c
	return road

## Лесная точка: вокруг >=2 деревьев (obstacles), клетка свободна.
func _forest_anchor(rng: RandomNumberGenerator) -> Vector2i:
	var tries := 0
	while tries < 500:
		tries += 1
		var x := rng.randi_range(2, W - 3)
		var y := rng.randi_range(2, H - 3)
		var c := Vector2i(x, y)
		if not _gray_cell_ok(c) or _near_point(c, _spawn_pos, 20):
			continue
		var trees := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
				continue
			if _obstacles[n.y * W + n.x] > 0:
				trees += 1
		if trees >= 2:
			return c
	return Vector2i(-1, -1)

## Клетка пригодна для Серого: суша, без объекта/здания/спавна/портала, вне городов.
func _gray_cell_ok(c: Vector2i) -> bool:
	if c.x < 2 or c.y < 2 or c.x >= W - 2 or c.y >= H - 2:
		return false
	var t := _terrain[c.y * W + c.x]
	if t != 0 and t != 4 and t != 5 and t != 6:
		return false
	if _obstacles[c.y * W + c.x] > 0:
		return false
	if _reserved.has(c) or c == _spawn_pos or c == _portal_pos:
		return false
	if _near_city(c, 6):
		return false
	return true

## Кластер из 2–4 Серых вокруг anchor (ячейки разнесены).
func _gray_cluster(rng: RandomNumberGenerator, anchor: Vector2i, cfg: Dictionary) -> int:
	var cells: Array = [anchor]
	for i in range(1, 3):
		var c := _near_gray_cell(rng, anchor, cells)
		if c.x < 0:
			break
		cells.append(c)
	for i in range(cells.size()):
		var cc: Vector2i = cells[i]
		var set_name: String = _pick(rng, cfg["pool"])
		var hp := rng.randi_range(int(cfg["hp"][0]), int(cfg["hp"][1]))
		var dmg := rng.randi_range(int(cfg["dmg"][0]), int(cfg["dmg"][1]))
		_npcs_out.append({
			"x": int(cc.x), "y": int(cc.y), "set": set_name,
			"hp_max": hp, "damage": dmg,
		})
	return cells.size()

func _near_gray_cell(rng: RandomNumberGenerator, anchor: Vector2i, taken: Array) -> Vector2i:
	for attempt in range(12):
		var off := Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
		if off == Vector2i.ZERO:
			continue
		var c: Vector2i = anchor + off
		if taken.has(c) or not _gray_cell_ok(c):
			continue
		taken.append(c)
		return c
	return Vector2i(-1, -1)

func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi() % arr.size()]

func _save_spawn_json() -> void:
	if _spawn_pos.x < 0:
		return
	var path: String = OUT_DIR + "gen_smart_01.spawn.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"x": _spawn_pos.x, "y": _spawn_pos.y}))
	f.close()

func _save_portal_json() -> void:
	if _portal_pos.x < 0:
		return
	var path: String = OUT_DIR + "gen_smart_01.portal.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"x": _portal_pos.x, "y": _portal_pos.y}))
	f.close()

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
	return t != 2  # Всё кроме воды проходимо для дороги

func _set_land_road(p: Vector2i) -> void:
	if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
		return
	var idx: int = p.y * W + p.x
	var t: int = _terrain[idx]
	if t == 2:
		return
	_terrain[idx] = 3

func _place_terrain(n: int) -> void:
	# === Этап 1: почва Voronoi (база). Горы/вода/дорога добавляются позже ===
	# Только базовые типы: 0 трава, 4 почва, 5 песок, 6 грязь.
	# Опорные точки: тип -> количество
	var seed_counts := {0: 3, 4: 2, 5: 2, 6: 1}

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Шум для деформации границ (создаёт извилистые берега/границы биомов)
	var jitter_noise := FastNoiseLite.new()
	jitter_noise.seed = 9999
	jitter_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	jitter_noise.frequency = 1.0 / 20.0
	jitter_noise.fractal_octaves = 3

	# Поле высот: используется гор/воды этапом 4 и высотами (шаг 7)
	var elev_noise := FastNoiseLite.new()
	elev_noise.seed = 42
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.frequency = 1.0 / 40.0
	elev_noise.fractal_octaves = 4
	elev_noise.fractal_gain = 0.5

	# Генерируем опорные точки
	var seeds: Array = []
	for t in seed_counts:
		for i in range(seed_counts[t]):
			var sx: float = rng.randf_range(5.0, W - 6.0)
			var sy: float = rng.randf_range(5.0, H - 6.0)
			seeds.append({"pos": Vector2(sx, sy), "type": t})

	var field := PackedFloat32Array()
	field.resize(n)

	# Для каждой клетки — ближайшая опорная точка
	for i in range(n):
		var x: float = float(i % W)
		var y: float = float(i / W)
		var elev: float = (elev_noise.get_noise_2d(x, y) + 1.0) * 0.5
		field[i] = elev

		# Ищем ближайшую опорную точку с шумовым смещением
		var best_type: int = 0
		var best_dist: float = 1e30
		for s in seeds:
			var sp: Vector2 = s["pos"]
			# Базовое расстояние
			var dx: float = x - sp.x
			var dy: float = y - sp.y
			var dist: float = dx * dx + dy * dy
			# Шумовое смещение для органичных границ (~10% от расстояния)
			var jx: float = jitter_noise.get_noise_2d(x * 3.0, y * 3.0)
			var jy: float = jitter_noise.get_noise_2d(x * 3.0 + 100, y * 3.0 + 100)
			dist += (jx * dx + jy * dy) * 3.0
			if dist < best_dist:
				best_dist = dist
				best_type = s["type"]

		_terrain[i] = best_type

	# Сохраняем field и пороги для высот
	_field = field
	var sorted := field.duplicate()
	sorted.sort()
	_water_thr = sorted[clampi(int(0.10 * n), 0, n - 1)]
	_mountain_thr = sorted[clampi(int(0.90 * n), 0, n - 1)]

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
	# Для типов >=4: перезаписываем file через TERRAIN_FILE
	if type_a >= 4:
		out["file"] = int(TERRAIN_FILE.get(type_a, out["file"]))
	return out

func _pick_height(x: int, y: int, t: int, field_value: float) -> int:
	# Псевдо-высота: noise field определяет И terrain И высоту.
	# Вода всегда низкая, горы высокие, остальные — средние с вариацией.
	match t:
		2: # Вода: 0-15 (всегда низко)
			return int(round(clampf(field_value * 15.0, 0.0, 15.0)))
		1: # Горы: 40-127 (высокие пики)
			var lo: float = _water_thr
			var hi: float = 1.0
			var span: float = maxf(0.0001, hi - lo)
			var u: float = clampf((field_value - lo) / span, 0.0, 1.0)
			return int(round(clampf(40.0 + u * 87.0, 40.0, 127.0)))
		0: # Трава: 10-60 (холмы)
			var lo: float = _water_thr
			var hi: float = _mountain_thr
			var span: float = maxf(0.0001, hi - lo)
			var u: float = clampf((field_value - lo) / span, 0.0, 1.0)
			return int(round(clampf(10.0 + u * 50.0, 10.0, 60.0)))
		4: # Почва: 10-50 (средняя)
			var lo: float = _water_thr
			var hi: float = _mountain_thr
			var span: float = maxf(0.0001, hi - lo)
			var u: float = clampf((field_value - lo) / span, 0.0, 1.0)
			return int(round(clampf(10.0 + u * 40.0, 10.0, 50.0)))
		5: # Песок: 5-35 (низина)
			var lo: float = _water_thr
			var hi: float = _mountain_thr
			var span: float = maxf(0.0001, hi - lo)
			var u: float = clampf((field_value - lo) / span, 0.0, 1.0)
			return int(round(clampf(5.0 + u * 30.0, 5.0, 35.0)))
		6: # Грязь: 8-33 (болото)
			var lo: float = _water_thr
			var hi: float = _mountain_thr
			var span: float = maxf(0.0001, hi - lo)
			var u: float = clampf((field_value - lo) / span, 0.0, 1.0)
			return int(round(clampf(8.0 + u * 25.0, 8.0, 33.0)))
		3: # Дорога: интерполяция от соседей
			return _interpolate_road_height(x, y)
		_: # Остальные: средняя
			return int(round(clampf(field_value * 60.0, 10.0, 60.0)))

func _interpolate_road_height(x: int, y: int) -> int:
	# Дорога: среднее от соседних не-дорожных клеток.
	var sum := 0.0
	var cnt := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx < 0 or ny < 0 or nx >= W or ny >= H:
			continue
		var nt: int = _terrain[ny * W + nx]
		if nt != 3:
			sum += float(_heights[ny * W + nx])
			cnt += 1
	if cnt > 0:
		return int(round(sum / float(cnt)))
	# Нет соседей — берём из field
	return int(round(clampf(_field[y * W + x] * 40.0, 10.0, 40.0)))

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
		var terrain_parts: Array = []
		var terrain_names := {0: "трава", 1: "горы", 2: "вода", 3: "дорога", 4: "почва", 5: "песок", 6: "грязь"}
		for tt in terrain_names:
			var cnt: int = tc.get(tt, 0)
			if cnt > 0:
				terrain_parts.append("%s=%.1f%%" % [terrain_names[tt], cnt * 100.0 / total])
		print("Terrain: " + ", ".join(terrain_parts))
		print("Shapes: exact=%d subset=%d rules-fallback=%d" % [
			_stat_exact, _stat_subset, _stat_rules])
		_road_stats(tc.get(3, 0))
		var obj_count := 0
		for v in _obstacles:
			if v > 0:
				obj_count += 1
		print("Объектов: %d (%.1f%%)" % [obj_count, obj_count * 100.0 / total])
		# Спавн sidecar-ами (buildings + NPC)
		_save_sidecars()
		var guards := 0
		var citizens := 0
		var greys := 0
		for n in _npcs_out:
			match str(n.get("role", "")):
				"guard": guards += 1
				"citizen": citizens += 1
				_: greys += 1
		print("Спавн: зданий=%d НПЦ=%d (стражи=%d жители=%d серые=%d) трав=%d" % [
			_structures_out.size(), _npcs_out.size(), guards, citizens, greys, _herbs_out.size()])
	else:
		print("ERROR load_map")
	print("Сохранено: " + path)

## Sidecar-ы спавна: структуры и NPC (грузит alm_map.gd/_load_sidecars).
func _save_sidecars() -> void:
	var f := FileAccess.open(OUT_DIR + "gen_smart_01.structures.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"structures": _structures_out}))
		f.close()
	var n := FileAccess.open(OUT_DIR + "gen_smart_01.npcs.json", FileAccess.WRITE)
	if n:
		n.store_string(JSON.stringify({"npcs": _npcs_out}))
		n.close()
	var h := FileAccess.open(OUT_DIR + "gen_smart_01.herbs.json", FileAccess.WRITE)
	if h:
		h.store_string(JSON.stringify({"herbs": _herbs_out}))
		h.close()

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
