extends SceneTree
##
## Смок динамических событий (19.10): спавн стычки, foe-цель, абстрактное
## разрешение боя, TTL-деспавн, чистка тегов, маркер в реестре.
## Запуск: godot --headless --path . --script res://tests/events_smoke.gd
## Результат: RESULT: OK events_smoke
##
## Страховка от зависания: таймер 120 с принудительно закрывает прогон
## с FAIL — иначе скрипт без quit() держит main loop вечно.

var _checks := 0
var _fails: Array[String] = []
var _done := false


func _init() -> void:
	var watchdog := create_timer(120.0)
	watchdog.timeout.connect(_force_quit)
	call_deferred("_run")


func _force_quit() -> void:
	if _done:
		return
	_done = true
	print("  FAIL тест не завершился за 120 с — принудительный выход")
	print("RESULT: FAIL events_smoke (таймаут)")
	quit(1)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _species_of(set_name: String) -> String:
	var idx := set_name.rfind("_t")
	if idx > 0:
		var tail := set_name.substr(idx + 2)
		var digits := true
		for ch in tail:
			if not (ch >= "0" and ch <= "9"):
				digits = false
				break
		if digits:
			return set_name.substr(0, idx)
	return set_name


func _tagged_count() -> int:
	var n := 0
	for e in Game.enemies:
		if e is Enemy and is_instance_valid(e) and str(e.event_tag) != "":
			n += 1
	return n


func _run() -> void:
	print("-- events_smoke --")
	# Карта нужна для is_walkable_world: настоящая сгенерированная карта.
	var map: Node = load("res://scripts/alm_map.gd").new()
	map.alm_path = "res://assets/maps/gen/gen_smart_01.alm"
	root.add_child(map)
	_check(int(map.get("map_width")) > 0, "карта загрузилась")
	# Реестр маркеров
	if MinimapMarkers.instance == null:
		MinimapMarkers.new()
	_check(MinimapMarkers.instance != null, "реестр маркеров живёт")
	# Система событий
	var es: EventSystem = load("res://scripts/event_system.gd").new()
	root.add_child(es)
	Game.map_seed = 12345
	Game.map_zone = "start"
	# Пара наборов — тем же селектором, что и в живом спавне.
	var pool: Array = MapGenerator.gray_pool_for_zone("start")
	_check(pool.size() >= 2, "пул Серых зоны start >= 2 наборов")
	var pair: Array = es._pick_event_sets(pool)
	var pa := "?" if pair.size() < 1 else str(pair[0])
	var pb := "?" if pair.size() < 2 else str(pair[1])
	_check(pair.size() == 2, "пара наборов выбрана (%s / %s)" % [pa, pb])
	if pair.size() < 2:
		_report()
		return
	var set_a := str(pair[0])
	var set_b := str(pair[1])
	_check(_species_of(set_a) != _species_of(set_b),
		"разные виды в паре (%s против %s)" % [_species_of(set_a), _species_of(set_b)])
	var cell := Vector2i(int(map.get("map_width")) / 2, int(map.get("map_height")) / 2)
	var id := es.debug_spawn_event_at(cell, set_a, set_b)
	_check(id > 0, "событие заспавнилось (id=%d)" % id)
	if id <= 0:
		_report()
		return
	_check(es.event_count() == 1, "одно активное событие")
	_check(MinimapMarkers.instance.item_count() == 1, "маркер боя в реестре")
	# Участники и foe-цель
	var members: Array = []
	for e in Game.enemies:
		if e is Enemy and is_instance_valid(e) and str(e.event_tag) != "":
			members.append(e)
	_check(members.size() >= 2, "участники стычки заспавнились (%d)" % members.size())
	if members.size() < 2:
		_report()
		return
	var a0: Enemy = members[0]
	var foe: Node2D = es.foe_for(a0)
	_check(foe != null, "цель-противник найдена")
	_check(foe != null and (foe as Enemy).event_tag != a0.event_tag,
		"противник из противоположной группы")
	# Абстрактное разрешение боя (туман не создан → считаем «не видно»).
	for i in range(300):
		es._abstract_tick()
		if es.event_count() == 0:
			break
	_check(es.event_count() == 0, "стычка разрешилась абстрактными обменами")
	_check(MinimapMarkers.instance.item_count() == 0, "маркер снят после боя")
	_check(_tagged_count() == 0, "выжившие вышли из стычки (теги сняты)")
	# TTL-деспавн
	var id2 := es.debug_spawn_event_at(cell, set_a, set_b)
	_check(id2 > 0, "второе событие заспавнилось")
	es.debug_expire_all()
	_check(es.event_count() == 0, "TTL-истечение чистит события")
	_check(MinimapMarkers.instance.item_count() == 0, "маркер снят после TTL")
	_report()


func _report() -> void:
	_done = true
	print("RESULT: %s events_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)
