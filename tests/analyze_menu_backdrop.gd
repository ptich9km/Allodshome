extends SceneTree
## Анализ карты-фона главного меню (assets/maps/menu/).
##
## Существует, потому что «красивый фон» нельзя выбрать на глаз: сначала меряем.
## Печатает долю биомов, плотность объектов и — главное — лучший квадрат
## обзора (окно, которое камера будет обходить) с оценкой по деревьям, воде и
## разнообразию биомов. Итоговую строку DRIFT_ORIGIN копируют в menu_backdrop.gd.
##
## Запуск:
##   godot --headless --path . --script res://tests/analyze_menu_backdrop.gd
##   godot --headless --path . --script res://tests/analyze_menu_backdrop.gd -- --map res://assets/maps/menu/menu_backdrop.alm

const MENU_DIR := "res://assets/maps/menu/"
const DEFAULT_MAP := MENU_DIR + "menu_backdrop.alm"

## Окно обзора камеры в клетках. Меню 1280x800 при зуме 2 — примерно
## 640x400 пикселей, то есть 20x13 клеток по 32 px. Дрейф идёт внутри окна.
const VIEW_CELLS := Vector2i(20, 13)

## Запас от края карты. Без него камера выводит обзор за последнюю клетку,
## и на экране вместо земли появляется пустота: первая версия выбрала окно с
## нижней кромкой на 127-й клетке из 128, и дрейф вниз уводил камеру за карту.
## Запас считается так: половина окна + радиус дрейфа.
const DRIFT_MARGIN_PX := Vector2(260, 150)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var map_path := DEFAULT_MAP
	# Тот же разбор аргументов, что в gen_smart_map.gd:63. Своей копии нет:
	# это единственное место в проекте, где так делают, и логика «сначала
	# user args, потом все» уже проверена.
	var all: PackedStringArray = OS.get_cmdline_user_args()
	var args: PackedStringArray = all if all.size() > 0 else OS.get_cmdline_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map_path = str(args[i + 1])

	if not FileAccess.file_exists(map_path):
		print("NO FILE: %s" % map_path)
		var d := DirAccess.open(MENU_DIR)
		if d != null:
			d.list_dir_begin()
			var fn := d.get_next()
			while fn != "":
				if fn.ends_with(".alm"):
					print("  found: " + fn)
				fn = d.get_next()
			d.list_dir_end()
		quit(1)
		return

	var m: Dictionary = AlmLoader.load_map(map_path)
	if m.is_empty():
		print("MAP UNREADABLE: %s" % map_path)
		quit(1)
		return

	# hflags — PackedByteArray, НЕ Int32. Проверено замером: ошибочный тип роняет
	# корутину до quit(), и headless-процесс живёт вечно вместо падения.
	var w := int(m["width"])
	var h := int(m["height"])
	var hflags: PackedByteArray = m["hflags"]
	var obstacles: PackedByteArray = m["obstacles"]

	var types := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0}
	var objects := 0
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			types[AlmLoader.terrain_type(hflags[idx])] += 1
			if obstacles[idx] != 0:
				objects += 1

	var total := float(w * h)
	print("MAP %s  %dx%d" % [map_path.get_file(), w, h])
	for t in [0, 1, 2, 3, 4, 5, 6]:
		print("  biome %d: %5d  (%.1f%%)" % [t, types[t], 100.0 * types[t] / total])
	print("  objects: %d  (%.1f%% of map)"
		% [objects, 100.0 * objects / total])

	_best_window(hflags, obstacles, w, h)
	quit(0)


## Перебирает все положения окна обзора и выбирает самое «живое».
##
## Метрика уже прошла одну неудачную итерацию, и это стоит записать: в первой
## версии вода не штрафовалась, и «лучшее» окно оказалось ОЗЕРОМ — 216 клеток
## воды из 260 и всего 3 дерева. Вода в фоне нужна берегом, а не озером.
## Деревья — главное (их 2.2% карты), вода ограничена потолком, разнообразие
## биомов тоже ограничено, иначе окно на 4 типа перевешивает красивое.
func _best_window(hflags: PackedByteArray, obstacles: PackedByteArray,
		w: int, h: int) -> void:
	var vw: int = mini(VIEW_CELLS.x, w)
	var vh: int = mini(VIEW_CELLS.y, h)
	var ts := 32.0
	# Допустимые положения окна: не ближе к краю, чем половина окна плюс
	# радиус дрейфа, иначе камера уедет за карту.
	var margin_x: float = (vw * 0.5 + DRIFT_MARGIN_PX.x / ts) + 1.0
	var margin_y: float = (vh * 0.5 + DRIFT_MARGIN_PX.y / ts) + 1.0
	var min_ox: int = int(ceil(margin_x))
	var min_oy: int = int(ceil(margin_y))
	var max_ox: int = w - vw - int(ceil(margin_x))
	var max_oy: int = h - vh - int(ceil(margin_y))
	print("ALLOWED origins: x %d..%d, y %d..%d" % [min_ox, max_ox, min_oy, max_oy])
	if min_ox > max_ox or min_oy > max_oy:
		print("NO SAFE WINDOW: map too small for view + drift")
		return
	var best_score := -1.0
	var best := Vector2i(0, 0)
	var best_trees := 0
	var best_kinds := 0
	var best_water := 0

	for oy in range(min_oy, max_oy + 1, 2):
		for ox in range(min_ox, max_ox + 1, 2):
			var seen := {}
			var trees := 0
			var water := 0
			for y in range(oy, oy + vh):
				for x in range(ox, ox + vw):
					var idx := y * w + x
					var ty := AlmLoader.terrain_type(hflags[idx])
					seen[ty] = true
					if ty == 2:
						water += 1
					if obstacles[idx] != 0:
						trees += 1
			var kinds := seen.size()
			var score := float(trees) * 3.0 + minf(float(water), 60.0) * 0.8 \
				+ minf(float(kinds), 4.0) * 4.0
			if score > best_score:
				best_score = score
				best = Vector2i(ox, oy)
				best_trees = trees
				best_kinds = kinds
				best_water = water

	print("VIEW %dx%d  best: (%d, %d)" % [vw, vh, best.x, best.y])
	print("  trees=%d  biomes=%d  water=%d  score=%.1f"
		% [best_trees, best_kinds, best_water, best_score])
	print("  DRIFT_ORIGIN = Vector2i(%d, %d)" % [best.x, best.y])