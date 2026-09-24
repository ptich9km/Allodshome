class_name BlacksmithPanel
extends CanvasLayer

signal closed

const _MATERIAL_MAP := {
	"Iron": "iron", "Bronze": "bronze", "Steel": "steel",
	"Silver": "argentum", "Gold": "lutetium",
	"Adamantium": "titanium", "Mithrill": "terbium",
	"Meteoric": "plutonium", "Crystal": "radium",
	"Dragon Leather": "chromium", "Hard Leather": "cobalt",
	"Leather": "wolfram", "Wood": "yttrium",
	"Magic Wood": "gallium",
}
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
	_previous_focus = get_viewport().gui_get_focus_owner()
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.connect(_update_layout)
	_update_layout()
	_refresh()

func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2(20, 14)
	title.size = Vector2(320, 44)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(title)

	_close_button = Button.new()
	_close_button.text = tr("Закрыть")
	_close_button.custom_minimum_size = Vector2(170, 44)
	_close_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_close_button.position = _DESIGN_SIZE - Vector2(194, 68)
	_close_button.size = _DESIGN_SIZE - Vector2(24, 24) - _close_button.position
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
	if not is_instance_valid(_panel_root):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor := minf(viewport_size.x / _DESIGN_SIZE.x, viewport_size.y / _DESIGN_SIZE.y)
	_panel_root.scale = Vector2.ONE * factor
	_panel_root.position = (viewport_size - _DESIGN_SIZE * factor) * 0.5

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
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)

func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", Color(0.95, 0.88, 0.72))
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.9, 0.55))
	theme.set_color("font_pressed_color", "Button", Color(1.0, 1.0, 0.9))
	theme.set_color("font_focus_color", "Button", Color(1.0, 0.9, 0.55))
	theme.set_stylebox("normal", "Button", _button_style(Color(0.22, 0.12, 0.07, 0.96), Color(0.72, 0.40, 0.12)))
	theme.set_stylebox("hover", "Button", _button_style(Color(0.32, 0.17, 0.08, 0.98), Color(1.0, 0.72, 0.25)))
	theme.set_stylebox("pressed", "Button", _button_style(Color(0.14, 0.07, 0.04, 1.0), Color(0.65, 0.34, 0.10)))
	theme.set_stylebox("focus", "Button", _button_style(Color(0.22, 0.12, 0.07, 0.0), Color(1.0, 0.75, 0.20), 3))
	theme.set_type_variation(&"BlacksmithOutputSlot", &"PanelContainer")
	theme.set_stylebox("panel", &"BlacksmithOutputSlot", _slot_style(Color(0.12, 0.09, 0.07, 0.70), Color(0.58, 0.35, 0.14, 0.90)))
	theme.set_type_variation(&"BlacksmithInventorySlot", &"PanelContainer")
	theme.set_stylebox("panel", &"BlacksmithInventorySlot", _slot_style(Color(0.08, 0.09, 0.13, 0.78), Color(0.45, 0.30, 0.16, 0.95)))
	theme.set_type_variation(&"BlacksmithCountLabel", &"Label")
	theme.set_color("font_color", &"BlacksmithCountLabel", Color.WHITE)
	theme.set_font_size("font_size", &"BlacksmithCountLabel", 13)
	return theme

func _button_style(background: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	return style

func _slot_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

func _smelt_item(key: String) -> void:
	if not is_instance_valid(player):
		return
	if not player.remove_item(key):
		return
	var item := ItemDB.find(key)
	var material := str(item.get("material", ""))
	_output_items.append({"key": key, "material": material})
	SoundDB.play(9)
	print("Переплавлено: %s → слиток %s" % [key, _ingot_material(material)])
	_refresh()

func _ingot_path(material: String) -> String:
	var material_id := _ingot_material(material)
	var ingot_path := "res://assets/professions/blacksmith/%s_ingot.png" % material_id
	if ResourceLoader.exists(ingot_path):
		return ingot_path
	var weapon_path := "res://assets/loot_icons/%s_weapon.png" % material_id
	if ResourceLoader.exists(weapon_path):
		return weapon_path
	return ""

func _ingot_material(material: String) -> String:
	return str(_MATERIAL_MAP.get(material, _DEFAULT_INGOT))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _previous_focus != null and is_instance_valid(_previous_focus):
		_previous_focus.call_deferred("grab_focus")
	closed.emit()
	queue_free()
