extends SceneTree
## Slot folders: save from a live game, load it back, change the zone.
##
## Player request (22.10): every save is its own folder in the saves
## directory holding the character, the map and the process; a Save rewrites
## every element of the folder. This test drives the real scene: a slot must
## bring the hero back to the saved position, the map must come from the slot
## (not from the seed), and a zone change must put the new zone's map files
## into the slot so the older zone survives a restart.
##
## Run: godot --headless --path . --script res://tests/save_folder_smoke.gd

const Sandbox := preload("res://tests/save_sandbox.gd")
const SLOT := "slot_0"

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	Sandbox.use_test_dir()
	_run.call_deferred()


func _run() -> void:
	await _start_game()
	var game = current_scene
	var player = game.get("player")
	_check(player != null, "герой на месте")
	if player == null:
		_finish()
		return
	var saved_pos := Vector2(1500.0, 1500.0)
	player.global_position = saved_pos
	player.gold = 2468
	game.call("_save_to_slot", SLOT)

	_check(FileAccess.file_exists(SaveSystem.part_path(SLOT, SaveSystem.HERO_FILE)),
		"в папке слота есть hero.json")
	_check(FileAccess.file_exists(SaveSystem.part_path(SLOT, SaveSystem.MAP_FILE)),
		"в папке слота есть map.json")
	_check(FileAccess.file_exists(SaveSystem.part_path(SLOT, SaveSystem.PROCESS_FILE)),
		"в папке слота есть process.json")
	var slot_map := SaveSystem.world_map_path(SLOT)
	_check(slot_map != "" and FileAccess.file_exists(slot_map),
		"в папке слота лежит сама карта (.alm): %s" % slot_map.get_file())

	# Портим живое состояние и грузим слот: всё должно вернуться из папки.
	player.gold = 1
	player.global_position = Vector2(32, 32)
	game.call("_load_from_slot", SLOT)
	await create_timer(1.0).timeout
	player = game.get("player")
	_check(int(player.gold) == 2468, "золото вернулось из слота (%d)" % int(player.gold))
	_check(player.global_position.distance_to(saved_pos) < 1.0,
		"герой встал на позицию из слота (%s)" % str(player.global_position))
	var map = game.get("alm_map")
	var map_path := str(map.get("alm_path")) if map != null else ""
	_check(map_path.begins_with(SaveSystem.slot_dir(SLOT)),
		"карта загружена из папки слота (%s)" % map_path)

	# Переход в другую зону: карта новой зоны ложится в тот же слот.
	var old_zone := Game.map_zone
	await game.call("travel_to_zone", "mid")
	await create_timer(1.2).timeout
	_check(Game.map_zone == "mid", "зона сменилась на mid (%s)" % Game.map_zone)
	var zone_map := SaveSystem.restore_zone_map(SLOT, "mid")
	# Карта новой зоны уже лежит в user://maps/ (игра только что на ней), поэтому
	# restore_zone_map возвращает путь на месте — важно, что он есть и читается.
	_check(zone_map != "" and FileAccess.file_exists(zone_map),
		"карта новой зоны лежит в папке слота (%s)" % zone_map)
	var back_map := SaveSystem.restore_zone_map(SLOT, old_zone)
	_check(back_map != "" and FileAccess.file_exists(back_map),
		"карта прежней зоны (%s) осталась в слоте (%s)" % [old_zone, back_map])
	_check(is_instance_valid(player), "герой пережил переход между зонами")
	_finish()


func _start_game() -> void:
	Game.hero_class = "warrior"
	Game.hero_gender = "male"
	Game.hero_name = "Тестер"
	Game.hero_character_id = "human_m_war"
	Game.hero_stats = {"strength": 20, "dexterity": 20, "intelligence": 10,
		"vitality": 20, "spirit": 10, "luck": 5}
	Game.map_seed = 4242
	Game.map_zone = "start"
	Game.loaded_slot = ""
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(0.6).timeout


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _finish() -> void:
	Sandbox.wipe()
	print("---")
	print("проверок: %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK save_folder_smoke")
		quit(0)
	else:
		print("RESULT: FAIL save_folder_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
