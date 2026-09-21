extends SceneTree
## Анализ DIRECTIONAL переходов на картах Nival.
## Для каждой клетки на границе: КАКОЙ стороной сосед отличается,
## и какой tile variant/row при этом стоит.

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

# Ключ: "type:dir:neighbor" -> { "file:variant:row": count }
# type = terrain type (0-3), dir = N/S/E/W, neighbor = neighbor terrain type
var directional := {}

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
			var tile_key: String = "%d:%d:%d" % [file_n, variant, r]

			# Проверить каждую сторону
			var dirs := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
			for dir_name in dirs:
				var d: Vector2i = dirs[dir_name]
				var nx: int = x + int(d.x)
				var ny: int = y + int(d.y)
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni: int = ny * w + nx
				var nt: int = AlmLoader.tile_type(tiles[ni])
				if nt == t:
					continue
				# Граница! t с dir_name стороны сосед nt
				var key: String = "%d:%s:%d" % [t, dir_name, nt]
				if not directional.has(key):
					directional[key] = {}
				directional[key][tile_key] = int(directional[key].get(tile_key, 0)) + 1

func _print() -> void:
	var type_names := {0: "GRASS", 1: "MOUNTAIN", 2: "WATER", 3: "ROAD"}
	var dir_names := ["N", "S", "E", "W"]

	# Собрать и отсортировать ключи
	var keys: Array = []
	for k in directional:
		keys.append(str(k))
	keys.sort()

	for key in keys:
		var parts: Array = key.split(":")
		var t: int = int(parts[0])
		var dir: String = parts[1]
		var nt: int = int(parts[2])
		var tname: String = str(type_names.get(t, "T%d" % t))
		var ntname: String = str(type_names.get(nt, "T%d" % nt))
		var items: Dictionary = directional[key]
		var total: int = 0
		for k2 in items:
			total += int(items[k2])
		print("--- %s %s→%s (%d cells) ---" % [tname, dir, ntname, total])
		var sorted_items: Array = []
		for k2 in items:
			sorted_items.append([int(items[k2]), str(k2)])
		sorted_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var top_n: int = mini(8, sorted_items.size())
		for j in range(top_n):
			var cnt: int = int(sorted_items[j][0])
			var tk: String = str(sorted_items[j][1])
			print("  %s x%d (%.0f%%)" % [tk, cnt, cnt * 100.0 / total])
		print("")
