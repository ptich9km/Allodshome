extends SceneTree
## Измерительный прогон панели таверны (scripts/inn_panel.gd).
##
## Жалоба игрока: «в таверне не вмещаются юниты для найма». По коду причина не
## находилась однозначно, поэтому здесь снимаются ФАКТЫ: реальные прямоугольники
## ячеек, требуемая и фактическая высота содержимого, ширина подписей против
## ширины ячейки, перекрытие панелью рекрутера.
##
## Прогон печатает таблицу измерений — по ней и принимается решение о правке.
## После правки те же проверки становятся утверждениями (RESULT: OK).
##
## Запуск: godot --headless --path . --script res://tests/inn_ui_smoke.gd

const SIZES := [Vector2i(1280, 800), Vector2i(1280, 600)]
const EXPECTED_CANDIDATES := 10

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
	print("=== ИЗМЕРЕНИЯ ТАВЕРНЫ ===")
	print("кандидатов: %d, ячеек в сетке: %d, колонок: %d"
		% [candidates.size(), grid.get_child_count(), grid.columns])
	# Разметка assets/taverna/README.md: RECRUIT_PANEL (26,136)-(219,889),
	# 7 рядов x 2 колонки, ячейка 96x108. Раскладку ломали дважды, поэтому
	# фиксируем её тестом, а не «на глаз».
	_check(grid.columns == 2,
		"сетка 2 колонки по разметке арта (получено %d)" % grid.columns)
	_check(grid.get_child_count() == 14,
		"сетка 7x2 = 14 ячеек по разметке (получено %d)" % grid.get_child_count())

	# --- Фактические размеры ячеек ---
	var cell_min := Vector2.ZERO
	var cell_actual := Vector2.ZERO
	var need_h := 0.0
	for child in grid.get_children():
		var c := child as Control
		cell_min = c.get_combined_minimum_size()
		cell_actual = c.size
		need_h = c.get_combined_minimum_size().y
		break
	print("ячейка: min=%s факт=%s  требуемая высота содержимого=%.1f"
		% [str(cell_min), str(cell_actual), need_h])
	var grid_bottom: float = grid.position.y + grid.size.y
	print("сетка: pos=%s size=%s  нижняя граница=%.1f" % [str(grid.position), str(grid.size), grid_bottom])

	# ГЛАВНОЕ, чего не было: ячейка обязана РОВНО совпадать с артовой.
	# Прежние проверки смотрели только на то, что текст не вылезает за ячейку,
	# но никогда — на размер самой ячейки. Из-за этого «сползание» прошло мимо
	# теста: ряд вырос (кнопка «Нанять» фактически ~32 px из-за content margin 6
	# в теме), семь рядов уехали с y=136 на y=941, а нарисованная зона кончается
	# на 889. Клетки вышли за рамки — и это было видно, но не проверялось.
	var art_cell := Vector2(192.0 / 2.0, 753.0 / 7.0)
	var worst_w := 0.0
	var worst_h := 0.0
	for child5 in grid.get_children():
		var c5 := child5 as Control
		worst_w = maxf(worst_w, absf(c5.size.x - art_cell.x))
		worst_h = maxf(worst_h, absf(c5.size.y - art_cell.y))
	print("ячейка: ожидается %s, худшая ячейка отличается на %.2f x %.2f"
		% [str(art_cell), worst_w, worst_h])
	_check(worst_w <= 1.0,
		"ширина ячейки = артовой 96 px (отличие %.2f)" % worst_w)
	_check(worst_h <= 1.0,
		("высота ячейки = артовой 107.57 px (отличие %.2f) — иначе ряд растёт "
			+ "и сетка уезжает за нарисованную зону") % worst_h)
	# Нижняя граница сетки должна совпасть с низом зоны из README: 136 + 753 = 889.
	var art_bottom := 136.0 + 753.0
	_check(absf(grid_bottom - art_bottom) <= 1.5,
		"низ сетки = 889 (низ зоны из README), получено %.1f" % grid_bottom)
	_check(grid.position.x + grid.size.x <= 219.0 + 1.5,
		"сетка не выходит за правый край зоны (x=%.1f)" % (grid.position.x + grid.size.x))

	# --- Панель рекрутера: перекрывает ли сетку ---
	# ВАЖНО: DesignRoot масштабируется (scale ~0.586), поэтому геометрию сравниваем
	# в ЛОКАЛЬНЫХ координатах DesignRoot. Смешивать size (локальный) с
	# global_position (экранный) — ошибка единиц, из-за которой перекрытие
	# находилось ложно.
	var talk: Control = _panel.get_node_or_null("DesignRoot/RecruiterPanel")
	if talk != null:
		print("панель рекрутера: путь=%s local_pos=%s local_size=%s"
			% [str(talk.get_path()), str(talk.position), str(talk.size)])
		var grid_rect := Rect2(grid.position, grid.size)
		var talk_rect := Rect2(talk.position, talk.size)
		print("  сетка (local)=%s   панель (local)=%s" % [str(grid_rect), str(talk_rect)])
		_check(not grid_rect.intersects(talk_rect),
			"сетка не перекрыта панелью рекрутера (в локальных координатах)")

		# Ячейки против панели — тоже в локальных координатах.
		var overlaps := 0
		for child2 in grid.get_children():
			var c2 := child2 as Control
			var r := Rect2(c2.position, c2.size)
			if r.intersects(talk_rect):
				overlaps += 1
		_check(overlaps == 0, "ни одна ячейка не перекрыта панелью рекрутера (перекрыто: %d)" % overlaps)

	# --- Подписи: влезает ли текст в ячейку ---
	# Требование НЕ «текст короче ячейки», а «текст не вылезает на соседей».
	# Ячейка 96 px задана разметкой арта (README), длинное имя кандидата туда не
	# влезает физически, поэтому оно обрезается многоточием, а полное имя и все
	# характеристики показываются в карточке по наведению. Первая редакция этой
	# проверки требовала «текст короче ячейки» — и ругалась на 9 подписей, хотя
	# они аккуратно обрезались и ничего не задевали.
	var widest := 0.0
	var overflowing := 0
	var not_ellipsized := 0
	for child3 in grid.get_children():
		var c3 := child3 as Control
		for label in _find_labels(c3):
			var l := label as Label
			if l.text.is_empty():
				continue
			var font: Font = l.get_theme_font("font")
			if font == null:
				continue
			var text_w: float = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, l.get_theme_font_size("font_size")).x
			widest = maxf(widest, text_w)
			if text_w > l.size.x + 1.0:
				# Длинный текст обязан обрезаться, иначе он заедет на соседнюю ячейку.
				if l.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
					overflowing += 1
				else:
					not_ellipsized += 1
	print("самая широкая подпись: %.1f px, обрезано многоточием: %d" % [widest, not_ellipsized])
	_check(overflowing == 0,
		"ни одна подпись не вылезает за ячейку (обрезается многоточием: %d, без обрезки: %d)"
			% [not_ellipsized, overflowing])

	# --- Содержимое ячейки: портрет / кнопка ---
	var first: Control = grid.get_child(0) as Control
	var portrait: Control = _find_by_type(first, "TextureRect")
	var hire: Button = _find_button(first, "Hire")
	if portrait != null:
		print("портрет: %s" % str(portrait.size))
		_check(portrait.size.x >= 36.0,
			"портрет не мелкий (%.0f px; ячейка по разметке 96 px)" % portrait.size.x)
	if hire != null:
		print("кнопка «Нанять»: %s  текст «%s»" % [str(hire.size), hire.text])
		_check(hire.size.y >= 20.0 and hire.size.y <= 34.0,
			("кнопка «Нанять» по высоте (%.0f): выше 34 — ряд вырастет, "
				+ "ниже 20 — не нажать") % hire.size.y)
		_check(hire.text.contains("з"), "на кнопке есть цена: «%s»" % hire.text)
	# Отдельного лейбла цены в ячейке быть не должно — именно он выталкивал
	# содержимое за пределы артовой ячейки 107.57 px.
	var cost_labels := 0
	for child6 in grid.get_children():
		for label2 in _find_labels(child6 as Control):
			if (label2 as Label).theme_type_variation == &"InnCandidateCost":
				cost_labels += 1
	_check(cost_labels == 0,
		"отдельной строки цены в ячейке нет (найдено: %d)" % cost_labels)

	# --- Все кандидаты видимы и кликабельны ---
	var filled := 0
	var clickable := 0
	for child4 in grid.get_children():
		var c4 := child4 as Control
		var h4: Button = _find_button(c4, "Hire")
		if h4 != null:
			filled += 1
			if c4.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(1280, 800))):
				clickable += 1
	_check(filled == EXPECTED_CANDIDATES,
		"видно всех кандидатов: %d из %d" % [filled, EXPECTED_CANDIDATES])

	# --- В окне 1280x600 ---
	await _fits(1280, 600, "1280x600")
	_report()

