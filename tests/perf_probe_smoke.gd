extends SceneTree
## Профилировка: почему «тормоза» на современном ПК.
##
## Меряет:
##  * время find_path на длинном маршруте
##  * число узлов карты (деревья/зда��ия/юниты)
##  * кэш текстур препятствий (был ли load() в горячем цикле)
##  * коллизии: мирные NPC не должны стоять в слое 1
##
## Запуск: godot --headless --path . --script res://tests/perf_probe_smoke.gd

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
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.map_seed = 4242
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(4):
		await process_frame
	var player = game.get("player")
	var am = game.get("alm_map")
	await process_frame

	print("-- узлы карты --")
	var obstacles := _count_script(am, "alm_obstacle.gd")
	var buildings := _count_script(am, "structure_node.gd")
	print("  AlmObstacle: %d" % obstacles)
	print("  StructureNode: %d" % buildings)
	print("  NPC: %d  Enemy: %d  Party: %d" % [Game.npcs.size(), Game.enemies.size(), Game.party.size()])
	_check(obstacles > 0 or buildings > 0, "объекты карты есть (obs=%d bld=%d)" % [obstacles, buildings])
	_check(Game.npcs.size() > 0, "NPC есть (%d)" % Game.npcs.size())

	print("-- find_path (длинный маршрут) --")
	var w: int = int(am.map_width)
	var h: int = int(am.map_height)
	var a := Vector2(4 * 32 + 16, 4 * 32 + 16)
	var b := Vector2((w - 5) * 32 + 16, (h - 5) * 32 + 16)
	if not am.is_walkable_world(a):
		a = _walk_near(am, Vector2i(4, 4))
	if not am.is_walkable_world(b):
		b = _walk_near(am, Vector2i(w - 5, h - 5))
	# Среднее по 5 прогонов (первый — прогрев кэша)
	var total := 0.0
	var path: Array = []
	for i in range(5):
		var t0 := Time.get_ticks_usec()
		path = am.find_path(a, b)
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0
		total += dt
		if i == 4:
			print("  find_path: %.2f ms (среднее 5), клеток=%d" % [total / 5.0, path.size()])
	_check(total / 5.0 < 32.0, "find_path средний < 32 ms — один кадр 60 FPS (=%.2f)" % (total / 5.0))
	_check(path.size() > 0, "путь непустой (%d)" % path.size())

	print("-- кэш текстур препятствий --")
	var cache: Dictionary = AlmObstacle._tex_cache
	print("  AlmObstacle._tex_cache: %d" % cache.size())
	_check(cache.size() > 0, "текстуры кэшируются (не load каждый кадр)")
	_check(StructureNode._tex_cache.size() > 0 or buildings == 0,
		"текстуры зданий кэшируются (%d)" % StructureNode._tex_cache.size())

	print("-- коллизии мирных NPC --")
	var blocking_peaceful := 0
	var peaceful := 0
	for n in Game.npcs:
		if not is_instance_valid(n) or not (n is CharacterBody2D):
			continue
		var role := str((n as Npc).role)
		var is_mag: bool = (n as Npc).is_archmage
		if role == "citizen" or is_mag:
			peaceful += 1
			var body := n as CharacterBody2D
			if body.collision_layer == 1:
				blocking_peaceful += 1
	print("  мирных: %d, из них в слое 1 (блокируют): %d" % [peaceful, blocking_peaceful])
	_check(peaceful > 0, "мирные NPC на карте (%d)" % peaceful)
	_check(blocking_peaceful == 0, "мирные NPC НЕ блокируют путь (layer!=1)")

	print("-- FPS-монитор (один кадр после загрузки) --")
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	print("  FPS=%.1f process=%.2fms physics=%.2fms draw_calls=%.0f" % [fps, process_ms, physics_ms, draw_calls])
	_check(draw_calls < 2000, "draw calls в разумных пределах (%d)" % int(draw_calls))

	_report()


func _count_script(root_node: Node, script_name: String) -> int:
	var n := 0
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var sc: Script = node.get_script()
		if sc != null and sc.resource_path.ends_with(script_name):
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n


func _count_type(root_node: Node, type_name: String) -> int:
	var n := 0
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_class() == type_name or node.is_class(type_name):
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n


func _walk_near(am, cell: Vector2i) -> Vector2:
	for r in range(1, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				var p := Vector2(c.x * 32 + 16, c.y * 32 + 16)
				if am.is_walkable_world(p):
					return p
	return Vector2(64, 64)


func _report() -> void:
	print()
	if _fails.is_empty():
		print("RESULT: OK perf_probe_smoke checks=%d" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL perf_probe_smoke checks=%d fails=%d" % [_checks, _fails.size()])
		for m in _fails:
			print("  - %s" % m)
		quit(1)
