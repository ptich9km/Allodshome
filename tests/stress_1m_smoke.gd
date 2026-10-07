extends SceneTree
## Стресс-тест движка: карта 1000×1000, ×100 деревьев и НПЦ.
##
## Включает [stress] enabled=1, генерит карту, грузит сцену, меряет:
##  * время генерации
##  * время загрузки сцены / spawn юнитов
##  * число узлов (деревья/NPC/враги)
##  * время find_path
##  * FPS / physics ms после загрузки
##
## Запуск: godot --headless --path . --script res://tests/stress_1m_smoke.gd

const CFG := "res://assets/config/game.cfg"
const USER_CFG := "user://config/game.cfg"

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _run() -> void:
	print("=== STRESS 1M: включаю [stress] ===")
	_enable_stress(true)

	Game.hero_class = "warrior"
	Game.hero_name = "Стресс"
	Game.hero_character_id = "mfighter"
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.map_seed = 777
	Game.pending_map_path = ""

	print("-- генерация карты --")
	var t_gen0 := Time.get_ticks_msec()
	var mg = load("res://scripts/world/map_generator.gd").new()
	var alm_path: String = mg.generate(777, "mid", "user://maps/", "stress_1m", "stress_1m")
	var gen_ms := Time.get_ticks_msec() - t_gen0
	print("  generate: %.1f с -> %s" % [float(gen_ms) / 1000.0, alm_path])
	_check(gen_ms > 0, "генерация запустилась")
	_check(FileAccess.file_exists(alm_path), ".alm существует")
	_check(GameConfig.geti("stress", "map_size") == 1000, "map_size=1000")

	# Статистика sidecar
	var npcs_path := alm_path.get_basename() + ".npcs.json"
	if FileAccess.file_exists(npcs_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(npcs_path))
		if parsed is Dictionary:
			var npcs: Array = (parsed as Dictionary).get("npcs", [])
			var greys := 0
			var guards := 0
			var cits := 0
			for n in npcs:
				var role := str((n as Dictionary).get("role", ""))
				if role == "guard":
					guards += 1
				elif role == "citizen":
					cits += 1
				else:
					greys += 1
			print("  npcs.json: всего=%d стражи=%d жители=%d серые=%d" % [npcs.size(), guards, cits, greys])
			_check(guards + cits > 1000, "городских NPC > 1000 (=%d)" % (guards + cits))
			_check(greys > 1000, "Серых > 1000 (=%d)" % greys)

	print("-- загрузка сцены --")
	var t_load0 := Time.get_ticks_msec()
	Game.pending_map_path = alm_path
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	# Ждём дольше обычного: спавн десятков тысяч юнитов
	for i in range(30):
		await process_frame
	var load_ms := Time.get_ticks_msec() - t_load0
	print("  scene+spawn: %.1f с" % [float(load_ms) / 1000.0])
	var player = game.get("player")
	var am = game.get("alm_map")
	_check(player != null, "игрок загружен")
	_check(am != null, "карта загружена")
	if am != null:
		var w := int(am.map_width)
		var h := int(am.map_height)
		print("  map: %dx%d" % [w, h])
		_check(w >= 1000 and h >= 1000, "карта 1000+ (%dx%d)" % [w, h])

	print("-- юниты в сцене --")
	print("  NPC=%d Enemy=%d Party=%d" % [Game.npcs.size(), Game.enemies.size(), Game.party.size()])
	_check(Game.npcs.size() > 500, "NPC в сцене > 500 (=%d)" % Game.npcs.size())
	_check(Game.enemies.size() > 500, "врагов в сцене > 500 (=%d)" % Game.enemies.size())

	# Деревья
	var trees := 0
	var stack: Array = [am]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var sc: Script = node.get_script()
		if sc != null and sc.resource_path.ends_with("alm_obstacle.gd"):
			trees += 1
		for c in node.get_children():
			stack.append(c)
	print("  AlmObstacle (деревья): %d" % trees)
	_check(trees > 5000, "деревьев > 5000 (=%d)" % trees)

	print("-- find_path --")
	if am != null:
		var a := Vector2(8 * 32 + 16, 8 * 32 + 16)
		var b := Vector2((int(am.map_width) - 8) * 32 + 16, (int(am.map_height) - 8) * 32 + 16)
		var total := 0.0
		var path: Array = []
		for i in range(3):
			var t0 := Time.get_ticks_usec()
			path = am.find_path(a, b)
			total += float(Time.get_ticks_usec() - t0) / 1000.0
		print("  find_path avg: %.2f ms, клеток=%d" % [total / 3.0, path.size()])
		_check(total / 3.0 < 100.0, "find_path < 100 ms (=%.2f)" % (total / 3.0))

	print("-- монитор --")
	# Даём кадрам отработать
	for i in range(20):
		await process_frame
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	print("  FPS=%.1f physics=%.1fms process=%.1fms static_mem=%.0fMB" % [fps, phys, proc, mem])
	_check(true, "монитор снят (FPS=%.1f)" % fps)

	_enable_stress(false)
	_report()


func _enable_stress(on: bool) -> void:
	# Пишем user://config/game.cfg — GameConfig перекрывает res://
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(USER_CFG):
		cfg.load(USER_CFG)
	cfg.set_value("stress", "enabled", 1 if on else 0)
	if on:
		cfg.set_value("stress", "map_size", 1000)
		cfg.set_value("stress", "tree_count", 83700)
		cfg.set_value("stress", "gray_count", 7500)
		cfg.set_value("stress", "city_guard_count", 2000)
		cfg.set_value("stress", "city_citizen_count", 1800)
		cfg.set_value("stress", "gen_version", 99)
	var dir := USER_CFG.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	cfg.save(USER_CFG)
	# Сбрасываем кэш GameConfig
	GameConfig._loaded = false
	GameConfig.load_all()
	print("  stress.enabled=%d map_size=%d" % [
		GameConfig.geti("stress", "enabled"),
		GameConfig.geti("stress", "map_size"),
	])


func _report() -> void:
	print()
	if _fails.is_empty():
		print("RESULT: OK stress_1m_smoke checks=%d" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL stress_1m_smoke checks=%d fails=%d" % [_checks, _fails.size()])
		for m in _fails:
			print("  - %s" % m)
		quit(1)
