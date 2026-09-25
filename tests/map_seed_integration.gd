extends SceneTree
## Интеграционная проверка выбора карты в игре (scripts/alm_map.gd:_resolve_map_path).
##
## Покрывает то, чего не покрывает gen_seeds_smoke: не генерацию как таковую, а
## проводку «запросили сид → игра грузит именно эту карту».
##
##   1. map_seed != 0  → грузится карта из user://maps/, сгенерированная по сиду;
##   2. два разных сида → в игре грузятся РАЗНЫЕ карты (то, ради чего всё затевалось);
##   3. повторный запуск с тем же сидом → та же карта (продолжение сохранения даст тот же мир);
##   4. map_seed == 0 и нет запроса → запасной путь из main.tscn (dev-режим, автотесты);
##   5. явно запрошенный путь (редактор карт) имеет приоритет над сидом.
##
## Запуск: godot --headless --path . --script res://tests/map_seed_integration.gd

const SEED_A := 1001
const SEED_B := 2002
const FALLBACK_PATH := "res://assets/maps/gen/gen_smart_01.alm"

var _fails: Array[String] = []

func _initialize() -> void:
	# Как в spawn_smoke: подставляем героя, иначе main.tscn уходит в character_select.
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Герой"
	call_deferred("_run")

func _run() -> void:
	# --- 1. Карта по сиду A ---
	Game.request_map_by_seed(SEED_A, "mid")
	var a: Dictionary = await _load_world()
	_check(a.get("loaded", false), "[A] мир загрузился по сиду %d" % SEED_A)
	_check(str(a.get("path", "")).begins_with("user://maps/"), "[A] путь ведёт в user://maps/ (%s)" % str(a.get("path", "")))
	_check(a.get("width", 0) == 128 and a.get("height", 0) == 128, "[A] размер 128x128")
	_check(int(a.get("units", 0)) > 0, "[A] на карте есть юниты (%d)" % int(a.get("units", 0)))
	_check(int(a.get("structures", 0)) > 0, "[A] на карте есть здания (%d)" % int(a.get("structures", 0)))
	var path_a: String = str(a.get("path", ""))

	# --- 2. Другой сид → другая карта в игре ---
	Game.request_map_by_seed(SEED_B, "mid")
	var b: Dictionary = await _load_world()
	_check(b.get("loaded", false), "[B] мир загрузился по сиду %d" % SEED_B)
	var path_b: String = str(b.get("path", ""))
	_check(path_b != path_a, "[A/B] в игре грузятся разные карты (%s vs %s)" % [path_a.get_file(), path_b.get_file()])
	_check(_tiles_differ(path_a, path_b), "[A/B] содержимое карт различается")

	# --- 3. Тот же сид → та же карта (продолжение сохранения) ---
	Game.request_map_by_seed(SEED_A, "mid")
	var a2: Dictionary = await _load_world()
	_check(str(a2.get("path", "")) == path_a, "[A2] тот же сид → тот же путь")
	_check(_tiles_differ(path_a, str(a2.get("path", ""))) == false, "[A2] карта не перегенерировалась")

	# --- 4. Без запроса — запасной путь из main.tscn ---
	Game.request_map_by_path("")
	Game.map_seed = 0
	var d: Dictionary = await _load_world()
	_check(str(d.get("path", "")) == FALLBACK_PATH, "[dev] без сида грузится запасной путь из main.tscn (%s)" % str(d.get("path", "")))

	# --- 5. Явно запрошенный путь важнее сида (редактор карт) ---
	Game.request_map_by_seed(SEED_A, "mid")
	Game.request_map_by_path(FALLBACK_PATH)
	var e: Dictionary = await _load_world()
	_check(str(e.get("path", "")) == FALLBACK_PATH, "[editor] явный путь имеет приоритет над сидом")
	_check(Game.map_seed == 0, "[editor] явный путь сбрасывает сид")

	_report()

## Загрузить main.tscn и снять состояние карты.
func _load_world() -> Dictionary:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		return {"loaded": false, "path": "", "width": 0, "height": 0, "units": 0, "structures": 0}
	await process_frame
	await create_timer(0.4).timeout
	var am = get_first_node_in_group("alm_map")
	if am == null:
		return {"loaded": false, "path": "", "width": 0, "height": 0, "units": 0, "structures": 0}
	return {
		"loaded": int(am.get("map_width")) > 0,
		"path": str(am.get("alm_path")),
		"width": int(am.get("map_width")),
		"height": int(am.get("map_height")),
		"units": am.call("get_units").size(),
		"structures": int(am.get("_structures").size()) if am.get("_structures") != null else 0,
	}

## Секция tiles в .alm различается? (смещение 680 = info, дальше tiles по 2 байта)
func _tiles_differ(p1: String, p2: String) -> bool:
	if not FileAccess.file_exists(p1) or not FileAccess.file_exists(p2):
		return false
	var f1 := FileAccess.open(p1, FileAccess.READ)
	var f2 := FileAccess.open(p2, FileAccess.READ)
	if f1 == null or f2 == null:
		return false
	f1.seek(700)
	f2.seek(700)
	var b1 := f1.get_buffer(512)
	var b2 := f2.get_buffer(512)
	f1.close()
	f2.close()
	return b1 != b2

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK map_seed_integration")
		quit(0)
	else:
		print("RESULT: FAIL map_seed_integration (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