func _fits(w: int, h: int, tag: String) -> void:
	root.size = Vector2i(w, h)
	for i in range(3):
		await process_frame
	var grid: GridContainer = _panel.get("_recruit_grid")
	var design: Control = _panel.get_node_or_null("DesignRoot")
	if design == null:
		_check(false, "[%s] нет DesignRoot" % tag)
		return
	print("[%s] DesignRoot: pos=%s size=%s scale=%s rect=%s"
		% [tag, str(design.position), str(design.size), str(design.scale), str(design.get_global_rect())])
	var win := Rect2(Vector2.ZERO, Vector2(w, h))
	var worst := ""
	for node in _walk(design):
		var c := node as Control
		if c == null or not c.is_visible_in_tree():
			continue
		if _inside_scroll(c):
			continue
		# get_global_rect() учитывает масштаб DesignRoot; size — нет.
		var r := c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not win.encloses(r):
			worst = "%s %s" % [c.name, str(r)]
			break
	_check(worst == "", "[%s] видимая часть таверны в окне%s" % [tag, "" if worst == "" else " — " + worst])

func _find_labels(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Label:
			out.append(child)
		out.append_array(_find_labels(child))
	return out

func _find_by_type(node: Node, cls: String) -> Control:
	for child in node.get_children():
		if child.is_class(cls):
			return child as Control
		var found := _find_by_type(child, cls)
		if found != null:
			return found
	return null

func _find_button(node: Node, btn_name: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).name == btn_name:
			return child as Button
		var found := _find_button(child, btn_name)
		if found != null:
			return found
	return null

func _inside_scroll(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK inn_ui_smoke")
		quit(0)
	else:
		print("RESULT: FAIL inn_ui_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)
