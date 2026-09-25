class_name ShopPanel
extends CanvasLayer

signal closed
signal inventory_changed

const CATEGORIES := [
	{"id": "armor", "label": "Броня", "rect": Rect2(60, 40, 120, 160)},
	{"id": "robe", "label": "Магическая броня", "rect": Rect2(850, 40, 130, 160)},
	{"id": "weapon", "label": "Оружие", "rect": Rect2(30, 850, 150, 140)},
	{"id": "potions", "label": "Зелья", "rect": Rect2(642, 842, 359, 156)},
	{"id": "books", "label": "Книги и свитки", "rect": Rect2(819, 473, 178, 370)},
]
const MERCHANT_LINES := [
	"Снаряжение дорожает с каждой новой стражей у ворот.",
	"Зелья всегда пригодятся: герои тоже умеют получать раны.",
	"Магические книги есть только у тех, кто действительно читает магию.",
	"Не торопись: хорошая броня окупается после второй вылазки.",
]
const _BG_PATH := "res://assets/shop/shop_human.jpeg"
const _DESIGN_SIZE := Vector2(1024, 1024)
const _NPC_ORIGIN := Vector2(26, 231)
const _NPC_CELL_SIZE := Vector2(95.5, 86.0)
const _NPC_COLUMNS := 2
const _NPC_ROWS := 7
const _PLAYER_ORIGIN := Vector2(250, 578)
const _PLAYER_CELL_SIZE := Vector2(90, 85.67)
const _PLAYER_COLUMNS := 6
const _PLAYER_ROWS := 3
const _PLAYER_TAB_ORIGIN := Vector2(216, 899)
const _PLAYER_TAB_CELL_SIZE := Vector2(100, 91)
const _CLOSE_SIZE := Vector2(150, 42)
const _CLOSE_POSITION := Vector2(742, 18)

var player: Player
var _panel_root: Control
var _npc_scroll: ScrollContainer
var _player_scroll: ScrollContainer
var _npc_grid: GridContainer
var _player_grid: GridContainer
var _player_tabs: GridContainer
var _gold_label: Label
var _hint_label: Label
var _merchant_label: Label
var _merchant_button: Button
var _close_button: Button
var _category_buttons: Array[Button] = []
var _category_group: ButtonGroup
var _previous_focus: Control
var _category_index := 0

static var _all_cache: Array = []

func setup(p: Player) -> void:
	player = p
	layer = 10
	if _all_cache.is_empty():
		_all_cache = ItemDB.all()
	_build_ui()

func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	UiKit.bind_resize(get_viewport(), _update_layout)
	_configure_category_focus()
	_refresh()

func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)

func _build_ui() -> void:
	var dim := UiKit.make_dim(0.58)
	add_child(dim)

	_panel_root = Control.new()
	_panel_root.name = "DesignRoot"
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.size = _DESIGN_SIZE
	_panel_root.theme = _make_theme()
	add_child(_panel_root)

	var background := TextureRect.new()
	background.name = "Background"
	if ResourceLoader.exists(_BG_PATH):
		background.texture = load(_BG_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.position = Vector2.ZERO
	background.size = _DESIGN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(background)

	var title := Label.new()
	title.theme_type_variation = &"ShopTitle"
	title.text = tr("МАГАЗИН")
	title.position = Vector2(300, 18)
	title.size = Vector2(250, 46)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(title)

	_gold_label = Label.new()
	_gold_label.theme_type_variation = &"ShopGoldLabel"
	_gold_label.position = Vector2(545, 24)
	_gold_label.size = Vector2(180, 36)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_gold_label)

	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = tr("Закрыть")
	_close_button.custom_minimum_size = _CLOSE_SIZE
	_close_button.position = _CLOSE_POSITION
	_close_button.size = _CLOSE_SIZE
	_close_button.pressed.connect(close)
	_panel_root.add_child(_close_button)

	_build_category_buttons()
	_build_shelves()
	_build_player_tabs()
	_build_merchant_panel()

	_hint_label = Label.new()
	_hint_label.name = "TradeHint"
	_hint_label.theme_type_variation = &"ShopHintLabel"
	_hint_label.position = Vector2(270, 544)
	_hint_label.size = Vector2(500, 30)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_hint_label)

