extends SceneTree
## Бюджет ИИ в городе (29.10): сторож против возврата перебора «все против всех».
##
## ЧТО БЫЛО. `Npc._nearest_enemy` считал точный хит-бокс (`Game.units_range`)
## для КАЖДОГО врага карты (на mid ~160), каждый кадр, у каждого стражника.
## 9 стражей × 160 = ~1440 тяжёлых расчётов в кадр; замер `city_perf_probe`
## показывал 160 мс только на этом скане и 5 FPS в городе.
##
## ЧТО ПРОВЕРЯЕТСЯ. Не миллисекунды (они плавают от машины), а СЧЁТЧИКИ:
## сколько раз за кадр зовётся `units_range` и скан цели стражей. Если кто-то
## снова начнёт перебирать всех врагов без отсечения по расстоянию, счётчик
## вырастет на порядок и тест упадёт.
##
## Запуск: godot --headless --path . --script res://tests/city_ai_budget_smoke.gd

const SEED := 9001
const TILE := 32
## Порог с запасом: было ~1440 вызовов/кадр, стало ~30-90 (зависит от того,
## сколько врагов реально рядом с городом на этом сиде).
const MAX_UNITS_RANGE_PER_FRAME := 300
const MAX_GUARD_SCANS_PER_FRAME := 60

var _fails: Array[String] = []


func _initialize() -> void:
	Game.hero_stats = {"strength": 20, "dexterity": 20, "intelligence": 10,
		"vitality": 20, "spirit": 10, "luck": 5}
	Game.hero_class = "warrior"
	Game.hero_gender = "male"
	Game.hero_name = "Страж бюджета"
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
		_fail("main.tscn не открылась")
		_report()
		return
	await create_timer(1.5).timeout
	var game = current_scene
	var am = get_first_node_in_group("alm_map")
	var player = game.get("player") if game != null else null
	if am == null or player == null:
		_fail("нет карты или героя")
		_report()
		return
	var city := _first_city_cell(am)
	if city == Vector2i(-1, -1):
		_fail("на карте нет города")
		_report()
		return
	player.global_position = Vector2(city.x * TILE + TILE / 2.0, city.y * TILE + TILE / 2.0)
	player.stop_movement()
	await create_timer(1.0).timeout

	# Чистый замер: только включённый профилировщик и один интервал < 2 с,
	# чтобы perf_frame не успел напечатать и обнулить счётчики.
	Game.perf_usec.clear()
	Game.perf_calls.clear()
	Game.perf_frames = 0
	Game.perf_enabled = true
	await create_timer(1.0).timeout
	Game.perf_enabled = false
	var frames := maxi(1, Game.perf_frames)
	var ranges := float(int(Game.perf_calls.get("units_range_calls", 0))) / float(frames)
	var scans := float(int(Game.perf_calls.get("npc_target_scan_n", 0))) / float(frames)
	_check(frames >= 20, "кадров в замере достаточно (%d)" % frames)
	_check(ranges <= float(MAX_UNITS_RANGE_PER_FRAME),
		"units_range в кадр: %.0f (порог %d)" % [ranges, MAX_UNITS_RANGE_PER_FRAME])
	_check(scans <= float(MAX_GUARD_SCANS_PER_FRAME),
		"скан цели стражей в кадр: %.0f (порог %d)" % [scans, MAX_GUARD_SCANS_PER_FRAME])
	# Причина жива: стража в городе действительно тикает, а не «спит вся».
	_check(_awake_guards(Game.npcs) > 0, "в городе есть тикающая стража (%d)"
		% _awake_guards(Game.npcs))
	# Отсечение не ослепило стражу: враг вплотную обязан быть найден.
	await _check_guard_sees_enemy()
	_report()


## Регрессия отсечения: стражник с врагом в 40 px обязан видеть этого врага.
func _check_guard_sees_enemy() -> void:
	var guard: Node2D = null
	for n in Game.npcs:
		if n != null and is_instance_valid(n) and str(n.get("role")) == "guard" \
				and n.is_physics_processing():
			guard = n
			break
	var foe: Node2D = null
	for e in Game.enemies:
		if e != null and is_instance_valid(e):
			foe = e
			break
	if guard == null or foe == null:
		_check(false, "нет пары страж/враг для проверки отсечения")
		return
	var saved := foe.global_position
	foe.global_position = guard.global_position + Vector2(40, 0)
	await physics_frame
	var found: Node2D = guard.call("_nearest_enemy")
	_check(found == foe, "стражник видит врага в 40 px (нашёл: %s)"
		% ("того же" if found == foe else str(found)))
	foe.global_position = saved


func _awake_guards(units: Array) -> int:
	var n := 0
	for u in units:
		if u != null and is_instance_valid(u) and str(u.get("role")) == "guard" \
				and u.is_physics_processing():
			n += 1
	return n


func _first_city_cell(am) -> Vector2i:
	var heads: Dictionary = am.call("city_heads")
	for cid in heads:
		var cells: Array = (heads[cid] as Dictionary).get("cells", [])
		if not cells.is_empty():
			var pair: Array = cells[0]
			return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i(-1, -1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _fail(label: String) -> void:
	print("FAIL ", label)
	_fails.append(label)


func _report() -> void:
	Game.perf_enabled = false
	print("---")
	if _fails.is_empty():
		print("RESULT: OK city_ai_budget_smoke")
		quit(0)
	else:
		print("RESULT: FAIL city_ai_budget_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
