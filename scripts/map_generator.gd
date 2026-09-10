extends Node

const TILE_WIDTH = 64
const TILE_HEIGHT = 32

func _ready():
	await get_tree().process_frame
	var tilemap = get_parent() as TileMapLayer
	generate_tilemap(tilemap)

func generate_tilemap(tilemap: TileMapLayer):
	print("Загружаем тайлы terrain...")

	# Загружаем тайлы для разных типов terrain
	var grass_tiles = [
		"res://assets/terrain/tiles/tile1-00_00.png",
		"res://assets/terrain/tiles/tile1-01_00.png",
		"res://assets/terrain/tiles/tile1-02_00.png",
		"res://assets/terrain/tiles/tile1-03_00.png",
	]
	
	var sand_tiles = [
		"res://assets/terrain/tiles/tile2-00_00.png",
		"res://assets/terrain/tiles/tile2-01_00.png",
	]
	
	var tile_textures = []
	var tile_types = []  # "grass" или "sand"
	
	for path in grass_tiles:
		var tex = load(path)
		if tex:
			tile_textures.append(tex)
			tile_types.append("grass")
	
	for path in sand_tiles:
		var tex = load(path)
		if tex:
			tile_textures.append(tex)
			tile_types.append("sand")
	
	if tile_textures.size() == 0:
		print("  WARNING: No tiles found! Using fallback.")
		_create_fallback(tilemap)
		return

	print("  Loaded %d tiles" % tile_textures.size())

	# Создаём TileSet — каждый тайл как отдельный источник
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	tileset.tile_layout = TileSet.TILE_LAYOUT_STACKED

	var source_ids = []
	for i in range(tile_textures.size()):
		var source = TileSetAtlasSource.new()
		source.texture = tile_textures[i]
		source.texture_region_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
		source.create_tile(Vector2i(0, 0))
		var src_id = tileset.add_source(source)
		source_ids.append(src_id)
	
	tilemap.tile_set = tileset
	print("  Created %d sources" % source_ids.size())

	# Генерируем остров с разными тайлами
	var map_radius = 10
	for x in range(-map_radius, map_radius + 1):
		for y in range(-map_radius, map_radius + 1):
			var dist = abs(x) + abs(y)
			var pos = Vector2i(x, y)
			
			if dist <= 5:
				# Центр — трава, случайная вариация
				var tile_idx = abs(x * 7 + y * 13) % 4
				tilemap.set_cell(pos, source_ids[tile_idx], Vector2i(0, 0))
			elif dist <= 8:
				# Середина — тоже трава но другие вариации
				var tile_idx = 4 + abs(x * 3 + y * 11) % 2
				tilemap.set_cell(pos, source_ids[tile_idx], Vector2i(0, 0))
			elif dist <= 10:
				# Край — песок
				if source_ids.size() > 4:
					var tile_idx = 4 + abs(x + y) % 2
					tilemap.set_cell(pos, source_ids[tile_idx], Vector2i(0, 0))
	
	print("Остров готов! Размер: %dx%d" % [map_radius*2+1, map_radius*2+1])

func _create_fallback(tilemap: TileMapLayer):
	var grass_img = Image.create(TILE_WIDTH, TILE_HEIGHT, false, Image.FORMAT_RGBA8)
	grass_img.fill(Color(0.2, 0.55, 0.15, 1.0))
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

	for x in range(-5, 6):
		for y in range(-5, 6):
			if abs(x) + abs(y) <= 5:
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	
	print("Fallback island created")