func _build_category_buttons() -> void:
	_category_group = ButtonGroup.new()
	for index in range(CATEGORIES.size()):
		var category: Dictionary = CATEGORIES[index]
		var button := Button.new()
		button.name = "Category%d" % index
		button.text = str(category["label"])
		button.tooltip_text = str(category["label"])
		button.theme_type_variation = &"ShopCategoryButton"
		button.toggle_mode = true
		button.button_group = _category_group
		button.button_pressed = index == _category_index
		button.position = category["rect"].position
		button.size = category["rect"].size
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_set_category.bind(index))
		_panel_root.add_child(button)
		_category_buttons.append(button)

func _configure_category_focus() -> void:
	for index in range(_category_buttons.size()):
		var button := _category_buttons[index]
		button.focus_previous = _category_buttons[maxi(index - 1, 0)].get_path()
		button.focus_next = _category_buttons[mini(index + 1, _category_buttons.size() - 1)].get_path()

func _build_shelves() -> void:
	_npc_scroll = ScrollContainer.new()
	_npc_scroll.name = "NpcShelfScroll"
	_npc_scroll.position = _NPC_ORIGIN
	_npc_scroll.size = Vector2(_NPC_CELL_SIZE.x * _NPC_COLUMNS, _NPC_CELL_SIZE.y * _NPC_ROWS)
	_npc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_npc_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_npc_scroll.follow_focus = true
	_npc_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.add_child(_npc_scroll)

	_npc_grid = GridContainer.new()
	_npc_grid.name = "NpcShelf"
	_npc_grid.columns = _NPC_COLUMNS
	_npc_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_grid.add_theme_constant_override("h_separation", 0)
	_npc_grid.add_theme_constant_override("v_separation", 0)
	_npc_scroll.add_child(_npc_grid)

	_player_scroll = ScrollContainer.new()
	_player_scroll.name = "PlayerShelfScroll"
	_player_scroll.position = _PLAYER_ORIGIN
	_player_scroll.size = Vector2(_PLAYER_CELL_SIZE.x * _PLAYER_COLUMNS, _PLAYER_CELL_SIZE.y * _PLAYER_ROWS)
	_player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_player_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_player_scroll.follow_focus = true
	_player_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.add_child(_player_scroll)

	_player_grid = GridContainer.new()
	_player_grid.name = "PlayerShelf"
	_player_grid.columns = _PLAYER_COLUMNS
	_player_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_grid.add_theme_constant_override("h_separation", 0)
	_player_grid.add_theme_constant_override("v_separation", 0)
	_player_scroll.add_child(_player_grid)

func _build_player_tabs() -> void:
	_player_tabs = GridContainer.new()
	_player_tabs.name = "PlayerTab"
	_player_tabs.columns = 4
	_player_tabs.position = _PLAYER_TAB_ORIGIN
	_player_tabs.size = Vector2(_PLAYER_TAB_CELL_SIZE.x * 4, _PLAYER_TAB_CELL_SIZE.y)
	_player_tabs.add_theme_constant_override("h_separation", 0)
	_player_tabs.add_theme_constant_override("v_separation", 0)
	_panel_root.add_child(_player_tabs)
	for index in range(4):
		_player_tabs.add_child(_make_player_tab(index == 0))

func _make_player_tab(active: bool) -> PanelContainer:
	var tab := PanelContainer.new()
	tab.theme_type_variation = &"ShopPlayerTab"
	tab.custom_minimum_size = _PLAYER_TAB_CELL_SIZE
	var margin := MarginContainer.new()
	_set_margins(margin, 5, 4, 5, 4)
	tab.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	margin.add_child(content)
	if active:
		var portrait := TextureRect.new()
		portrait.name = "HeroPortrait"
		portrait.texture = _hero_portrait()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(portrait)
		var label := Label.new()
		label.text = tr("Герой")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
	else:
		var empty := Label.new()
		empty.theme_type_variation = &"ShopEmptyTabLabel"
		empty.text = tr("Пусто")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(empty)
	return tab

