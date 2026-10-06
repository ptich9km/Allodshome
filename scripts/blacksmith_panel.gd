class_name BlacksmithPanel
extends CanvasLayer

signal closed
## Склад героя изменился (появился слиток) — GameUI пересобирает свою сетку.
signal inventory_changed

const _DEFAULT_INGOT := "iron"
## 05.10: JPEG blacksmith.jpeg убран. Раскладка контейнерная, UiTheme.
## Ячейки вывода и склада ОДИНАКОВЫЕ — иначе слитки и вещи выглядят разным калибром.
const _OUTPUT_COLUMNS := 4
const _CELL := Vector2(100, 100)
const _INV_COLUMNS := 4

var player: Player
var _root: MarginContainer
var _panel: PanelContainer
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
	_refresh()

func _exit_tree() -> void:
	pass

func _build_ui() -> void:
	var dim := UiKit.make_dim(0.6)
	add_child(dim)

	_root = MarginContainer.new()
	_root.name = "BlacksmithRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.set_margins(_root, UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET,
		UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET)
	_root.theme = _make_theme()
	add_child(_root)

	var center := HBoxContainer.new()
	center.name = "Center"
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var side := Control.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(side)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"BlacksmithPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	UiKit.set_margins(margin, UiTheme.SPACE_4, UiTheme.SPACE_3,
		UiTheme.SPACE_4, UiTheme.SPACE_3)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", UiTheme.SPACE_2)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", UiTheme.SPACE_3)
	content.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = tr("КУЗНИЦА")
	title.theme_type_variation = &"BlacksmithTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = tr("Закрыть")
	_close_button.theme_type_variation = &"BlacksmithClose"
	_close_button.custom_minimum_size = Vector2(120, 32)
	_close_button.pressed.connect(close)
	header.add_child(_close_button)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", UiTheme.SPACE_3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	var out_col := VBoxContainer.new()
	out_col.name = "OutputCol"
	out_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(out_col)
	var out_title := Label.new()
	out_title.theme_type_variation = &"BlacksmithSection"
	out_title.text = tr("Переплавка")
	out_col.add_child(out_title)
	var out_scroll := ScrollContainer.new()
	out_scroll.name = "OutputScroll"
	out_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	out_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	out_scroll.follow_focus = true
	out_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_col.add_child(out_scroll)
	_output_grid = GridContainer.new()
	_output_grid.name = "BlacksmithOutput"
	_output_grid.columns = _OUTPUT_COLUMNS
	_output_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_grid.add_theme_constant_override("h_separation", UiTheme.SPACE_1)
	_output_grid.add_theme_constant_override("v_separation", UiTheme.SPACE_1)
	out_scroll.add_child(_output_grid)

	var inv_col := VBoxContainer.new()
	inv_col.name = "InvCol"
	inv_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(inv_col)
	var inv_title := Label.new()
	inv_title.theme_type_variation = &"BlacksmithSection"
	inv_title.text = tr("Склад (металлы)")
	inv_col.add_child(inv_title)
	var inv_scroll := ScrollContainer.new()
	inv_scroll.name = "InvScroll"
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inv_scroll.follow_focus = true
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_col.add_child(inv_scroll)
	_inventory_grid = GridContainer.new()
	_inventory_grid.name = "PlayerInventory"
	_inventory_grid.columns = _INV_COLUMNS
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_grid.add_theme_constant_override("h_separation", UiTheme.SPACE_1)
	_inventory_grid.add_theme_constant_override("v_separation", UiTheme.SPACE_1)
	inv_scroll.add_child(_inventory_grid)

func _refresh() -> void:
	_clear_grid(_output_grid)
	_clear_grid(_inventory_grid)
	_build_output_slots()
	_build_inventory_slots()

