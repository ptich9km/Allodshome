extends SceneTree
## Тест полного цикла: эмулируем выбор персонажа (маг-женщина) и запускаем main.tscn.
## Запуск: godot --headless --path . -s res://tests/test_hero_select.gd

func _init():
	# Эмулируем выбор на экране старта
	Game.hero_class = "mage"
	Game.hero_gender = "female"
	Game.hero_name = "Афина"
	Game.hero_character_id = "fmage"
	Game.hero_stats = {
		"body": 7, "agility": 10, "mind": 12, "spirit": 13,
		"blade": 5, "bludgeon": 5, "pike": 5,
		"fire": 25, "water": 25, "air": 15, "earth": 10, "astral": 10,
		"weapon": "staff", "shield": false, "armor": "heavy",
	}
	var scene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	# Несколько кадров, чтобы всё инициализировалось
	var frames := 0
	while frames < 20:
		await process_frame
		frames += 1
	# Проверки
	var player := root.get_node("Main/Player")
	print("=== ТЕСТ ВЫБОРА ПЕРСОНАЖА ===")
	print("name:", Game.hero_name)
	print("body=%d agility=%d mind=%d spirit=%d" % [player.body, player.agility, player.mind, player.spirit])
	print("weapon=%s armor=%s shield=%s" % [player.weapon, player.armor_kind, player.has_shield])
	print("max_hp=%d max_mana=%d speed=%.1f" % [player.max_hp, player.max_mana, player.move_speed])
	print("anim_set:", player.anim_set_name())
	var port := player.get_node("../UI/PortraitBorder/PortraitTexture") if player.get_node_or_null("../UI/PortraitBorder/PortraitTexture") else null
	var ui_name := player.get_node("../UI/HeroName")
	if ui_name:
		print("UI hero name:", (ui_name as Label).text)
	var ok: bool = player.body == 7 and player.mind == 12 and player.fire_skill == 25 \
		and player.weapon == "staff" and player.max_hp == 76 and player.max_mana == 62
	print("RESULT:", "OK" if ok else "FAIL")
	quit(0 if ok else 1)