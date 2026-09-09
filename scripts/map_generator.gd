extends Node

# Этот скрипт встроен в TileMap в main.tscn
# Генерация происходит в _ready()

func _ready():
	await get_tree().process_frame
	var tilemap = get_parent() as TileMapLayer
	generate_island(tilemap)

func generate_island(tilemap: TileMapLayer):
	print("Генерируем остров...")
	
	# Генерируем ромбовидный остров как в Unity
	for x in range(-8, 9):
		for y in range(-8, 9):
			var distance = abs(x) + abs(y)
			var cell_pos = Vector2i(x, y)
			
			if distance <= 7:
				# Трава - используем source_id = 0, atlas_coords = (0, 0)
				tilemap.set_cell(cell_pos, 0, Vector2i(0, 0))
			elif distance == 8:
				# Стена - используем source_id = 1, atlas_coords = (0, 0)
				tilemap.set_cell(cell_pos, 1, Vector2i(0, 0))
	
	print("Остров сгенерирован!")
