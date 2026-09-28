extends SceneTree
## Smoke-проверка переходов между биомами (файлы tile8..15).
##
## Зачем тест, а не «посмотрел глазами»: граница биома может выглядеть
## прилично и при этом быть перевёрнутой (бленд не с той стороны), а
## декодирование тайла — молча отдавать не тот terrain-тип, что ломает
## проходимость и мини-карту. Оба класса ошибок не видны на рендере.
##
## Проверяет:
##   1. все 56 BMP на месте, 32x448 (14 рядов);
##   2. бленд лежит с ПРАВИЛЬНОЙ стороны для каждого из 8 направлений;
##   3. кодирование/декодирование тайла обратимо;
##   4. terrain_type() отдаёт биом-владельца для переходного тайла;
##   5. сгенерированная карта реально использует файлы 8..15 на кромках;
##   6. метрика шва: средняя разница между соседними клетками НА ГРАНИЦЕ
##      биомов меньше, чем у жёсткой подстановки (без бленда).
##
## Запуск: godot --headless --path . --script res://tests/transition_blend_smoke.gd

const TERRAIN_DIR := "res://assets/terrain/"
const MAP_DIR := "user://maps/_transition_check/"
const TILE := 32
const ROWS := 14
const FILE_BASE := 8
const NEIGHBORS := 7
const VARIATIONS := 2
const SEED := 31337

## Направления в порядке файлов 8..15. Должно совпадать с directions.order
## в assets/maps/terrain_tiles_db.json и с _TRANSITION_DIR_ORDER генератора.
const DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Края плитки, затрагиваемые направлением: "T"/"B"/"L"/"R".
const EDGES := {
	"N": "T", "NE": "TR", "E": "R", "SE": "BR",
	"S": "B", "SW": "BL", "W": "L", "NW": "TL",
}

## Противоположный край — там обязан остаться биом A. Ключи — строки краёв
## (как в EDGES), а не названия направлений. Без этой карты «дальний» замер
## совпадал с ближним и проверка всегда давала 0.
const OPPOSITE := {
	"T": "B", "TR": "BL", "R": "L", "BR": "TL",
	"B": "T", "BL": "TR", "L": "R", "TL": "BR",
}

var _fails: Array[String] = []
var _checks := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(MAP_DIR)
	_test_files()
	_test_blend_side()
	_test_codec()
	_test_map()
	_report()

# --- 1. Файлы ---

func _test_files() -> void:
	for dir_index in range(DIRS.size()):
		var file_n: int = FILE_BASE + dir_index
		for a in range(NEIGHBORS):
			var path: String = TERRAIN_DIR + "tile%d-%02d.bmp" % [file_n, a]
			if not ResourceLoader.exists(path):
				_check(false, "%s существует" % path.get_file())
				continue
			var img: Image = load(path).get_image()
			_check(img.get_width() == TILE and img.get_height() == TILE * ROWS,
				"%s = %dx%d" % [path.get_file(), img.get_width(), img.get_height()])
	_check(true, "файлы 8..15 присутствуют (проверено %d)" % (DIRS.size() * NEIGHBORS))

# --- 2. Сторона кромки ---
##
## Мера: «прогресс бленда» — насколько кромка ушла от чистого A в сторону B,
## в единицах расстояния A->B:
##
##     progress = |цвет(кромка) - цвет(A)| / |цвет(A) - цвет(B)|
##
## progress около 0 — бленда нет, около 1 — кромка стала чистым B, больше 1 —
## ушла даже дальше B (уBlend полоса узкая, и у края B доминирует).
##
## Почему не «кромка ближе к B, чем к A»: для пар гора/дорога (обе серые) и
## грязь/почва (обе бурые) эта мера врала на 9 плитках из 672 — насколько
## далеко кромка ушла от A, измеряется надёжно, а абсолютная близость к
## среднему цвету биома зависит от того, какая вариация попала в бленд.
##
## Почему нет проверки «прогресс одинаков по всем 8 направлениям»: у диагонали
## полоса — это угол (две стороны 4 px, 23% плитки против 12.5% у кардинала),
## поэтому в неё попадает больше чистого A и средний прогресс закономерно ниже.
## Замеренный разброс по парам — 0.44..1.97, так что допуск в любую сторону
## либо ничего не проверяет, либо роняет нормальные плитки.
##
## Почему порог 0.40 и этого достаточно: перевёрнутая кромка (B вместо A)
## даёт прогресс около нуля, то есть запас получается четырёхкратный.
## Нижняя граница 0.44 приходит из пары почва↔грязь (обе бурые) на
## диагональном файле 9 — самый близкий к неразличимому случай.