func _build_output_slots() -> void:
	var cells := maxi(_output_items.size(), _OUTPUT_COLUMNS)
	for i in range(cells):
		var slot := PanelContainer.new()
		slot.theme_type_variation = &"BlacksmithOutputSlot"
		slot.custom_minimum_size = _CELL
		_output_grid.add_child(slot)
		var margin := MarginContainer.new()
		_set_margins(margin, UiTheme.SPACE_1, UiTheme.SPACE_1, UiTheme.SPACE_1, UiTheme.SPACE_1)
		slot.add_child(margin)
		if i >= _output_items.size():
			continue
		var item: Dictionary = _output_items[i]
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
	var cells := maxi(equip_items.size(), _INV_COLUMNS)
	for i in range(cells):
		var slot := _make_inventory_slot(equip_items[i] if i < equip_items.size() else {})
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
	slot.custom_minimum_size = _CELL

	var margin := MarginContainer.new()
	margin.name = "Margin"
	_set_margins(margin, UiTheme.SPACE_1, UiTheme.SPACE_1, UiTheme.SPACE_1, UiTheme.SPACE_1)
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
		icon.custom_minimum_size = Vector2(0, 64)
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
		count.custom_minimum_size = Vector2(30, 24)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(count)

	var button := Button.new()
	button.name = "Smelt"
	button.text = tr("Плавить")
	button.custom_minimum_size = Vector2(76, 26)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_smelt_item.bind(str(entry["key"])))
	actions.add_child(button)
	return slot

func _configure_focus(buttons: Array[Button]) -> void:
	UiKit.wire_grid_focus(buttons, _INV_COLUMNS)
	if buttons.is_empty() or not is_instance_valid(_close_button):
		return
	buttons[0].focus_next = _close_button.get_path()
	buttons[-1].focus_previous = _close_button.get_path()
	_close_button.focus_previous = buttons[-1].get_path()
	_close_button.focus_next = buttons[0].get_path()

func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	UiKit.set_margins(container, left, top, right, bottom)

func _make_theme() -> Theme:
	var theme := UiTheme.app_theme()
	theme.set_stylebox("normal", "Button", UiKit.button_style(
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE,
		UiTheme.BORDER_NORMAL, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	theme.set_stylebox("hover", "Button", UiKit.button_style(
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.BORDER_NORMAL, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	theme.set_stylebox("pressed", "Button", UiKit.button_style(
		UiTheme.BG_DEEP, UiTheme.PANEL_EDGE,
		UiTheme.BORDER_NORMAL, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	theme.set_stylebox("focus", "Button", UiKit.button_style(
		UiTheme.TRANSPARENT, UiTheme.ACCENT,
		UiTheme.BORDER_FOCUS, UiTheme.RADIUS_PANEL, UiTheme.SPACE_2))
	UiKit.apply_scrollbar(theme, UiTheme.RADIUS_SLOT, UiTheme.SPACE_1)
	UiKit.add_panel(theme, &"BlacksmithPanel",
		UiTheme.PANEL_BG, UiTheme.PANEL_EDGE, UiTheme.RADIUS_FRAME)
	UiTheme.add_display_label(theme, &"BlacksmithTitle", UiTheme.FONT_TITLE, UiTheme.ACCENT)
	UiKit.add_label(theme, &"BlacksmithSection", UiTheme.TEXT_MUTED, UiTheme.FONT_SECTION)
	UiKit.add_panel(theme, &"BlacksmithOutputSlot",
		UiTheme.SLOT_BG, UiTheme.SLOT_EDGE, UiTheme.RADIUS_SLOT)
	UiKit.add_panel(theme, &"BlacksmithInventorySlot",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.2), UiTheme.RADIUS_SLOT)
	UiKit.add_label(theme, &"BlacksmithCountLabel", UiTheme.TEXT, UiTheme.FONT_MICRO)
	UiKit.add_button(theme, &"BlacksmithClose",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.25),
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	return theme

func _clear_grid(grid: GridContainer) -> void:
	UiKit.clear(grid)

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
	if not player.remove_item(key):
		return
	player.add_item(ingot_key)
	_output_items.append({"key": key, "material": material})
	SoundDB.play(9)
	print("Переплавлено: %s → %s" % [key, ingot_key])
	inventory_changed.emit()
	_refresh()

func _ingot_path(material: String) -> String:
	var ingot := ItemDB.find(ItemDB.ingot_key(material))
	var path := str(ingot.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		return path
	return ""

func _ingot_material(material: String) -> String:
	var ingot := ItemDB.find(ItemDB.ingot_key(material))
	return material if ItemDB.is_smeltable(ingot) else _DEFAULT_INGOT

func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
