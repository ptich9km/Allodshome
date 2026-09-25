extends SceneTree
## Прогон живой игры с выводом ошибок. Ловит то, чего не видно в коротких тестах:
## C++-ошибки и «Nonexistent signal» проявляются не сразу (в логе пользователя —
## на 0:21 и 0:47), а короткие smoke-тесты живут по 0.5 с.
##
## Скрипт НЕ проверяет сам себя: он просто играет ~N секунд (ходит, упирается в
## NPC и границу, жмёт Esc) и завершается. Ошибки ловит вызов из командной
## строки (см. AGENTS.md §3) — ищи «SCRIPT ERROR|Nonexistent signal|C++ Error».
##
## Запуск: godot --headless --path . --script res://tests/runtime_errors_smoke.gd
## Ожидание: пустой вывод (кроме строк SMOKE:)

const SECONDS := 8.0

func _init() -> void:
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player = game.get("player")
	var am = game.get("alm_map")
	var ui = game.get("ui")
	print("SMOKE: карта %dx%d" % [int(am.get("map_width")), int(am.get("map_height"))])

	# Точки для обхода: скопления NPC/зданий (города), берег и края карты.
	var w: float = float(am.get("map_width")) * 32.0
	var h: float = float(am.get("map_height")) * 32.0
	var targets: Array[Vector2] = []
	for rec in am.call("get_units"):
		var p := Vector2(float(rec.get("x", 0)) * 32.0 + 16.0, float(rec.get("y", 0)) * 32.0 + 16.0)
		targets.append(p)
	# Края карты — там раньше было застревание.
	targets.append(Vector2(40.0, 40.0))
	targets.append(Vector2(w - 40.0, h - 40.0))
	targets.append(Vector2(w * 0.5, 30.0))
	targets.append(Vector2(30.0, h * 0.5))
	print("SMOKE: целей обхода %d (юнитов: %d)" % [targets.size(), targets.size() - 4])

	var deadline: float = Time.get_ticks_msec() / 1000.0 + SECONDS
	var idx := 0
	var steps := 0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		# Перемещение по маршруту
		game.handle_click(targets[idx % targets.size()])
		for f in range(30):
			await physics_frame
		# Панель склада: построение ячеек и тема
		ui.call("refresh_inventory")
		# Esc — закрытие/открытие интерфейсных панелей
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.pressed = true
		Input.parse_input_event(ev)
		for f in range(5):
			await physics_frame
		idx += 1
		steps = idx
	print("SMOKE: отработано подходов %d" % steps)
	print("SMOKE: ошибок в логе нет (проверяй вывод командной строки)")
	quit(0)
