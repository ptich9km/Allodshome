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
##
## 29.10: арт Аллодов удалён (ids 1..179), остались только наши здания 200..232 —
## у всех цельный спрайт 3×3 (whole_image=1), `full_height == tile_height`.
## Прежние проверки («есть выступ fh > th» и «есть вырожденный sel») держались
## на Аллодовских тайл-сетах и без них всегда падали бы.
func _test_db_has_full_height() -> void:
	var ids := StructureDB.ids()
	_check(ids.size() > 0, "в structure_db.json есть здания (%d)" % ids.size())
	var with_fh := 0
	var whole := 0
	var bad_sel := 0
	for id in ids:
		var def := StructureDB.get_by_id(int(id))
		var fh := int(def.get("full_height", 0))
		var th := int(def.get("tile_height", 1))
		if fh > 0:
			with_fh += 1
		if int(def.get("whole_image", 0)) == 1 and fh == th \
				and int(def.get("tile_width", 0)) == 3:
			whole += 1
		var sel: Variant = def.get("sel", null)
		if sel is Array and (sel as Array).size() == 4:
			if int((sel as Array)[0]) >= int((sel as Array)[1]) \
					or int((sel as Array)[2]) >= int((sel as Array)[3]):
				bad_sel += 1
	_check(with_fh == ids.size(), "full_height есть у всех зданий: %d из %d"
		% [with_fh, ids.size()])
	# Наши здания — цельный спрайт 3×3, без сетки кадров и без выступа крыши.
	_check(whole == ids.size(),
		"все здания — цельный спрайт 3×3 (whole_image, fh == th): %d из %d"
			% [whole, ids.size()])
	# Вырожденных sel больше нет; футпринт всё равно берём по tile_*, а не из sel.
	_check(bad_sel == 0, "вырожденных sel нет (%d)" % bad_sel)


## Геометрия города — по решению игрока: овал 17×17, зазор 2.
func _test_geometry_constants() -> void:
	_check(MapGenerator.CITY_RADIUS == 8,
		"радиус города 8 -> овал 17×17 (было 7 -> 15×15)")
	_check(MapGenerator.CITY_GAP == 2, "зазор между зданиями 2 клетки (была 1)")

	# full_height обязан доезжать из спеки в генератор (иначе vis_rows = 0).
	var spec := MapGenerator.new()._structure_spec("inn_s2")
	_check(not spec.is_empty(), "спека здания inn_s2 получена")
	if not spec.is_empty():
		_check(int(spec.get("fh", 0)) == 3 and int(spec.get("w", 0)) == 3
				and int(spec.get("h", 0)) == 3,
			"спека несёт футпринт и full_height 3×3: fh=%s w=%s h=%s"
				% [str(spec.get("fh")), str(spec.get("w")), str(spec.get("h"))])


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
	_test_guards_on_edges(base)

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

	# Зазор: между соседними прямоугольниками хотя бы city_gap свободных клеток.
	# Раньше проверка была `CITY_GAP - 1`, то есть >= 1 — она подстроилась под
	# фактический зашитый в коде зазор 1 и молча разрешала ему расти.
	# Теперь зазор реально берётся из конфига, и проверка требует честного значения.
	#
	# ИСКЛЮЧЕНИЕ (пакет B, 28.10): форпосты. У лагеря костёр стоит ВПЛОТНУЮ к
	# шатру — это его смысл, а не «город с домами». Городские правила зазора к
	# лагерю не применяются; проверка пересечений выше по-прежнему общая.
	var camp_ids := _camp_structure_ids()
	var too_close: Array = []
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var a2: Dictionary = boxes[i]
			var b2: Dictionary = boxes[j]
			if camp_ids.has(int(a2["id"])) or camp_ids.has(int(b2["id"])):
				continue
			var g := _gap_between(a2, b2)
			if g < MapGenerator.city_gap():
				too_close.append([a2["id"], b2["id"], g])
	_check(too_close.is_empty(),
		"между зданиями не меньше %d клеток, нарушений: %d %s"
			% [MapGenerator.city_gap(), too_close.size(), str(too_close.duplicate().slice(0, 3))])

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


## Guards stand at the edge of the town (player request 22.10: there were too
## many in the centre and they got under the hero's feet): every guard post is
## at least city_radius - 2 cells from the centre, the square (|dx|,|dy| <= 2)
## stays free for the captain, the head and the citizens.
func _test_guards_on_edges(base: String) -> void:
	var npcs := _read_sidecar(base + "/layout.npcs.json", "npcs")
	_check(npcs.size() > 0, "НПЦ города расставлены: %d" % npcs.size())
	var guards := 0
	var edge := MapGenerator.CITY_RADIUS - 2
	var too_close: Array = []
	for raw in npcs:
		var rec: Dictionary = raw
		# The captain is a guard by role but keeps the square: no city_x in his
		# record, so the edge rule does not cover him.
		if str(rec.get("role", "")) != "guard" or not rec.has("city_x"):
			continue
		guards += 1
		var gx := int(rec.get("x", 0))
		var gy := int(rec.get("y", 0))
		var cx := int(rec.get("city_x", gx))
		var cy := int(rec.get("city_y", gy))
		var d := maxi(absi(gx - cx), absi(gy - cy))
		if d < edge:
			too_close.append([gx, gy, d])
	_check(guards > 0, "стража на постах по краю: %d" % guards)
	_check(too_close.is_empty(),
		"стража стоит по краю города (>= %d клеток от центра), нарушений: %d %s"
			% [edge, too_close.size(), str(too_close.slice(0, 3))])


## Клеток между прямоугольниками; вдоль пересекающейся оси = 0.
func _gap_between(a: Dictionary, b: Dictionary) -> int:
	var dx := maxi(maxi(int(a["x0"]) - int(b["x1"]), int(b["x0"]) - int(a["x1"])), 0)
	var dy := maxi(maxi(int(a["y0"]) - int(b["y1"]), int(b["y0"]) - int(a["y1"])), 0)
	return maxi(dx, dy)


## id построек, которые ставит форпост (шатры фракций). Зазор «городского»
## типа к ним не применяется: лагерь стоит отдельно от овала города.
## 29.10: костра больше нет — у шатра стоит проп (MapGenerator.OUTPOST_PROP_ID).
func _camp_structure_ids() -> Dictionary:
	var out := {}
	for race in MapGenerator.OUTPOST_CAMPS:
		for folder in (MapGenerator.OUTPOST_CAMPS[race] as Array):
			if StructureDB.has(str(folder)):
				out[int(StructureDB.get_structure(str(folder)).get("id", 0))] = true
	return out


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
