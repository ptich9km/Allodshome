extends SceneTree
## Сравнение сгенерированной карты с Beach.alm.

func _init() -> void:
	for path in ["res://assets/maps/Beach.alm", "res://assets/maps/gen/gen_smart_01.alm"]:
		var m: Dictionary = AlmLoader.load_map(path)
		if m.is_empty():
			continue
		var w: int = int(m["width"])
		var h: int = int(m["height"])
		var tiles: PackedInt32Array = m["tiles"]
		var heights: PackedByteArray = m.get("heights", PackedByteArray())
		var obstacles: PackedByteArray = m.get("obstacles", PackedByteArray())
		var total := w * h

		var tcount := {0: 0, 1: 0, 2: 0, 3: 0}
		var hsum := {0: 0, 1: 0, 2: 0, 3: 0}
		var hcnt := {0: 0, 1: 0, 2: 0, 3: 0}
		var obj_t := {0: 0, 1: 0, 2: 0, 3: 0}

		for i in range(total):
			var tt: int = AlmLoader.tile_type(tiles[i])
			tcount[tt] = tcount.get(tt, 0) + 1
			if heights.size() == total:
				hsum[tt] = hsum.get(tt, 0) + int(heights[i])
				hcnt[tt] = hcnt.get(tt, 0) + 1
			if obstacles.size() == total and obstacles[i] > 0:
				obj_t[tt] = obj_t.get(tt, 0) + 1

		var name: String = path.get_file()
		print("=== %s  %dx%d ===" % [name, w, h])
		print("  Трава:  %.1f%% (высота %.0f, объекты %.1f%%)" % [
			tcount[0] * 100.0 / total,
			float(hsum[0]) / maxi(1, hcnt[0]),
			obj_t[0] * 100.0 / maxi(1, tcount[0])])
		print("  Горы:   %.1f%% (высота %.0f, объекты %.1f%%)" % [
			tcount[1] * 100.0 / total,
			float(hsum[1]) / maxi(1, hcnt[1]),
			obj_t[1] * 100.0 / maxi(1, tcount[1])])
		print("  Вода:   %.1f%% (высота %.0f)" % [
			tcount[2] * 100.0 / total,
			float(hsum[2]) / maxi(1, hcnt[2])])
		print("  Дорога: %.1f%%" % (tcount[3] * 100.0 / total))
		print("")

	quit(0)
