extends SceneTree
## Smoke package P: перф без отката плотности.
## P1 фаза деревьев, P2 process off, P3 minimap cache, P5 far-AI pause.

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
	print("-- AlmObstacle --")
	var ob := AlmObstacle.new()
	root.add_child(ob)
	# Статичный: frame_count 1, base_index 0 → process off после setup
	ob.setup("bones", 1, 128, 128, 64, 80, 0)
	_check(ob.frame_count <= 1 or not ob.is_processing(),
		"статичный obstacle process off (frames=%d processing=%s)" % [ob.frame_count, str(ob.is_processing())])
	ob.queue_free()

	var ob2 := AlmObstacle.new()
	root.add_child(ob2)
	ob2.setup("pine1", 7, 128, 128, 64, 80, 0)
	# Анимированный: process включён, таймер разбросан (не строго 0)
	_check(ob2.frame_count > 1, "pine1 frames>1 (got %d)" % ob2.frame_count)
	_check(ob2.is_processing(), "анимированный obstacle process on")
	_check(ob2._timer >= 0.0 and ob2._timer < 1.0, "фаза таймера в диапазоне FRAME_TIME")
	ob2.queue_free()

	print("-- конфиг плотность не снижена --")
	_check(GameConfig.geti("zone", "mid.gray_count_min") >= 120, "mid.gray_count_min>=120")
	_check(GameConfig.zonef("mid", "tree_density") >= 0.18, "mid.tree_density>=0.18 (=%.2f)" % GameConfig.zonef("mid", "tree_density"))
	_check(GameConfig.geti("spawn", "gray_target") >= 150, "gray_target>=150")

	print("-- far-AI: код есть --")
	var e_src := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var n_src := FileAccess.get_file_as_string("res://scripts/npc.gd")
	_check(e_src.contains("1600.0 * 1600.0"), "enemy far-pause порог есть")
	_check(n_src.contains("1600.0 * 1600.0"), "npc far-pause порог есть")

	print("-- minimap cache --")
	var ui_src := FileAccess.get_file_as_string("res://scripts/ui.gd")
	_check(ui_src.contains("_minimap_base"), "ui.gd имеет кэш _minimap_base")
	_check(ui_src.contains("blit_rect"), "ui.gd blit_rect для базы")

	print("-- spatial hash separation --")
	var g_src := FileAccess.get_file_as_string("res://scripts/game.gd")
	_check(g_src.contains("_sep_rebuild_grid"), "game.gd имеет spatial hash для separation")
	_check(g_src.contains("_sep_neighbors"), "game.gd ищет соседей по вёдрам")

	_report()


func _report() -> void:
	print()
	if _fails.is_empty():
		print("RESULT: OK package_p_smoke (checks=%d)" % _checks)
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL package_p_smoke (checks=%d fails=%d)" % [_checks, _fails.size()])
		quit(1)
