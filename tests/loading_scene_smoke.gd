extends SceneTree
## Новая игра через loading.tscn (23.10).
##
## Запуск: godot --headless --path . --script res://tests/loading_scene_smoke.gd
##
## Проверяет: сцена загрузки запускается, генерирует стартовую карту и
## передаёт её в main.tscn; оверлей сборки в main снимается, герой и карта живы.

var _checks := 0
var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_race = "human"
	Game.hero_name = "Загрузчик"
	Game.new_random_map("start")
	_run.call_deferred()


func _run() -> void:
	var err := change_scene_to_file("res://scenes/loading.tscn")
	_check(err == OK, "loading.tscn загрузилась (err=%d)" % err)
	await process_frame
	var saw_loading := false
	var waited := 0.0
	while waited < 20.0:
		if current_scene != null and current_scene.name == "Loading":
			saw_loading = true
		if current_scene != null and current_scene.name != "Loading" \
				and current_scene.get("player") != null:
			break
		await create_timer(0.1).timeout
		waited += 0.1
	_check(saw_loading, "экран загрузки был показан")
	_check(current_scene != null and current_scene.name != "Loading",
		"после загрузки открылась игровая сцена (%s)" % (current_scene.name if current_scene != null else "null"))
	var player = current_scene.get("player") if current_scene != null else null
	var map = current_scene.get("alm_map") if current_scene != null else null
	_check(player != null, "герой жив после загрузки")
	_check(map != null, "карта загружена")
	_check(Game.pending_map_path != "" and FileAccess.file_exists(Game.pending_map_path),
		"карта передана через pending_map_path")
	_check(Game.map_sector == "s41", "стартовый сектор s41 (%s)" % Game.map_sector)
	_check(Game.map_zone == "start", "тир start (%s)" % Game.map_zone)
	# Оверлей сборки не должен остаться висеть: расселение идёт пачками.
	var overlay = current_scene.get("_loading_layer") if current_scene != null else null
	var waited_overlay := 0.0
	while waited_overlay < 10.0 and overlay != null and is_instance_valid(overlay):
		await create_timer(0.1).timeout
		waited_overlay += 0.1
		overlay = current_scene.get("_loading_layer") if current_scene != null else null
	_check(overlay == null or not is_instance_valid(overlay), "оверлей сборки снят")

	print("")
	if _fails.is_empty():
		print("RESULT: OK loading_scene_smoke (%d checks)" % _checks)
	else:
		print("RESULT: FAIL loading_scene_smoke (%d checks, %d fails)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)
