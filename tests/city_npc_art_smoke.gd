## Целостность спрайтов городских NPC — а не спавн (это в npc_spawn_smoke).
##
## Жалоба игрока 10.10: «t0 с большего хорошо нарезан, во всех других у кого
## головы нет, у кого вся грудь дырявая, очень похоже что ты съел цвет
## металла и вместо него теперь дыры».
##
## Причина оказалась НЕ в маске атласа (она была чистая), а в сжатии:
## `fit_game` ужимал кроп ~143x252 в 35x62 методом NEAREST, то есть по X
## примерно в 4 раза, и NEAREST выбрасывал 3 пикселя из 4. Тонкая светлая
## деталь (блеск стали, цепь, коготь) исчезала целиком. Чем выше тир, тем
## больше металла — тем больше дыр (замер: t0 = 6..15, t3 = 68..220).
##
## Тест ловит именно это. Без него нарезка молча портила арт, и ни один
## другой тест этого не видел: спрайт оставался валидным PNG 52x64.
##
## Запуск:
##   godot --headless --path . --script res://tests/city_npc_art_smoke.gd

extends SceneTree

const UNITS_DIR := "res://assets/units/"
const OUT_W := 52
const OUT_H := 64
const FEET_PAD := 2

## Инвариант: число ОТДЕЛЬНЫХ дыр размером не меньше MIN_HOLE_PX.
##
## Два уточнения, оба пришли из замеров, а не из рассуждений:
##
## 1) Считать ВСЕ дыры нельзя: 1-2 px полости не видно на кадре 52x64 и
##    они появляются у любого снятия антиалиасового края. Замер по тирам:
##    худший кадр = одна настоящая полость (29/44/57 px — просвет между рукой
##    и посохом) плюс россыпь по 1 px: t0 = 7 дыр, t1 = 9, t2 = 15.
##    Порог 10 стоял, посчирав первые два тира, и на t2 давал 8 ложных
##    срабатываний на полностью чистых кадрах.
##
## 2) Считать ПЛОЩАДЬ дыр тоже нельзя: просвет между рукой и посохом —
##    законная одна крупная полость.
##
## Пересчёт порога на настоящей сломанной версии (93ac9ebb, NEAREST-альфа),
## при отсчёте дыр >= 3 px:
##   починено: максимум 7 дыр в кадре
##   сломано:  максимум 20 дыр в кадре, 25 кадров из 256 выше 9
##
## Порог 9, а не 6, и это СЛЕДСТВИЕ ЗАМЕРА, а не подгонка: снятие края даёт
## мелкие замкнутые щели в деталях доспеха, и их количество закономерно растёт
## с тиром. Замер максимума по тирам после перегенерации всех четырёх:
##   t0 = 3, t1 = 3, t2 = 4, t3 = 7 дыр >= 3 px
## Порог 6 стоял, посчирав первые три тира, и дал 4 ложных срабатывания на
## чистых кадрах t3.
##
## ЦЕНА ВЫБОРА, чтобы её не потерять: чувствительность снизилась с 41/256
## (порог 6) до 25/256 (порог 9). Замер по метрике «площадь полостей 3..39 px
## как доля силуэта» разделяет лучше и не зависит от детализации тира:
## починено максимум 5.3%, сломано 19.5% — если сторож станет шуметь, менять
## надо именно на неё, а не поднимать порог ещё выше.
const MIN_HOLE_PX := 3
const MAX_HOLE_COMPONENTS := 9

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
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(UNITS_DIR + "units_db.json"))
	if not (parsed is Dictionary):
		_check(false, "units_db.json читается")
		_report()
		return
	var sets: Array = (parsed as Dictionary).keys()
	var city: Array = []
	for s in sets:
		var key := str(s)
		if key.begins_with("city_"):
			# Путь берём из поля folder ("city_necro_mage/t0"), а не собираем
			# из имени ключа: у ключей масть тира уже "/tN", и склейка дала
			# бы "t0/t0" — то есть тест проверял бы несуществующие файлы.
			city.append((parsed as Dictionary)[key].get("folder", ""))
	_check(city.size() > 0, "найдены городские наборы (%d)" % city.size())

	for folder in city:
		_test_set(str(folder))

	_report()


func _test_set(folder: String) -> void:
	# folder = "city_<раса>_<роль>/t<тир>" — ровно то, что записано в units_db.
	for d in range(1, 9):
		var sp := UNITS_DIR + folder + "/sprites-%03d.png" % d
		if not FileAccess.file_exists(sp):
			_check(false, "кадр на месте: %s" % sp)
			continue
		var img := Image.load_from_file(sp)
		if img == null:
			_check(false, "кадр читается: %s" % sp)
			continue
		if img.get_width() != OUT_W or img.get_height() != OUT_H:
			_check(false, "%s = %dx%d" % [sp, img.get_width(), img.get_height()])
			continue
		_test_sprite(img, sp)


