extends SceneTree
## Форпосты фракций и бирки (пакет B переработки ковки, 28.10).
##
## Проверяет ровно то, что нельзя увидеть глазами в коде:
##   1. бирки четырёх фракций есть в базе, с существующими иконками;
##   2. генератор ставит по ТРИ форпоста (кроме стартовой зоны, где их нет),
##      детерминированно, на проходимой земле и врозь от городов/спавна;
##   3. стража каждого лагеря — своя фракция, наборы из units_db, тир по зоне;
##   4. стража не стоит внутри постройки и не делит клетку;
##   5. бирка падает со стражника всегда;
##   6. захват: последний стражник зачищает лагерь, флаг переживает
##      сохранение (pending) и привязан к карте (зона/сектор/сид).
##
## Запуск: godot --headless --path . --script res://tests/outpost_smoke.gd

const DIR := "user://maps/"
const DIR_DET := "user://maps/_outpost_det/"
const Sandbox := preload("res://tests/save_sandbox.gd")
const SEED_MID := 9001
const SEED_HARD := 9003
const SEED_FACTION := 9004
const SEED_START := 9002
const RACES := ["humans", "ork", "necro", "druid"]

var _fails: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	DirAccess.make_dir_recursive_absolute(DIR_DET)
	_run.call_deferred()


func _run() -> void:
	_check_tags()
	_check_generation()
	_check_capture()
	await _check_live_game()
	_report()


# --- 1. Бирки -------------------------------------------------------------

func _check_tags() -> void:
	for race in RACES:
		var key := ItemDB.tag_key(race)
		_check(key != "", "бирка есть для %s (%s)" % [race, key])
		var it := ItemDB.find(key)
		_check(not it.is_empty(), "запись бирки %s найдена" % key)
		_check(ItemDB.is_tag(it), "бирка %s опознаётся как Trophy" % key)
		var icon := str(it.get("icon", ""))
		_check(icon != "" and ResourceLoader.exists(icon), "иконка бирки %s существует" % key)
		_check(not ItemDB.is_equippable(it), "бирка %s не надевается" % key)
	_check(ItemDB.tag_key("orc") == "", "неизвестная раса не даёт бирку (ork, не orc)")


# --- 2. Генерация ---------------------------------------------------------

func _check_generation() -> void:
	var start_path := MapGenerator.new().generate(SEED_START, "start", DIR, "op_start")
	var mid_path := MapGenerator.new().generate(SEED_MID, "mid", DIR, "op_mid")
	var hard_path := MapGenerator.new().generate(SEED_HARD, "hard", DIR, "op_hard")
	var faction_path := MapGenerator.new().generate(SEED_FACTION, "faction", DIR, "op_faction")
	_check(start_path != "" and mid_path != "" and hard_path != "" and faction_path != "",
		"карты всех зон сгенерированы")

	var start_ops := _outposts(start_path)
	_check(start_ops.is_empty(), "в стартовой зоне форпостов НЕТ (найдено: %d)" % start_ops.size())
	_check(_guards(start_path).is_empty(), "в стартовой зоне нет фракционной стражи")
	_check(_has_outpost_sidecar(start_path), "sidecar .outposts.json пишется даже пустым")
	_check_no_legacy_structures("start", start_path)

	var per_map := GameConfig.geti("outpost", "per_map")
	for pair in [["mid", mid_path, SEED_MID], ["hard", hard_path, SEED_HARD],
			["faction", faction_path, SEED_FACTION]]:
		var zone := str(pair[0])
		var path := str(pair[1])
		var ops := _outposts(path)
		_check(ops.size() == per_map,
			"зона %s: форпостов %d (ждали %d)" % [zone, ops.size(), per_map])
		_check_factions(zone, ops)
		_check_terrain(zone, ops)
		_check_distances(zone, path, ops)
		_check_guards(zone, path, ops)
		_check_no_legacy_structures(zone, path)
	_check_tier()
	# Детерминизм: тот же сид в другом каталоге — те же форпосты.
	var mid2 := MapGenerator.new().generate(SEED_MID, "mid", DIR_DET, "op_mid")
	_check(_outposts(mid2) == _outposts(mid_path), "тот же сид даёт те же форпосты")


