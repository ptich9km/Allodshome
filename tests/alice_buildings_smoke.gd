extends SceneTree
## Здания Alice (05.10): structure_id 200..206, клик по папке, футпринт.
## Запуск: godot --headless --path . --script res://tests/alice_buildings_smoke.gd

const SEED := 4242

var _fails: Array[String] = []
var _checks := 0

func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Герой"
	call_deferred("_run")

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)

func _run() -> void:
	# --- StructureDB ---
	var expect := {
		200: ["shop3", "shop"],
		201: ["inn4", "inn"],
		202: ["blacksmith3", "blacksmith"],
		203: ["train4", "school"],
		204: ["druidshop4", "alchemy"],
		205: ["house_ogre", ""],
		206: ["barracks1", ""],
	}
	for id in expect:
		var def: Dictionary = StructureDB.get_by_id(id)
		_check(not def.is_empty(), "structure_db id %d есть" % id)
		if def.is_empty():
			continue
		var folder: String = str(def.get("folder", ""))
		_check(folder == expect[id][0], "id %d folder=%s" % [id, folder])
		_check(int(def.get("tile_width", 0)) == 3 and int(def.get("tile_height", 0)) == 3,
			"id %d футпринт 3x3" % id)
		_check(int(def.get("full_height", 0)) == 3, "id %d full_height=3" % id)
		var tex: Texture2D = StructureDB.preview_texture(id)
		_check(tex != null, "id %d house-001.png грузится" % id)
		_check(int(def.get("whole_image", 0)) == 1, "id %d whole_image=1" % id)
		var png := "res://assets/structures/%s/house-001.png" % folder
		_check(ResourceLoader.exists(png), "id %d один файл house-001" % id)
		# не должно остаться нарезки house-002..
		_check(not ResourceLoader.exists("res://assets/structures/%s/house-002.png" % folder),
			"id %d нет house-002 (не сетка)" % id)

	# --- Клик: _structure_kind по type_id ---
	var game := Game
	# kind через статический путь StructureDB + тот же код, что в game.gd
	var kinds := {200: "shop", 201: "inn", 202: "blacksmith", 203: "school", 204: "alchemy"}
	for id in kinds:
		var folder := str(StructureDB.get_by_id(id).get("folder", "")).to_lower()
		var kind := ""
		if folder.contains("druidshop") or folder.contains("hive"):
			kind = "alchemy"
		elif folder.contains("shop"):
			kind = "shop"
		elif folder.contains("inn"):
			kind = "inn"
		elif folder.contains("train") or folder.contains("school"):
			kind = "school"
		elif folder.contains("blacksmith"):
			kind = "blacksmith"
		_check(kind == kinds[id], "клик id %d -> %s (получено %s)" % [id, kinds[id], kind])

	# --- Карта: генерация с новыми зданиями ---
	Game.request_map_by_seed(SEED, "mid")
	var err := change_scene_to_file("res://scenes/main.tscn")
	_check(err == OK, "main.tscn")
	await process_frame
	await create_timer(0.6).timeout

	var am = get_first_node_in_group("alm_map")
	_check(am != null, "AlmMap")
	if am == null:
		_report()
		return

	var new_ids := {200: 0, 201: 0, 202: 0, 203: 0, 204: 0, 205: 0, 206: 0}
	var all_st: Array = am.get("_structures") if "structures" in am else []
	if all_st.is_empty() and am.has_method("get_structures"):
		all_st = am.call("get_structures")
	# structures могут быть в _structures
	if am.get("_structures") != null:
		all_st = am.get("_structures")
	var found := 0
	for st in all_st:
		var tid := int(st.get("type_id", 0))
		if new_ids.has(tid):
			new_ids[tid] = int(new_ids[tid]) + 1
			found += 1
	print("INFO новые здания на карте: %s (всего записей %d)" % [str(new_ids), all_st.size()])
	_check(found > 0, "на карте есть здания Alice (найдено %d)" % found)
	# хотя бы функциональные
	_check(int(new_ids[200]) + int(new_ids[201]) + int(new_ids[202]) + int(new_ids[203]) + int(new_ids[204]) > 0,
		"есть функциональные shop/inn/bs/train/alchemy")

	# --- Дверь / nav: у функционального здания есть проходимая клетка рядом ---
	var nav: Array = am.get("_structure_nav") if "_structure_nav" in am else []
	_check(nav.size() > 0, "навигационные футпринты есть (%d)" % nav.size())
	var walk_ok := 0
	var walk_bad := 0
	if am.has_method("is_walkable_world"):
		for h in nav:
			var x0 := int(h["x0"])
			var y1 := int(h["y1"])
			# южнее футпринта — дверь
			var door := Vector2((x0 + 1) * 32 + 16, (y1 + 1) * 32 + 16)
			if bool(am.is_walkable_world(door)):
				walk_ok += 1
			else:
				# попробовать соседние клетки юга
				var alt := Vector2((x0 + 2) * 32 + 16, (y1 + 1) * 32 + 16)
				if bool(am.is_walkable_world(alt)):
					walk_ok += 1
				else:
					walk_bad += 1
	print("INFO двери: проходимо=%d непроходимо=%d" % [walk_ok, walk_bad])
	_check(walk_ok > 0, "есть проходимые двери у зданий (%d)" % walk_ok)

	_report()

func _report() -> void:
	if _fails.is_empty():
		print("RESULT: OK alice_buildings_smoke (%d)" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)
