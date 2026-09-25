extends SceneTree
## Smoke-проверка панели склада (scripts/ui.gd, узлы UI/BottomPanel/InventoryPanel).
##
## Проверяет, что склад собран контейнерами по правилам проекта:
##   — панель без фоновой картинки (PanelContainer + стиль темы, не TextureRect);
##   — ячейки PanelContainer, а не TextureRect с картинкой myitem.png;
##   — несколько колонок (сетка не в один ряд на 100 колонок) и вертикальная прокрутка;
##   — иконки не обрезаются (STRETCH_KEEP_ASPECT_CENTERED);
##   — у стака есть счётчик количества;
##   — панель мыши/фокус не блокирует: ячейки ловят клик.
##
## Запуск: godot --headless --path . --script res://tests/inventory_ui_smoke.gd

const ITEMS := [
	"iron_sword", "steel_armor", "wooden_shield",
	"potion_health_small", "potion_health_small", "potion_health_small",
]

var _fails: Array[String] = []

func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player = game.get("player")
	var ui = game.get("ui")
	await process_frame

	# Наполняем склад известными предметами (ключи берём из item_db).
	var added := 0
	for key in _known_item_keys():
		if added >= 12:
			break
		player.inventory.append(key)
		added += 1
	ui.call("refresh_inventory")
	await process_frame

	var panel: Control = ui.get("inventory_panel")
	var grid: GridContainer = ui.get("inventory_grid")
	var scroll: ScrollContainer = ui.get("inventory_scroll")
	var slots: Array = ui.get("inventory_slots")

	# 1. Панель — не картинка.
	_check(not (panel is TextureRect), "панель склада не TextureRect (была картинка invframe.bmp)")
	_check(panel is PanelContainer, "панель склада — PanelContainer")
	_check(panel.theme != null, "на панели висит единая тема UiKit")
	var sb: StyleBox = panel.get_theme_stylebox(&"panel")
	_check(sb != null, "у панели есть StyleBox из темы")

	# 2. Сетка: несколько колонок + вертикальная прокрутка.
	_check(grid.columns > 1, "сетка многоколоночная (columns=%d, был 1 ряд на 100)" % grid.columns)
	_check(grid.columns > 1 and grid.columns < 30, "число колонок разумное (%d)" % grid.columns)
	_check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "вертикальная прокрутка включена")
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "горизонтальная прокрутка отключена")
	_check(scroll.follow_focus, "прокрутка следует за фокусом")

	# 3. Ячейки — PanelContainer, без фоновой картинки слота.
	_check(slots.size() > 0, "склад наполнен (ячеек: %d)" % slots.size())
	var cells := 0
	var icons := 0
	var bad_stretch := 0
	var stacked_label := false
	for s in slots:
		if s is PanelContainer:
			cells += 1
		if s is TextureRect:
			_fails.append("ячейка осталась TextureRect с фоновой картинкой")
		for child in s.get_children():
			if child is TextureRect:
				var tr := child as TextureRect
				icons += 1
				if tr.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
					bad_stretch += 1
			elif child is Label and str((child as Label).text).is_valid_int():
				stacked_label = true
	_check(cells == slots.size(), "все ячейки — PanelContainer (%d из %d)" % [cells, slots.size()])
	_check(icons > 0, "иконки предметов на месте (%d)" % icons)
	_check(bad_stretch == 0, "иконки не обрезаются (KEEP_ASPECT_CENTERED), плохих: %d" % bad_stretch)
	_check(stacked_label, "у стака есть счётчик количества")

	# 4. Ячейка ловит мышь (иначе экипировка не работает).
	var clickable := 0
	for s in slots:
		if s.mouse_filter == Control.MOUSE_FILTER_STOP:
			clickable += 1
	_check(clickable == slots.size(), "все ячейки принимают клик (%d из %d)" % [clickable, slots.size()])

	# 5. Размер ячейки не меньше рекомендуемого — иначе иконку не разглядеть.
	var first: Control = slots[0] if slots.size() > 0 else null
	if first != null:
		var sz: Vector2 = first.custom_minimum_size
		_check(sz.x >= 56 and sz.y >= 56, "ячейка не мелкая (%.0fx%.0f)" % [sz.x, sz.y])

	_report()

## Несколько реальных ключей из item_db.
func _known_item_keys() -> Array[String]:
	var out: Array[String] = []
	for entry in ItemDB.all():
		var key := str((entry as Dictionary).get("key", ""))
		if key == "":
			continue
		out.append(key)
		if out.size() >= 12:
			break
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
		print("RESULT: OK inventory_ui_smoke")
		quit(0)
	else:
		print("RESULT: FAIL inventory_ui_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