## Фракции: три лагеря — три РАЗНЫЕ расы, имена не пустые.
func _check_factions(zone: String, ops: Array) -> void:
	var seen := {}
	for raw in ops:
		var o: Dictionary = raw
		var race := str(o.get("faction", ""))
		seen[race] = true
		_check(RACES.has(race), "зона %s: фракция лагеря валидна (%s)" % [zone, race])
		_check(str(o.get("name", "")) != "", "зона %s: у лагеря есть имя" % zone)
	_check(seen.size() == ops.size(),
		"зона %s: лагеря разных фракций (%d из %d)" % [zone, seen.size(), ops.size()])


## Лагерь стоит на проходимой земле (не гора/вода) и не на препятствии.
func _check_terrain(zone: String, ops: Array) -> void:
	for raw in ops:
		var o: Dictionary = raw
		var cell := Vector2i(int(o.get("x", -1)), int(o.get("y", -1)))
		var path := _alm_of(zone)
		var map := AlmLoader.load_map(path)
		var w := int(map.get("width", 0))
		var h := int(map.get("height", 0))
		_check(cell.x > 0 and cell.y > 0 and cell.x < w - 1 and cell.y < h - 1,
			"зона %s: якорь лагеря внутри карты (%d,%d)" % [zone, cell.x, cell.y])
		if cell.x <= 0 or cell.y <= 0 or cell.x >= w - 1 or cell.y >= h - 1:
			continue
		var idx := cell.y * w + cell.x
		var tile := int((map.get("tiles", PackedInt32Array()) as PackedInt32Array)[idx])
		var terr := AlmLoader.tile_type(tile)
		_check(terr != 1 and terr != 2,
			"зона %s: лагерь не на горах/воде (terrain %d)" % [zone, terr])
		var obs := int((map.get("obstacles", PackedByteArray()) as PackedByteArray)[idx])
		_check(obs == 0, "зона %s: на якоре лагеря нет препятствия" % zone)


## Дистанции: от спавна/портала и между лагерями.
func _check_distances(zone: String, path: String, ops: Array) -> void:
	var base := _basename(path)
	var spawn := _read_cell(base + ".spawn.json")
	var portal := _read_cell(base + ".portal.json")
	var min_spawn := 14
	for raw in ops:
		var o: Dictionary = raw
		var cell := Vector2i(int(o.get("x", 0)), int(o.get("y", 0)))
		if spawn != Vector2i(-1, -1):
			_check(_cheb(cell, spawn) >= min_spawn,
				"зона %s: лагерь далеко от спавна (%d)" % [zone, _cheb(cell, spawn)])
		if portal != Vector2i(-1, -1):
			_check(_cheb(cell, portal) >= min_spawn,
				"зона %s: лагерь далеко от портала (%d)" % [zone, _cheb(cell, portal)])
	for i in range(ops.size()):
		for j in range(i + 1, ops.size()):
			var a: Dictionary = ops[i]
			var b: Dictionary = ops[j]
			var ca := Vector2i(int(a["x"]), int(a["y"]))
			var cb := Vector2i(int(b["x"]), int(b["y"]))
			_check(_cheb(ca, cb) >= MapGenerator.OUTPOST_MIN_EACH_OTHER,
				"зона %s: лагеря не слипаются (%d)" % [zone, _cheb(ca, cb)])