func _build_merchant_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "MerchantPanel"
	panel.theme_type_variation = &"ShopDialogPanel"
	panel.position = Vector2(350, 486)
	panel.size = Vector2(350, 78)
	_panel_root.add_child(panel)
	var margin := MarginContainer.new()
	_set_margins(margin, 12, 8, 12, 8)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	_merchant_label = Label.new()
	_merchant_label.name = "MerchantText"
	_merchant_label.text = tr("Торговец предлагает снаряжение и зелья.")
	_merchant_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_merchant_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merchant_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_merchant_label)
	_merchant_button = Button.new()
	_merchant_button.name = "Talk"
	_merchant_button.text = tr("Поговорить")
	_merchant_button.custom_minimum_size = Vector2(150, 38)
	_merchant_button.pressed.connect(_talk)
	row.add_child(_merchant_button)

func _update_layout() -> void:
	UiKit.fit_design_root(_panel_root, _DESIGN_SIZE)

func _refresh() -> void:
	if not is_instance_valid(player):
		return
	_gold_label.text = tr("Золото: %d") % player.gold
	_hint_label.text = tr("Сверху покупка · снизу продажа · заблокированное не хватает золота")
	for index in range(_category_buttons.size()):
		_category_buttons[index].button_pressed = index == _category_index
	var npc_buttons := _build_buy_shelf(_category_index)
	var player_buttons := _build_sell_list()
	_configure_focus(npc_buttons, player_buttons)
	if not npc_buttons.is_empty():
		npc_buttons[0].call_deferred("grab_focus")
	elif not player_buttons.is_empty():
		player_buttons[0].call_deferred("grab_focus")
	else:
		_category_buttons[_category_index].call_deferred("grab_focus")

func _set_category(index: int) -> void:
	_category_index = clampi(index, 0, CATEGORIES.size() - 1)
	_refresh()

func _build_buy_shelf(category_index: int) -> Array[Button]:
	_clear_grid(_npc_grid)
	var pool := _category_items(category_index)
	pool.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("price", 0)) < int(b.get("price", 0)))
	var buttons: Array[Button] = []
	for item in pool:
		var slot := _make_shop_slot(item, true, 1)
		_npc_grid.add_child(slot)
		var button := slot.find_child("Trade", true, false) as Button
		if button != null:
			button.disabled = player.gold < int(item.get("price", 0))
			if not button.disabled:
				buttons.append(button)
	return buttons

func _build_sell_list() -> Array[Button]:
	_clear_grid(_player_grid)
	var entries: Array[Dictionary] = []
	if is_instance_valid(player):
		var seen: Dictionary = {}
		for key in player.inventory:
			var item := ItemDB.find(str(key))
			if item.is_empty():
				continue
			var item_key := str(key)
			seen[item_key] = int(seen.get(item_key, 0)) + 1
		for item_key in seen:
			entries.append({
				"item": ItemDB.find(item_key),
				"count": int(seen[item_key]),
				"price": maxi(1, int(ItemDB.find(item_key).get("price", 0)) / 2),
			})
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["price"]) < int(b["price"]))
	var buttons: Array[Button] = []
	for entry in entries:
		var item: Dictionary = entry.get("item", {})
		var slot := _make_shop_slot(item, false, int(entry.get("count", 1)))
		_player_grid.add_child(slot)
		var button := slot.find_child("Trade", true, false) as Button
		if button != null:
			buttons.append(button)
	return buttons

