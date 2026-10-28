extends SceneTree
## Замер кадра в городе и в поле (29.10, разбор «в городе 6 FPS»).
##
## Это ИНСТРУМЕНТ, а не сторож: он ничего не проверяет, а печатает таблицу
## Game.perf_* (мс на кадр по блокам). Нужен, чтобы не гадать, кто ест кадр.
##
## Что делает: поднимает настоящую игру на карте mid, ставит героя в центр
## первого города, 4 секунды печатает профиль, затем переносит его на спавн
## (поле) и печатает второй профиль. Разница «город / поле» — цена городского
## ИИ, потому что рендер в замере не участвует (headless).
##
## Запуск:
##   godot --headless --path . --script res://tests/city_perf_probe.gd

const SEED := 9001
const TILE := 32
const MEASURE_SECONDS := 4.2

var _game: Node = null


func _initialize() -> void:
	Game.hero_stats = {"strength": 20, "dexterity": 20, "intelligence": 10,
		"vitality": 20, "spirit": 10, "luck": 5}
	Game.hero_class = "warrior"
	Game.hero_gender = "male"
	Game.hero_name = "Профилировщик"
	Game.hero_character_id = "human_m_war"
	Game.map_seed = SEED
	Game.map_zone = "mid"
	Game.map_sector = "s00"
	Game.loaded_slot = ""
	Game.pending_map_path = ""
	call_deferred("_run")


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		print("RESULT: FAIL — main.tscn не открылась")
		quit(1)
		return
	await create_timer(1.5).timeout
	_game = current_scene
	if _game == null:
		print("RESULT: FAIL — сцена не создалась")
		quit(1)
		return
	var am = get_first_node_in_group("alm_map")
	if am == null:
		print("RESULT: FAIL — нет alm_map")
		quit(1)
		return
	var player = _game.get("player")
	if player == null:
		print("RESULT: FAIL — нет героя")
		quit(1)
		return
	print("юнитов: врагов=%d, НПЦ=%d, чанков=%d" % [
		Game.enemies.size(), Game.npcs.size(), int(am.get("_blend_chunks").size())])
	var city := _first_city_cell(am)
	if city == Vector2i(-1, -1):
		print("RESULT: FAIL — на карте нет города")
		quit(1)
		return
	_teleport(player, city)
	await create_timer(0.6).timeout
	_bench_units(player)
	print("=== ГОРОД (%s), врагов рядом: %d, НПЦ рядом: %d ===" % [
		str(city), _near(Game.enemies, player, 700.0), _near(Game.npcs, player, 700.0)])
	Game.perf_enabled = true
	await create_timer(MEASURE_SECONDS).timeout
	Game.perf_enabled = false

	var spawn_cell: Vector2i = am.call("get_spawn_cell")
	_teleport(player, spawn_cell)
	await create_timer(0.8).timeout
	print("=== ПОЛЕ (%s), врагов рядом: %d, НПЦ рядом: %d ===" % [
		str(spawn_cell), _near(Game.enemies, player, 700.0), _near(Game.npcs, player, 700.0)])
	Game.perf_enabled = true
	await create_timer(MEASURE_SECONDS).timeout
	Game.perf_enabled = false
	print("RESULT: DONE city_perf_probe")
	quit(0)


func _first_city_cell(am) -> Vector2i:
	var heads: Dictionary = am.call("city_heads")
	for cid in heads:
		var cells: Array = (heads[cid] as Dictionary).get("cells", [])
		if not cells.is_empty():
			var pair: Array = cells[0]
			return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i(-1, -1)


func _teleport(player, cell: Vector2i) -> void:
	player.global_position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
	player.stop_movement()
	player.reset_physics_interpolation()
	if Game.fog != null:
		Game.fog.call("reveal_around", cell)


## Микрозамер: сколько реально стоит один вызов units_range и его части.
func _bench_units(player) -> void:
	var guard: Node2D = null
	for n in Game.npcs:
		if n != null and is_instance_valid(n) and str(n.get("role")) == "guard":
			guard = n
			break
	var foe: Node2D = null
	for e in Game.enemies:
		if e != null and is_instance_valid(e):
			foe = e
			break
	if guard == null or foe == null:
		print("BENCH: нет пары страж/враг")
		return
	var n := 2000
	var t0 := Time.get_ticks_usec()
	for _i in n:
		Game.units_range(guard, foe)
	var t1 := Time.get_ticks_usec()
	for _i in n:
		Game.unit_hit_rect(guard)
	var t2 := Time.get_ticks_usec()
	for _i in n:
		Game.unit_body_rect(guard)
	var t3 := Time.get_ticks_usec()
	print("BENCH: units_range=%.1f мкс, unit_hit_rect=%.1f мкс, unit_body_rect=%.1f мкс" % [
		float(t1 - t0) / n, float(t2 - t1) / n, float(t3 - t2) / n])
	# Сколько стражей реально тикает и сколько врагов они перебирают
	var guards := 0
	for n2 in Game.npcs:
		if n2 != null and is_instance_valid(n2) and str(n2.get("role")) == "guard" \
				and n2.is_physics_processing():
			guards += 1
	print("BENCH: тикающих стражей=%d, врагов в списке=%d -> вызовов %.0f/кадр" % [
		guards, Game.enemies.size(), float(guards) * float(Game.enemies.size())])


func _near(units: Array, player, radius: float) -> int:
	var n := 0
	var r2 := radius * radius
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		if (u as Node2D).global_position.distance_squared_to(player.global_position) <= r2:
			n += 1
	return n
