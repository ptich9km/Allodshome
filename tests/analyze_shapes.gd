extends SceneTree
## Audit of transition SHAPES on real Nival maps (pvm/).
## For every border cell: builds an 8-bit peer mask (which of the 8 neighbors
## have a DIFFERENT terrain type than the center), then records which tile
## the designers placed there. Result shows which shapes real art supports.
##
## Mask bit layout (index = bit): [N, NE, E, SE, S, SW, W, NW]
## e.g. "100100000" -> N and W neighbors differ.

const PV := "res://assets/maps/pvm/"
const SHAPES_JSON := "res://assets/maps/shapes_db.json"

const DIRS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const DIR_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# shape -> neighbor-types map (for context: which other terrain borders this shape)
# shape -> tile_key -> count
var shapes := {}
var shape_types := {}
# type -> tile_key -> count (base/interior textures: cells with all-8 same-type neighbors)
var interiors := {}

func _init() -> void:
	var maps := _scan_maps()
	print("maps: %d -> %s" % [maps.size(), str(maps)])
	var loaded := 0
	var border_cells := 0
	for f in maps:
		var m: Dictionary = AlmLoader.load_map(PV + f)
		if m.is_empty():
			continue
		loaded += 1
		border_cells += _analyze(m)
	print("loaded: %d, border cells: %d" % [loaded, border_cells])
	_print()
	_dump_json()
	quit(0)

## Compact shape table for the generator:
## {"shapes": {"0:00000010": {"tiles": [{"file":1,"variant":5,"row":4}, ...], "total": n}, ...}}
## {"interior": {"0": {"tiles": [top base textures], "total": n}, ...}}
## Only masks with >= MIN_CELLS are included; top-N weighted tiles each.
func _dump_json() -> void:
	const MIN_CELLS := 20
	const TOP_N := 4
	var out := {"shapes": {}}
	for key in shapes:
		var parts: Array = key.split(":")
		var t: int = int(parts[0])
		if t > 3:
			continue
		var mask: String = str(parts[1])
		var items: Dictionary = shapes[key]
		var total: int = 0
		for k in items:
			total += int(items[k])
		if total < MIN_CELLS:
			continue
		var sorted_items: Array = []
		for k in items:
			sorted_items.append([int(items[k]), str(k)])
		sorted_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var tiles: Array = []
		for j in range(mini(TOP_N, sorted_items.size())):
			var tk: Array = String(str(sorted_items[j][1])).split(":")
			tiles.append({
				"file": int(tk[0]), "variant": int(tk[1]), "row": int(tk[2]),
				"w": int(sorted_items[j][0]),
			})
		out["shapes"]["%d:%s" % [t, mask]] = {"tiles": tiles, "total": total}
	# Interior base textures: top-6 per type (0-3).
	var interior_out := {}
	for tkey in interiors:
		var t: int = int(tkey)
		if t > 3:
			continue
		var items: Dictionary = interiors[tkey]
		var total: int = 0
		for k in items:
			total += int(items[k])
		if total < MIN_CELLS:
			continue
		var sorted_items: Array = []
		for k in items:
			sorted_items.append([int(items[k]), str(k)])
		sorted_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var tiles: Array = []
		for j in range(mini(6, sorted_items.size())):
			var tk: Array = String(str(sorted_items[j][1])).split(":")
			tiles.append({
				"file": int(tk[0]), "variant": int(tk[1]), "row": int(tk[2]),
				"w": int(sorted_items[j][0]),
			})
		interior_out[str(t)] = {"tiles": tiles, "total": total}
	out["interior"] = interior_out
	var f := FileAccess.open(SHAPES_JSON, FileAccess.WRITE)
	if f == null:
		print("ERROR: cant write " + SHAPES_JSON)
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("shapes table: %s (%d entries, %d interior sets)" % [SHAPES_JSON, out["shapes"].size(), interior_out.size()])

func _scan_maps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(PV)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.to_lower().ends_with(".alm"):
			out.append(f)
	out.sort()
	return out

