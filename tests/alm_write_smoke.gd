extends SceneTree
## Полная запись .alm с нуля (AlmLoader.write_map / build_map_bytes).
##
## Раньше writer был только внутри MapGenerator, поэтому редактор не мог
## сохранить НОВУЮ карту в .alm — только патчить тайлы открытой. Теперь
## генератор и редактор зовут один и тот же AlmLoader.
##
## Запуск: godot --headless --path . --script res://tests/alm_write_smoke.gd

const W := 16
const H := 12
const PATH := "user://alm_write_smoke.alm"

var _fails: Array[String] = []


func _init() -> void:
	var w := W
	var h := H
	var n := w * h
	var tiles := PackedInt32Array()
	tiles.resize(n)
	var heights := PackedByteArray()
	heights.resize(n)
	var obstacles := PackedByteArray()
	obstacles.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in range(n):
		tiles[i] = AlmLoader.tile_from_spec({"file": 1 + (i % 5), "variant": i % 6, "row": i % 4})
		heights[i] = i % 100
		obstacles[i] = 193 if i % 17 == 0 else 0

	var bytes := AlmLoader.build_map_bytes(w, h, tiles, heights, obstacles, "smoke")
	_check(not bytes.is_empty(), "build_map_bytes вернул данные")
	_check(AlmLoader.write_map(PATH, w, h, tiles, heights, obstacles, "smoke"),
		"write_map записал файл")
	_check(FileAccess.file_exists(PATH), "файл .alm существует")

	var data := AlmLoader.load_map(PATH)
	_check(int(data.get("width", 0)) == w, "ширина прочиталась: %s" % data.get("width"))
	_check(int(data.get("height", 0)) == h, "высота прочиталась: %s" % data.get("height"))
	var t2: PackedInt32Array = data.get("tiles", PackedInt32Array())
	_check(t2.size() == n, "тайлов %d (ждали %d)" % [t2.size(), n])
	var same_tiles := 0
	for i in range(n):
		if t2[i] == tiles[i]:
			same_tiles += 1
	_check(same_tiles == n, "все тайлы совпали (%d/%d)" % [same_tiles, n])

	var h2: PackedByteArray = data.get("heights", PackedByteArray())
	var same_h := 0
	for i in range(n):
		if i < h2.size() and h2[i] == heights[i]:
			same_h += 1
	_check(same_h == n, "все высоты совпали (%d/%d)" % [same_h, n])

	var o2: PackedByteArray = data.get("obstacles", PackedByteArray())
	var same_o := 0
	for i in range(n):
		if i < o2.size() and o2[i] == obstacles[i]:
			same_o += 1
	_check(same_o == n, "все препятствия совпали (%d/%d)" % [same_o, n])

	# Границы: писатель обязан отказать, а не записать битую карту.
	var bad := AlmLoader.build_map_bytes(w, h, PackedInt32Array(), heights, obstacles)
	_check(bad.is_empty(), "несовпадающий размер тайлов -> пустые данные")

	# Генератор обязан давать тот же .alm, что и раньше (writer общий, не копия).
	var gen := MapGenerator.new()
	var map_path: String = gen.generate(9091, "mid", "user://alm_write_smoke_maps/", "alm_writer")
	_check(map_path != "" and FileAccess.file_exists(map_path), "генератор записал карту")
	var gd := AlmLoader.load_map(map_path)
	_check(int(gd.get("width", 0)) > 0, "карта генератора читается")
	_check((gd.get("tiles", PackedInt32Array()) as PackedInt32Array).size()
		== int(gd.get("width", 0)) * int(gd.get("height", 0)),
		"тайлы карты генератора совпадают с W*H")
	_cleanup(map_path)

	_report()


func _cleanup(gen_path: String) -> void:
	for p in [PATH, gen_path]:
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var base := gen_path.get_basename()
	for suffix in [".spawn.json", ".portal.json", ".structures.json", ".npcs.json",
			".herbs.json", ".outposts.json", ".nowalk.json", ".allowwalk.json"]:
		if FileAccess.file_exists(base + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(base + suffix))


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK alm_write_smoke")
		quit(0)
	else:
		print("RESULT: FAIL alm_write_smoke (%d)" % _fails.size())
		quit(1)
