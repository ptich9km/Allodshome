extends Node

func _ready():
	await get_tree().process_frame
	var tilemap = get_parent() as TileMapLayer
	generate_island(tilemap)

func generate_island(tilemap: TileMapLayer):
	print("Генерируем остров...")
	
	# Создаём текстуры
	var grass_img = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(64):
			var n = ((x * 7 + y * 13) % 40) - 20
			grass_img.set_pixel(x, y, Color((55+n)/255.0, (145+n)/255.0, (45+n/2)/255.0, 1.0))
	var grass_tex = ImageTexture.create_from_image(grass_img)
	
	var wall_img = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(64):
			var n = ((x * 11 + y * 7) % 30) - 15
			var b = 100 + int(y / 8) * 8
			wall_img.set_pixel(x, y, Color((b+n)/255.0, (b+n-5)/255.0, (b+n-10)/255.0, 1.0))
	var wall_tex = ImageTexture.create_from_image(wall_img)
	
	# Создаём TileSet
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(64, 32)
	tileset.tile_layout = 3
	
	# Source 0 — трава
	var gs = TileSetAtlasSource.new()
	gs.texture = grass_tex
	gs.texture_region_size = Vector2i(64, 32)
	gs.create_tile(Vector2i(0, 0))
	var gid = tileset.add_source(gs)
	print("  Grass source_id=", gid)
	
	# Source 1 — стена
	var ws = TileSetAtlasSource.new()
	ws.texture = wall_tex
	ws.texture_region_size = Vector2i(64, 32)
	ws.create_tile(Vector2i(0, 0))
	var wid = tileset.add_source(ws)
	print("  Wall source_id=", wid)
	
	tilemap.tile_set = tileset
	
	for x in range(-8, 9):
		for y in range(-8, 9):
			var dist = abs(x) + abs(y)
			var pos = Vector2i(x, y)
			if dist <= 7:
				tilemap.set_cell(pos, gid, Vector2i(0, 0))
			elif dist == 8:
				tilemap.set_cell(pos, wid, Vector2i(0, 0))
	
	print("Остров готов! Трава=", gid, " Стена=", wid)
