extends SceneTree

func _init() -> void:
	_diag("res://assets/maps/Kids3.alm")
	_diag("res://assets/maps/Beach.alm")
	quit()

func _diag(path: String) -> void:
	var data := AlmLoader.load_map(path)
	if data.is_empty():
		print("FAIL load", path)
		return
	var hflags: PackedByteArray = data["hflags"]
	var terrain: PackedByteArray = data["terrain"]
	print("=== %s (%dx%d, n=%d) ===" % [path.get_file(), data["width"], data["height"], hflags.size()])
	var dist := {}
	for i in range(hflags.size()):
		var hf := int(hflags[i])
		var key := str(hf)
		dist[key] = int(dist.get(key, 0)) + 1
	print("hflags < 16: ", {})
	for hf in range(16):
		if dist.has(str(hf)):
			print("  hflags=%d (n=%d)" % [hf, dist[str(hf)]])
	var special := 0
	for hf in range(16, 41):
		special += int(dist.get(str(hf), 0))
	if special > 0:
		print("  спец hflags 16..40: n=%d" % special)
	# آب: сколько клеток с hflags лlow nibble == 2 (file 3)
	var water3 := 0
	var water3_variants := {}
	for i in range(hflags.size()):
		var hf := int(hflags[i])
		if (hf & 0xF) + 1 == 3:
			water3 += 1
			var v := int((terrain[i] >> 4) & 0xF)
			water3_variants[str(v)] = int(water3_variants.get(str(v), 0)) + 1
	print("  file3-клетки (вода по нашим правилам): n=%d variants=%s" % [water3, water3_variants])
	# по WalkTable
	var walkable_water := 0
	var walked := 0
	for i in range(hflags.size()):
		if WalkTable.walkable_at(int(hflags[i]), int(terrain[i])):
			walked += 1
		var hf := int(hflags[i])
		if (hf & 0xF) + 1 == 3 and WalkTable.walkable_at(hf, int(terrain[i])):
			walkable_water += 1
	print("  проходимых клеток всего: %d (%.1f%%), из них file3-воды: %d" % [
		walked, 100.0 * walked / hflags.size(), walkable_water])