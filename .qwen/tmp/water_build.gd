extends SceneTree

func _init() -> void:
	_chec("res://assets/maps/Kids3.alm")
	_chec("res://assets/maps/Beach.alm")
	quit()

func _chec(path: String) -> void:
	var m := AlmMap.new()
	m.alm_path = path
	root.add_child(m)
	await process_frame
	print("=== %s ===" % path.get_file())
	print("  water_tex=%s rows=%d total=%d vidx=%s" % [
		"null" if m._water_tex == null else "ok",
		m._water_rows, m._water_total, m._water_vidx])
	var atlas: ImageTexture = m.get_atlas_texture()
	print("  atlas: %s (%dx%d)" % ["null" if atlas == null else "ok", atlas.get_width() if atlas != null else 0, atlas.get_height() if atlas != null else 0])
	print("  cell_uv keys=%d" % m._cell_uv.size())
	# найди первую водную клетку и её UV
	var found := 0
	for i in range(m.map_width * m.map_height):
		var hf := int(m._hflags[i])
		if (hf & 0xF) + 1 == 3:
			var v := int((m._terrain[i] >> 4) & 0xF)
			var r := int(m._terrain[i] & 0xF)
			var key := "f3-v%d-r%d" % [v, r]
			if found < 3:
				print("  вода клетка %d: hf=%d v=%d r=%d uv=%s" % [i, hf, v, r, m._cell_uv.get(key, "НЕТ!")])
				found += 1
	m.queue_free()
	await process_frame