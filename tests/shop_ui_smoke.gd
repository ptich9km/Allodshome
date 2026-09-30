extends SceneTree
## Headless-проверка магазина: раскладка полок под фоновый арт + карточка товара.
##
## Регрессия, из-за которой тест написан: сетка полок была переставлена с 2×7 на 3×5
## ради «названия и характеристик в ячейке», но фон shop_human.jpeg нарисован под
## исходные полки, и интерфейс разъехался с артом. Тест фиксирует и раскладку,
## и то, что читаемое вынесено в карточку по наведению, а не в ячейку.
##
## Запуск:
##   godot --headless --path . --script res://tests/shop_ui_smoke.gd

var _fails: Array = []
var _shop: ShopPanel = null


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 13, "spirit": 12,
		"blade": 10, "bludgeon": 10, "pike": 10, "shooting": 10,
		"fire": 20, "water": 20, "air": 20, "earth": 20, "astral": 20,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Покупатель"
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("SHOP: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "загрузка main.tscn: %d" % err)
		_finish()
		return
	await process_frame
	await create_timer(0.6).timeout
	var hero = get_first_node_in_group("player")
	if hero == null:
		_check(false, "герой не загружен")
		_finish()
		return
	# Даём предметы, чтобы полки игрока не были пустыми.
	hero.call("add_item", "Common iron Long Sword")
	hero.call("add_item", "Common Leather Mail")
	hero.call("add_item", "Potion Medium Healing")
	hero.gold = 100000

	_shop = ShopPanel.new()
	_shop.setup(hero)
	current_scene.add_child(_shop)
	await process_frame
	await create_timer(0.3).timeout

	_test_layout()
	_test_cells_fit_art()
	_test_no_text_in_cell()
	await _test_hover_card()
	_finish()


## 1. Раскладка полок — ровно та, под которую нарисован фон.
func _test_layout() -> void:
	var npc_grid: GridContainer = _find("NpcShelf")
	var player_grid: GridContainer = _find("PlayerShelf")
	_check(npc_grid != null, "полка торговца найдена")
	_check(player_grid != null, "полка игрока найдена")
	if npc_grid == null or player_grid == null:
		return
	_check(npc_grid.columns == 2,
		"полка торговца: 2 колонки (арт рассчитан на 2×7), получено %d" % npc_grid.columns)
	_check(player_grid.columns == 6,
		"полка игрока: 6 колонок, получено %d" % player_grid.columns)

	# Размер ячейки должен совпадать с исходным (95.5×86), а не с расширенным.
	var npc_slot: Control = _first_child_of_type(npc_grid, "PanelContainer")
	_check(npc_slot != null and is_equal_approx(npc_slot.custom_minimum_size.x, 95.5),
		"ячейка полки торговца = 95.5 px по ширине (под арт), получено %s"
			% (str(npc_slot.custom_minimum_size.x) if npc_slot != null else "нет ячейки"))


## 2. Полки не вылезают за пределы фонового арта 1024×1024.
func _test_cells_fit_art() -> void:
	var scroll: ScrollContainer = _find("NpcShelfScroll")
	var pscroll: ScrollContainer = _find("PlayerShelfScroll")
	_check(scroll != null and pscroll != null, "скролл-полки найдены")
	if scroll == null or pscroll == null:
		return
	_check(scroll.position + scroll.size <= Vector2(1024, 1024) + Vector2(1, 1),
		"полка торговца не выходит за пределы арта (%.0f,%.0f + %.0fx%.0f)"
			% [scroll.position.x, scroll.position.y, scroll.size.x, scroll.size.y])
	_check(pscroll.position + pscroll.size <= Vector2(1024, 1024) + Vector2(1, 1),
		"полка игрока не выходит за пределы арта (%.0f,%.0f + %.0fx%.0f)"
			% [pscroll.position.x, pscroll.position.y, pscroll.size.x, pscroll.size.y])


## 3. В ячейке нет ни текстовых ярлыков, ни лишних узлов: только иконка и кнопка.
##    Читаемое живёт в карточке по наведению.
func _test_no_text_in_cell() -> void:
	var grid: GridContainer = _find("NpcShelf")
	if grid == null:
		_check(false, "полка торговца не найдена")
		return
	var slot: Control = _first_child_of_type(grid, "PanelContainer")
	if slot == null:
		_check(false, "в полке нет ячеек")
		return
	var labels := _count_labels(slot)
	_check(labels == 0,
		"в ячейке нет текстовых ярлыков (название ушло в карточку), найдено %d" % labels)
	var buttons := _count_of_type(slot, "Button")
	_check(buttons == 1, "в ячейке ровно одна кнопка (Купить), найдено %d" % buttons)


## 4. Карточка по наведению: появляется, наполнена реальными полями, не перехватывает мышь.
func _test_hover_card() -> void:
	var card: PanelContainer = _find("HoverCard")
	_check(card != null, "карточка создана")
	if card == null:
		return
	# Сбрасываем фокус: первая кнопка панели захватывает его автоматически,
	# и карточка показывается ещё до наведения — это правильное поведение,
	# а не повод спорить с тестом.
	root.gui_release_focus()
	await process_frame
	_check(not card.visible, "карточка скрыта, когда ни один предмет не выбран")
	_check(card.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"карточка не перехватывает мышь (иначе блокирует кнопку «Купить» под собой)")

	var grid: GridContainer = _find("NpcShelf")
	var slot: Control = _first_child_of_type(grid, "PanelContainer")
	if slot == null:
		_check(false, "нет ячейки для проверки карточки")
		return
	# Наведение мышью.
	slot.emit_signal("mouse_entered")
	await process_frame
	_check(card.visible, "карточка появилась при наведении")
	var lines := _card_lines(card)
	_check(lines.size() >= 3,
		"в карточке строк с данными: %d (ожидалось название, тип/материал, характеристики, цена)"
			% lines.size())
	if lines.size() > 0:
		_check(not str(lines[0]).is_empty(), "первая строка — название: «%s»" % str(lines[0]))
	var joined := " | ".join(lines)
	_check(joined.contains("з") or joined.contains("Цена"),
		"в карточке есть цена: «%s»" % joined.substr(maxi(0, joined.length() - 40)))
	_check(card.position.x + card.size.x <= 1024.0 and card.position.y + card.size.y <= 1024.0,
		"карточка удержана в пределах панели (%.0f,%.0f %.0fx%.0f)"
			% [card.position.x, card.position.y, card.size.x, card.size.y])

	# Уход курсора прячет.
	slot.emit_signal("mouse_exited")
	await process_frame
	_check(not card.visible, "карточка спряталась после ухода курсора")

	# Фокус (клавиатура/геймпад) тоже показывает карточку — иначе товар
	# не прочитать с пульта.
	var btn: Button = _find_button(slot)
	if btn != null:
		# Фокус должен быть СНЯТ, иначе grab_focus() на уже сфокусированной
		# кнопке не выдаст focus_entered повторно.
		root.gui_release_focus()
		await process_frame
		btn.grab_focus()
		await process_frame
		_check(card.visible, "карточка появилась по фокусу кнопки (клавиатура/геймпад)")
		root.gui_release_focus()
		await process_frame
		_check(not card.visible, "карточка спряталась по потере фокуса")


# --- поиск узлов ---

func _find(node_name: String) -> Node:
	return _shop.find_child(node_name, true, false)


func _first_child_of_type(root: Node, type_name: String) -> Control:
	for c in root.get_children():
		if c.get_class() == type_name:
			return c as Control
	return null


func _count_labels(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is Label:
			n += 1
		n += _count_labels(c)
	return n


func _count_of_type(root: Node, type_name: String) -> int:
	var n := 0
	for c in root.get_children():
		if c.get_class() == type_name:
			n += 1
		n += _count_of_type(c, type_name)
	return n


func _find_button(root: Node) -> Button:
	for c in root.get_children():
		if c is Button:
			return c as Button
		var found := _find_button(c)
		if found != null:
			return found
	return null


func _card_lines(card: PanelContainer) -> Array:
	var out: Array = []
	var box: Node = card.find_child("Box", true, false)
	if box == null:
		return out
	for c in box.get_children():
		if c is Label:
			out.append(str((c as Label).text))
	return out


func _finish() -> void:
	if _fails.is_empty():
		print("SHOP: RESULT: OK")
	else:
		print("SHOP: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