func _analyze(m: Dictionary) -> int:
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedInt32Array = m["tiles"]
	var types := PackedByteArray()
	types.resize(w * h)
	for i in range(w * h):
		types[i] = (tiles[i] & 0xFF0) >> 8

	var cnt := 0
	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			var t: int = types[i]
			var mask := 0
			var ntypes := {}
			var is_border := false
			for d in range(8):
				var dd: Vector2i = DIRS[d]
				var nx: int = x + dd.x
				var ny: int = y + dd.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var nt: int = types[ny * w + nx]
				if nt != t:
					mask |= (1 << d)
					ntypes[nt] = true
					is_border = true
			var raw_f: int = AlmLoader.tile_file(tiles[i])
			var file_n: int = (raw_f >> 4) + 1
			var variant: int = raw_f & 0xF
			var row: int = AlmLoader.tile_frame(tiles[i])
			var tk: String = "%d:%d:%d" % [file_n, variant, row]
			if not is_border:
				# Interior base texture
				if not interiors.has(str(t)):
					interiors[str(t)] = {}
				interiors[str(t)][tk] = int(interiors[str(t)].get(tk, 0)) + 1
				continue
			cnt += 1
			var mkey := "%d:%s" % [t, _mask_str(mask)]
			if not shapes.has(mkey):
				shapes[mkey] = {}
				shape_types[mkey] = {}
			shapes[mkey][tk] = int(shapes[mkey].get(tk, 0)) + 1
			for nt in ntypes:
				shape_types[mkey][nt] = int(shape_types[mkey].get(nt, 0)) + 1
	return cnt

func _mask_str(mask: int) -> String:
	var s := ""
	for d in range(8):
		s += "1" if (mask & (1 << (7 - d))) != 0 else "0"
	return s

func _print() -> void:
	var type_names := {0: "GRASS", 1: "MOUNTAIN", 2: "WATER", 3: "ROAD", 4: "SOIL", 5: "SAND", 6: "MUD"}
	print("=== SHAPE SUMMARY (edge types present in real maps) ===")
	var type_totals := {}
	var type_shapecount := {}
	for key in shapes:
		var parts: Array = key.split(":")
		var t: int = int(parts[0])
		var total: int = 0
		for k in shapes[key]:
			total += int(shapes[key][k])
		type_totals[t] = int(type_totals.get(t, 0)) + total
		type_shapecount[t] = int(type_shapecount.get(t, 0)) + 1
	for t in [0, 1, 2, 3, 4, 5, 6]:
		if not type_totals.has(t):
			continue
		var tn: String = str(type_names.get(t, "T%d" % t))
		print("  %s: %d cells, %d distinct shapes" % [tn, int(type_totals[t]), int(type_shapecount[t])])

	print("")
	print("=== SHAPE DETAILS (top tiles per shape, min 20 cells) ===")
	var keys: Array = []
	for k in shapes:
		keys.append(str(k))
	keys.sort()
	for key in keys:
		var parts: Array = key.split(":")
		var t: int = int(parts[0])
		var total: int = 0
		for k in shapes[key]:
			total += int(shapes[key][k])
		if total < 20:
			continue
		var items: Dictionary = shapes[key]
		var sorted_items: Array = []
		for k in items:
			sorted_items.append([int(items[k]), str(k)])
		sorted_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var tn: String = str(type_names.get(t, "T%d" % t))
		var nt_ctx := ""
		for nt in shape_types[key]:
			nt_ctx += " %s=%d" % [str(type_names.get(int(nt), "T%s" % nt)), int(shape_types[key][nt])]
		print("--- %s mask=%s (%d cells; neighbors:%s) ---" % [tn, parts[1], total, nt_ctx])
		var top_n: int = mini(6, sorted_items.size())
		for j in range(top_n):
			var cnt: int = int(sorted_items[j][0])
			var tk: String = str(sorted_items[j][1])
			print("  %s x%d (%.0f%%)" % [tk, cnt, cnt * 100.0 / total])
	print("")