## Стража: количество, фракция, наборы, клетки вне построек, без наложений.
func _check_guards(zone: String, path: String, ops: Array) -> void:
	var guards := _guards(path)
	var by_outpost := {}
	for raw in guards:
		var g: Dictionary = raw
		var oid := str(g.get("outpost", ""))
		by_outpost[oid] = int(by_outpost.get(oid, 0)) + 1
		var race := str(g.get("faction", ""))
		_check(race != "", "зона %s: у стражника есть фракция" % zone)
		var set_name := str(g.get("set", ""))
		_check(UnitDB.has(set_name), "зона %s: набор стражи %s существует" % [zone, set_name])
		_check(MapGenerator.race_of_set(set_name) == race,
			"зона %s: набор %s принадлежит фракции %s" % [zone, set_name, race])
	var gmin := GameConfig.geti("outpost", "guards_min")
	var gmax := GameConfig.geti("outpost", "guards_max")
	for raw in ops:
		var o: Dictionary = raw
		var oid := str(o.get("id", ""))
		var n := int(by_outpost.get(oid, 0))
		_check(n >= gmin and n <= gmax,
			"зона %s: в лагере %s стражников %d (ждём %d..%d)" % [zone, oid, n, gmin, gmax])
	var cells := {}
	for raw2 in guards:
		var g2: Dictionary = raw2
		var c := Vector2i(int(g2.get("x", -1)), int(g2.get("y", -1)))
		_check(not cells.has(c), "зона %s: два стражника не на одной клетке %s" % [zone, str(c)])
		cells[c] = true
		_check(not _inside_structure(path, c),
			"зона %s: стражник %s не внутри постройки" % [zone, str(c)])
		var map := AlmLoader.load_map(_alm_of(zone))
		var w := int(map.get("width", 0))
		var idx := c.y * w + c.x
		if w <= 0 or idx < 0 or idx >= (map.get("tiles", PackedInt32Array()) as PackedInt32Array).size():
			continue
		var tile := int((map.get("tiles", PackedInt32Array()) as PackedInt32Array)[idx])
		var terr := AlmLoader.tile_type(tile)
		_check(terr != 1 and terr != 2,
			"зона %s: стражник %s стоит на проходимой земле" % [zone, str(c)])


## Тир стражи по зоне: start->0, mid->1, hard->2, faction->3.
func _check_tier() -> void:
	_check(_tier_ok("mid", "t1") and _tier_ok("hard", "t2") and _tier_ok("faction", "t3"),
		"тир стражи растёт по зонам (mid t1, hard t2, faction t3)")


func _tier_ok(zone: String, suffix: String) -> bool:
	var guards := _guards(_alm_of(zone))
	for raw in guards:
		if not str((raw as Dictionary).get("set", "")).ends_with("/" + suffix):
			return false
	return not guards.is_empty()


# --- 3. Захват и бирки в луте ---------------------------------------------

