## Магента не должна попадать в готовые seedream-ассеты (здания, природа, пропы).
##
## Жалоба игрока 10.10: «магента не вырезана на деревьях, на магазине, на
## таверне». Замер: остаточная магента в 36 файлах, до 6.9% (bush_thorn).
##
## Причина - тот же класс, что с карманами шахматки у городских НПЦ:
## `cut_bg` резал фон ЗАЛИВКОЙ ОТ КРАЁВ, поэтому магента, окружённая
## объектом (просвет между ветвями, полость под кроной, пятно в кроне),
## до края не доходила и оставалась непрозрачной. Слой `kill_halo` её не
## спасал: он чистил только магенту вплотную к уже прозрачным.
##
## Магента в арте не встречается - её и выбрали фоном именно поэтому, - так
## что фон определяется ЦВЕТОМ, а не связностью. Тест сторожит результат:
## генераторы починены, но исходников (import/_stage*) в репозитории нет,
## поэтому чинить пришлось готовые файлы, и повод вернуться к ошибке реальный.
##
## Проверяется оттенок, а не яркость: у магенты r-g И b-g высокие
## одновременно, у листвы/дерева/черепицы только один из двух.
##
## Запуск:
##   godot --headless --path . --script res://tests/seedream_art_smoke.gd

extends SceneTree

## Допустимая остаточная магента. Замер ДО починки: до 6.9% (bush_thorn),
## 4.6% (tree_willow), 4.5% (tree_birch). ПОСЛЕ починки: максимум 0.55%,
## большинство файлов чистые. Порог 1.5% - с запасом на иву, у которой
## нити тонкие и полупрозрачные и часть смеси неизбежно остаётся.
const MAX_MAGENTA_PCT := 1.5

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _run() -> void:
	var files: Array[String] = []
	_scan_dir("res://assets/map-objects/", files)
	_scan_seedream_structures(files)
	_check(files.size() > 0, "найдены seedream-ассеты (%d)" % files.size())

	for f in files:
		if not FileAccess.file_exists(f):
			_check(false, "файл на месте: %s" % f)
			continue
		var img := Image.load_from_file(f)
		if img == null:
			_check(false, "файл читается: %s" % f)
			continue
		_test(f, img)

	_report()


## Только папки, которые генератор реально использует (см. TREE_* в
## map_generator.gd и структуры 200+ в structure_db.json). Старые аллодовские
## папки в assets/structures не трогаем - они к сегодняшнему контенту
## не относятся и вырезались другим пайплайном.
func _scan_dir(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not name.begins_with("_"):
				_scan_dir(dir_path.path_join(name), out)
		elif name.ends_with(".png") and not name.begins_with("_"):
			out.append(dir_path.path_join(name))
		name = d.get_next()
	d.list_dir_end()


func _scan_seedream_structures(out: Array[String]) -> void:
	var db_path := "res://assets/structures/structure_db.json"
	if not FileAccess.file_exists(db_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(db_path))
	if not (parsed is Dictionary):
		return
	for key in (parsed as Dictionary).keys():
		var entry: Dictionary = (parsed as Dictionary)[key]
		var folder := str(entry.get("folder", ""))
		if folder == "":
			continue
		# seedream-здания получили id >= 200 (см. extract_seedream_buildings.py)
		if int(key) < 200:
			continue
		var p := "res://assets/structures/%s/house-001.png" % folder
		if FileAccess.file_exists(p):
			out.append(p)


func _test(path: String, img: Image) -> void:
	if img.get_width() * img.get_height() == 0:
		_check(false, "%s не пустой" % path)
		return
	var total := img.get_width() * img.get_height()
	var mag := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.15:
				continue
			# маджента: R и B заметно выше G одновременно
			if c.r - c.g > 0.18 and c.b - c.g > 0.16:
				mag += 1
	var pct := 100.0 * float(mag) / float(total)
	_check(pct <= MAX_MAGENTA_PCT,
		"%s без магенты (%.2f%%, допустимо <= %.2f%%)"
			% [path.get_file(), pct, MAX_MAGENTA_PCT])


func _report() -> void:
	print("\n==== ИТОГ ====")
	if _fails.is_empty():
		print("RESULT: OK seedream_art_smoke (проверок: %d, провалов: 0)" % _checks)
	else:
		print("RESULT: FAIL seedream_art_smoke (проверок: %d, провалов: %d)"
			% [_checks, _fails.size()])
		for f in _fails.slice(0, 20):
			print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)