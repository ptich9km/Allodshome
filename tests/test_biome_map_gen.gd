extends SceneTree

# Тест генерации карты с биомными текстурами

func _init():
	print("=== Тест генерации карты с биомными текстурами ===")
	
	var generator = load("res://scripts/world/map_generator.gd").new()
	generator.use_biome_textures = true  # Включаем режим биомных текстур
	
	var path = generator.generate(12345, "mid", "res://assets/maps/gen/", "test_biome", "test_biome")
	
	if path != "":
		print("Карта сгенерирована: %s" % path)
		print("Открой res://scenes/main.tscn и установи alm_path = '%s'" % path)
	else:
		print("Ошибка генерации карты!")
	
	quit(0)
