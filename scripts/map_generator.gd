extends Node

# Размер тайла в оригинале (из .reg файлов)
const TILE_WIDTH = 64
const TILE_HEIGHT = 32

func _ready():
	await get_tree().process_frame
	var tilemap = get_parent() as TileMapLayer
	generate_original_terrain(tilemap)

func generate_original_terrain(tilemap: TileMapLayer):
	print("Загружаем оригинальные тайлы Allods 2...")

	# Загружаем тайлы из BMP файлов
	# tile1-XX — основной terrain (4 тайлсета)
	var tilesets = []
	var tileset_names = ["tile1", "tile2", "tile3", "tile4"]
	
	for ts_name in tileset_names:
		var tiles = []
		var max_variants = 16
		# tile4 имеет только 4 вариации (00-03)
		if ts_name == "tile4":
			max_variants = 4
		
		for i in range(max_variants):
			var path = "res://assets/terrain/%s-%02d.bmp" % [ts_name, i]
			var tex = load(path)
			if tex:
				tiles.append(tex)
				print("  Loaded: %s-%02d.bmp (%dx%d)" % [ts_name, i, tex.get_width(), tex.get_height()])
			else:
				# Файл не найден — пробуем без leading zero
				path = "res://assets/terrain/%s-%d.bmp" % [ts_name, i]
				tex = load(path)
				if tex:
					tiles.append(tex)
		
		if tiles.size() > 0:
			tilesets.append({
				"name": ts_name,
				"tiles": tiles
			})

	if tilesets.size() == 0:
		print("  WARNING: No terrain tiles found! Using fallback grass texture.")
		_create_fallback_terrain(tilemap)
		return

	print("  Loaded %d tilesets" % tilesets.size())

	# Создаём TileSet
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	tileset.tile_layout = TileSet.TILE_LAYOUT_STACKED  # Изометрическая раскладка

	# Добавляем каждый тайлсет как источник
	var source_ids = {}
	for ts_data in tilesets:
		var source = TileSetAtlasSource.new()
		
		# Первая текстура (вариация 00) — основная
		var main_tex = ts_data["tiles"][0]
		source.texture = main_tex
		source.texture_region_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
		
		# Создаём тайлы для каждой вариации
		for i in range(ts_data["tiles"].size()):
			source.create_tile(Vector2i(i, 0))
		
		var src_id = tileset.add_source(source)
		source_ids[ts_data["name"]] = src_id
		print("  Source '%s': %d tiles, ID=%d" % [ts_data["name"], ts_data["tiles"].size(), src_id])

	tilemap.tile_set = tileset

	# Генерируем карту как в оригинале (диамантовый остров)
	var map_radius = 10
	
	for x in range(-map_radius, map_radius + 1):
		for y in range(-map_radius, map_radius + 1):
			var dist = abs(x) + abs(y)
			var pos = Vector2i(x, y)
			
			if dist <= 5:
				# Центр — тайлсет 1 (трава), вариация 0
				tilemap.set_cell(pos, source_ids["tile1"], Vector2i(0, 0))
			elif dist <= 7:
				# Середина — тайлсет 1, разные вариации
				var variant = (x + y * 3) % 16
				tilemap.set_cell(pos, source_ids["tile1"], Vector2i(variant, 0))
			elif dist <= 9:
				# Край — тайлсет 2 (песок/камень)
				var variant = (x * 2 + y) % 16
				if source_ids.has("tile2"):
					tilemap.set_cell(pos, source_ids["tile2"], Vector2i(variant, 0))
				else:
					tilemap.set_cell(pos, source_ids["tile1"], Vector2i(0, 0))
			elif dist <= 10:
				# Обод — тайлсет 3 (вода/край)
				if source_ids.has("tile3"):
					tilemap.set_cell(pos, source_ids["tile3"], Vector2i(0, 0))

	print("Остров готов! Размер: %dx%d" % [map_radius*2+1, map_radius*2+1])

func _create_fallback_terrain(tilemap: TileMapLayer):
	# Фоллбэк если BMP не загрузились
	var grass_img = Image.create(TILE_WIDTH, TILE_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in range(TILE_HEIGHT):
		for x in range(TILE_WIDTH):
			var n = ((x * 7 + y * 13) % 40) - 20
			grass_img.set_pixel(x, y, Color(
				float(55 + n) / 255.0,
				float(145 + n) / 255.0,
				float(45 + n / 2) / 255.0,
				1.0
			))
	var grass_tex = ImageTexture.create_from_image(grass_img)

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	tileset.tile_layout = TileSet.TILE_LAYOUT_STACKED

	var gs = TileSetAtlasSource.new()
	gs.texture = grass_tex
	gs.texture_region_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	gs.create_tile(Vector2i(0, 0))
	tileset.add_source(gs)
	tilemap.tile_set = tileset

	# Маленький остров
	for x in range(-5, 6):
		for y in range(-5, 6):
			if abs(x) + abs(y) <= 5:
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	
	print("Fallback island created (no terrain BMP found)")
