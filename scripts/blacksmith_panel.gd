class_name BlacksmithPanel
extends CanvasLayer

signal closed
## Склад героя изменился (появился слиток) — GameUI пересобирает свою сетку.
signal inventory_changed

const _DEFAULT_INGOT := "iron"
const _BG_PATH := "res://assets/blacksmith/blacksmith.jpeg"
const _DESIGN_SIZE := Vector2(1024, 1024)
const _OUTPUT_ORIGIN := Vector2(46, 210)
const _OUTPUT_CELL_SIZE := Vector2(172, 91.857)
const _OUTPUT_ROWS := 7
const _INVENTORY_ORIGIN := Vector2(265, 789)
const _INVENTORY_CELL_SIZE := Vector2(123.5, 114.5)
const _INVENTORY_COLUMNS := 6
const _INVENTORY_ROWS := 2

var player: Player
var _panel_root: Control
var _output_grid: GridContainer
var _inventory_grid: GridContainer
var _close_button: Button
var _previous_focus: Control
var _output_items: Array[Dictionary] = []

func setup(p: Player) -> void:
	player = p
	layer = 10
	_build_ui()

func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	UiKit.bind_resize(get_viewport(), _update_layout)
	_refresh()

func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)

func _build_ui() -> void:
	var dim := UiKit.make_dim(0.6)
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
	title.text = tr("КУЗНИЦА")
	title.theme_type_variation = &"BlacksmithTitle"
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2(20, 14)
	title.size = Vector2(320, 44)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(title)

	_close_button = Button.new()
	_close_button.text = tr("Закрыть")
	_close_button.custom_minimum_size = Vector2(170, 44)
	_close_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# После PRESET_BOTTOM_RIGHT Position/size задавать нельзя: якорь уже привязан
	# к правому нижнему углу, и присваивание position уводило кнопку за экран.
	# После якоря — только offset_* (та же ошибка была в inn_panel).
	_close_button.offset_left = -194.0
	_close_button.offset_top = -68.0
	_close_button.offset_right = -24.0
	_close_button.offset_bottom = -24.0
	_close_button.pressed.connect(close)
	_panel_root.add_child(_close_button)

	_output_grid = GridContainer.new()
	_output_grid.name = "BlacksmithOutput"
	_output_grid.columns = 1
	_output_grid.position = _OUTPUT_ORIGIN
	_output_grid.size = Vector2(_OUTPUT_CELL_SIZE.x, _OUTPUT_CELL_SIZE.y * _OUTPUT_ROWS)
	_output_grid.add_theme_constant_override("h_separation", 0)
	_output_grid.add_theme_constant_override("v_separation", 0)
	_panel_root.add_child(_output_grid)

	_inventory_grid = GridContainer.new()
	_inventory_grid.name = "PlayerInventory"
	_inventory_grid.columns = _INVENTORY_COLUMNS
	_inventory_grid.position = _INVENTORY_ORIGIN
	_inventory_grid.size = Vector2(
		_INVENTORY_CELL_SIZE.x * _INVENTORY_COLUMNS,
		_INVENTORY_CELL_SIZE.y * _INVENTORY_ROWS
	)
	_inventory_grid.add_theme_constant_override("h_separation", 0)
	_inventory_grid.add_theme_constant_override("v_separation", 0)
	_panel_root.add_child(_inventory_grid)

func _update_layout() -> void:
	UiKit.fit_design_root(_panel_root, _DESIGN_SIZE)

func _refresh() -> void:
	_clear_grid(_output_grid)
	_clear_grid(_inventory_grid)
	_build_output_slots()
	_build_inventory_slots()

func _build_output_slots() -> void:
	for row in range(_OUTPUT_ROWS):
		var slot := PanelContainer.new()
		slot.theme_type_variation = &"BlacksmithOutputSlot"
		slot.custom_minimum_size = _OUTPUT_CELL_SIZE
		_output_grid.add_child(slot)

		var margin := MarginContainer.new()
		_set_margins(margin, 8, 8, 8, 8)
		slot.add_child(margin)

		if row >= _output_items.size():
			continue
		var item: Dictionary = _output_items[row]
		var ingot_path := _ingot_path(str(item.get("material", "")))
		if not ingot_path.is_empty():
			var icon := TextureRect.new()
			icon.texture = load(ingot_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			margin.add_child(icon)

func _build_inventory_slots() -> void:
	var equip_items: Array[Dictionary] = []
	if is_instance_valid(player):
		var seen: Dictionary = {}
		for key in player.inventory:
			var item := ItemDB.find(str(key))
			if item.is_empty() or not ItemDB.is_equippable(item):
				continue
			# Кузнец берёт только металлы: кожа, дерево и ткань в список не попадают
			# (переплавка кожи в металл бессмыслина — решение игрока).
			if not ItemDB.is_smeltable(item):
				continue
			var item_key := str(key)
			seen[item_key] = int(seen.get(item_key, 0)) + 1
		for item_key in seen:
			equip_items.append({
				"key": item_key,
				"count": int(seen[item_key]),
				"item": ItemDB.find(item_key),
			})

	var action_buttons: Array[Button] = []
	for row in range(_INVENTORY_ROWS):
		for column in range(_INVENTORY_COLUMNS):
			var index := row * _INVENTORY_COLUMNS + column
			var slot := _make_inventory_slot(equip_items[index] if index < equip_items.size() else {})
			_inventory_grid.add_child(slot)
			var button := slot.find_child("Smelt", true, false) as Button
			if button != null:
				action_buttons.append(button)

	_configure_focus(action_buttons)
	if not action_buttons.is_empty():
		action_buttons[0].call_deferred("grab_focus")
	elif is_instance_valid(_close_button):
		_close_button.call_deferred("grab_focus")

func _make_inventory_slot(entry: Dictionary) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"BlacksmithInventorySlot"
	slot.custom_minimum_size = _INVENTORY_CELL_SIZE

	var margin := MarginContainer.new()
	margin.name = "Margin"
	_set_margins(margin, 5, 5, 5, 5)
	slot.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 3)
	margin.add_child(content)

	if entry.is_empty():
		return slot

	var item: Dictionary = entry["item"]
	var icon_path := str(item.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon.custom_minimum_size = Vector2(0, 68)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 3)
	content.add_child(actions)

	if int(entry["count"]) > 1:
		var count := Label.new()
		count.theme_type_variation = &"BlacksmithCountLabel"
		count.text = "×%d" % int(entry["count"])
		count.custom_minimum_size = Vector2(30, 28)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(count)

	var button := Button.new()
	button.name = "Smelt"
	button.text = tr("Плавить")
	button.custom_minimum_size = Vector2(76, 28)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_smelt_item.bind(str(entry["key"])))
	actions.add_child(button)
	return slot

