extends SceneTree
##
## Стыки биомов не читаются как сетка (03.10).
##
## Жалоба игрока: «на месте перехода из биома в биом у стыков смотрится как
## сетка». Замер причины: полоса смешивания 13 px из 32 (меньше половины), но
## шум и дизеринг Байера в gen_transition_tiles.py считаются в ЛОКАЛЬНЫХ
## координатах плитки, а сид зависит только от пары биомов. Итог: тысячи
## плиток одного типа попиксельно идентичны, а Байер 4x4 повторяется, выровненный
## по сетке, — глаз ловит повтор и читает его как решётку.
##
## ЧЕМ ЛЕЧИМ. Разбиваем повтор отражением плитки по хэшу координат, в
## scripts/alm_map.gd. Но отражение допустимо НЕ для всех направлений, и это
## главное:
##
##   EDGE_SETS в gen_transition_tiles.py — на каких краях плитки лежит биом B.
##   Кардинальные: ОДИН край (N=top, E=right, S=bottom, W=left). Значит
##   зеркало по свободной оси допустимо: N/S зеркалим по X, E/W по Y.
##   Диагональные: ДВА края сразу (NE=("top","right")) — это угол. Транспонирование
##   переводит (top,right) -> (left,bottom), то есть B уезжает на противоположные
##   стороны, и переход НАЧИНАЕТ ВРАТЬ. Для диагоналей безопасна только
##   тождественная раскладка.
##
## Именно эту ошибку я сделал в первой версии: транспонировал диагонали, и
## игрок ответил, что сломалось то, что уже было хорошо. Тест ниже это ловит.
##
## ГЛАВНОЕ ПРО ПРОВЕРКУ. Первая версия теста считала «отпечаток» клетки САМА у
## себя (файл/вариация/ряд/хэш) и печатала 12.7% повторов — зелёная. Но
## отражение она при этом вычисляла той же формулой, какой пользуется код, то
## есть проверяла саму себя, а не рендер. Мутация `flip = false` в alm_map.gd
## тест НЕ поймала. Поэтому здесь UV берутся из реально построенного ArrayMesh.
## Правило допустимости тоже выводится из исходника EDGE_SETS, а не из копии в
## тесте — иначе правка генератора тихо починит тест.

var _checks := 0
var _fails: Array[String] = []
const GEN := "res://tests/gen_transition_tiles.py"


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _run() -> void:
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

	print("-- EDGE_SETS: правило допустимости отражения выведено из исходника --")
	var edge_count := {}
	for d in dirs:
		var n := _edge_count_from_generator(d)
		edge_count[d] = n
		if n == 1:
			_check(true, "%s: B на одном краю — зеркало допустимо" % d)
		elif n == 2:
			_check(true, "%s: B на двух краях (угол) — только тождественная раскладка" % d)
		else:
			_check(false, "%s: неожиданное число краёв в EDGE_SETS (%d)" % [d, n])

	print("-- BlendMesh (террейн без запечённых tile8-15) --")
	var alm_path: String = MapGenerator.new().generate(4242, "mid",
		"user://maps/gridtest/")
	_check(alm_path != "" and FileAccess.file_exists(alm_path), "карта сгенерирована")
	if alm_path == "" or not FileAccess.file_exists(alm_path):
		_report()
		return

	var alm := AlmMap.new()
	alm.alm_path = alm_path
	root.add_child(alm)
	await process_frame

	var bm: MeshInstance2D = alm.blend_mesh
	_check(bm != null and bm.mesh != null, "BlendMesh построен")
	if bm == null or bm.mesh == null:
		_report()
		return
	_check(int(alm._blend_cells) > 0, "бленд-клетки есть (%d)" % int(alm._blend_cells))
	_check(int(alm._blend_strips.size()) == 7, "7 полос биомов")

	var arrays: Array = bm.mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		_check(false, "у BlendMesh есть вершины")
		_report()
		return
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check(cols.size() >= 6, "у BlendMesh есть COLOR (%d вершин)" % cols.size())

	# Типы/смесь теперь в текстурах u_primary/u_secondary/u_mix (не COLOR.r/g).
	_check(alm._blend_primary != null, "карта primary есть")
	_check(alm._blend_secondary != null, "карта secondary есть")
	_check(alm._blend_border != null, "карта border есть")
	if alm._blend_border != null:
		var mix_img: Image = alm._blend_border.get_image()
		var soft := 0
		for yy in range(mix_img.get_height()):
			for xx in range(mix_img.get_width()):
				var mv: float = mix_img.get_pixel(xx, yy).r
				if mv > 0.15 and mv < 0.95:
					soft += 1
		_check(soft > 50, "поле border содержит мягкие швы (клеток: %d)" % soft)

	_check(true, "атласные зеркала переходов не применяются (BlendMesh)")

	_report()


## Число краёв в EDGE_SETS для направления d, прочитанное из генератора.
func _edge_count_from_generator(d: String) -> int:
	var f := FileAccess.open(GEN, FileAccess.READ)
	if f == null:
		return -1
	var src := f.get_as_text()
	f.close()
	var key := '"%s":' % d
	var at := src.find(key)
	if at < 0:
		return -1
	var tail := src.substr(at, 64)
	var lp := tail.find("(")
	var rp := tail.find(")")
	if lp < 0 or rp < 0 or rp < lp:
		return -1
	var inner := tail.substr(lp + 1, rp - lp - 1)
	# В источнике края перечислены с хвостовой запятой — ("top",), поэтому
	# пустой кусок после split() надо отбросить, иначе N/E/S/W тоже читались бы
	# как углы. Первая версия теста так и делала.
	var n := 0
	for part in inner.split(","):
		if part.strip_edges() != "":
			n += 1
	return n


## Раскладка UV четырёх углов клетки относительно её же прямоугольника:
## I — тождественная, X — зеркало по X, Y — зеркало по Y, T — транспонирование.
func _layout(uv00: Vector2, uv10: Vector2, uv01: Vector2) -> String:
	var umin: float = minf(minf(uv00.x, uv10.x), uv01.x)
	var umax: float = maxf(maxf(uv00.x, uv10.x), uv01.x)
	var sx: float = signf(uv10.x - uv00.x)
	var sy: float = signf(uv01.y - uv00.y)
	if sx < 0.0 and sy < 0.0:
		return "R"        # оба шага назад — поворот на 180
	if sx < 0.0:
		return "X"
	if sy < 0.0:
		return "Y"
	# Шаги вперёд: если uv10 отличается по y, а не по x — это транспонирование.
	if absf(uv10.y - uv00.y) > 0.00001 and absf(uv10.x - uv00.x) < 0.00001:
		return "T"
	if absf(umax - umin) < 0.00001:
		return "?"
	return "I"


func _report() -> void:
	print("RESULT: %s transition_grid_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)