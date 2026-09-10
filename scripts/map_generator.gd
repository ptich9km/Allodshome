extends Node

const TILE_WIDTH = 64
const TILE_HEIGHT = 32

func _ready():
	await get_tree().process_frame
	var tilemap = get_parent() as TileMapLayer
	generate_tilemap(tilemap)

func generate_tilemap(tilemap: TileMapLayer):
	print("Загружаем тайлы terrain...")

	# Загружаем все PNG тайлы из tiles/
	var tile_dir = "res://assets/terrain/tiles/"
	var tile_textures = []
	
	# Загружаем tile1 (трава) - первые 16 вариаций * 14 рядов = 224 тайла
	for i in range(224):
		var path = tile_dir + "tile1-%02d_%02d.png" % [i / 14, i % 14]
		var tex = load(path)
		if tex:
			tile_textures.append(tex)
	
	if tile_textures.size() == 0:
		print("  WARNING: No tiles found! Using fallback.")
		_create_fallback(tilemap)
		return

	print("  Loaded %d tiles" % tile_textures.size())

	# Создаём TileSet
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	tileset.tile_layout = TileSet.TILE_LAYOUT_STACKED

	var source = TileSetAtlasSource.new()
	source.texture = tile_textures[0]
	source.texture_region_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	
	for i in range(min(50, tile_textures.size())):
		source.create_tile(Vector2i(i, 0))
	
	var src_id = tileset.add_source(source)
	tilemap.tile_set = tileset
	
	print("  Source created with ID=%d" % src_id)

	# Генерируем остров
	var map_radius = 10
	for x in range(-map_radius, map_radius + 1):
		for y in range(-map_radius, map_radius + 1):
			var dist = abs(x) + abs(y)
			var pos = Vector2i(x, y)
			
			if dist <= 7:
				tilemap.set_cell(pos, src_id, Vector2i(0, 0))
	
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