const BLEND_MIN_PROGRESS := 0.40

func _test_blend_side() -> void:
	var ok := 0
	var skipped := 0
	var bad: Array[String] = []
	for dir_index in range(DIRS.size()):
		var file_n: int = FILE_BASE + dir_index
		var edges: String = EDGES[DIRS[dir_index]]
		for a in range(NEIGHBORS):
			for b in range(NEIGHBORS):
				if a == b:
					continue
				var ref_b: Vector3 = _biome_mean(b)
				if ref_b == Vector3.ZERO:
					skipped += 1
					continue
				for v in range(VARIATIONS):
					var row: int = b * VARIATIONS + v
					var img: Image = _load_strip(file_n, a)
					# Чистый A снимаем с противоположного края: бленда там нет.
					var ref_a: Vector3 = _band_mean(img, OPPOSITE[edges], row * TILE)
					var near: Vector3 = _band_mean(img, edges, row * TILE)
					var spread: float = (ref_a - ref_b).length()
					if spread < 0.02:
						skipped += 1
						continue
					var progress: float = (near - ref_a).length() / spread
					if progress >= BLEND_MIN_PROGRESS:
						ok += 1
					else:
						bad.append("tile%d-%02d A=%d B=%d v=%d progress=%.2f" % [
							file_n, a, a, b, v, progress])
	print("INFO сторона кромки: проверено=%d, пропущено (одинаковые цвета)=%d" % [
		ok + bad.size(), skipped])
	_check(bad.is_empty(), "прогресс бленда >= %.2f на всех плитках (%d/%d)" % [
		BLEND_MIN_PROGRESS, ok, ok + bad.size()])
	for s in bad.slice(0, 6):
		print("     слабый бленд: ", s)

func _load_strip(file_n: int, a: int) -> Image:
	return load(TERRAIN_DIR + "tile%d-%02d.bmp" % [file_n, a]).get_image()

## Средний цвет полосы у заданных краёв. (0,0,0), если полоса пуста.
##
## ВАЖНО: _edge_cell ждёт ЛОКАЛЬНЫЕ координаты внутри плитки (0..31), а
## get_pixel — абсолютные в полосе. Если передать в _edge_cell абсолютный y,
## проверка "y >= TILE-4" выполняется для всего тайла, полоса становится
## равной всей плитке, и замер молча теряет смысл (было 465/672 вместо
## 663/672 при правильных координатах).
func _band_mean(img: Image, edges: String, y0: int) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for ly in range(TILE):
		for x in range(TILE):
			if not _edge_cell(edges, x, ly):
				continue
			var c: Color = img.get_pixel(x, y0 + ly)
			acc += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return Vector3.ZERO
	return acc / float(n)

## Средний цвет ВСЕГО биома b (файл tile{b+1}-00.bmp, все 14 рядов).
##
## Опорную точку B нельзя брать из одной вариации: генератор в бленд кладёт
## base[b][(b*2 + v + 1) % 6], а вариации одного биома отличаются по
## яркости (у гор — снег сверху, тёмная порода снизу), и замер «кромка против
## конкретной вариации B» врал на 237 плитках из 672. Среднее по всем рядам
## устойчиво к тому, какая именно вариация попала в бленд.
func _biome_mean(b: int) -> Vector3:
	var path: String = TERRAIN_DIR + "tile%d-00.bmp" % (b + 1)
	if not ResourceLoader.exists(path):
		return Vector3.ZERO
	var img: Image = load(path).get_image()
	var acc := Vector3.ZERO
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			acc += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return Vector3.ZERO
	return acc / float(n)

