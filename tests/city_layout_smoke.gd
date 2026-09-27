extends SceneTree
## Headless-проверка раскладки города: здания не наезжают друг на друга.
##
## Три причины, по которым дома наезжали:
##  1. `_structure_spec()` не возвращал `fh` (full_height) из structure_db.json,
##     поэтому vis_rows всегда был 0 и выступ здания (крыша/башня) НЕ
##     резервировался — соседние крыши перекрывались;
##  2. овал города был 15×15 (радиус 7), и здания на 4-6 клеток не помещались
##     в кольцо — вытеснялись наружу и налезали на другие;
##  3. зазор между зданиями был 1 клетка — дома стояли вплотную.
##
## Запуск:
##   godot --headless --path . --script res://tests/city_layout_smoke.gd

const TILE := 32

var _fails: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("CITY: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	_test_db_has_full_height()
	_test_geometry_constants()
	await _test_no_overlap()
	_finish()


## full_height реально приходит из базы — иначе визуальный выступ не резервируется.
func _test_db_has_full_height() -> void:
	var with_fh := 0
	var with_over := 0
	for id in StructureDB.ids():
		var def := StructureDB.get_by_id(int(id))
		var fh := int(def.get("full_height", 0))
		var th := int(def.get("tile_height", 1))
		if fh > 0:
			with_fh += 1
			if fh > th:
				with_over += 1
	_check(with_fh > 0, "в structure_db.json full_height есть у %d зданий" % with_fh)
	_check(with_over > 0,
		"есть здания с выступом выше футпринта (full_height > tile_height): %d"
			% with_over)

	# `sel` в базе самопротиворечив, поэтому в футпринте не используется.
	var bad_sel := 0
	for id2 in StructureDB.ids():
		var d2 := StructureDB.get_by_id(int(id2))
		var sel: Variant = d2.get("sel", null)
		if sel is Array and (sel as Array).size() == 4:
			if int((sel as Array)[0]) >= int((sel as Array)[1]) \
					or int((sel as Array)[2]) >= int((sel as Array)[3]):
				bad_sel += 1
	_check(bad_sel > 0,
		"у %d зданий sel вырожден (x0>=x1) — поэтому футпринт берём по tile_*/full_height"
			% bad_sel)


## Геометрия города — по решению игрока: овал 17×17, зазор 2.
func _test_geometry_constants() -> void:
	_check(MapGenerator.CITY_RADIUS == 8,
		"радиус города 8 -> овал 17×17 (было 7 -> 15×15)")
	_check(MapGenerator.CITY_GAP == 2, "зазор между зданиями 2 клетки (была 1)")

	# full_height обязан доезжать из спеки в генератор (иначе vis_rows = 0).
	var spec := MapGenerator.new()._structure_spec("druidinn2")
	_check(not spec.is_empty(), "спека здания druidinn2 получена")
	if not spec.is_empty():
		_check(int(spec.get("fh", 0)) > int(spec.get("h", 0)),
			"спека несёт full_height: fh=%s > h=%s (без fh выступ не резервировался)"
				% [str(spec.get("fh")), str(spec.get("h"))])


## Ставим здания и проверяем, что полные визуальные прямоугольники
## (футпринт + выступ вверх) не пересекаются и не слипаются.
func _test_no_overlap() -> void:
	var gen := MapGenerator.new()
	var base := "user://city_layout/"
	var alm_path: String = gen.generate(4242, "mid", base, "layout")
	_check(alm_path != "" and FileAccess.file_exists(alm_path),
		"карта сгенерирована: %s" % alm_path)

	var structures := _read_sidecar(base + "/layout.structures.json", "structures")
	_check(structures.size() > 0, "здания расставлены: %d" % structures.size())
	if structures.is_empty():
		_cleanup(base)
		return

	# Полные прямоугольники в клетках: x..x+w-1, y-(fh-h)..y+(h-1).
	var boxes: Array = []
	for s in structures:
		var st: Dictionary = s
		var def := StructureDB.get_by_id(int(st.get("type_id", 0)))
		if def.is_empty():
			continue
		var w := int(def.get("tile_width", 1))
		var h := int(def.get("tile_height", 1))
		var fh: int = maxi(h, int(def.get("full_height", h)))
		var vis := fh - h
		boxes.append({
			"x0": int(st["x"]), "x1": int(st["x"]) + w - 1,
			"y0": int(st["y"]) - vis, "y1": int(st["y"]) + h - 1,
			"id": int(st.get("type_id", 0)),
		})
	_check(boxes.size() > 0, "здания со шкалой из базы: %d" % boxes.size())

	var overlaps: Array = []
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var a: Dictionary = boxes[i]
			var b: Dictionary = boxes[j]
			if a["x0"] <= b["x1"] and b["x0"] <= a["x1"] \
					and a["y0"] <= b["y1"] and b["y0"] <= a["y1"]:
				overlaps.append([a["id"], b["id"]])
	_check(overlaps.is_empty(),
		"здания не пересекаются (включая выступ вверх), пар: %d %s"
			% [overlaps.size(), str(overlaps.duplicate().slice(0, 3))])

	# Зазор: между соседними прямоугольниками хотя бы CITY_GAP-1 свободных клеток.
	var too_close: Array = []
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var a2: Dictionary = boxes[i]
			var b2: Dictionary = boxes[j]
			var g := _gap_between(a2, b2)
			if g < MapGenerator.CITY_GAP - 1:
				too_close.append([a2["id"], b2["id"], g])
	_check(too_close.is_empty(),
		"между зданиями не меньше %d клеток, нарушений: %d %s"
			% [MapGenerator.CITY_GAP - 1, too_close.size(), str(too_close.duplicate().slice(0, 3))])

	# Все функциональные здания на месте (магазин/таверна/кузница/школа/алхимия).
	var usable := 0
	for b3 in boxes:
		for id3 in StructureDB.ids():
			var d3 := StructureDB.get_by_id(int(id3))
			if int(d3.get("id", 0)) == int((b3 as Dictionary)["id"]) \
					and bool(d3.get("usable", false)):
				usable += 1
				break
	_check(usable >= 5,
		"функциональных зданий (usable) поставлено: %d" % usable)

	_cleanup(base)


## Клеток между прямоугольниками; вдоль пересекающейся оси = 0.
func _gap_between(a: Dictionary, b: Dictionary) -> int:
	var dx := maxi(maxi(int(a["x0"]) - int(b["x1"]), int(b["x0"]) - int(a["x1"])), 0)
	var dy := maxi(maxi(int(a["y0"]) - int(b["y1"]), int(b["y0"]) - int(a["y1"])), 0)
	return maxi(dx, dy)


func _read_sidecar(path: String, key: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var v: Variant = (parsed as Dictionary).get(key, [])
		return v if v is Array else []
	return []


func _cleanup(base: String) -> void:
	for suffix in [".alm", ".structures.json", ".npcs.json", ".herbs.json",
			".spawn.json", ".portal.json"]:
		var p: String = base + "/layout" + str(suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _finish() -> void:
	if _fails.is_empty():
		print("CITY: RESULT: OK")
	else:
		print("CITY: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
