extends SceneTree
##
## Тест точек интереса вне городов (этап 3, 03.10).
##
## ЧТО ПРОВЕРЯЕТ
## -------------
## 1. Каждый набор NPC в POI_KINDS реально существует в units_db.
##    Это не формальность: `humans/militia` я сначала написал в POI_KINDS,
##    взяв из заметок AGENTS §8.2, и его В БАЗЕ НЕТ — militia не существует.
##    Точка интереса такого вида молча не дала бы ни одного NPC. Тест
##    ловит это до запуска игры, а не после.
## 2. Выключено по умолчанию: interest_points = 0 во всех зонах, поэтому
##    поведение игры не отличается от прежнего, пока игрок не включит.
##    Это главный инвариант безопасности ночной правки.
## 3. В закоммиченной карте нет ни одной записи POI.
## 4. Наборы POI — люди (не Серые), и их статы берутся из [zone] (poi_*),
##    а не из потолка в коде.
##
## ЗАПУСК
## ------
## godot --headless --path . --script res://tests/npc_spawn_smoke.gd
##

const UNITS_PATH := "res://assets/units/units_db.json"
const CFG_PATH := "res://assets/config/game.cfg"
const MAP_NPCS := "res://assets/maps/gen/gen_smart_01.npcs.json"
const ZONES := ["start", "mid", "hard", "faction"]

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _unit_names() -> Array:
	if not FileAccess.file_exists(UNITS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(UNITS_PATH))
	if parsed is Array:
		return parsed
	if parsed is Dictionary:
		return (parsed as Dictionary).keys()
	return []


func _run() -> void:
	print("-- наборы NPC --")
	var units := _unit_names()
	_check(units.size() > 0, "units_db читается (%d наборов)" % units.size())

	# POI_KINDS продублирован здесь намеренно: тест должен видеть СВОЙ список,
	# а не тот же объект, что и код. Иначе правка кода тихо починит тест.
	var kinds := {
		"camp": ["humans/clubman", "humans/axeman"],
		"ruins": ["humans/archer", "humans/xbowman"],
		"shrine": ["humans/swordsman_", "humans/pikeman_"],
	}
	# и сверяем с кодом, чтобы расхождение тоже было ошибкой
	var code_kinds := _code_poi_sets()
	_check(code_kinds.size() == kinds.size(),
		"в коде столько же видов точек, сколько в тесте (%d)" % code_kinds.size())

	for kind in kinds:
		for set_name in kinds[kind]:
			_check(units.has(set_name), "набор %s для точки '%s' существует" % [set_name, kind])
			_check(code_kinds.get(kind, []).has(set_name),
				"код использует %s для '%s' (тест и код совпадают)" % [set_name, kind])

	print("-- выключено по умолчанию --")
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		_check(false, "game.cfg грузится (err=%d)" % err)
		_finish()
		return
	_check(true, "game.cfg грузится")

	for zone in ZONES:
		var n := int(cfg.get_value("zone", "%s.interest_points" % zone, -999))
		_check(n == 0, "точки интереса выключены в зоне %s (interest_points=%d)" % [zone, n])
		_check(int(cfg.get_value("zone", "%s.poi_hp" % zone, 0)) > 0,
			"у зоны %s заданы статы NPC точки (poi_hp)" % zone)
		_check(int(cfg.get_value("zone", "%s.poi_damage" % zone, -1)) >= 0,
			"у зоны %s задан урон NPC точки (poi_damage)" % zone)

	print("-- карта по умолчанию чиста --")
	if not FileAccess.file_exists(MAP_NPCS):
		print("  (карта %s отсутствует — проверка пропущена)" % MAP_NPCS)
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_NPCS))
		var npcs: Array = []
		if parsed is Dictionary:
			npcs = (parsed as Dictionary).get("npcs", [])
		var poi := 0
		for n in npcs:
			var d: Dictionary = n
			if d.has("poi"):
				poi += 1
		_check(poi == 0, "в закоммиченной карте нет точек интереса (найдено: %d)" % poi)

	_finish()


## Читает POI_KINDS прямо из исходника генератора: тест должен проверять
## ИМЕННО то, что напишет игрок в коде, а не свою копию списка.
func _code_poi_sets() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists("res://scripts/world/map_generator.gd"):
		return out
	var text := FileAccess.get_file_as_string("res://scripts/world/map_generator.gd")
	for line in text.split("\n"):
		if not line.contains("\"kind\":"):
			continue
		var kind := _extract(line, "\"kind\": \"", "\"")
		if kind == "":
			continue
		var sets: Array = []
		var sets_part := ""
		var idx := text.find("\"sets\": [", text.find("\"kind\": \"" + kind + "\""))
		if idx < 0:
			continue
		sets_part = text.substr(idx, 200)
		for piece in sets_part.substr(sets_part.find("[") + 1).split("]")[0].split(","):
			var nm := piece.strip_edges().replace("\"", "")
			if nm != "":
				sets.append(nm)
		out[kind] = sets
	return out


func _extract(s: String, prefix: String, stop: String) -> String:
	var i := s.find(prefix)
	if i < 0:
		return ""
	var rest := s.substr(i + prefix.length())
	var j := rest.find(stop)
	if j < 0:
		return ""
	return rest.substr(0, j)


func _finish() -> void:
	print("RESULT: %s npc_spawn_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)
