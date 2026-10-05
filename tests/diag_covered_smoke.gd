extends SceneTree
## Диагональный переход не ставится, если шов к тому же биому уже нарисован
## у кардинальных соседей угла (05.10).
##
## Жалоба игрока (2x2): 1:1=A, 1:2=B, 2:1=B, 2:2=B. Старый код ставил на 2:2
## NW-диагональ к A, хотя 1:2 уже режется к A слева, а 2:1 — сверху.
##
## ГЕОМЕТРИЧЕСКИЙ ФАКТ: у чистой диагонали (оба кардинала == t) диагональный
## сосед ВСЕГДА является кардинальным соседом обоих кардиналов угла
## (NW ячейки = W у N-соседа и N у W-соседа). Значит _diag_covered для
## чистой диагонали всегда true → чистые диагональные переходы фактически
## отключаются, границы держат кардиналы. Это осознанно и совпадает с
## решением игрока: лишний угловой срез внутри биома не нужен.
##
## Диагональ может остаться только у края карты, когда кардинал вышел за
## границу (-1) и «проверить покрытие» не у кого.
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
	g._terrain.fill(1)

	# --- Схема игрока 2x2 ---
	# (0,0)=A  (1,0)=B
	# (0,1)=B  (1,1)=B
	g._terrain[0] = 0
	print("-- 2x2: A B / B B --")
	_check(g._diag_covered(1, 1, 1, 0, "NW"),
		"2:2: NW покрыта (у 1:2 есть W=A, у 2:1 есть N=A)")

	var s_22 := _sides(g, 1, 1)
	var d_22: int = g._transition_dir(s_22, 1, 1, 1)
	_check(d_22 == -1, "2:2 без диагонали, dir=%d (ожидаем -1)" % d_22)

	var s_12 := _sides(g, 1, 0)
	var d_12: int = g._transition_dir(s_12, 1, 1, 0)
	_check(d_12 == 6, "1:2 ставит W, dir=%d (ожидаем 6)" % d_12)

	var s_21 := _sides(g, 0, 1)
	var d_21: int = g._transition_dir(s_21, 1, 0, 1)
	_check(d_21 == 0, "2:1 ставит N, dir=%d (ожидаем 0)" % d_21)

	# --- Чистая диагональ на更大的 карте: тоже покрыта (геометрия) ---
	# (2,0)=A; клетка (1,1): NE=A, N=B, E=B. У N сосед E=A, у E сосед N=A.
	print("-- чистая диагональ NE: геометрически покрыта --")
	g._terrain.fill(1)
	g._terrain[0 * w + 2] = 0
	_check(g._diag_covered(1, 1, 1, 0, "NE"),
		"(1,1): NE покрыта — диагональный сосед всегда кардинален для угловых клеток")
	var s_diag := _sides(g, 1, 1)
	var d_diag: int = g._transition_dir(s_diag, 1, 1, 1)
	_check(d_diag == -1, "(1,1) без NE, dir=%d (ожидаем -1)" % d_diag)
	# N-сосед (1,0) сам соприкасается с A через E → у него будет переход.
	var s_n := _sides(g, 1, 0)
	var d_n: int = g._transition_dir(s_n, 1, 1, 0)
	_check(d_n == 2, "(1,0) ставит E к A, dir=%d (ожидаем 2)" % d_n)

	# --- Кардинал не задет ---
	print("-- кардинал E --")
	g._terrain.fill(0)
	g._terrain[1 * w + 2] = 1
	var s_e := _sides(g, 1, 1)
	var d_e: int = g._transition_dir(s_e, 0, 1, 1)
	_check(d_e == 2, "(1,1) ставит E к B, dir=%d (ожидаем 2)" % d_e)

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
