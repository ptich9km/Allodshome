extends SceneTree
## Детальный анализ Beach.alm — карты со ВСЕМИ типами terrain и переходами.

func _init() -> void:
	var m: Dictionary = AlmLoader.load_map("res://assets/maps/Beach.alm")
	if m.is_empty():
		print("ERROR: cannot load Beach.alm")
		quit(1)
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedInt32Array = m["tiles"]
	var heights: PackedByteArray = m.get("heights", PackedByteArray())
	var obstacles: PackedByteArray = m.get("obstacles", PackedByteArray())
	var structs: Array = m.get("structures", [])
	var units: Array = m.get("units", [])
	var total := w * h

	print("=== Beach.alm  %dx%d  (%d клеток) ===" % [w, h, total])

	# Terrain distribution
	var tcount := {}
	for i in range(total):
		var tt: int = AlmLoader.tile_type(tiles[i])
		tcount[tt] = tcount.get(tt, 0) + 1
	print("\n--- Terrain ---")
	for tt in [0, 1, 2, 3]:
		print("  тип %d: %d (%.1f%%)" % [tt, tcount.get(tt, 0), tcount.get(tt, 0) * 100.0 / total])

	# Tile file usage (file_n = raw_f >> 4)
	var file_usage := {}
	for i in range(total):
		var raw_f: int = AlmLoader.tile_file(tiles[i])
		var fn: int = (raw_f >> 4) + 1
		file_usage[fn] = file_usage.get(fn, 0) + 1
	print("\n--- Tile files ---")
	for fn in file_usage:
		print("  tile%d: %d клеток (%.1f%%)" % [fn, file_usage[fn], file_usage[fn] * 100.0 / total])

	# Height per terrain type
	if heights.size() == total:
		print("\n--- Высоты по типам ---")
		var hsum := {}
		var hmin := {}
		var hmax := {}
		var hcnt := {}
		for i in range(total):
			var tt: int = AlmLoader.tile_type(tiles[i])
			var hv: int = int(heights[i])
			hsum[tt] = hsum.get(tt, 0) + hv
			hcnt[tt] = hcnt.get(tt, 0) + 1
			if not hmin.has(tt) or hv < hmin[tt]:
				hmin[tt] = hv
			if not hmax.has(tt) or hv > hmax[tt]:
				hmax[tt] = hv
		for tt in [0, 1, 2, 3]:
			if hcnt.has(tt):
				print("  тип %d: min=%d max=%d avg=%.0f" % [tt, hmin.get(tt,0), hmax.get(tt,0), float(hsum.get(tt,0)) / hcnt[tt]])

	# Obstacles per terrain
	if obstacles.size() == total:
		print("\n--- Объекты по terrain ---")
		var obj_t := {}
		for i in range(total):
			if obstacles[i] > 0:
				var tt: int = AlmLoader.tile_type(tiles[i])
				obj_t[tt] = obj_t.get(tt, 0) + 1
		for tt in [0, 1, 2, 3]:
			var tc: int = tcount.get(tt, 1)
			print("  тип %d: %d объектов (%.1f%% terrain)" % [tt, obj_t.get(tt, 0), obj_t.get(tt, 0) * 100.0 / tc])

	# Structures
	print("\n--- Структуры: %d ---" % structs.size())
	var s_folders := {}
	for s in structs:
		var sid: int = int(s.get("type_id", 0))
		var rec: Dictionary = StructureDB.get_by_id(sid)
		var folder: String = str(rec.get("folder", "?"))
		s_folders[folder] = s_folders.get(folder, 0) + 1
	for f in s_folders:
		print("  %s: %d" % [f, s_folders[f]])

	# Units
	print("\n--- Юниты: %d ---" % units.size())
	var u_types := {}
	for u in units:
		var tid: int = int(u.get("type_id", 0))
		var sname: String = UnitDB.set_name_for_id(tid)
		u_types[sname] = u_types.get(sname, 0) + 1
	var u_sorted: Array = []
	for k in u_types:
		u_sorted.append([u_types[k], k])
	u_sorted.sort_custom(func(a, b): return a[0] > b[0])
	for pair in u_sorted:
		print("  %s: %d" % [pair[1], pair[0]])

	# Transition analysis: what terrain types border each other
	print("\n--- Границы terrain ---")
	var borders := {}
	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			var t: int = AlmLoader.tile_type(tiles[i])
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var nt: int = AlmLoader.tile_type(tiles[ny * w + nx])
				if nt != t:
					var key: String = "%d<->%d" % [mini(t, nt), maxi(t, nt)]
					borders[key] = borders.get(key, 0) + 1
	var b_sorted: Array = []
	for k in borders:
		b_sorted.append([borders[k], k])
	b_sorted.sort_custom(func(a, b): return a[0] > b[0])
	for pair in b_sorted:
		print("  %s: %d переходов" % [pair[1], pair[0]])

	quit(0)
