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
	# Панель склада надо ОТКРЫТЬ: раньше тест брал поля прямо у ui
	# (inventory_panel/inventory_grid/inventory_slots), но эти узлы живут
	# внутри InventoryPanel, который ui создаёт только по open_inventory_panel().
	# ui.get("inventory_grid") возвращал Nil, и скрипт падал на присваивании
	# Nil в типизированную Array - после чего висел до конца прогона.
	ui.call("open_inventory_panel")
	await process_frame
	await process_frame

	var inv: Node = ui.get("_inventory_panel")
	_check(inv != null, "склад открыт и панель создана")
	if inv == null:
		_report()
		return

	# Узлы берём из полей самой панели (_inventory_grid/_inventory_scroll), а НЕ
	# обходом дерева: внутри панели есть чужие ScrollContainer/GridContainer, и
	# первый найденный - не складской.
	var panel = _first_of_type(inv, "PanelContainer")
	var grid = inv.get("_inventory_grid")
	var scroll = inv.get("_inventory_scroll")
	var slots: Array = inv.get("_inventory_slots")
	# Тема висит на корневом MarginContainer (_root), а не на DesignRoot —
	# DesignRoot убран 06.10 (контейнерный паттерн как у shop/inn).
	var theme_root: Control = inv.get("_root")
	if theme_root == null:
		theme_root = inv.get("_panel_root")

	# 1. Панель — не картинка.
	_check(not (panel is TextureRect), "панель склада не TextureRect (была картинка invframe.bmp)")
	_check(panel is PanelContainer, "панель склада — PanelContainer")
	_check(theme_root != null and theme_root.theme != null,
		"на панели висит единая тема UiKit")
	var sb: StyleBox = panel.get_theme_stylebox(&"panel")
	_check(sb != null, "у панели есть StyleBox из темы")
	_check(inv.get("_panel_root") == null, "DesignRoot 1024×768 убран")

	# 2. Сетка: несколько колонок + вертикальная прокрутка.
	_check(grid.columns > 1, "сетка многоколоночная (columns=%d, был 1 ряд на 100)" % grid.columns)
	_check(grid.columns > 1 and grid.columns < 30, "число колонок разумное (%d)" % grid.columns)
	_check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "вертикальная прокрутка включена")
	# Godot 4: горизонтальная прокрутка отключена через SCROLL_MODE_DISABLED.
	# Старое SCROLL_MODE_SHOW_NEVER в 4.7 объявлено устаревшим в пользу DISABLED,
	# и панель использует именно его.
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"горизонтальная прокрутка отключена (mode=%d)" % scroll.horizontal_scroll_mode)
	_check(scroll.follow_focus, "прокрутка следует за фокусом")

	# 2×2 вариант A: имя над куклой, статы секциями, без name_label в статах
	_check(inv.get("_stats_box") != null, "блок характеристик в инвентаре")
	_check(inv.get("_equip_slots") is Dictionary and (inv.get("_equip_slots") as Dictionary).size() >= 8,
		"слоты экипировки на месте")
	_check(inv.get("_hero_name") is Label and str((inv.get("_hero_name") as Label).text) != "",
		"имя героя над куклой")
	_check(inv.get("_stat_labels") is Dictionary and not (inv.get("_stat_labels") as Dictionary).has("name_label"),
		"имя не в статах (вариант A)")
	var stats_scroll = inv.get("_stats_scroll")
	_check(stats_scroll is ScrollContainer, "статы со скроллом")
	var sec_titles := 0
	var sbox = inv.get("_stats_box")
	if sbox != null:
		for c in (sbox as Node).get_children():
			if c is HBoxContainer:
				for lab in (c as HBoxContainer).get_children():
					if lab is Label and str((lab as Label).text).to_upper() in [
						"АТРИБУТЫ", "БОЙ", "НАВЫКИ", "ПРОЧЕЕ"]:
						sec_titles += 1
	_check(sec_titles >= 3, "в статах есть секции (найдено заголовков: %d)" % sec_titles)
	var shield_lab = inv.get("_shield_label")
	_check(shield_lab is Label, "строка «Щит» в характеристиках")
	var stats_col = inv.get("_stats_col")
	if stats_col == null and panel is Control:
		stats_col = (panel as Control).find_child("StatsCol", true, false)
	_check(stats_col != null, "колонка статов существует")
	if stats_col is Control:
		# Колонка не должна тянуться на пол-окна (EXPAND_FILL).
		_check(not ((stats_col as Control).size_flags_horizontal & Control.SIZE_EXPAND_FILL),
			"StatsCol без EXPAND_FILL (узкая колонка)")

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
## Первый узел дерева node, совпадающий с именем класса. Нужно, потому что
## InventoryPanel строит сетку и скролл анонимно (без name), и поля у самой
## панели нет - всё держится на переменных с подчёркиванием.
func _first_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var got := _first_of_type(child, type_name)
		if got != null:
			return got
	return null

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
