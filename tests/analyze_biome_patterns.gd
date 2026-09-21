extends SceneTree
## Глубокий анализ паттернов 9 карт разработчиков.
## Извлекает: профили биомов, кластеры, высоты по типам, плотность объектов.

const PV := "res://assets/maps/pvm/"
const MAPS := [
	"sb_anp_greenlnd_1_1.alm",
	"sb_anp_tropic_1_0.alm",
	"sb_anp_canyon_1_0.alm",
	"sb_anp_orcish_1_0.alm",
	"sb_anp_gothic_1_2.alm",
	"sb_anp_som_1_0.alm",
	"sc_an_nord_3_2.alm",
	"hc_an_4islands_4_6.alm",
	"sc_an_madp_2_1.alm",
]

var _biome_profiles := {}

func _init() -> void:
	for f in MAPS:
		var p: String = PV + f
		if not FileAccess.file_exists(p):
			continue
		_analyze(p)
	_print_summary()
	quit(0)

func _analyze(path: String) -> void:
	var m: Dictionary = AlmLoader.load_map(path)
	if m.is_empty():
		return
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedInt32Array = m["tiles"]
	var heights: PackedByteArray = m.get("heights", PackedByteArray())
	var obstacles: PackedByteArray = m.get("obstacles", PackedByteArray())
	var structs: Array = m.get("structures", [])
	var units: Array = m.get("units", [])

	var name := path.get_file().replace(".alm", "")
	var total := w * h

	# 1. Распределение terrain
	var tcount := {0: 0, 1: 0, 2: 0, 3: 0}
	for i in range(total):
		var tt: int = AlmLoader.tile_type(tiles[i])
		tcount[tt] = tcount.get(tt, 0) + 1

	# 2. Высоты по типам
	var h_by_type := {0: [], 1: [], 2: [], 3: []}
	if heights.size() == total:
		for i in range(total):
			var tt: int = AlmLoader.tile_type(tiles[i])
			h_by_type[tt].append(int(heights[i]))

	# 3. Плотность объектов по terrain
	var obj_by_type := {0: 0, 1: 0, 2: 0, 3: 0}
	if obstacles.size() == total:
		for i in range(total):
			if obstacles[i] > 0:
				var tt: int = AlmLoader.tile_type(tiles[i])
				obj_by_type[tt] = obj_by_type.get(tt, 0) + 1

	# 4. Кластеризация: % terrain в окне 8×8
	var cluster_grass := 0.0
	var cluster_samples := 0
	for cy in range(0, h - 8, 4):
		for cx in range(0, w - 8, 4):
			var g := 0
			for dy in range(8):
				for dx in range(8):
					var tt: int = AlmLoader.tile_type(tiles[(cy + dy) * w + (cx + dx)])
					if tt == 0:
						g += 1
			cluster_grass += g / 64.0
			cluster_samples += 1
	cluster_grass = cluster_grass / maxi(1, cluster_samples) * 100.0

	# 5. Водные тела: крупные vs россыпь
	var water_cells := []
	for i in range(total):
		if AlmLoader.tile_type(tiles[i]) == 2:
			water_cells.append(Vector2i(i % w, i / w))
	var water_clusters := _count_clusters(water_cells, w, h, Vector2i(3, 3))

	# 6. Дороги: протяжённость
	var road_cells := []
	for i in range(total):
		if AlmLoader.tile_type(tiles[i]) == 3:
			road_cells.append(Vector2i(i % w, i / w))

	# Сохраняем профиль
	var profile := {
		"name": name, "w": w, "h": h,
		"grass": tcount.get(0, 0) * 100.0 / total,
		"mountain": tcount.get(1, 0) * 100.0 / total,
		"water": tcount.get(2, 0) * 100.0 / total,
		"road": tcount.get(3, 0) * 100.0 / total,
		"h_grass": _avg(h_by_type.get(0, [])),
		"h_mountain": _avg(h_by_type.get(1, [])),
		"h_water": _avg(h_by_type.get(2, [])),
		"h_road": _avg(h_by_type.get(3, [])),
		"obj_grass": obj_by_type.get(0, 0) * 100.0 / maxi(1, tcount.get(0, 1)),
		"obj_mountain": obj_by_type.get(1, 0) * 100.0 / maxi(1, tcount.get(1, 1)),
		"cluster_grass": cluster_grass,
		"water_bodies": water_clusters,
		"road_pct": tcount.get(3, 0) * 100.0 / total,
		"structures": structs.size(),
		"units": units.size(),
	}
	_biome_profiles[name] = profile

	print("=== %s ===" % name)
	print("  Трава: %.1f%% (высота %.0f, объекты %.1f%%)" % [profile["grass"], profile["h_grass"], profile["obj_grass"]])
	print("  Горы:  %.1f%% (высота %.0f, объекты %.1f%%)" % [profile["mountain"], profile["h_mountain"], profile["obj_mountain"]])
	print("  Вода:  %.1f%% (высота %.0f, тел: %d)" % [profile["water"], profile["h_water"], profile["water_bodies"]])
	print("  Дорога: %.1f%%" % profile["road"])
	print("  Кластер травы: %.0f%%, Структур: %d, Юнитов: %d" % [profile["cluster_grass"], profile["structures"], profile["units"]])

func _print_summary() -> void:
	print("\n=== СВОДКА ПРОФИЛЕЙ ===")
	print("%-12s %6s %6s %6s %6s %6s %6s" % ["Биом", "Трава", "Горы", "Вода", "Дорога", "КластерG", "Вод.тела"])
	for name in _biome_profiles:
		var p: Dictionary = _biome_profiles[name]
		print("%-12s %5.1f%% %5.1f%% %5.1f%% %5.1f%% %5.0f%% %5d" % [
			name, p["grass"], p["mountain"], p["water"], p["road"], p["cluster_grass"], p["water_bodies"]])

func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / arr.size()

func _count_clusters(cells: Array, w: int, h: int, min_size: Vector2i) -> int:
	if cells.is_empty():
		return 0
	var visited := {}
	var clusters := 0
	for c in cells:
		var key: int = c.y * w + c.x
		if visited.has(key):
			continue
		# BFS
		var queue := [c]
		var size := 0
		var bounds := Rect2i(c, Vector2i(1, 1))
		visited[key] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			size += 1
			bounds = bounds.expand(cur)
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n: Vector2i = cur + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var nk: int = n.y * w + n.x
				if visited.has(nk):
					continue
				if n in cells:
					visited[nk] = true
					queue.append(n)
		if bounds.size.x >= min_size.x and bounds.size.y >= min_size.y:
			clusters += 1
	return clusters