func _check_capture() -> void:
	# Бирка падает со стражника всегда (решение игрока 28.10).
	var e := Enemy.new()
	e.anim_set = "city_ork_warrior/t1"
	e.faction = "ork"
	var pool: Array = e._make_loot()
	var has_tag := false
	for raw in pool:
		if str((raw as Dictionary).get("key", "")) == ItemDB.tag_key("ork"):
			has_tag = true
	_check(has_tag, "с орка-стражника падает его бирка")
	e.free()

	Game.outposts_captured.clear()
	Game.pending_outposts_captured.clear()
	Game.map_zone = "mid"
	Game.map_sector = "s00"
	Game.map_seed = 9001
	Game.outposts = [{"id": "op0", "faction": "ork", "name": "Форпост Орды", "x": 10, "y": 10}]
	# Гибель стражи снижает репутацию, а живая игра ниже стартует в том же
	# дереве (автолоады в --script есть) — значение откатываем, иначе тест
	# сделал бы стражу враждебной сам себе.
	var bus := root.get_node_or_null("WorldBus")
	var rep_before := int(bus.state.hero_rep("ork")) \
		if bus != null and ("state" in bus) and bus.state != null else 0
	var a := Enemy.new()
	a.faction = "ork"
	a.outpost_id = "op0"
	var b := Enemy.new()
	b.faction = "ork"
	b.outpost_id = "op0"
	Game.enemies = [a, b]
	Game.on_outpost_guard_died(a)
	_check(not Game.is_outpost_captured("op0"), "один стражник — лагерь ещё не захвачен")
	Game.enemies = []
	var player := Player.new()
	Game.hero = player
	Game.on_outpost_guard_died(b)
	_check(Game.is_outpost_captured("op0"), "последний стражник захватывает лагерь")
	_check(not Game.is_outpost_captured("op1"), "соседний лагерь не захвачен заодно")
	# Захват даёт чертежи наборов этой фракции (пакет C+D).
	var scrolls := CraftDB.recipe_ids_of_faction("ork")
	var got := 0
	for rid in scrolls:
		if player.inventory.has(CraftDB.recipe_scroll_key(str(rid))):
			got += 1
	_check(scrolls.size() > 0 and got == scrolls.size(),
		"захват выдал чертежи фракции (%d из %d)" % [got, scrolls.size()])
	# Наборы пакета C+D: рецепты читаются мастерской, броня делится по классам,
	# а бирка — обязательный ингредиент.
	var heavy_recipes := CraftDB.known_recipes(CraftDB.SMITH, player).filter(
		func(r: Dictionary) -> bool: return str(r.get("id", "")).begins_with("faction_ork_heavy"))
	var light_recipes := CraftDB.known_recipes(CraftDB.TAILOR, player).filter(
		func(r: Dictionary) -> bool: return str(r.get("id", "")).begins_with("faction_ork_light"))
	_check(heavy_recipes.size() == 4 and light_recipes.size() == 4,
		"после захвата мастерская знает 4+4 рецепта (%d+%d)"
			% [heavy_recipes.size(), light_recipes.size()])
	# Магический комплект (29.10): третья линия наборов, тоже 4 рецепта.
	var magic_recipes := CraftDB.known_recipes(CraftDB.TAILOR, player).filter(
		func(r: Dictionary) -> bool: return str(r.get("id", "")).begins_with("faction_ork_magic"))
	_check(magic_recipes.size() == 4, "после захвата есть 4 рецепта магического набора (%d)"
		% magic_recipes.size())
	var cuirass := ItemDB.find(CraftDB.output_key(CraftDB.recipe_by_id("faction_ork_heavy_body"), 0))
	var robe := ItemDB.find(CraftDB.output_key(CraftDB.recipe_by_id("faction_ork_light_body"), 0))
	_check(not cuirass.is_empty() and ItemDB.allows_class(cuirass, "warrior")
		and not ItemDB.allows_class(cuirass, "mage"),
		"тяжёлая кираса набора — только воину")
	_check(not robe.is_empty() and ItemDB.allows_class(robe, "mage")
		and not ItemDB.allows_class(robe, "warrior"),
		"лёгкая роба набора — только магу")
	var magic_robe := ItemDB.find(CraftDB.output_key(
		CraftDB.recipe_by_id("faction_ork_magic_body"), 0))
	_check(not magic_robe.is_empty() and ItemDB.allows_class(magic_robe, "mage")
		and not ItemDB.allows_class(magic_robe, "warrior"),
		"магическая мантия — только магу")
	var rbody := CraftDB.recipe_by_id("faction_ork_heavy_body")
	var needs_tag := false
	for ing in rbody.get("inputs", []):
		if str((ing as Dictionary).get("item", "")) == ItemDB.tag_key("ork"):
			needs_tag = true
	_check(needs_tag, "рецепт тяжёлого набора требует бирку фракции")
	# Крафт целиком: сталь + ткань + бирка -> кираса набора.
	for _i in 10:
		player.add_item("steel Ingot")
	player.add_item("Fabric")
	player.add_item(ItemDB.tag_key("ork"))
	var tab := CraftTab.new()
	tab.setup(player, CraftDB.SMITH)
	var made := str(tab.call("_craft", rbody))
	_check(made != "", "кираса набора скрафчена (%s)" % made)
	var crafted_key := CraftDB.output_key(rbody, 0)
	var has_result := false
	for raw in player.inventory:
		if str(raw) == crafted_key or str(raw) == CraftDB.output_key(rbody, 1) \
				or str(raw) == CraftDB.output_key(rbody, 2):
			has_result = true
	_check(has_result, "вещь набора легла в склад")
	tab.free()
	# Повторный захват того же лагеря чертежи не дублирует.
	Game.outposts_captured.erase(Game.outpost_key("op0"))
	Game.on_outpost_guard_died(b)
	var dup := 0
	for raw in player.inventory:
		if str(raw).begins_with("Recipe faction_ork_"):
			dup += 1
	_check(dup == scrolls.size(), "повторный захват не дублирует чертежи (%d)" % dup)
	Game.hero = null
	player.free()
	a.free()
	b.free()

	# Ключ захвата привязан к карте: тот же id на другой карте — свой флаг.
	var key_mid := Game.outpost_key("op0")
	Game.map_seed = 9003
	_check(Game.outpost_key("op0") != key_mid, "ключ захвата различает карты по сиду")
	_check(not Game.is_outpost_captured("op0"), "на другой карте лагерь не захвачен")

	# Флаг из сейва доезжает через pending (порядок: apply_payload → reload).
	Game.map_seed = 9001
	Game.outposts_captured.clear()
	Game.pending_outposts_captured = {Game.outpost_key("op2"): true}
	Game.reload_outposts(null)
	_check(Game.is_outpost_captured("op2"), "захват из сейва применяется через pending")
	_check(Game.pending_outposts_captured.is_empty(), "pending-словарь не остаётся на второй раз")

	# Захваченная стража не спавнится: предикат, на который смотрит спавн.
	_check(Game.is_outpost_captured("op2") and not Game.is_outpost_captured("op0"),
		"спавн отличит захваченный лагерь от нетронутого")

	# Sidecar карты обязан копироваться в слот вместе с остальными файлами.
	_check(SaveSystem.WORLD_SUFFIXES.has(".outposts.json"),
		"sidecar форпостов попадает в папку сохранения")

	Game.outposts.clear()
	Game.outposts_captured.clear()
	Game.pending_outposts_captured.clear()
	Game.enemies.clear()
	# Откат репутации, испорченной проверкой гибели стражи (см. выше).
	if bus != null and ("state" in bus) and bus.state != null:
		var now := int(bus.state.hero_rep("ork"))
		if now != rep_before:
			bus.state.add_hero_reputation("ork", rep_before - now)


