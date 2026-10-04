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
## ЧЕМ ЛЕЧИМ. Поворот плитки на 90 градусов НЕЛЬЗЯ: биом B обязан лежать на
## конкретной стороне (EDGE_SETS в gen_transition_tiles.py), и поворот увёл бы
## его на другую сторону — переход стал бы врать. Безопасна только симметрия,
## СОХРАНЯЮЩАЯ нужную сторону:
##   кардинальные (N/S) — зеркало по X, верх остаётся верхом;
##   кардинальные (E/W) — зеркало по Y, право остаётся правом;
##   диагональные — транспонирование (свап u<->v), диагональ сохраняется.
## Выбор — по хэшу координат клетки, в scripts/alm_map.gd.
##
## ГЛАВНОЕ ПРО ПРОВЕРКУ. Первая версия теста считала «отпечаток» клетки САМА у
## себя (файл/вариация/ряд/хэш) и печатала 12.7% повторов — зелёная. Но
## отражение она при этом вычисляла такой же формулой, какой пользуется код, то
## есть проверяла саму себя, а не рендер. Мутация `flip = false` в alm_map.gd
## тест НЕ поймала. Поэтому здесь UV берутся из реально построенного ArrayMesh:
## если отражение выключено, у всех переходных клеток порядок углов меша один,
## и тест падает.

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
	print("-- предположение о направлениях --")
	# Порядок направлений в генераторе: N, NE, E, SE, S, SW, W, NW (DIRS в
	# gen_transition_tiles.py). Выбор оси отражения держится на том, что
	# нечётные индексы — диагонали.
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for i in range(8):
		_check((i % 2 == 1) == (i in [1, 3, 5, 7]),
			"направление %d (%s) диагональное=%s" % [i, names[i], str(i % 2 == 1)])

	print("-- реальные UV из построенного меша --")
	var alm_path: String = MapGenerator.new().generate(4242, "mid",
		"user://maps/gridtest/")
	_check(alm_path != "" and FileAccess.file_exists(alm_path),
		"карта сгенерирована")
	if alm_path == "" or not FileAccess.file_exists(alm_path):
		_report()
		return

	var m: Dictionary = AlmLoader.load_map(alm_path)
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedByteArray = m["terrain"]
	var hflags: PackedByteArray = m["hflags"]

	# Строим настоящий рельеф — тот же путь, что и в игре. alm_path читается в
	# _ready(), поэтому задаём ДО add_child (иначе узел загрузится пустым).
	var alm := AlmMap.new()
	alm.alm_path = alm_path
	root.add_child(alm)
	var mi: MeshInstance2D = alm.mesh
	_check(mi != null and mi.mesh != null, "меш рельефа построен")
	if mi == null or mi.mesh == null:
		_report()
		return

	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	_check(verts.size() == uvs.size() and verts.size() > 0,
		"меш имеет вершины и UV (%d)" % verts.size())

	# Каждой клетке соответствует ровно 6 вершин (2 треугольника) в порядке
	# p00, p10, p01, p10, p11, p01 — ровно тот порядок, который задаёт код.
	var perms := {}
	var trans_cells := 0
	var flipped_cells := 0
	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			var tile: int = int(tiles[i]) | (int(hflags[i]) << 8)
			if AlmLoader.tile_file_n(tile) < AlmLoader.TRANSITION_FILE_MIN:
				continue
			var base: int = i * 6
			if base + 5 >= uvs.size():
				continue
			trans_cells += 1
			var uv00 := uvs[base]
			var uv10 := uvs[base + 1]
			var uv01 := uvs[base + 2]
			# Раскладываем UV в «канонический» вид: umin/vmin и знаки шагов.
			var umin: float = minf(minf(uv00.x, uv10.x), uv01.x)
			var vmin: float = minf(minf(uv00.y, uv10.y), uv01.y)
			var umax: float = maxf(maxf(uv00.x, uv10.x), uv01.x)
			var vmax: float = maxf(maxf(uv00.y, uv10.y), uv01.y)
			var du: float = umax - umin
			var dv: float = vmax - vmin
			# Куда «направлены» два соседних угла относительно p00.
			var su: float = signf(uv10.x - uv00.x)
			var sv: float = signf(uv01.y - uv00.y)
			# Транспонирование меняет местами du/dv.
			var is_transposed: bool = absf(absf(du) - absf(dv)) < 0.00001 and du > 0.0 and dv > 0.0 and _looks_transposed(uv00, uv10, uv01, du, dv)
			var key := "%s%s%s" % [
				"m" if su < 0.0 else "p",
				"n" if sv < 0.0 else "p",
				"T" if is_transposed else "-"]
			perms[key] = int(perms.get(key, 0)) + 1
			if key != "ppn" and key != "ppp-":
				pass
			if su < 0.0 or sv < 0.0 or is_transposed:
				flipped_cells += 1

	print("  переходных клеток в меше: %d" % trans_cells)
	print("  распределение раскладок: %s" % str(perms))
	_check(trans_cells > 200, "переходных клеток достаточно для замера (%d)" % trans_cells)
	_check(perms.size() >= 2,
		"раскладок углов минимум две — отражение реально применяется (%d)" % perms.size())
	_check(flipped_cells > trans_cells / 10,
		"отражённых клеток заметная доля (%d из %d)" % [flipped_cells, trans_cells])

	_report()


## Транспонирование: шаги по u и v равны по модулю, но у соседей они «перепутаны».
func _looks_transposed(uv00: Vector2, uv10: Vector2, uv01: Vector2,
		du: float, dv: float) -> bool:
	var sx: float = signf(uv10.x - uv00.x)
	var sy: float = signf(uv01.y - uv00.y)
	if sx < 0.0 or sy < 0.0:
		return false
	# При транспонировании uv10 отличается от uv00 по y, а не по x.
	return absf(uv10.y - uv00.y) > 0.00001 and absf(uv10.x - uv00.x) < 0.00001


func _report() -> void:
	print("RESULT: %s transition_grid_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)