func _make_shop_slot(item: Dictionary, buying: bool, count: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"ShopItemSlot"
	slot.custom_minimum_size = _NPC_CELL_SIZE if buying else _PLAYER_CELL_SIZE
	var margin := MarginContainer.new()
	_set_margins(margin, 2, 2, 2, 2)
	slot.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	margin.add_child(content)
	if item.is_empty():
		return slot
	var key := str(item.get("key", ""))
	var name := str(item.get("name_ru", key))
	var price := int(item.get("price", 0))
	var icon := TextureRect.new()
	var icon_path := str(item.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(0, 52 if buying else 42)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 1)
	content.add_child(actions)
	if not buying and count > 1:
		var count_label := Label.new()
		count_label.theme_type_variation = &"ShopCountLabel"
		count_label.text = "×%d" % count
		count_label.custom_minimum_size = Vector2(20, 22)
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(count_label)
	var button := Button.new()
	button.name = "Trade"
	button.text = tr("Купить %d") % price if buying else tr("%d з") % (maxi(1, price / 2))
	button.tooltip_text = "%s — %s" % [name, tr("продать за %d з") % (maxi(1, price / 2)) if not buying else tr("купить за %d з") % price]
	button.custom_minimum_size = Vector2(0, 22)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_buy_item.bind(key, price) if buying else _sell_item.bind(key, maxi(1, price / 2)))
	actions.add_child(button)
	return slot

func _category_items(category_index: int) -> Array[Dictionary]:
	var category := str(CATEGORIES[category_index]["id"])
	var pool: Array[Dictionary] = []
	for raw in _all_cache:
		var item: Dictionary = raw
		var quality := str(item.get("quality", ""))
		var price := int(item.get("price", 0))
		if price <= 0 or price > 60000:
			continue
		var matches := false
		match category:
			"armor":
				matches = ItemDB.is_equippable(item) and ItemDB.slot_of(item) != "weapon" and ItemDB.armor_kind(item) == "heavy"
			"robe":
				matches = ItemDB.is_equippable(item) and ItemDB.slot_of(item) != "weapon" and ItemDB.armor_kind(item) == "light"
			"weapon":
				matches = ItemDB.slot_of(item) == "weapon"
			"potions":
				matches = quality == "Potion"
			"books":
				matches = quality in ["Scroll", "SuperScroll"]
		if matches:
			pool.append(item)
	if category == "books" and is_instance_valid(player) and player.has_mana:
		for spell in SpellDB.catalog_spells():
			pool.append(SpellDB.make_book_item(spell))
	return pool

func _configure_focus(npc_buttons: Array[Button], player_buttons: Array[Button]) -> void:
	_wire_grid_focus(npc_buttons, _NPC_COLUMNS)
	_wire_grid_focus(player_buttons, _PLAYER_COLUMNS)
	var first_target: Control = _category_buttons[_category_index]
	if not npc_buttons.is_empty():
		first_target = npc_buttons[0]
	elif not player_buttons.is_empty():
		first_target = player_buttons[0]
	_category_buttons[_category_index].focus_next = first_target.get_path()
	first_target.focus_previous = _category_buttons[_category_index].get_path()
	if not npc_buttons.is_empty() and not player_buttons.is_empty():
		npc_buttons[-1].focus_next = player_buttons[0].get_path()
		player_buttons[0].focus_previous = npc_buttons[-1].get_path()
	var last_action: Control = npc_buttons[-1] if not npc_buttons.is_empty() else (player_buttons[-1] if not player_buttons.is_empty() else first_target)
	last_action.focus_next = _merchant_button.get_path()
	_merchant_button.focus_previous = last_action.get_path()
	_merchant_button.focus_next = _close_button.get_path()
	_close_button.focus_previous = _merchant_button.get_path()
	_close_button.focus_next = _category_buttons[0].get_path()

func _wire_grid_focus(buttons: Array[Button], columns: int) -> void:
	UiKit.wire_grid_focus(buttons, columns)

func _hero_portrait() -> Texture2D:
	var equipment_path := "res://assets/equipment/%s/1.png" % Game.hero_character_id
	if ResourceLoader.exists(equipment_path):
		return load(equipment_path) as Texture2D
	if is_instance_valid(player):
		var preview := UnitDB.preview_frame(player.anim_set_name())
		if preview != null:
			return preview
	if ResourceLoader.exists("res://assets/sprites/hero.png"):
		return load("res://assets/sprites/hero.png") as Texture2D
	return null

