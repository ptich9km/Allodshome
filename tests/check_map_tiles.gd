extends SceneTree
## Quick numeric check of the generated map: per (type, mask) how many
## distinct tiles were placed and which exact (file,variant,row) top ones.

const MAP := "res://assets/maps/gen/gen_smart_01.alm"
const DIRS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const TYPE_NAMES := {0: "GRASS", 1: "MOUNTAIN", 2: "WATER", 3: "ROAD", 4: "SOIL", 5: "SAND", 6: "MUD"}

func _init() -> void:
	var m: Dictionary = AlmLoader.load_map(MAP)
	if m.is_empty():
		print("ERROR load " + MAP)
		quit(1)
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedInt32Array = m["tiles"]
	var types := PackedByteArray()
	types.resize(w * h)
	for i in range(w * h):
		types[i] = AlmLoader.tile_type(tiles[i])

	var stats := {}
	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			var t: int = types[i]
			var mask := _mask(x, y, w, h, types)
			if mask == 0:
				continue
			var raw_f: int = AlmLoader.tile_file(tiles[i])
			var file_n: int = (raw_f >> 4) + 1
			var variant: int = raw_f & 0xF
			var row: int = AlmLoader.tile_frame(tiles[i])
			var key := "%d:%s" % [t, _mask_str(mask)]
			if not stats.has(key):
				stats[key] = {}
			var tk := "%d:%d:%d" % [file_n, variant, row]
			stats[key][tk] = int(stats[key].get(tk, 0)) + 1

	var keys: Array = []
	for k in stats:
		keys.append(str(k))
	keys.sort()
	for key in keys:
		var items: Dictionary = stats[key]
		var total := 0
		for k in items:
			total += int(items[k])
		var parts: Array = key.split(":")
		var tn: String = TYPE_NAMES.get(int(parts[0]), "T%s" % parts[0])
		var distinct := items.size()
		print("%s mask=%s n=%d distinct_tiles=%d" % [tn, parts[1], total, distinct])
		var sorted_items: Array = []
		for k in items:
			sorted_items.append([int(items[k]), str(k)])
		sorted_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for j in range(mini(4, sorted_items.size())):
			var c: int = int(sorted_items[j][0])
			print("    %s x%d (%.0f%%)" % [str(sorted_items[j][1]), c, c * 100.0 / total])
	quit(0)

func _mask(x: int, y: int, w: int, h: int, types: PackedByteArray) -> int:
	var t: int = types[y * w + x]
	var mask := 0
	for d in range(8):
		var dd: Vector2i = DIRS[d]
		var nx: int = x + dd.x
		var ny: int = y + dd.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		if types[ny * w + nx] != t:
			mask |= 1 << d
	return mask

func _mask_str(mask: int) -> String:
	var s := ""
	for d in range(8):
		s += "1" if (mask & (1 << (7 - d))) != 0 else "0"
	return s