extends Node

# Генерирует изометрический остров программно, без TileSet
func _ready():
	await get_tree().process_frame
	var tilemap = get_parent() as TileMapLayer
	generate_island(tilemap)

func generate_island(tilemap: TileMapLayer):
	print("Генерируем остров программно...")
	
	# Создаём текстуру травы
	var grass_img = Image.new()
	grass_img.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(64):
			var noise = ((x * 7 + y * 13) % 40) - 20
			grass_img.set_pixel(x, y, Color(
				(55 + noise) / 255.0,
				(145 + noise) / 255.0,
				(45 + noise / 2) / 255.0,
				1.0
			))
	var grass_tex = ImageTexture.create_from_image(grass_img)
	
	# Создаём текстуру стены
	var wall_img = Image.new()
	wall_img.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(64):
			var noise = ((x * 11 + y * 7) % 30) - 15
			var base = 100 + (y / 8) * 8
			wall_img.set_pixel(x, y, Color(
				(base + noise) / 255.0,
				(base + noise - 5) / 255.0,
				(base + noise - 10) / 255.0,
				1.0
			))
	var wall_tex = ImageTexture.create_from_image(wall_img)
	
	# Создаём TileSet программно
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(64, 32)
	tileset.tile_layout = 3  # Isometric
	
	# Source 0: трава
	var grass_source = TileSetAtlasSource.new()
	grass_source.texture = grass_tex
	grass_source.texture_region_size = Vector2i(64, 32)
	var grass_source_id = tileset.add_source(grass_source)
	grass_source.create_tile(Vector2i(0, 0))
	
	# Source 1: стена
	var wall_source = TileSetAtlasSource.new()
	wall_source.texture = wall_tex
	wall_source.texture_region_size = Vector2i(64, 32)
	var wall_source_id = tileset.add_source(wall_source)
	wall_source.create_tile(Vector2i(0, 0))
	
	# Применяем TileSet
	tilemap.tile_set = tileset
	
	# Генерируем остров
	for x in range(-8, 9):
		for y in range(-8, 9):
			var distance = abs(x) + abs(y)
			var cell_pos = Vector2i(x, y)
			if distance <= 7:
				tilemap.set_cell(cell_pos, 0, Vector2i(0, 0))
			elif distance == 8:
				tilemap.set_cell(cell_pos, 1, Vector2i(0, 0))
	
	print("Остров сгенерирован! TileSet source IDs: grass=", grass_source_id, " wall=", wall_source_id)