# --- 4. Живая игра: стража заспавнилась и она нейтральна -------------------

## Живая сцена, а не только sidecar: проверяет проводку Game._spawn_monster
## (faction/outpost_id) и то, что при репутации 0 стража НЕ бросается на героя.
func _check_live_game() -> void:
	Game.hero_class = "warrior"
	Game.hero_gender = "male"
	Game.hero_name = "Тестер"
	Game.hero_character_id = "human_m_war"
	Game.hero_stats = {"strength": 20, "dexterity": 20, "intelligence": 10,
		"vitality": 20, "spirit": 10, "luck": 5}
	Game.map_seed = SEED_MID
	Game.map_zone = "mid"
	Game.map_sector = "s00"
	Game.loaded_slot = ""
	Game.outposts.clear()
	Game.outposts_captured.clear()
	Game.pending_outposts_captured.clear()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(2.5).timeout
	_check(Game.outposts.size() == GameConfig.geti("outpost", "per_map"),
		"живая игра: форпосты прочитаны из sidecar (%d)" % Game.outposts.size())
	var guards := 0
	var neutral := 0
	for e in Game.enemies:
		if e == null or not is_instance_valid(e):
			continue
		if str(e.get("outpost_id")) == "":
			continue
		guards += 1
		if not bool(e.call("is_hostile_to_hero")):
			neutral += 1
	_check(guards > 0, "живая игра: стража форпостов заспавнилась (%d)" % guards)
	_check(neutral == guards,
		"живая игра: при репутации 0 вся стража нейтральна (%d из %d)" % [neutral, guards])
	# Вражда: тот же стражник отвечает, если его ударили (провокация).
	if guards > 0:
		var first: Node2D = null
		for e in Game.enemies:
			if e != null and str(e.get("outpost_id")) != "":
				first = e
				break
		if first != null:
			first.set("provoked", true)
			_check(bool(first.call("is_hostile_to_hero")),
				"живая игра: удар по стражнику делает его враждебным")
	# Захват переживает сохранение: словарь едет в map.outposts, а не только
	# в памяти (иначе после перезапуска лагерь снова полон стражи).
	Sandbox.use_test_dir()
	Game.outposts_captured["test|key"] = true
	game.call("_save_to_slot", "slot_0")
	var res: Dictionary = SaveSystem.load_slot("slot_0")
	var saved_map: Dictionary = (res.get("data", {}) as Dictionary).get("map", {})
	var saved_cap: Variant = (saved_map as Dictionary).get("outposts", {})
	_check(saved_cap is Dictionary and (saved_cap as Dictionary).has("test|key"),
		"живая игра: захват форпоста записан в map.outposts")
	Sandbox.wipe()
	game.queue_free()
	await process_frame

	# Обратный путь: apply_payload кладёт захват в pending, reload — в словарь.
	SaveSystem.apply_payload({"map": {"seed": SEED_MID, "zone": "mid",
		"sector": "s00", "outposts": {"mid|s00|9001|op9": true}}}, null)
	_check(Game.pending_outposts_captured.has(Game.outpost_key("op9")),
		"apply_payload кладёт захват в pending по ключу карты")
	Game.outposts_captured.clear()
	Game.reload_outposts(null)
	_check(Game.is_outpost_captured("op9"), "после reload форпост из сейва захвачен")
	Game.outposts_captured.clear()
	Game.pending_outposts_captured.clear()


