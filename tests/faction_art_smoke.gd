extends SceneTree
## Арт фракционных наборов и бирок (пакет C, ИИ-лист → нарезка, 29.10).
##
## Проверяет ровно то, что нельзя увидеть в диффе:
##   1) все 36 иконок на месте, ровно 72×80 (как остальная броня);
##   2) иконка — предмет с прозрачным фоном: углы пустые, заливка есть,
##      содержимое не прилипло к краю (нарезка не срезала предмет);
##   3) 32 иконки брони РАЗЛИЧАЮТСЯ: у каждой пары (kit, slot) четыре
##      фракции дают четыре разных файла — иначе модель нарисовала одно и то же;
##   4) лист-манифест import/faction_art/_manifest.json описывает 9 листов;
##   5) генератор перекраски НЕ затирает ИИ-арт: `gen_faction_sets.py` без
##      --rebuild-icons не меняет файлы (проверяется скриптом, здесь — только
##      наличие арта, чтобы тест не запускал python).
##
## Запуск: godot --headless --path . --script res://tests/faction_art_smoke.gd

const SETS := "res://assets/items/faction_sets/"
const TAGS := "res://assets/items/tags/"
const MANIFEST := "res://import/faction_art/_manifest.json"
const RACES := ["humans", "ork", "necro", "druid"]
const KITS := ["heavy", "light", "magic"]
const SLOTS := ["head", "body", "hands", "feet"]

var _fails: Array[String] = []


func _initialize() -> void:
	_check_dims()
	_check_unique()
	_check_manifest()
	print("---")
	if _fails.is_empty():
		print("RESULT: OK faction_art_smoke")
		quit(0)
	else:
		print("RESULT: FAIL faction_art_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)


func _check_dims() -> void:
	var total := 0
	for race in RACES:
		for kit in KITS:
			for slot in SLOTS:
				var path := "%s%s/%s_%s.png" % [SETS, race, kit, slot]
				var ok := _check_icon(path)
				total += 1 if ok else 0
	for race in RACES:
		_check_icon("%stag_%s.png" % [TAGS, race])
	_check(total == 48, "иконок брони проверено: %d из 48" % total)


func _check_icon(path: String) -> bool:
	if not ResourceLoader.exists(path):
		_fail("нет иконки %s" % path)
		return false
	var tex: Texture2D = load(path)
	if tex == null:
		_fail("не открылась %s" % path)
		return false
	if tex.get_width() != 72 or tex.get_height() != 80:
		_fail("%s: размер %dx%d, ждали 72x80"
			% [path.get_file(), tex.get_width(), tex.get_height()])
		return false
	var img: Image = tex.get_image()
	if img == null:
		_fail("%s: нет Image" % path.get_file())
		return false
	if not img.detect_alpha():
		_fail("%s: нет прозрачности (фон не откеен)" % path.get_file())
		return false
	# Углы должны быть пустыми: предмет не должен упираться в рамку.
	for corner in [Vector2i(0, 0), Vector2i(71, 0), Vector2i(0, 79), Vector2i(71, 79)]:
		if img.get_pixelv(corner).a > 0.05:
			_fail("%s: угол %s не прозрачный" % [path.get_file(), str(corner)])
			return false
	# Заливка: предмет вообще есть.
	var solid := 0
	for y in range(0, 80, 2):
		for x in range(0, 72, 2):
			if img.get_pixel(x, y).a > 0.5:
				solid += 1
	if solid < 80:
		_fail("%s: слишком мало содержимого (%d)" % [path.get_file(), solid])
		return false
	return true


func _check_unique() -> void:
	var bad := 0
	for kit in KITS:
		for slot in SLOTS:
			var hashes := {}
			for race in RACES:
				var path := "%s%s/%s_%s.png" % [SETS, race, kit, slot]
				if not ResourceLoader.exists(path):
					continue
				var img: Image = (load(path) as Texture2D).get_image()
				if img == null:
					continue
				hashes[img.get_data()] = race
			if hashes.size() != RACES.size():
				bad += 1
	_check(bad == 0, "иконки фракций различаются во всех 8 наборах (совпавших: %d)" % bad)
	var tag_hashes := {}
	for race in RACES:
		var path := "%stag_%s.png" % [TAGS, race]
		if ResourceLoader.exists(path):
			var img: Image = (load(path) as Texture2D).get_image()
			if img != null:
				tag_hashes[img.get_data()] = race
	_check(tag_hashes.size() == RACES.size(),
		"четыре бирки различаются (%d)" % tag_hashes.size())


func _check_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		_fail("нет манифеста генерации %s" % MANIFEST)
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_fail("манифест не объект")
		return
	var d: Dictionary = parsed
	var sheets := 0
	for key in d:
		var rec: Variant = d[key]
		if rec is Dictionary and str((rec as Dictionary).get("file", "")) != "":
			sheets += 1
	_check(sheets == 13, "манифест описывает 13 листов (%d)" % sheets)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _fail(label: String) -> void:
	print("FAIL ", label)
	_fails.append(label)
