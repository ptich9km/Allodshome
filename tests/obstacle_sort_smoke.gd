## Порядок отрисовки препятствий: сортировать надо по ЗЕМЛЕ, а не по вершине.
##
## Жалоба игрока 10.10: «камни, которые сегодня сгенерили, лежат поверх
## деревьев. Должно быть не так, деревья перекрывают камни».
##
## Причина: `place_at` ставил position УЗЛА в левый верхний угол спрайта.
## Сортировка по Y в Godot идёт именно по position узла, то есть сравнивались
## вершины спрайтов, а не точки земли. Чем объект выше, тем раньше он рисуется.
## Замер по реестру: дерево h=128 против камня h=56 — разница 72 px при тайле
## 32 px, то есть камень "выше" дерева на две с половиной клетки и перекрывал
## его, даже стоя на более дальнем ряду.
##
## Исправление: узел стоит в точке земли, спрайт смещён внутри на якорь.
##
## Запуск:
##   godot --headless --path . --script res://tests/obstacle_sort_smoke.gd

extends SceneTree

const TILE := 32

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _make(folder: String, tex_h: int, cx: int, cy: int) -> AlmObstacle:
	var ob := AlmObstacle.new()
	ob.reg_w = tex_h
	ob.reg_h = tex_h
	ob.cx = float(cx)
	ob.cy = float(cy)
	# Текстуры нет и не нужно: проверяем только позиционирование. Но размер
	# текстуры задаём явно - иначе остаётся дефолт 32 и разница высот
	# (дерево 128 против камня 56) не воспроизводится, то есть проверки
	# порядка проходили бы даже на сломанной схеме.
	ob._tex_w = tex_h / 2
	ob._tex_h = tex_h
	ob.name = folder
	return ob


func _run() -> void:
	var tree := _make("tree_oak", 128, 56, 128)
	var rock := _make("rock", 56, 32, 56)

	# Дерево на ряду 0, камень на ряду 1 (ближе к зрителю).
	tree.place_at(Vector2i(5, 0), TILE, 0.0)
	rock.place_at(Vector2i(5, 1), TILE, 0.0)

	var tree_x := 5 * TILE + TILE / 2.0
	var tree_y := 0 * TILE + TILE / 2.0
	var rock_x := 5 * TILE + TILE / 2.0
	var rock_y := 1 * TILE + TILE / 2.0

	_check(is_equal_approx(tree.position.x, tree_x) and is_equal_approx(tree.position.y, tree_y),
		"узел дерева стоит в точке земли (%.1f, %.1f)" % [tree.position.x, tree.position.y])
	_check(is_equal_approx(rock.position.x, rock_x) and is_equal_approx(rock.position.y, rock_y),
		"узел камня стоит в точке земли (%.1f, %.1f)" % [rock.position.x, rock.position.y])

	# Главный инвариант: узел ДОЛЖЕН совпадать с точкой земли. Именно её
	# сравнивает y_sort. Если position узла уедет к вершине спрайта, порядок
	# снова сломается.
	_check(tree.position.y < rock.position.y,
		" nearer объект сортится позже (камень %.1f > дерево %.1f)"
			% [rock.position.y, tree.position.y])

	# Обратный случай, который и ломал картину: камень на дальнем ряду,
	# дерево на ближнем. По земле дерево должно быть позади камня? Нет —
	# ближний ряд рисуется позже, значит дерево (ряд 1) позже камня (ряд 0).
	var rock_far := _make("rock", 56, 32, 56)
	var tree_near := _make("tree_oak", 128, 56, 128)
	rock_far.place_at(Vector2i(9, 0), TILE, 0.0)
	tree_near.place_at(Vector2i(9, 1), TILE, 0.0)
	_check(rock_far.position.y < tree_near.position.y,
		"на ближнем ряду дерево сортится позже камня с дальнего ряда")

	# Рельеф: сдвиг вверх на единицу тайла не должен ломать порядок.
	var rock_up := _make("rock", 56, 32, 56)
	rock_up.place_at(Vector2i(9, 1), TILE, float(TILE))
	_check(is_equal_approx(rock_up.position.y, 1 * TILE + TILE / 2.0 - TILE),
		"рельеф поднимает точку земли, а не спрайт")

	tree.free()
	rock.free()
	rock_far.free()
	tree_near.free()
	rock_up.free()
	_report()


func _report() -> void:
	print("\n==== ИТОГ ====")
	if _fails.is_empty():
		print("RESULT: OK obstacle_sort_smoke (проверок: %d, провалов: 0)" % _checks)
	else:
		print("RESULT: FAIL obstacle_sort_smoke (проверок: %d, провалов: %d)"
			% [_checks, _fails.size()])
		for f in _fails:
			print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)