# --- Утилиты --------------------------------------------------------------

func _alm_of(zone: String) -> String:
	match zone:
		"start": return DIR + "op_start.alm"
		"mid": return DIR + "op_mid.alm"
		"hard": return DIR + "op_hard.alm"
		"faction": return DIR + "op_faction.alm"
	return ""


func _basename(path: String) -> String:
	return path.get_basename()


func _outposts(path: String) -> Array:
	var f := FileAccess.open(_basename(path) + ".outposts.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and (parsed as Dictionary).get("outposts", null) is Array:
		return (parsed as Dictionary)["outposts"]
	return []


func _guards(path: String) -> Array:
	var f := FileAccess.open(_basename(path) + ".npcs.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var out: Array = []
	if parsed is Dictionary and (parsed as Dictionary).get("npcs", null) is Array:
		for raw in (parsed as Dictionary)["npcs"]:
			if (raw as Dictionary).has("outpost"):
				out.append(raw)
	return out


func _has_outpost_sidecar(path: String) -> bool:
	return FileAccess.file_exists(_basename(path) + ".outposts.json")


func _read_cell(path: String) -> Vector2i:
	if not FileAccess.file_exists(path):
		return Vector2i(-1, -1)
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return Vector2i(int((parsed as Dictionary).get("x", -1)),
			int((parsed as Dictionary).get("y", -1)))
	return Vector2i(-1, -1)


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Арт Аллодов удалён (29.10): на карте не должно остаться ни одного здания
## с id < 200 и ни одной ссылки на снесённую папку. Сторож ловит возврат
## legacy-пулов в генератор (форпосты, города, декор).
func _check_no_legacy_structures(zone: String, path: String) -> void:
	var f := FileAccess.open(_basename(path) + ".structures.json", FileAccess.READ)
	if f == null:
		_check(false, "зона %s: нет sidecar .structures.json" % zone)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var list: Variant = (parsed as Dictionary).get("structures", []) if parsed is Dictionary else []
	if not (list is Array):
		_check(false, "зона %s: structures — не массив" % zone)
		return
	var legacy := 0
	var broken := 0
	for raw in list as Array:
		var s: Dictionary = raw
		var tid := int(s.get("type_id", 0))
		if tid < 200:
			legacy += 1
			continue
		var def := StructureDB.get_by_id(tid)
		var folder := str(def.get("folder", ""))
		if folder == "" or not ResourceLoader.exists(
				"res://assets/structures/%s/house-001.png" % folder):
			broken += 1
	_check(legacy == 0, "зона %s: Аллодовских зданий (id < 200) нет (%d)" % [zone, legacy])
	_check(broken == 0, "зона %s: все постройки ссылаются на существующие папки (%d битых)"
		% [zone, broken])
	_check((list as Array).size() > 0, "зона %s: постройки на карте есть (%d)"
		% [zone, (list as Array).size()])


## Лежит ли клетка внутри футпринта любой постройки из sidecar.
func _inside_structure(path: String, cell: Vector2i) -> bool:
	var f := FileAccess.open(_basename(path) + ".structures.json", FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	var list: Variant = (parsed as Dictionary).get("structures", [])
	if not (list is Array):
		return false
	for raw in list as Array:
		var s: Dictionary = raw
		var def := StructureDB.get_by_id(int(s.get("type_id", 0)))
		var w := int(def.get("tile_width", 1))
		var h := int(def.get("tile_height", 1))
		var tl := Vector2i(int(s.get("x", -1000)), int(s.get("y", -1000)))
		if cell.x >= tl.x and cell.x < tl.x + w and cell.y >= tl.y and cell.y < tl.y + h:
			return true
	return false


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK outpost_smoke")
		quit(0)
	else:
		print("RESULT: FAIL outpost_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
