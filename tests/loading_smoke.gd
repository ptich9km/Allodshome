extends SceneTree
## Экран загрузки и прогресс генерации (23.10).
##
## Запуск: godot --headless --path . --script res://tests/loading_smoke.gd
##
## Проверяет: вид загрузки строится, полоса не откатывается, все фазы
## локализованы, MapLoadJob принимает прогресс из потока, потоковая
## генерация карты завершается и отдаёт существующий .alm.

const DIR := "user://maps/_loading_check/"

var _checks := 0
var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	Game.hero_race = "human"
	GameConfig.load_all()

	# --- 1. Вид ---
	var view_script: GDScript = load("res://scripts/loading_view.gd")
	var view = view_script.new()
	root.add_child(view)
	view.setup("Новый мир")
	await process_frame
	var bar = view.get("_bar")
	var status = view.get("_status")
	var back = view.get("_back")
	_check(bar != null, "полоса прогресса есть")
	_check(status != null, "строка фазы есть")
	_check(back != null and not back.visible, "кнопка «Назад» скрыта до ошибки")
	_check(view.anchor_right >= 1.0 and view.anchor_bottom >= 1.0,
		"вид растянут на весь экран (anchors)")

	view.set_progress(40, "Дороги")
	view._process(0.5)
	var v1: float = float(bar.value)
	view.set_progress(10, "Рельеф")
	view._process(0.5)
	var v2: float = float(bar.value)
	_check(v2 >= v1, "полоса не откатывается (%.1f -> %.1f)" % [v1, v2])
	view.set_error("Ошибка")
	_check(back.visible, "при ошибке появляется «Назад»")
	view.queue_free()

	# --- 2. Локализация фаз ---
	var missing := 0
	for i in range(13):
		var key := "ui.loading.phase.%d" % i
		if not Loc.has_key(key) or Loc.t(key) == key:
			missing += 1
	_check(missing == 0, "все 13 фаз локализованы (нет %d)" % missing)
	_check(Loc.has_key("ui.loading.hint"), "подсказка локализована")

	# --- 3. Прогресс из потока ---
	var job = load("res://scripts/world/map_load_job.gd").new()
	var wm = load("res://scripts/world/world_map.gd")
	var sector := "s41"
	# Уникальный сид на прогон: кэшированная карта вернулась бы сразу и фаз не
	# было бы видно (в игре это нормальный быстрый путь).
	var seed_value := int(4242 + (Time.get_ticks_usec() % 1000000))
	var ns: Array = wm.neighbors(sector)
	var thread := Thread.new()
	var err := thread.start(_thread_gen.bind(seed_value, sector, ns, job))
	_check(err == OK, "поток генерации запущен")
	var seen := {}
	var last := -1
	var monotonic := true
	while err == OK and thread.is_alive():
		var snap: Dictionary = job.snapshot()
		var p := int(snap.get("percent", 0))
		seen[int(snap.get("phase", 0))] = true
		if p < last:
			monotonic = false
		last = p
		await process_frame
	var path := ""
	if err == OK:
		path = str(thread.wait_to_finish())
	_check(monotonic, "прогресс в потоке не откатывается")
	_check(seen.size() >= 5, "поток прошёл фазы (увидено %d)" % seen.size())
	_check(path != "" and FileAccess.file_exists(path), "поток вернул существующий .alm")
	var snap_end: Dictionary = job.snapshot()
	_check(int(snap_end.get("percent", 0)) >= 95,
		"к концу генерации процент >= 95 (сейчас %d)" % int(snap_end.get("percent", 0)))

	print("")
	if _fails.is_empty():
		print("RESULT: OK loading_smoke (%d checks)" % _checks)
	else:
		print("RESULT: FAIL loading_smoke (%d checks, %d fails)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)


func _thread_gen(seed_value: int, sector: String, ns: Array, job) -> String:
	var wm = load("res://scripts/world/world_map.gd")
	var info: Dictionary = wm.sector(sector)
	return MapGenerator.ensure_map(seed_value, str(info.get("tier", "start")), DIR,
		"humans", sector, int(info.get("size", 96)), ns,
		str(info.get("relief", "")), job)
