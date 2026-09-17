extends SceneTree

func _init() -> void:
	# Размеры текстур воды tile3-XX.bmp
	for v in [0, 1, 3, 5]:
		var path := "res://assets/terrain/tile3-%02d.bmp" % v
		if not ResourceLoader.exists(path):
			print("нет файла: ", path)
			continue
		var tex: Texture2D = load(path)
		print("tile3-%02d: %dx%d" % [v, tex.get_width(), tex.get_height()])
	# Разбор байтов реальной карты: для водных клеток (file3) какие row/variant
	var data := AlmLoader.load_map("res://assets/maps/Beach.alm")
	var hflags: PackedByteArray = data["hflags"]
	var terrain: PackedByteArray = data["terrain"]
	var water_rows := {}
	var max_row := 0
	var water_variants := {}
	for i in range(hflags.size()):
		var hf := int(hflags[i])
		if (hf & 0xF) + 1 != 3:
			continue
		var v := int((terrain[i] >> 4) & 0xF)
		var r := int(terrain[i] & 0xF)
		water_variants[str(v)] = int(water_variants.get(str(v), 0)) + 1
		max_row = maxi(max_row, r)
	print("Beach: варианты воды: ", water_variants, " max_row=", max_row)
	quit()