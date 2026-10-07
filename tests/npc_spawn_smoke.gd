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

	for key in ["ork_mage_a52/t0", "ork_mage_a52/t1", "ork_mage_a52/t2", "ork_mage_a52/t3"]:
		_check(units.has(key), "набор %s есть в units_db" % key)

	# POI выключены (решение игрока 07.10: арта мало, interest_points=0).
	var kinds := {}
	var code_kinds := _code_poi_sets()
	_check(code_kinds.is_empty(),
		"POI_KINDS в коде пуст (аллодовские humans/* убраны, POI off)")
	_check(kinds.size() == code_kinds.size(),
		"тест и код согласованы по POI (0 == 0)")

	print("-- выключено по умолчанию --")
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		_check(false, "game.cfg грузится (err=%d)" % err)
		_finish()
		return
	_check(true, "game.cfg грузится")

	# Все зоны: interest_points = 0 (пока арта мало).
	var want_poi := {"start": 0, "mid": 0, "hard": 0, "faction": 0}

	for zone in ZONES:
		var n := int(cfg.get_value("zone", "%s.interest_points" % zone, -999))
		_check(n == int(want_poi.get(zone, 0)),
			"interest_points в зоне %s = %d (ожидалось 0)" % [zone, n])
		_check(int(cfg.get_value("zone", "%s.poi_hp" % zone, 0)) > 0,
			"у зоны %s заданы статы NPC точки (poi_hp)" % zone)
		_check(int(cfg.get_value("zone", "%s.poi_damage" % zone, -1)) >= 0,
			"у зоны %s задан урон NPC точки (poi_damage)" % zone)

	print("-- городские NPC — ork_mage_a52, без humans --")
	if not FileAccess.file_exists(MAP_NPCS):
		print("  (карта %s отсутствует — проверка пропущена)" % MAP_NPCS)
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_NPCS))
		var npcs: Array = []
		if parsed is Dictionary:
			npcs = (parsed as Dictionary).get("npcs", [])
		var poi := 0
		var city_sets := {}
		var humans_left := 0
		var guards := 0
		var citizens := 0
		for n3 in npcs:
			var d3: Dictionary = n3
			if d3.has("poi"):
				poi += 1
			var role := str(d3.get("role", ""))
			var setn := str(d3.get("set", ""))
			if role == "guard" or role == "citizen":
				city_sets[setn] = true
				if role == "guard":
					guards += 1
				else:
					citizens += 1
				if setn.begins_with("humans/"):
					humans_left += 1
		_check(poi == 0, "на карте нет POI (найдено: %d)" % poi)
		_check(city_sets.size() > 0, "городские NPC на карте есть (наборов: %d)" % city_sets.size())
		_check(humans_left == 0,
			"аллодовские humans/* в городе не спавнятся (найдено: %d)" % humans_left)
		for setn2 in city_sets:
			_check(str(setn2).begins_with("ork_mage_a52/"),
				"городской набор %s — ork_mage_a52" % setn2)
			_check(units.has(str(setn2)), "набор %s существует в units_db" % setn2)
		_check(guards > 0, "на карте есть стражи (%d)" % guards)
		_check(citizens > 0, "на карте есть жители (%d)" % citizens)

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
			gray_regions["%d,%d" % [int(d.get("x", 0)) * 3 / 192,
				int(d.get("y", 0)) * 3 / 192]] = true
		_check(gray_n > 0, "Серые на карте есть (%d)" % gray_n)
		_check(gray_cells.size() == gray_n,
			"на каждой клетке ровно один Серый (клеток: %d, Серых: %d) — было 6 клеток на 15"
				% [gray_cells.size(), gray_n])
		_check(gray_regions.size() >= 4,
			"Серые разведены по карте (регионов 3x3: %d из 9) — было 2" % gray_regions.size())

	_finish()


## Читает POI_KINDS прямо из исходника генератора: тест должен проверять
## ИМЕННО то, что напишет игрок в коде, а не свою копию списка.
## 07.10: ENCOUNTER_KINDS (боевые ульи/логова) — ОТДЕЛЬНАЯ система, не POI.
## POI — статичные точки без боя; их список по-прежнему пуст.
func _code_poi_sets() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists("res://scripts/world/map_generator.gd"):
		return out
	var text := FileAccess.get_file_as_string("res://scripts/world/map_generator.gd")
	# Берём только блок POI_KINDS := [...], не ENCOUNTER_KINDS
	var poi_start := text.find("POI_KINDS")
	if poi_start < 0:
		return out
	var poi_end := text.find("\n]", poi_start)
	if poi_end < 0:
		poi_end = poi_start + 400
	var block := text.substr(poi_start, poi_end - poi_start)
	if block.find("[]") >= 0 or block.find("{ }") >= 0:
		return out
	for line in block.split("\n"):
		if not line.contains("\"kind\":"):
			continue
		var kind := _extract(line, "\"kind\": \"", "\"")
		if kind == "":
			continue
		out[kind] = ["(poi)"]
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
