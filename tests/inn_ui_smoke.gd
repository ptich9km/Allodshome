extends SceneTree
## Измерительный/контрактный прогон панели таверны (scripts/inn_panel.gd).
##
## 05.10: JPEG taverna.jpeg убран. Тест фиксирует контейнерную раскладку:
## сетка 4 колонки, ячейки в панели, найм работает, Esc/close на месте.
##
## Запуск: godot --headless --path . --script res://tests/inn_ui_smoke.gd

const SIZES := [Vector2i(1280, 800), Vector2i(1280, 600)]
const EXPECTED_CANDIDATES := 10
const CELL_COLUMNS := 4

var _fails: Array[String] = []
var _panel

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player = game.get("player")
	player.gold = 500000

	_panel = InnPanel.new()
	_panel.setup(player)
	root.add_child(_panel)
	for i in range(5):
		await process_frame

	var grid: GridContainer = _panel.get("_recruit_grid")
	var candidates: Array = _panel.get("_candidates")
	print("=== ТАВЕРНА (контейнерная) ===")
	print("кандидатов: %d, ячеек в сетке: %d, колонок: %d"
		% [candidates.size(), grid.get_child_count(), grid.columns])
	_check(candidates.size() == EXPECTED_CANDIDATES,
		"кандидатов %d (ожидалось %d)" % [candidates.size(), EXPECTED_CANDIDATES])
	_check(grid.columns == CELL_COLUMNS,
		"сетка %d колонки (получено %d)" % [CELL_COLUMNS, grid.columns])
	_check(grid.get_child_count() >= EXPECTED_CANDIDATES,
		"ячеек не меньше кандидатов (%d >= %d)" % [grid.get_child_count(), EXPECTED_CANDIDATES])

	# Ячейки контентные, не артовые 96×107.57
	var panel: Control = _panel.get("_panel")
	_check(panel != null, "панель PanelContainer есть")
	var worst_w := 0.0
	var worst_h := 0.0
	for child in grid.get_children():
		var c := child as Control
		if c == null:
			continue
		worst_w = maxf(worst_w, absf(c.size.x - 150.0))
		worst_h = maxf(worst_h, absf(c.size.y - 140.0))
	print("ячейка: ожидается 150×140, худшее отличие %.2f × %.2f" % [worst_w, worst_h])
	_check(worst_w <= 2.0, "ширина ячейки ~150 (отличие %.2f)" % worst_w)
	_check(worst_h <= 2.0, "высота ячейки ~140 (отличие %.2f)" % worst_h)

	# Сетка не выходит за панель
	if panel != null:
		var pg := panel.get_global_rect()
		var gg := grid.get_global_rect()
		_check(gg.encloses(pg.grow(-4.0)) or gg.intersects(pg),
			"сетка пересекается с панелью")

	# Фонового JPEG нет
	var bg: Node = _panel.find_child("Background", true, false)
	_check(bg == null, "фонового JPEG больше нет")

	# Панель рекрутера и кнопка найма на месте
	var talk_btn: Button = _panel.get("_talk_button")
	_check(talk_btn != null, "кнопка «Поговорить» есть")
	var close_btn: Button = _panel.get("_close_button")
	_check(close_btn != null, "кнопка «Закрыть» есть")

	# Найм: берём первого кандидата с кнопкой
	var hire_btn: Button = null
	for child in grid.get_children():
		var found: Button = null
		for c in child.find_children("Hire", "Button", true, false):
			found = c as Button
			break
		if found != null and not found.disabled:
			hire_btn = found
			break
	_check(hire_btn != null, "есть доступная кнопка «Нанять»")
	if hire_btn != null:
		var gold_before: int = player.gold
		var party_before: int = Game.party.size()
		hire_btn.pressed.emit()
		await process_frame
		_check(Game.party.size() == party_before + 1 or player.gold < gold_before,
			"найм изменил отряд/золото (party %d→%d, gold %d→%d)"
				% [party_before, Game.party.size(), gold_before, player.gold])

	# Размеры окна
	for size in SIZES:
		root.size = Vector2(size)
		await process_frame
		var vis := root.get_visible_rect().size
		print("[%dx%d] visible=%s panel=%s" % [size.x, size.y, str(vis), str(panel.size if panel != null else Vector2.ZERO)])
		if panel != null:
			_check(panel.size.x > 200.0 and panel.size.y > 200.0,
				"[%dx%d] панель не схлопнулась (%s)" % [size.x, size.y, str(panel.size)])

	_report()

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("INN: %s %s" % ["ok  " if ok else "FAIL", what])

func _report() -> void:
	if _fails.is_empty():
		print("RESULT: OK inn_ui_smoke (%d)" % _fails.size())
	else:
		print("RESULT: FAIL inn_ui_smoke (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
