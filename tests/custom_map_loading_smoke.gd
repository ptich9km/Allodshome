extends SceneTree
## Старт новой игры с ГОТОВОЙ картой (сделана редактором).
##
## Проверяет всю цепочку: StartSetup(mode=map) -> loading.tscn НЕ генерирует
## карту по сиду -> main.tscn открывает именно этот .alm -> герой стоит на
## точке спавна из .spawn.json.
##
## Запуск: godot --headless --path . --script res://tests/custom_map_loading_smoke.gd

const DIR := "user://maps/custom/"
const MAP := "user://maps/custom/custom_loading_smoke.alm"
const W := 24
const H := 24
const SPAWN := Vector2i(10, 10)
const Sandbox := preload("res://tests/save_sandbox.gd")

var _fails: Array[String] = []


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_race = "human"
	Game.hero_name = "Картограф"
	_make_map()
	var setup := StartSetup.new()
	setup.mode = "map"
	setup.map_path = MAP
	setup.world_seed = 555
	var err := setup.apply()
	_check(err == "", "StartSetup.apply: %s" % err)
	_run.call_deferred()


func _make_map() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var n := W * H
	var tiles := PackedInt32Array()
	tiles.resize(n)
	tiles.fill(AlmLoader.tile_from_spec({"file": 1, "variant": 0, "row": 0}))
	AlmLoader.write_map(MAP, W, H, tiles, PackedByteArray(), PackedByteArray(), "smoke")
	# Спавн и мета (их пишет редактор)
	var f := FileAccess.open(MAP.get_basename() + ".spawn.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"x": SPAWN.x, "y": SPAWN.y}))
	f.close()
	MapMeta.write(MAP, {"title": "Смоук-карта", "zone": "start", "w": W, "h": H})


func _run() -> void:
	var err := change_scene_to_file("res://scenes/loading.tscn")
	_check(err == OK, "loading.tscn загрузилась (err=%d)" % err)
	await process_frame
	var waited := 0.0
	while waited < 20.0:
		if current_scene != null and current_scene.name != "Loading" \
				and current_scene.get("player") != null:
			break
		await create_timer(0.1).timeout
		waited += 0.1
	var player = current_scene.get("player") if current_scene != null else null
	var map = current_scene.get("alm_map") if current_scene != null else null
	_check(player != null, "герой жив после загрузки")
	_check(map != null, "карта загружена")
	_check(Game.pending_map_path == MAP,
		"loading не перезатёр путь карты (%s)" % Game.pending_map_path)
	_check(Game.map_seed == StartSetup.identity_seed(MAP),
		"identity-сид сохранён (%d)" % Game.map_seed)
	if map != null:
		_check(int(map.get("map_width")) == W and int(map.get("map_height")) == H,
			"размер карты из редактора (%sx%s)" % [map.get("map_width"), map.get("map_height")])
	if player != null:
		var want := Vector2(SPAWN.x * 32 + 16, SPAWN.y * 32 + 16)
		_check(player.global_position.distance_to(want) < 40.0,
			"герой на спавне из .spawn.json (%s, ждали ~%s)"
				% [str(player.global_position), str(want)])

	# Сейв должен зеркалить карту вместе с .meta.json
	var info := SaveSystem.world_files()
	_check(str(info.get("path", "")) == MAP, "world_files знает карту (%s)" % info.get("path"))
	_check(str(info.get("basename", "")).contains(Game.map_sector),
		"имя карты несёт сектор для возврата (%s)" % info.get("basename"))

	# Сейв -> слот -> восстановление карты (проверяем, что .meta.json едет с ней)
	Sandbox.use_test_dir()
	var payload := {
		"version": SaveSystem.VERSION,
		"map": {
			"seed": Game.map_seed, "zone": Game.map_zone,
			"world_seed": Game.world_seed, "sector": Game.map_sector,
			"path": str(info.get("path", "")), "basename": str(info.get("basename", "")),
		},
		"hero": {"name": "Картограф", "class": "warrior", "current_hp": 10,
			"max_hp": 10, "current_mana": 0, "max_mana": 0, "gold": 0,
			"inventory": [], "equipped": {}, "experience": {},
			"known_spells": {}, "sphere_books": {}, "position": Vector2.ZERO},
		"world": {"day": 1, "cities": {}},
		"quests": {},
		"meta": {},
	}
	var save_err: String = SaveSystem.save("smoke", payload)
	_check(save_err == "", "сейв с кастомной картой: %s" % save_err)
	SaveSystem.restore_map("smoke")
	var staged := Game.pending_map_path
	_check(staged != "" and FileAccess.file_exists(staged), "карта восстановлена из слота (%s)" % staged)
	if staged != "":
		_check(FileAccess.file_exists(staged.get_basename() + ".meta.json"),
			"meta.json уехала в слот и обратно")
		for suffix in ["", ".meta.json"]:
			var p: String = staged + suffix if suffix != "" else staged
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	_cleanup()
	_report()


func _cleanup() -> void:
	for suffix in ["", ".spawn.json", ".meta.json"]:
		var p: String = (MAP.get_basename() + suffix) if suffix != "" else MAP
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK custom_map_loading_smoke")
		quit(0)
	else:
		print("RESULT: FAIL custom_map_loading_smoke (%d)" % _fails.size())
		quit(1)