func _configure_focus(buttons: Array[Button]) -> void:
	for index in range(buttons.size()):
		var button := buttons[index]
		var left := buttons[(index - 1 + buttons.size()) % buttons.size()]
		var right := buttons[(index + 1) % buttons.size()]
		button.focus_neighbor_left = left.get_path()
		button.focus_neighbor_right = right.get_path()
		button.focus_neighbor_top = buttons[maxi(index - _INVENTORY_COLUMNS, 0)].get_path()
		button.focus_neighbor_bottom = buttons[mini(index + _INVENTORY_COLUMNS, buttons.size() - 1)].get_path()
		button.focus_previous = buttons[maxi(index - 1, 0)].get_path()
		button.focus_next = buttons[mini(index + 1, buttons.size() - 1)].get_path()
	if not buttons.is_empty() and is_instance_valid(_close_button):
		buttons[0].focus_next = _close_button.get_path()
		buttons[-1].focus_previous = _close_button.get_path()
		_close_button.focus_previous = buttons[-1].get_path()
		_close_button.focus_next = buttons[0].get_path()

func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	UiKit.set_margins(container, left, top, right, bottom)

func _make_theme() -> Theme:
	# Раньше здесь не было стиля disabled и font_disabled_color — кнопка
	# «Плавить» в неактивном состоянии рисовалась системной серой. Теперь
	# берёт общую тёплую кнопку интерьера (видимое, но правильное изменение).
	var theme := UiKit.base_theme({
		"font_size": 14,
		"font_color": Color(0.95, 0.88, 0.72),
		"font_hover_color": Color(1.0, 0.9, 0.55),
		"font_pressed_color": Color(1.0, 1.0, 0.9),
		"font_focus_color": Color(1.0, 0.9, 0.55),
		"radius": 6, "margin": 6,
		"normal_bg": Color(0.22, 0.12, 0.07, 0.96),
		"normal_border": Color(0.72, 0.40, 0.12),
		"hover_bg": Color(0.32, 0.17, 0.08, 0.98),
		"hover_border": Color(1.0, 0.72, 0.25),
		"pressed_bg": Color(0.14, 0.07, 0.04, 1.0),
		"pressed_border": Color(0.65, 0.34, 0.10),
		"focus_border": Color(1.0, 0.75, 0.20),
		"scrollbar": true,
	})
	UiKit.add_title(theme, &"BlacksmithTitle")
	UiKit.add_panel(theme, &"BlacksmithOutputSlot",
		Color(0.12, 0.09, 0.07, 0.70), Color(0.58, 0.35, 0.14, 0.90), 4)
	UiKit.add_panel(theme, &"BlacksmithInventorySlot",
		Color(0.08, 0.09, 0.13, 0.78), Color(0.45, 0.30, 0.16, 0.95), 4)
	UiKit.add_label(theme, &"BlacksmithCountLabel", Color.WHITE, 13)
	return theme

func _clear_grid(grid: GridContainer) -> void:
	UiKit.clear(grid)

## Переплавить предмет: забрать его из инвентаря и отдать слиток его материала.
## Раньше предмет просто исчезал — player.add_item() не вызывался нигде, и
## игрок терял вещь, не получив ничего.
func _smelt_item(key: String) -> void:
	if not is_instance_valid(player):
		return
	var item := ItemDB.find(key)
	var material := str(item.get("material", ""))
	if not ItemDB.is_smeltable(item):
		print("Кузнец не берёт: %s (материал %s)" % [key, material])
		return
	var ingot_key := ItemDB.ingot_key(material)
	if ingot_key == "":
		print("Нет слитка для материала %s" % material)
		return
	# Сначала проверяем, что слот найден: снимать вещь, не отдав слиток, нельзя.
	if not player.remove_item(key):
		return
	player.add_item(ingot_key)
	_output_items.append({"key": key, "material": material})
	SoundDB.play(9)
	print("Переплавлено: %s → %s" % [key, ingot_key])
	# Склад героя должен увидеть новый слиток сразу, а не после переоткрытия панели.
	inventory_changed.emit()
	_refresh()

## Иконка слитка берётся из самого предмета item_db (поле icon), чтобы путь
## жил в данных, а не в коде панели.
func _ingot_path(material: String) -> String:
	var ingot := ItemDB.find(ItemDB.ingot_key(material))
	var path := str(ingot.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		return path
	return ""

func _ingot_material(material: String) -> String:
	return material if ItemDB.is_smeltable(ItemDB.find("%s Ingot" % material)) else _DEFAULT_INGOT

func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