func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	UiKit.set_margins(container, left, top, right, bottom)

func _make_theme() -> Theme:
	var theme := UiKit.base_theme({
		"font_size": 14,
		"font_color": Color(0.96, 0.90, 0.76),
		"radius": 5, "margin": 4,
		"normal_bg": Color(0.23, 0.13, 0.07, 0.96),
		"normal_border": Color(0.70, 0.40, 0.14),
		"hover_bg": Color(0.36, 0.19, 0.08, 0.98),
		"hover_border": Color(1.0, 0.74, 0.26),
		"pressed_bg": Color(0.15, 0.08, 0.04, 1.0),
		"pressed_border": Color(0.66, 0.36, 0.12),
		"disabled_bg": Color(0.15, 0.13, 0.12, 0.90),
		"disabled_border": Color(0.34, 0.29, 0.25),
		"focus_border": Color(1.0, 0.78, 0.20),
		"scrollbar": true,
	})
	UiKit.add_title(theme, &"ShopTitle")
	UiKit.add_gold_label(theme, &"ShopGoldLabel")
	UiKit.add_label(theme, &"ShopHintLabel", UiKit.HINT_COLOR, UiKit.HINT_SIZE)
	UiKit.add_slot(theme, &"ShopItemSlot")
	UiKit.add_panel(theme, &"ShopPlayerTab",
		Color(0.09, 0.10, 0.15, 0.86), Color(0.48, 0.42, 0.24, 0.96), 4)
	UiKit.add_panel(theme, &"ShopDialogPanel",
		Color(0.10, 0.08, 0.07, 0.88), UiKit.DIALOG_BORDER, 4)
	UiKit.add_label(theme, &"ShopEmptyTabLabel", Color(0.54, 0.50, 0.43), 15)
	UiKit.add_label(theme, &"ShopCountLabel", Color(1.0, 0.88, 0.58), 12)
	# Категория — прозрачная кнопка-чип: в покое без заливки и рамки.
	theme.set_type_variation(&"ShopCategoryButton", &"Button")
	theme.set_color("font_color", &"ShopCategoryButton", Color(1.0, 0.82, 0.48))
	theme.set_font_size("font_size", &"ShopCategoryButton", 16)
	theme.set_stylebox("normal", &"ShopCategoryButton",
		UiKit.ghost_button_style(Color(0, 0, 0, 0), 0, 5, 4))
	theme.set_stylebox("hover", &"ShopCategoryButton",
		UiKit.button_style(Color(0.12, 0.06, 0.02, 0.18), Color(1.0, 0.78, 0.26, 0.60), 2, 5, 4))
	theme.set_stylebox("pressed", &"ShopCategoryButton",
		UiKit.button_style(Color(0.14, 0.07, 0.02, 0.30), Color(0.96, 0.66, 0.20, 0.95), 2, 5, 4))
	theme.set_stylebox("focus", &"ShopCategoryButton",
		UiKit.button_style(Color(0, 0, 0, 0), Color(1.0, 0.82, 0.28, 0.95), 3, 5, 4))
	return theme

func _clear_grid(grid: GridContainer) -> void:
	UiKit.clear(grid)

func _buy_item(key: String, price: int) -> void:
	if not is_instance_valid(player) or player.gold < price:
		return
	player.gold -= price
	player.add_item(key)
	SoundDB.play(9)
	inventory_changed.emit()
	_refresh()
	print("Куплено: " + key)

func _sell_item(key: String, price: int) -> void:
	if not is_instance_valid(player) or not player.remove_item(key):
		return
	player.gold += price
	SoundDB.play(9)
	inventory_changed.emit()
	_refresh()
	print("Продано: " + key)

func _talk() -> void:
	if not is_instance_valid(_merchant_label):
		return
	var lines: Array = MERCHANT_LINES.duplicate()
	_merchant_label.text = tr("Торговец: «%s»") % str(lines[randi() % lines.size()])

func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
