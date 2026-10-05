extends SceneTree
## Расстановка переходов (05.10): односторонний t < n + запас угловых диагоналей.
##
## Двойной берег (жалоба игрока): 2x2 вода|песок, где ОБЕ стороны ставят
## переход (вода→песок и песок→вода). У края воды чистый песок, у края песка
## чистая вода → на шве жёсткий B|A посреди двух смесей.
##
## Контракт t < n: переход ставит только клетка с меньшим типом. Сосед с
## большим типом — чистый интерьер. Вода(2) | песок(5): режет только вода.
##
## Диагональ: шов уже у кардиналов угла → не ставим (см. _diag_covered).
##
## Запуск: godot --headless --path . --script res://tests/diag_covered_smoke.gd

var _fails: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)

func _run() -> void:
	var g := MapGenerator.new()
	var w := MapGenerator.W
	g._terrain.resize(w * MapGenerator.H)

	# --- Двойной берег: вода(2) сверху, песок(5) снизу ---
	# (0,0)=2 (1,0)=2
	# (0,1)=5 (1,1)=5
	print("-- двойной берег: вода | песок --")
	g._terrain.fill(5)
	g._terrain[0] = 2
	g._terrain[1] = 2

	# Вода (t=2) с соседом-песком (n=5): 2<5 → переход есть.
	var s_w1 := _sides(g, 0, 0)
	var d_w1: int = g._transition_dir(s_w1, 2, 0, 0)
	_check(d_w1 >= 0, "(0,0) вода: переход к песку, dir=%d" % d_w1)

	var s_w2 := _sides(g, 1, 0)
	var d_w2: int = g._transition_dir(s_w2, 2, 1, 0)
	_check(d_w2 >= 0, "(1,0) вода: переход к песку, dir=%d" % d_w2)

	# Песок (t=5) с соседом-водой (n=2): 5>2 → ЧИСТЫЙ интерьер, без перехода.
	var s_s1 := _sides(g, 0, 1)
	var d_s1: int = g._transition_dir(s_s1, 5, 0, 1)
	_check(d_s1 == -1, "(0,1) песок: без встречного перехода, dir=%d (ожидаем -1)" % d_s1)

	var s_s2 := _sides(g, 1, 1)
	var d_s2: int = g._transition_dir(s_s2, 5, 1, 1)
	_check(d_s2 == -1, "(1,1) песок: без встречного перехода, dir=%d (ожидаем -1)" % d_s2)

	# --- Раньше был NW на B-клетке (A B / B B) — теперь и туда -1 из-за t>n ---
	print("-- A B / B B: B-клетки чистые --")
	g._terrain.fill(1)
	g._terrain[0] = 0
	var s_22 := _sides(g, 1, 1)
	var d_22: int = g._transition_dir(s_22, 1, 1, 1)
	_check(d_22 == -1, "2:2 (B>A) без NW, dir=%d" % d_22)
	_check(g._diag_covered(1, 1, 1, 0, "NW"), "NW геометрически покрыта (диагностика)")
	var s_12 := _sides(g, 1, 0)
	var d_12: int = g._transition_dir(s_12, 1, 1, 0)
	_check(d_12 == -1, "1:2 (B>A) чистый, dir=%d" % d_12)
	var s_21 := _sides(g, 0, 1)
	var d_21: int = g._transition_dir(s_21, 1, 0, 1)
	_check(d_21 == -1, "2:1 (B>A) чистый, dir=%d" % d_21)
	# Сторона A (0<1) — переход остаётся.
	var s_11 := _sides(g, 0, 0)
	var d_11: int = g._transition_dir(s_11, 0, 0, 0)
	_check(d_11 >= 0, "1:1 (A<B) ставит переход, dir=%d" % d_11)

	# --- Кардинал E: младший тип смешивается в больший ---
	print("-- кардинал: A(0) у B(1) --")
	g._terrain.fill(0)
	g._terrain[1 * w + 2] = 1
	var s_e := _sides(g, 1, 1)
	var d_e: int = g._transition_dir(s_e, 0, 1, 1)
	_check(d_e == 2, "(1,1) A ставит E к B, dir=%d (ожидаем 2)" % d_e)
	# Обратный: B у A — без перехода.
	var s_e2 := _sides(g, 2, 1)
	var d_e2: int = g._transition_dir(s_e2, 1, 2, 1)
	_check(d_e2 == -1, "(2,1) B у A без перехода, dir=%d" % d_e2)

	if _fails.is_empty():
		print("RESULT: OK diag_covered_smoke (%d)" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)

func _sides(g: MapGenerator, x: int, y: int) -> Dictionary:
	var r := {"N": -1, "S": -1, "E": -1, "W": -1,
			  "NE": -1, "NW": -1, "SE": -1, "SW": -1}
	r["N"] = g._terrain_at(x, y - 1)
	r["S"] = g._terrain_at(x, y + 1)
	r["E"] = g._terrain_at(x + 1, y)
	r["W"] = g._terrain_at(x - 1, y)
	r["NE"] = g._terrain_at(x + 1, y - 1)
	r["NW"] = g._terrain_at(x - 1, y - 1)
	r["SE"] = g._terrain_at(x + 1, y + 1)
	r["SW"] = g._terrain_at(x - 1, y + 1)
	return r
