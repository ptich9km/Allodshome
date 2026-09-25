extends SceneTree
## Smoke-проверка меню школы (scripts/school_panel.gd).
##
## Панель была единственной интерьерной, оставшейся на хардкоженных координатах
## (Panel(340, 90) 600x620 + position/size у каждого узла, локальные theme
## override, свой KEY_ESCAPE, без fit_design_root). Проверяем, что теперь это
## контейнеры + единая тема, есть фокус/навигация/Esc, и — главное — интерфейс
## целиком помещается в окно 1280x800 и 1280x600.
##
## Запуск: godot --headless --path . --script res://tests/school_ui_smoke.gd

const SIZES := [Vector2i(1280, 800), Vector2i(1280, 600)]

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

	_panel = SchoolPanel.new()
	_panel.setup(player)
	root.add_child(_panel)
	for i in range(4):
		await process_frame

	_structure()
	_training(player)
	await _fits(1280, 800, "1280x800")
	await _fits(1280, 600, "1280x600")
	_close_behaviour()
	_report()

## Контейнерная структура, тема, фокус, навигация.
func _structure() -> void:
	var root: Control = _panel.get_node_or_null("SchoolRoot")
	_check(root != null, "есть корневой MarginContainer")
	_check(root != null and root.theme != null, "на корне висит единая тема UiKit")

	var panel: Control = _panel.get_node_or_null("SchoolRoot/Center/Panel")
	_check(panel != null and panel is PanelContainer, "панель — PanelContainer, а не Panel с координатами")

	var scroll: ScrollContainer = _panel.get_node_or_null("SchoolRoot/Center/Panel/Margin/Content/Scroll")
	_check(scroll != null, "список навыков в ScrollContainer")
	if scroll != null:
		_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"горизонтальный скролл выключен")
		_check(scroll.follow_focus, "прокрутка следует за фокусом")

	var rows: Array = _panel.get("_rows")
	_check(rows.size() == 10, "10 строк навыков (%d)" % rows.size())
	var buttons: Array[Button] = _panel.get("_train_buttons")
	_check(buttons.size() == 10, "10 кнопок «Обучить» (%d)" % buttons.size())
	var wired := 0
	for b in buttons:
		if not b.focus_neighbor_left.is_empty() and not b.focus_neighbor_right.is_empty():
			wired += 1
	_check(wired == buttons.size(), "у кнопок прописаны соседи фокуса (%d из %d)" % [wired, buttons.size()])
	_check(buttons.size() > 0 and buttons[0].has_focus(), "начальный фокус на кнопке «Обучить»")

	var close_btn: Button = _panel.get("_close_button")
	_check(close_btn != null, "кнопка «Закрыть» есть")

	# Ручной раскладки быть не должно: все узлы внутри контейнеров.
	var manual := 0
	for node in _walk(_panel):
		var c := node as Control
		if c == null or c is Container:
			continue
		if c.get_parent() is Container:
			continue
		if c is ColorRect or c == _panel:
			continue
		if c is Label and c.position != Vector2.ZERO:
			manual += 1
	_check(manual == 0, "нет ручной раскладки узлов (найдено: %d)" % manual)

## Тренировка реально повышает навык и тратит золото.
func _training(player) -> void:
	player.gold = 100000
	_panel.call("_refresh")
	var before_gold: int = player.gold
	var before_level: int = int(player.fire_skill)
	var btn: Button = _panel.get("_train_buttons")[5]  # Огонь
	btn.pressed.emit()
	await process_frame
	_check(int(player.fire_skill) == before_level + 1,
		"навык повышен (%d -> %d)" % [before_level, int(player.fire_skill)])
	_check(player.gold < before_gold, "золото списано (%d -> %d)" % [before_gold, player.gold])

	# Дорогая ступень при пустом кошельке — кнопка заблокирована, навык не растёт.
	player.gold = 0
	_panel.call("_refresh")
	var lvl2: int = int(player.fire_skill)
	_panel.call("_train", "fire_skill")
	await process_frame
	_check(int(player.fire_skill) == lvl2, "без золота навык не растёт")

## Весь интерфейс внутри окна.
func _fits(w: int, h: int, tag: String) -> void:
	root.size = Vector2i(w, h)
	for i in range(3):
		await process_frame
	var win := Rect2(Vector2.ZERO, Vector2(w, h))
	var worst := ""
	for node in _walk(_panel):
		var c := node as Control
		if c == null or not c.is_visible_in_tree():
			continue
		# Содержимое ScrollContainer по определению выше видимой области —
		# оно обрезается и прокручивается. Проверяем видимую часть интерфейса.
		if _inside_scroll(c):
			continue
		var r := Rect2(c.global_position, c.size)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not win.encloses(r):
			worst = "%s %s" % [c.name, str(r)]
			break
	_check(worst == "", "[%s] школа внутри окна%s" % [tag, "" if worst == "" else " — " + worst])

## Есть ли ScrollContainer среди предков.
func _inside_scroll(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

## Esc закрывает панель.
func _close_behaviour() -> void:
	var closed_fired := [false]
	_panel.closed.connect(func(): closed_fired[0] = true)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	_panel.call("_input", ev)
	await process_frame
	_check(closed_fired[0], "Esc закрывает панель")

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
		print("RESULT: OK school_ui_smoke")
		quit(0)
	else:
		print("RESULT: FAIL school_ui_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)
