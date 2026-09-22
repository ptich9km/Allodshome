extends SceneTree
## Проверяет какие tile id стоят на границах soil(4)↔mud(6) в gen_smart_01.alm

func _init() -> void:
	var m: Dictionary = AlmLoader.load_map("res://assets/maps/gen/gen_smart_01.alm")
	if m.is_empty():
		print("ERROR")
		quit(1)
		return
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedInt32Array = m["tiles"]

	# Найти клетки на границе soil↔mud и показать их tile spec
	var count := 0
	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			var t: int = AlmLoader.tile_type(tiles[i])
			# Проверить соседей
			var has_mud := false
			for d in [Vector2i(0,-1), Vector2i(0,1), Vector2i(1,0), Vector2i(-1,0)]:
				var nx: int = x + int(d.x)
				var ny: int = y + int(d.y)
				if nx >= 0 and ny >= 0 and nx < w and ny < h:
					var nt: int = AlmLoader.tile_type(tiles[ny * w + nx])
					if nt != t and (t == 4 and nt == 6 or t == 6 and nt == 4):
						has_mud = true
						break
			if has_mud and count < 20:
				var raw_f: int = AlmLoader.tile_file(tiles[i])
				var r: int = AlmLoader.tile_frame(tiles[i])
				var file_n: int = (raw_f >> 4) + 1
				var variant: int = raw_f & 0xF
				print("soil↔mud @ %d,%d: terrain=%d tile=%d -> file=%d variant=%d row=%d" % [x, y, t, tiles[i], file_n, variant, r])
				count += 1

	# Также показать все уникальные tile specs на карте
	var specs := {}
	for i in range(w * h):
		var t: int = AlmLoader.tile_type(tiles[i])
		var raw_f: int = AlmLoader.tile_file(tiles[i])
		var r: int = AlmLoader.tile_frame(tiles[i])
		var file_n: int = (raw_f >> 4) + 1
		var variant: int = raw_f & 0xF
		var key: String = "terrain%d: file%d v%d r%d" % [t, file_n, variant, r]
		specs[key] = int(specs.get(key, 0)) + 1

	print("\n=== Все уникальные tile specs на карте ===")
	var sorted := []
	for k in specs:
		sorted.append([int(specs[k]), str(k)])
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for s in sorted:
		print("  %s x%d" % [str(s[1]), int(s[0])])

	quit(0)