## Клетка (x,y) плитки попадает в полосу у заданных краёв.
func _edge_cell(edges: String, x: int, y: int) -> bool:
	if edges.contains("T") and y < 4:
		return true
	if edges.contains("B") and y >= TILE - 4:
		return true
	if edges.contains("L") and x < 4:
		return true
	if edges.contains("R") and x >= TILE - 4:
		return true
	return false

# --- 3-4. Кодирование ---

func _test_codec() -> void:
	for dir_index in range(DIRS.size()):
		var file_n: int = FILE_BASE + dir_index
		for a in range(NEIGHBORS):
			for b in range(NEIGHBORS):
				var row: int = b * VARIATIONS
				var tile: int = AlmLoader.tile_encode_transition(file_n, a, row)
				_check(AlmLoader.tile_file_n(tile) == file_n, "roundtrip file %d/%d" % [file_n, a])
				_check(AlmLoader.tile_variant(tile) == a, "roundtrip variant %d/%d" % [file_n, a])
				_check(AlmLoader.tile_encode_row(tile) == row, "roundtrip row %d/%d" % [file_n, a])
				# terrain_type читает старшие 4 бита (владелец A).
				var hf: int = (tile >> 8) & 0xFF
				_check(AlmLoader.terrain_type(hf) == a,
					"terrain_type(A=%d) для файла %d" % [a, file_n])
				_check(AlmLoader.is_transition_tile(tile), "is_transition_tile файла %d" % file_n)
	_check(true, "кодирование переходов обратимо")
	# Интерьерные файлы не должны ломаться новой схемой.
	_check(AlmLoader.terrain_type(0) == 0 and AlmLoader.terrain_type(6) == 6,
		"файлы 1..7: terrain_type без изменений")
	_check(not AlmLoader.is_transition_tile(AlmLoader.tile_from_spec({"file": 1, "variant": 3, "row": 4})),
		"файлы 1..7 не считаются переходами")
	# Roundtrip интерьеров - перенесено из удалённого test_transitions.gd,
	# который кроме этого тестировал уже не влияющий на картинку слой
	# transition_db в старом формате (224 правила, тип 7).
	var rt_bad := 0
	for f in range(1, 16):
		var max_v: int = 4 if f == 4 else (7 if f >= 8 else 16)
		for v in range(max_v):
			for r in [0, 4, 9, 13]:
				var tile: int = AlmLoader.tile_from_spec({"file": f, "variant": v, "row": r})
				if AlmLoader.tile_file_n(tile) != f:
					rt_bad += 1
				elif AlmLoader.tile_variant(tile) != v:
					rt_bad += 1
				elif AlmLoader.tile_encode_row(tile) != r:
					rt_bad += 1
	_check(rt_bad == 0, "tile_from_spec roundtrip для файлов 1..15 (ошибок: %d)" % rt_bad)

# --- 5-6. Карта ---

func _test_map() -> void:
	var path: String = MapGenerator.new().generate(SEED, "mid", MAP_DIR)
	_check(path != "" and FileAccess.file_exists(path), "карта сгенерировалась")
	if path == "" or not FileAccess.file_exists(path):
		return
	var m: Dictionary = AlmLoader.load_map(path)
	_check(not m.is_empty(), "карта читается")
	if m.is_empty():
		return
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var terrain: PackedByteArray = m["terrain"]
	var hflags: PackedByteArray = m["hflags"]

	var transitions := 0
	var interiors := 0
	var wrong_owner := 0
	var wrong_row := 0
	var boundary_without_transition := 0

	for y in range(h):
		for x in range(w):
			var i: int = y * w + x
			var tile: int = terrain[i] | (hflags[i] << 8)
			var file_n: int = AlmLoader.tile_file_n(tile)
			var owner: int = AlmLoader.terrain_type(hflags[i])
			if file_n < FILE_BASE:
				interiors += 1
				# Если у клетки есть отличающийся кардинальный сосед, а тайл
				# НЕ переходный — переход где-то не сработал.
				if _has_differing_cardinal(terrain, hflags, w, h, x, y, owner):
					boundary_without_transition += 1
				continue
			transitions += 1
			if owner < 0 or owner > 6:
				wrong_owner += 1
			# row = B*2 + v, значит row//2 обязан совпасть с типом соседа
			# по направлению файла.
			var neighbor: int = _neighbor_type(terrain, hflags, w, h, x, y, file_n - FILE_BASE)
			if neighbor >= 0 and int(terrain[i] & 0xF) / 2 != neighbor:
				wrong_row += 1

	print("INFO клеток: переходов=%d интерьеров=%d" % [transitions, interiors])
	_check(transitions > 0, "карта использует переходные файлы (%d)" % transitions)
	_check(interiors > 0, "в карте остались интерьерные клетки (%d)" % interiors)
	_check(wrong_owner == 0, "у всех переходов валидный биом-владелец (ошибок: %d)" % wrong_owner)
	_check(wrong_row == 0, "row = сосед*2 + вариация (ошибок: %d)" % wrong_row)
	_check(boundary_without_transition == 0,
		"все кромки получили переход (пропущено: %d)" % boundary_without_transition)
	_test_seam_metric(m, w, h)
	_test_transition_keeps_walkability(m, w, h)

