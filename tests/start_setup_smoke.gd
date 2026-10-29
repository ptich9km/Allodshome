extends SceneTree
## «Своя игра»: детерминизм сида, зона и старт с готовой карты.
##
## Проверяет StartSetup.apply(): один и тот же сид+зона дают один и тот же
## map_seed, разные сиды — разные; готовая карта получает identity-сид и
## путь в Game.pending_map_path; мета (зона) читается и копируется сейвом.
##
## Запуск: godot --headless --path . --script res://tests/start_setup_smoke.gd

const CUSTOM := "user://maps/custom/"
const TEST_MAP := "user://maps/custom/start_setup_smoke.alm"

var _fails: Array[String] = []


func _init() -> void:
	_test_seeded()
	_test_map()
	_test_meta()
	_cleanup()
	_report()


func _test_seeded() -> void:
	var a := StartSetup.new()
	a.mode = "seed"
	a.world_seed = 123456
	a.zone = "start"
	var b := StartSetup.new()
	b.mode = "seed"
	b.world_seed = 123456
	b.zone = "start"
	_check(a.apply() == "" and b.apply() == "", "seed: apply без ошибок")
	var first := Game.map_seed
	_check(first != 0, "seed: map_seed не ноль (%d)" % first)
	a.apply()
	_check(Game.map_seed == first, "seed: тот же сид -> та же карта (%d)" % Game.map_seed)
	b.mode = "seed"
	b.world_seed = 654321
	b.apply()
	_check(Game.map_seed != first, "другой сид -> другая карта")
	_check(Game.pending_map_path == "", "seed: pending path очищен")

	var z := StartSetup.new()
	z.mode = "seed"
	z.world_seed = 123456
	z.zone = "hard"
	z.apply()
	_check(Game.map_zone == "hard" or Game.map_zone == StartSetup.ZONES[2],
		"seed: зона доехала в Game.map_zone (%s)" % Game.map_zone)
	_check(Game.map_sector != "", "seed: сектор выбран (%s)" % Game.map_sector)

	# random: каждый apply — новый сид
	var r := StartSetup.new()
	r.mode = "random"
	r.apply()
	var s1 := Game.world_seed
	r.apply()
	var s2 := Game.world_seed
	_check(s1 != s2, "random: сид меняется между запусками (%d/%d)" % [s1, s2])


func _test_map() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CUSTOM))
	# Готовая карта: маленький .alm, записанный полным writer-ом.
	var w := 8
	var h := 8
	var tiles := PackedInt32Array()
	tiles.resize(w * h)
	tiles.fill(AlmLoader.tile_from_spec({"file": 1, "variant": 0, "row": 0}))
	_check(AlmLoader.write_map(TEST_MAP, w, h, tiles, PackedByteArray(), PackedByteArray(), "smoke"),
		"map: тестовая карта записана")
	MapMeta.write(TEST_MAP, {"title": "Смоук", "zone": "mid", "w": w, "h": h})
	_check(FileAccess.file_exists(MapMeta.meta_path(TEST_MAP)), "map: meta.json записан")

	var s := StartSetup.new()
	s.mode = "map"
	s.map_path = TEST_MAP
	s.world_seed = 222
	var err := s.apply()
	_check(err == "", "map: apply без ошибок (%s)" % err)
	_check(Game.pending_map_path == TEST_MAP, "map: путь карты в pending_map_path")
	_check(Game.map_seed == StartSetup.identity_seed(TEST_MAP),
		"map: identity-сид стабилен (%d)" % Game.map_seed)
	_check(Game.map_seed != 0, "map: identity-сид не ноль")
	_check(Game.map_zone == "mid", "map: зона из меты (%s)" % Game.map_zone)
	_check(Game.map_sector != "", "map: сектор мира выбран (%s)" % Game.map_sector)

	# Путь переживает повторный identity (одинаковый между запусками/машинами)
	_check(StartSetup.identity_seed(TEST_MAP) == StartSetup.identity_seed(TEST_MAP),
		"map: identity-сид детерминирован")

	var bad := StartSetup.new()
	bad.mode = "map"
	bad.map_path = "user://maps/custom/does_not_exist.alm"
	_check(bad.apply() != "", "map: несуществующая карта -> ошибка")

	var summ := StartSetup.new()
	summ.mode = "seed"
	summ.world_seed = 4242
	summ.zone = "start"
	_check(summ.summary().contains("4242"), "summary: сид виден (%s)" % summ.summary())


func _test_meta() -> void:
	var meta := MapMeta.read(TEST_MAP)
	_check(str(meta.get("title", "")) == "Смоук", "meta: заголовок прочитан")
	_check(str(meta.get("zone", "")) == "mid", "meta: зона прочитана")
	# Неизвестная зона нормализуется в start, а не роняет игру.
	MapMeta.write(TEST_MAP, {"title": "Смоук", "zone": "faction", "w": 8, "h": 8})
	_check(MapMeta.zone_of(TEST_MAP) == "faction", "meta: зона faction")
	MapMeta.write(TEST_MAP, {"title": "Смоук", "zone": "wat", "w": 8, "h": 8})
	_check(MapMeta.zone_of(TEST_MAP) == "start", "meta: неизвестная зона -> start")
	var list := MapMeta.list()
	var found := false
	for raw in list:
		if str((raw as Dictionary).get("path", "")) == TEST_MAP:
			found = true
			_check(str((raw as Dictionary).get("title", "")) == "Смоук",
				"list: заголовок карты")
			break
	_check(found, "list: карта видна в списке (%d)" % list.size())
	_check(MapMeta.slug("Долина ветров") == "map", "slug: кириллица -> запасное имя")
	_check(MapMeta.slug("Valley of Winds") == "valley_of_winds",
		"slug: латиница (%s)" % MapMeta.slug("Valley of Winds"))


func _cleanup() -> void:
	for p in [TEST_MAP, MapMeta.meta_path(TEST_MAP)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Game.pending_map_path = ""
	Game.map_seed = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK start_setup_smoke")
		quit(0)
	else:
		print("RESULT: FAIL start_setup_smoke (%d)" % _fails.size())
		quit(1)