func _test_sprite(img: Image, sp: String) -> void:
	var mask := _alpha_mask(img)
	var area := 0
	for v in mask:
		if v == 1:
			area += 1
	_check(area > OUT_W * OUT_H / 6,
		"%s силуэт не пустой (%d px)" % [sp.get_file(), area])

	var comps := _hole_components(mask)
	var counted := 0
	for c in comps:
		if c >= MIN_HOLE_PX:
			counted += 1
	_check(counted <= MAX_HOLE_COMPONENTS,
		"%s нет крапины дыр по телу (%d отдельных дыр >= %d px, допустимо <= %d)"
			% [sp.get_file(), counted, MIN_HOLE_PX, MAX_HOLE_COMPONENTS])

	# Светлая шахматка атласа не должна попасть в кадр: она бесцветная и
	# очень светлая, поэтому любая светлая полупрозрачная кромка — мусор.
	var light_partial := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.02 and c.a < 0.98 and maxf(c.r, maxf(c.g, c.b)) > 0.78:
				light_partial += 1
	_check(light_partial <= 12,
		"%s нет светлой каймы шахматки (%d px)" % [sp.get_file(), light_partial])

	# Фигура стоит на земле и не обрезана снизу. Замер по всем 256 кадрам:
	# низ силуэта везде на строке 59 (canvas 64, FEETS_PAD=2 — две нижние
	# строки остаются под ногами плюс кроп может не доставать до края).
	var last := -1
	for y2 in range(OUT_H - 1, -1, -1):
		for x2 in OUT_W:
			if mask[y2 * OUT_W + x2] == 1:
				last = y2
				break
		if last >= 0:
			break
	_check(last >= OUT_H - FEET_PAD - 4 and last < OUT_H,
		"%s низ силуэта на земле (строка %d)" % [sp.get_file(), last])


## Плоская маска 1 = непрозрачно, построчно (y * OUT_W + x).
func _alpha_mask(img: Image) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(OUT_W * OUT_H)
	for y in img.get_height():
		for x in img.get_width():
			mask[y * OUT_W + x] = 1 if img.get_pixel(x, y).a >= 0.5 else 0
	return mask


## Размеры отдельных внутренних дыр (прозрачные области, НЕ связанные с краем).
## Промежуток между рукой и посохом связан с краем, поэтому не считается.
func _hole_components(mask: PackedByteArray) -> PackedInt32Array:
	var free := PackedByteArray()
	free.resize(OUT_W * OUT_H)
	for i in mask.size():
		free[i] = 1 if mask[i] == 0 else 0
	var seen := PackedByteArray()
	seen.resize(OUT_W * OUT_H)
	var stack: Array[Vector2i] = []
	for x in OUT_W:
		for y in [0, OUT_H - 1]:
			var i2: int = int(y) * OUT_W + x
			if free[i2] == 1 and seen[i2] == 0:
				seen[i2] = 1
				stack.append(Vector2i(x, int(y)))
	for y2 in OUT_H:
		for x2 in [0, OUT_W - 1]:
			var j: int = int(y2) * OUT_W + int(x2)
			if free[j] == 1 and seen[j] == 0:
				seen[j] = 1
				stack.append(Vector2i(int(x2), int(y2)))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q := Vector2i(p.x + d.x, p.y + d.y)
			if q.x < 0 or q.y < 0 or q.x >= OUT_W or q.y >= OUT_H:
				continue
			var k: int = q.y * OUT_W + q.x
			if free[k] == 1 and seen[k] == 0:
				seen[k] = 1
				stack.append(q)
	var sizes := PackedInt32Array()
	var done := PackedByteArray()
	done.resize(OUT_W * OUT_H)
	for y3 in OUT_H:
		for x3 in OUT_W:
			var s: int = y3 * OUT_W + x3
			if free[s] == 0 or done[s] == 1:
				continue
			var n := 0
			var st: Array[Vector2i] = [Vector2i(x3, y3)]
			done[s] = 1
			while not st.is_empty():
				var c: Vector2i = st.pop_back()
				n += 1
				for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var r := Vector2i(c.x + d2.x, c.y + d2.y)
					if r.x < 0 or r.y < 0 or r.x >= OUT_W or r.y >= OUT_H:
						continue
					var m: int = r.y * OUT_W + r.x
					if free[m] == 1 and done[m] == 0:
						done[m] = 1
						st.append(r)
			sizes.append(n)
	return sizes


func _report() -> void:
	print("\n==== ИТОГ ====")
	if _fails.is_empty():
		print("RESULT: OK city_npc_art_smoke (проверок: %d, провалов: 0)" % _checks)
	else:
		print("RESULT: FAIL city_npc_art_smoke (проверок: %d, провалов: %d)"
			% [_checks, _fails.size()])
		for f in _fails.slice(0, 20):
			print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)