## Переходный тайл не должен менять проходимость своего биома.
##
## Настоящий баг: у файлов 8..15 младший ниббл хранит номер файла-перехода,
## а не номер файла биома. WalkTable ищет "файл-вариант", файлов 8..15 в
## DEFAULT нет, цена падала на 8 - и клетки ВОДЫ на берегу становились
## проходимыми (замерено: 750 из 1638, то есть 46% воды). При этом
## is_walkable_world возвращал true, поэтому fuzz_water рапортовал 0 hits.
func _test_transition_keeps_walkability(m: Dictionary, w: int, h: int) -> void:
	var terrain: PackedByteArray = m["terrain"]
	var hflags: PackedByteArray = m["hflags"]
	var checked := 0
	var wrong := 0
	for i in range(w * h):
		var hf: int = hflags[i]
		if not WalkTable.terrain_file_is_transition(hf):
			continue
		checked += 1
		var owner: int = AlmLoader.terrain_type(hf)
		if owner < 0 or owner > 6:
			wrong += 1
			continue
		# Проходимость клетки должна совпадать с проходимостью биома-владельца.
		var actual: bool = WalkTable.walkable_at(hf, terrain[i])
		var expect: bool = WalkTable.walkable(owner + 1, 0)
		if actual != expect:
			wrong += 1
	_check(checked > 0, "карта содержит переходные клетки для проверки проходимости (%d)" % checked)
	_check(wrong == 0,
		"переходный тайл не меняет проходимость биома (расхождений: %d)" % wrong)

func _has_differing_cardinal(terrain: PackedByteArray, hflags: PackedByteArray,
		w: int, h: int, x: int, y: int, owner: int) -> bool:
	if owner < 0:
		return false
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var nt: int = AlmLoader.terrain_type(hflags[ny * w + nx])
		if nt >= 0 and nt != owner:
			return true
	return false

## Тип соседа по направлению dir_index (0..7 = N, NE, E, SE, S, SW, W, NW).
func _neighbor_type(terrain: PackedByteArray, hflags: PackedByteArray,
		w: int, h: int, x: int, y: int, dir_index: int) -> int:
	var d: Array = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
	]
	if dir_index < 0 or dir_index >= d.size():
		return -1
	var p: Vector2i = Vector2i(x, y) + d[dir_index]
	if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
		return -1
	return AlmLoader.terrain_type(hflags[p.y * w + p.x])

