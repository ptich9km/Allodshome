extends SceneTree
## Диагностика: блокируют ли здания Alice клетки (навигация) и открывается ли меню.
## Запуск: godot --headless --path . --script res://tests/building_nav_smoke.gd

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
	Game.request_map_by_seed(SEED, "mid")
	var err := change_scene_to_file("res://scenes/main.tscn")
	_check(err == OK, "main.tscn")
	await process_frame
	await create_timer(0.5).timeout

	var am = get_first_node_in_group("alm_map")
	_check(am != null, "AlmMap")
	if am == null:
		_report()
		return

	var nav: Array = am.get("_structure_nav") if "_structure_nav" in am else []
	var hits: Array = am.get("_structure_hits") if "_structure_hits" in am else []
	var structs: Array = am.get("_structures") if "_structures" in am else []
	print("INFO structures=%d nav=%d hits=%d" % [structs.size(), nav.size(), hits.size()])
	_check(nav.size() > 0, "навигация заполнена (%d)" % nav.size())

	var blocked := 0
	var walk_on := 0
	var samples := 0
	for h in nav:
		var x0 := int(h["x0"])
		var y0 := int(h["y0"])
		var x1 := int(h["x1"])
		var y1 := int(h["y1"])
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var p := Vector2(xx * 32.0 + 16.0, yy * 32.0 + 16.0)
				samples += 1
				if bool(am.is_walkable_world(p)):
					walk_on += 1
					print("  WALK-ON building cell (%d,%d)" % [xx, yy])
				else:
					blocked += 1
	print("INFO клетки зданий: blocked=%d walk_on=%d из %d" % [blocked, walk_on, samples])
	_check(walk_on == 0, "клетки футпринта зданий НЕ проходимы (walk_on=%d)" % walk_on)
	_check(blocked > 0, "есть заблокированные клетки зданий (%d)" % blocked)

	# Дверь: южнее футпринта должна быть проходима
	var door_ok := 0
	var door_bad := 0
	for st in structs:
		var tid := int(st.get("type_id", 0))
		if tid < 200 or tid > 206:
			continue
		var def: Dictionary = StructureDB.get_by_id(tid)
		var fw := int(def.get("tile_width", 3))
		var th := int(def.get("tile_height", 3))
		var x := int(st.get("x", 0))
		var y := int(st.get("y", 0))
		var found := false
		for dx in range(fw):
			var c := Vector2i(x + dx, y + th)
			var p := Vector2(c.x * 32.0 + 16.0, c.y * 32.0 + 16.0)
			if bool(am.is_walkable_world(p)):
				found = true
				break
		if found:
			door_ok += 1
		else:
			door_bad += 1
			print("  DOOR-BAD id=%d at (%d,%d)" % [tid, x, y])
	print("INFO двери: ok=%d bad=%d" % [door_ok, door_bad])
	_check(door_ok > 0, "есть проходимые двери (%d)" % door_ok)

	# structure_at: клик по центру здания должен находить постройку
	var hit_ok := 0
	for st in structs:
		var tid := int(st.get("type_id", 0))
		if tid < 200 or tid > 206:
			continue
		var cell := Vector2i(int(st.get("x", 0)) + 1, int(st.get("y", 0)) + 1)
		var s: Dictionary = am.call("structure_at", cell)
		if not s.is_empty() and int(s.get("type_id", -1)) == tid:
			hit_ok += 1
	print("INFO structure_at: %d/%d" % [hit_ok, structs.size()])
	_check(hit_ok > 0, "structure_at находит здания")

	# Физика: у StructureNode есть StaticBody2D FootprintBody
	var bodies := 0
	var buildings_node: Node2D = am.get("buildings") if "buildings" in am else null
	if buildings_node != null:
		for ch in buildings_node.get_children():
			if ch.has_node("FootprintBody"):
				bodies += 1
	print("INFO FootprintBody: %d зданий с физикой" % bodies)
	_check(bodies > 0, "есть StaticBody2D у зданий (%d)" % bodies)

	_report()

func _report() -> void:
	if _fails.is_empty():
		print("RESULT: OK building_nav_smoke (%d)" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)
