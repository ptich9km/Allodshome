extends SceneTree
## Анализ переходов terrain-типов на реальных картах Nival.

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

var transitions := {}
var all_tiles := {}

func _init() -> void:
	for f in MAPS:
		var p: String = PV + f
		if not FileAccess.file_exists(p):
			continue
		var m: Dictionary = AlmLoader.load_map(p)
		if m.is_empty():
			continue
		_analyze(m)
	_print()
	quit(0)

func _analyze(m: Dictionary) -> void:
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedInt32Array = m["tiles"]

	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			var t: int = AlmLoader.tile_type(tiles[i])
			var raw_f: int = AlmLoader.tile_file(tiles[i])
			var r: int = AlmLoader.tile_frame(tiles[i])
			var file_n: int = (raw_f >> 4) + 1
			var variant: int = raw_f & 0xF
			var key: String = "%d:%d:%d" % [file_n, variant, r]

			if not all_tiles.has(t):
				all_tiles[t] = {}
			all_tiles[t][key] = int(all_tiles[t].get(key, 0)) + 1

			var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
			for d_idx in range(4):
				var d: Vector2i = dirs[d_idx]
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni: int = ny * w + nx
				var nt: int = AlmLoader.tile_type(tiles[ni])
				if nt == t:
					continue
				var pair: String = "%d->%d" % [t, nt]
				if not transitions.has(pair):
					transitions[pair] = {}
				transitions[pair][key] = int(transitions[pair].get(key, 0)) + 1

func _print() -> void:
	print("=== TRANSITIONS (top 10 per pair) ===")
	var pairs := []
	for pair in transitions:
		var total: int = 0
		var items: Dictionary = transitions[pair]
		for k in items:
			total += int(items[k])
		pairs.append([total, pair])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])

	for entry in pairs:
		var pair: String = str(entry[1])
		var total: int = int(entry[0])
		print("--- %s (%d cells) ---" % [pair, total])
		var items: Dictionary = transitions[pair]
		var sorted_items: Array = []
		for k in items:
			sorted_items.append([int(items[k]), str(k)])
		sorted_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var top_n: int = mini(10, sorted_items.size())
		for j in range(top_n):
			var cnt: int = int(sorted_items[j][0])
			var key: String = str(sorted_items[j][1])
			print("  %s x%d (%.0f%%)" % [key, cnt, cnt * 100.0 / total])
		print("")

	print("")
	print("=== ALL TILES BY TYPE (top 15) ===")
	var type_names := {0: "GRASS", 1: "MOUNTAIN", 2: "WATER", 3: "ROAD"}
	for t in [0, 1, 2, 3]:
		if not all_tiles.has(t):
			continue
		var items: Dictionary = all_tiles[t]
		var sorted_items: Array = []
		for k in items:
			sorted_items.append([int(items[k]), str(k)])
		sorted_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var total: int = 0
		for s in sorted_items:
			total += int(s[0])
		var tname: String = str(type_names.get(t, "T%d" % t))
		print("--- %s (total %d) ---" % [tname, total])
		var top_n: int = mini(15, sorted_items.size())
		for j in range(top_n):
			var cnt: int = int(sorted_items[j][0])
			var key: String = str(sorted_items[j][1])
			print("  %s x%d (%.1f%%)" % [key, cnt, cnt * 100.0 / total])
		print("")