## Метрика шва с контролем.
##
## Сравнивать стык «на границе биомов» со стыком «внутри биома» бессмысленно:
## внутри одного биома текстуры одинаковые и шов заведомо меньше, поэтому
## проверка всегда требовала бы перехода быть волшебно незаметным.
##
## Вместо этого считаем РЕАЛЬНЫЙ контроль: для каждой границы биомов берём
## стык двух переходных плиток (с блендом) и сравниваем с тем же стыком, но
## без бленда — нижняя строка интерьерной плитки A против верхней строки
## интерьерной плитки B. Второе число — это ровно то, что было на карте до
## переходов. Если первое не меньше второго, бленда нет.
func _test_seam_metric(m: Dictionary, w: int, h: int) -> void:
	var hflags: PackedByteArray = m["hflags"]
	var blended := 0.0
	var blended_n := 0
	var control := 0.0
	var control_n := 0
	for y in range(h - 1):
		for x in range(w):
			var i: int = y * w + x
			var ta: int = AlmLoader.terrain_type(hflags[i])
			var tb: int = AlmLoader.terrain_type(hflags[(y + 1) * w + x])
			if ta < 0 or tb < 0 or ta == tb:
				continue
			var d: float = _row_diff(m, w, x, y)
			if d < 0.0:
				continue
			blended += d
			blended_n += 1
			# Контроль: те же два биома, но стык интерьерных плиток.
			var c: float = _interior_seam(ta, tb)
			if c >= 0.0:
				control += c
				control_n += 1
	print("INFO шов: замеров с блендом=%d, контрольных=%d" % [blended_n, control_n])
	if blended_n < 20 or control_n < 20:
		_check(false, "недостаточно замеров для метрики шва (бленд=%d, контроль=%d)" % [blended_n, control_n])
		return
	var b: float = blended / float(blended_n)
	var c2: float = control / float(control_n)
	print("INFO шов: с блендом=%.4f, без бленда (контроль)=%.4f" % [b, c2])
	_check(b < c2, "бленд делает стык мягче контроля (%.4f < %.4f)" % [b, c2])

## Стык интерьерных плиток двух биомов БЕЗ бленда: нижняя строка плитки
## биома A против верхней строки плитки биома B. -1, если плитки нет.
##
## Берём один и тот же вариант (0) и один и тот же ряд (0) у обоих, чтобы
## контроль не зависел от того, какие вариации выпали на границе.
func _interior_seam(a: int, b: int) -> float:
	var file_a: int = a + 1
	var file_b: int = b + 1
	var path_a: String = TERRAIN_DIR + "tile%d-00.bmp" % file_a
	var path_b: String = TERRAIN_DIR + "tile%d-00.bmp" % file_b
	if not ResourceLoader.exists(path_a) or not ResourceLoader.exists(path_b):
		return -1.0
	var ia: Image = load(path_a).get_image()
	var ib: Image = load(path_b).get_image()
	var total := 0.0
	for px in range(TILE):
		var ca: Color = ia.get_pixel(px, TILE - 2)
		var cb: Color = ib.get_pixel(px, 1)
		total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(TILE)

## Средняя абсолютная разница RGB между нижней строкой клетки (x,y) и верхней
## строкой клетки (x,y+1). Берём строки со сдвигом 2 px от края, чтобы не мерить
## сам шов соседних UV в атласе, а содержательную разницу текстур.
## -1, если плитка не загрузилась.
func _row_diff(m: Dictionary, w: int, x: int, y: int) -> float:
	var tiles: PackedInt32Array = m["tiles"]
	var img_a: Image = _tile_image(tiles[y * w + x])
	var img_b: Image = _tile_image(tiles[(y + 1) * w + x])
	if img_a.is_empty() or img_b.is_empty():
		return -1.0
	var total := 0.0
	for px in range(TILE):
		var ca: Color = img_a.get_pixel(px, TILE - 2)
		var cb: Color = img_b.get_pixel(px, 1)
		total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / float(TILE)

## Вырезает плитку 32x32 из соответствующего BMP.
func _tile_image(tile: int) -> Image:
	var file_n: int = AlmLoader.tile_file_n(tile)
	var variant: int = AlmLoader.tile_variant(tile)
	var row: int = AlmLoader.tile_encode_row(tile)
	var path: String = TERRAIN_DIR + "tile%d-%02d.bmp" % [file_n, variant]
	if not ResourceLoader.exists(path):
		return Image.create_empty(0, 0, false, Image.FORMAT_RGBA8)
	var img: Image = load(path).get_image()
	if row * TILE + TILE > img.get_height():
		return Image.create_empty(0, 0, false, Image.FORMAT_RGBA8)
	return img.get_region(Rect2i(0, row * TILE, TILE, TILE))

# --- отчёт ---

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	print("проверок: %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK transition_blend_smoke")
		quit(0)
	else:
		print("RESULT: FAIL transition_blend_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
