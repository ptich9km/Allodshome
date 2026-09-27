extends SceneTree

# Тест генерации карты с биомными текстурами

func _init():
	print("=== Тест генерации карты с биомными текстурами ===")

	var generator = load("res://scripts/world/map_generator.gd").new()
	generator.use_biome_textures = true  # Включаем режим биомных текстур

	var path = generator.generate(12345, "mid", "res://assets/maps/gen/", "test_biome", "test_biome")

	if path != "":
		print("Карта сгенерирована: %s" % path)
		
		# Проверяем что биомные тайлы записаны
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			var data = f.get_buffer(f.get_length())
			f.close()
			
			# Ищем бит 12 в тайлах (секция id=1)
			var biome_tiles = 0
			var total_tiles = 128 * 128
			# Секция tiles начинается после заголовка и info секции
			# Упрощённо: проверяем несколько тайлов в середине
			for i in range(100):
				var offset = 0x14 + 20 + 660 + 20 + (64 * 128 + 64) * 2  # Примерно середина карты
				if offset + i * 2 < data.size():
					var tile = data[offset + i * 2] | (data[offset + i * 2 + 1] << 8)
					if tile & 0x1000:
						biome_tiles += 1
			
			print("Найдено %d биомных тайлов из %d проверенных" % [biome_tiles, 100])
		
		print("Открой res://scenes/main.tscn и установи alm_path = '%s'" % path)
	else:
		print("Ошибка генерации карты!")

	quit(0)
