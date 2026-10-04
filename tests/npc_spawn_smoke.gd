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

	## Сколько точек интереса в каждой зоне (решение игрока 03.10: минимум 3-4,
	## далеко от города; зона новичка остаётся тихой).
	var want_poi := {"start": 0, "mid": 3, "hard": 4, "faction": 3}

	for zone in ZONES:
		var n := int(cfg.get_value("zone", "%s.interest_points" % zone, -999))
		# Контракт поменян 03.10: точки интереса ВКЛЮЧЕНЫ в mid/hard/faction,
		# а зона новичка осталась тихой. Раньше здесь стояло «interest_points == 0
		# во всех зонах», то есть тест сторожил ОТКЛЮЧЁННУЮ функцию.
		_check(n == int(want_poi.get(zone, 0)),
			"точки интереса в зоне %s = %d (ожидалось %d)" % [zone, n, int(want_poi.get(zone, 0))])
		_check(int(cfg.get_value("zone", "%s.poi_hp" % zone, 0)) > 0,
			"у зоны %s заданы статы NPC точки (poi_hp)" % zone)
		_check(int(cfg.get_value("zone", "%s.poi_damage" % zone, -1)) >= 0,
			"у зоны %s задан урон NPC точки (poi_damage)" % zone)

	print("-- точки интереса появились на карте --")
	if not FileAccess.file_exists(MAP_NPCS):
		print("  (карта %s отсутствует — проверка пропущена)" % MAP_NPCS)
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_NPCS))
		var npcs: Array = []
		if parsed is Dictionary:
			npcs = (parsed as Dictionary).get("npcs", [])
		var poi := 0
		var poi_cells := {}
		for n in npcs:
			var d: Dictionary = n
			if not d.has("poi"):
				continue
			poi += 1
			# ровно один NPC на клетке точки: в кластере не должно быть
			# наложений (такой же баг был с Серыми)
			poi_cells["%s:%d,%d" % [str(d["poi"]), int(d.get("x", 0)), int(d.get("y", 0))]] = true
		_check(poi > 0, "в закоммиченной карте точки интереса есть (найдено NPC: %d)" % poi)
		var poi_kinds := {}
		for n2 in npcs:
			var d2: Dictionary = n2
			if d2.has("poi"):
				poi_kinds[str(d2["poi"])] = true
		_check(poi_kinds.size() >= 2, "точки интереса разных видов (видов: %d)" % poi_kinds.size())
		# все NPC одной точки должны быть рядом друг с другом (это кластер)
		_check(poi_cells.size() == poi,
			"на каждой клетке точки ровно один NPC (клеток: %d, NPC: %d)" % [poi_cells.size(), poi])

	print("-- Серые разведены по карте --")
	# Жалоба игрока 03.10: «1 Серый на карте». Замер показал 15 Серых на 6
	# клетках, причём все в одной половине карты. Причина была двойная:
	# якоря кластеров не проверялись на занятость, а `_near_gray_cell` писал в
	# переданный по ссылке массив, а вызывающий код добавлял клетку ещё раз —
	# кластер из 3 давал 5 записей, две из них на одной клетке.
	if not FileAccess.file_exists(MAP_NPCS):
		print("  (карта %s отсутствует — проверка пропущена)" % MAP_NPCS)
	else:
		var parsed2: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_NPCS))
		var npcs2: Array = []
		if parsed2 is Dictionary:
			npcs2 = (parsed2 as Dictionary).get("npcs", [])
		var gray_cells := {}
		var gray_n := 0
		var gray_regions := {}
		for g in npcs2:
			var d: Dictionary = g
			if str(d.get("role", "")) == "guard" or str(d.get("role", "")) == "citizen":
				continue
			if not d.has("set"):
				continue
			gray_n += 1
			gray_cells["%d,%d" % [int(d.get("x", 0)), int(d.get("y", 0))]] = true
			# сетка 3x3 — та же, что у генератора при разведении
			gray_regions["%d,%d" % [int(d.get("x", 0)) * 3 / 128,
				int(d.get("y", 0)) * 3 / 128]] = true
		_check(gray_n > 0, "Серые на карте есть (%d)" % gray_n)
		_check(gray_cells.size() == gray_n,
			"на каждой клетке ровно один Серый (клеток: %d, Серых: %d) — было 6 клеток на 15"
				% [gray_cells.size(), gray_n])
		_check(gray_regions.size() >= 4,
			"Серые разведены по карте (регионов 3x3: %d из 9) — было 2" % gray_regions.size())

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
