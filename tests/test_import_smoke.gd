extends SceneTree
## Smoke-тест импорта .alm: та же логика, что в transition_editor._on_import_alm,
## без UI — проверяет, что папка pvm сканируется и статистика собирается.

const DIRS := {
	"N": Vector2i(0, -1), "S": Vector2i(0, 1),
	"E": Vector2i(1, 0), "W": Vector2i(-1, 0),
	"NE": Vector2i(1, -1), "NW": Vector2i(-1, -1),
	"SE": Vector2i(1, 1), "SW": Vector2i(-1, 1),
}

func _init() -> void:
	var pv := "res://assets/maps/pvm/"
	var maps: Array[String] = []
	var dir := DirAccess.open(pv)
	if dir == null:
		print("FAIL: cannot open ", pv)
		quit(1)
		return
	for f in dir.get_files():
		if f.to_lower().ends_with(".alm"):
			maps.append(f)
	maps.sort()
	print("maps found: ", maps.size(), " -> ", maps)
	if maps.is_empty():
		print("FAIL: no .alm")
		quit(1)
		return

	var stats := {}
	var interior_stats := {}
	var total_cells := 0
	var loaded := 0
	var type_seen := {}

	for f in maps:
		var p: String = pv + f
		var m: Dictionary = AlmLoader.load_map(p)
		if m.is_empty():
			print("  skip empty: ", f)
			continue
		loaded += 1
		var w: int = int(m["width"])
		var h: int = int(m["height"])
		var tiles: PackedInt32Array = m["tiles"]
		for y in range(h):
			for x in range(w):
				var i: int = y * w + x
				var t: int = AlmLoader.tile_type(tiles[i])
				type_seen[t] = true
				var raw_f: int = AlmLoader.tile_file(tiles[i])
				var r: int = AlmLoader.tile_frame(tiles[i])
				var file_n: int = (raw_f >> 4) + 1
				var variant: int = raw_f & 0xF
				var tile_key: String = "%d:%d:%d" % [file_n, variant, r]
				var is_edge := false
				for dir_name in DIRS:
					var d: Vector2i = DIRS[dir_name]
					var nx: int = x + int(d.x)
					var ny: int = y + int(d.y)
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni: int = ny * w + nx
					var nt: int = AlmLoader.tile_type(tiles[ni])
					if nt == t:
						continue
					is_edge = true
					var key: String = "%d:%s:%d" % [t, dir_name, nt]
					if not stats.has(key):
						stats[key] = {}
					stats[key][tile_key] = int(stats[key].get(tile_key, 0)) + 1
					total_cells += 1
				if not is_edge:
					if not interior_stats.has(str(t)):
						interior_stats[str(t)] = {}
					interior_stats[str(t)][tile_key] = int(interior_stats[str(t)].get(tile_key, 0)) + 1

	var types := type_seen.keys()
	types.sort()
	print("loaded=%d total_edge_cells=%d unique_rules=%d types=%s" % [
		loaded, total_cells, stats.size(), str(types)])
	print("interior types: ", interior_stats.keys())

	# Берём самый частый тайл для 4:NE:5 (почва→песок), если есть
	for probe in ["4:N:5", "4:E:5", "5:N:4", "0:N:3", "6:N:0"]:
		if stats.has(probe):
			var best := ""
			var best_c := 0
			for tk in stats[probe]:
				if int(stats[probe][tk]) > best_c:
					best_c = int(stats[probe][tk])
					best = str(tk)
			print("  sample %s -> %s (x%d)" % [probe, best, best_c])

	if loaded == 0:
		print("FAIL: no maps loaded")
		quit(1)
	elif total_cells == 0:
		print("FAIL: no edge cells")
		quit(1)
	elif stats.size() < 10:
		print("FAIL: too few unique rules: ", stats.size())
		quit(1)
	else:
		print("RESULT:OK import_smoke loaded=%d rules=%d edges=%d" % [
			loaded, stats.size(), total_cells])
	quit(0)
