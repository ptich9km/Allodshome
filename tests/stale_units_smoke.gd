extends SceneTree
##
## Мёртвые узлы в статических массивах Game (09.10).
##
## Жалоба игрока: новая игра за другую расу — краш
##   `_sep_insert(unit: Node2D): Invalid type ... argument 1 (previously freed)`
##   game.gd:306 @ _sep_rebuild_grid() <- npc.gd:428 @ _move_checked()
##
## Причина: Game.enemies/npcs — `static var`, они переживают смену сцены,
## а `Main._ready()` чистил только `Game.party`. К моменту новой игры узлы
## прежней карты уже освобождены движком, но остаются в массивах.
##
## Проверка кладёт в Game.npcs узел, тут же его освобождает, и требует, чтобы
## `Game.movement_direction()` пережил это. До правки — SCRIPT ERROR и падение.
##
## godot --headless --path . --script res://tests/stale_units_smoke.gd
##

var _checks := 0
var _fails: Array[String] = []


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 13, "spirit": 12,
		"blade": 10, "bludgeon": 10, "pike": 10, "shooting": 10,
		"fire": 20, "water": 20, "air": 20, "earth": 20, "astral": 20,
		"weapon": "staff", "shield": false, "armor": "light"}
	Game.hero_class = "mage"
	Game.hero_name = "Маг"
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _run() -> void:
	print("-- статические массивы Game --")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "загрузка main.tscn: %d" % err)
		_finish()
		return
	await process_frame
	await create_timer(0.6).timeout
	var hero := get_first_node_in_group("player") as Player
	_check(hero != null, "герой загружен")
	if hero == null:
		_finish()
		return

	# 1. Битых узлов от прежней сцены быть не должно (сейчас сцена первая —
	#    проверка всё равно нужна как инвариант на будущие перезагрузки).
	_check(_dead_count() == 0,
		"после загрузки сцены в массивах нет освобождённых узлов (нашлось %d)"
			% _dead_count())

	# 2. Кладём ghost: добавляем в массив и сразу освобождаем — узел остаётся
	#    в статике, но уже freed. Именно это состояние и роняло игру.
	var ghost := Npc.new()
	ghost.anim_set = "city_human_mage/t0"
	(current_scene as Node).add_child(ghost)
	Game.npcs.append(ghost)
	ghost.queue_free()
	await process_frame
	_check(not is_instance_valid(ghost), "ghost-узел действительно освобождён")

	# 3. Реальный вызов по живому пути: npc -> _move_checked -> movement_direction
	#    -> _sep_rebuild_grid -> _sep_insert. До правки падало здесь.
	#    Сетка separation кешируется на кадр физики — сбрасываем, иначе
	#    _sep_rebuild_grid вернётся раньше и до ghost не дойдёт.
	Game._sep_grid_frame = -1
	Game.movement_direction(hero, Vector2.RIGHT)
	_check(true, "movement_direction пережил освобождённый узел (до правки был SCRIPT ERROR)")

	# 4. Тот же вызов, но через _sep_rebuild_grid напрямую — он и был в стектресе.
	Game._sep_grid_frame = -1
	Game._sep_rebuild_grid()
	_check(true, "_sep_rebuild_grid пережил освобождённый узел")

	# 5. Убираем ghost и проверяем, что событие смены сцены чистит статику.
	#    Сами NPC в массивах законны (их наспавнил генератор), нужны только
	#    живые.
	Game.npcs.erase(ghost)
	_check(_dead_count() == 0,
		"после ручной чистки в массивах снова нет битых узлов (%d)" % _dead_count())

	# 6. ГЛАВНАЯ ПРОВЕРКА: вторая загрузка сцены. Именно её делает игрок,
	#    когда берёт другую расу. Узлы прежней карты к этому моменту уже
	#    освобождены движком, но остаются в статических массивах — если
	#    Main._ready() их не чистит. Первая загрузка этого НЕ показывает:
	#    старой сцены не было.
	var npcs_before := Game.npcs.size()
	await process_frame
	var err2 := change_scene_to_file("res://scenes/main.tscn")
	_check(err2 == OK, "повторная загрузка main.tscn (смена расы/новой игры)")
	await process_frame
	await create_timer(0.5).timeout
	_check(_dead_count() == 0,
		"после ВТОРОЙ загрузки в массивах нет освобождённых узлов (%d)"
			% _dead_count())
	# И они реально присутствуют: если бы массив был просто пуст, проверка
	# выше прошла бы вхолостую.
	_check(Game.npcs.size() > 0,
		"новая сцена наспавнила NPC (до: %d, после: %d)" % [npcs_before, Game.npcs.size()])

	_finish()


func _dead_count() -> int:
	# Game - class_name со static var, а не autoload: обращаться надо
	# напрямую (Game.get() на классе - ошибка парсинга).
	var dead := 0
	for arr in [Game.enemies, Game.npcs, Game.party]:
		for x in arr:
			if not is_instance_valid(x):
				dead += 1
	return dead


func _finish() -> void:
	print("RESULT: %s stale_units_smoke (проверок: %d, провалов: %d)"
		% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)