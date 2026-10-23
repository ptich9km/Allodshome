extends CanvasLayer
## Карта мира 4x3 (23.10).
##
## Показывает 12 секторов, владельца, тир сложности и аванпосты. Переход —
## только порталами на локальной карте; здесь fast travel нет.
##
## Look: UiTheme roles and UiKit variations only. Mouse, keyboard, gamepad:
## a 4-column grid with UiKit.wire_grid_focus, initial focus on the current
## sector, Esc closes.

signal closed

const PANEL_WIDTH := 1120
const PANEL_HEIGHT := 520
const COLUMNS := 4
const CELL_SIZE := Vector2(252, 120)

var _root: MarginContainer
var _panel: PanelContainer
var _grid: GridContainer
var _previous_focus: Control
var _buttons: Array[Button] = []
var _cells: Dictionary = {}   # sector id -> Button


func setup() -> void:
	layer = 10
	_build_ui()


func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	UiKit.animate_in(_root)
	_refresh()
	if _cells.has(Game.map_sector) and is_instance_valid(_cells[Game.map_sector]):
		_cells[Game.map_sector].call_deferred("grab_focus")
	elif not _buttons.is_empty():
		_buttons[0].call_deferred("grab_focus")


func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()


func _make_theme() -> Theme:
	var theme := UiTheme.app_theme()
	UiKit.add_frame(theme, &"WorldPanel", "res://assets/ui/frames/panel_frame.png")
	UiKit.add_label(theme, &"WorldTitle", UiTheme.ACCENT, UiTheme.FONT_TITLE)
	UiKit.add_label(theme, &"WorldSection", UiTheme.ACCENT_DIM, UiTheme.FONT_SECTION)
	UiKit.add_label(theme, &"WorldName", UiTheme.TEXT, UiTheme.FONT_SUBHEAD)
	UiKit.add_label(theme, &"WorldMeta", UiTheme.TEXT_MUTED, UiTheme.FONT_MICRO)
	UiKit.add_label(theme, &"WorldHint", UiTheme.TEXT_MUTED, UiTheme.FONT_MICRO)
	UiKit.add_button(theme, &"WorldCell",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE,
		UiTheme.PANEL_INNER.lightened(0.10), UiTheme.ACCENT,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	UiKit.add_button(theme, &"WorldCellCurrent",
		UiTheme.PANEL_INNER.lightened(0.06), UiTheme.ACCENT,
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	UiKit.add_button(theme, &"WorldClose",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE.darkened(0.25),
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT_DIM,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	return theme


func _build_ui() -> void:
	var dim := UiKit.make_dim(UiTheme.SCRIM.a)
	add_child(dim)

	_root = MarginContainer.new()
	_root.name = "WorldRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.set_margins(_root, UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET,
		UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET)
	_root.theme = _make_theme()
	add_child(_root)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"WorldPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	UiKit.set_margins(margin, UiTheme.SPACE_5, UiTheme.SPACE_4,
		UiTheme.SPACE_5, UiTheme.SPACE_4)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", UiTheme.SPACE_3)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", UiTheme.SPACE_3)
	content.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"WorldTitle"
	title.text = Loc.t("ui.world_map.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = Loc.t("ui.world_map.close")
	close_button.theme_type_variation = &"WorldClose"
	close_button.custom_minimum_size = Vector2(120, 32)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", UiTheme.SPACE_3)
	_grid.add_theme_constant_override("v_separation", UiTheme.SPACE_3)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_grid)

	var hint := Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"WorldHint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = Loc.t("ui.world_map.hint")
	content.add_child(hint)


func _refresh() -> void:
	UiKit.clear(_grid)
	_buttons.clear()
	_cells.clear()
	var rows := _sector_rows()
	for raw in rows:
		var rec: Dictionary = raw as Dictionary
		var id := str(rec.get("id", ""))
		var button := _make_cell(id, rec)
		_grid.add_child(button)
		_buttons.append(button)
		_cells[id] = button
	UiKit.wire_grid_focus(_buttons, COLUMNS)


func _sector_rows() -> Array:
	var bus = get_node_or_null("/root/WorldBus")
	var state = bus.state if bus != null and "state" in bus else null
	if state != null and not state.sectors.is_empty():
		var out: Array = []
		var wm = load("res://scripts/world/world_map.gd")
		for id in wm.ids():
			var s: Dictionary = state.sector_state(str(id))
			var rec := s.duplicate(true)
			rec["id"] = str(id)
			out.append(rec)
		return out
	# Нет состояния мира (dev-карта): показываем сетку как неисследованную.
	var fallback: Array = []
	var map_script = load("res://scripts/world/world_map.gd")
	for id in map_script.ids():
		var s: Dictionary = map_script.sector(str(id))
		s["id"] = str(id)
		s["owner"] = ""
		s["discovered"] = 2 if str(id) == Game.map_sector else 0
		s["outposts"] = []
		fallback.append(s)
	return fallback


func _make_cell(id: String, rec: Dictionary) -> Button:
	var discovered := int(rec.get("discovered", 0))
	var current := id == Game.map_sector
	var button := Button.new()
	button.name = "Sector_" + id
	button.theme_type_variation = &"WorldCellCurrent" if current else &"WorldCell"
	button.custom_minimum_size = CELL_SIZE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = _tooltip(id, rec, discovered)

	var box_margin := MarginContainer.new()
	box_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	box_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.set_margins(box_margin, UiTheme.SPACE_3, UiTheme.SPACE_2,
		UiTheme.SPACE_3, UiTheme.SPACE_2)
	button.add_child(box_margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", UiTheme.SPACE_1)
	box_margin.add_child(box)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.theme_type_variation = &"WorldName"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.clip_text = true
	name_label.text = _sector_name(id, discovered)
	box.add_child(name_label)

	var meta := Label.new()
	meta.name = "Meta"
	meta.theme_type_variation = &"WorldMeta"
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.max_lines_visible = 3
	meta.text = _sector_meta(rec, discovered)
	box.add_child(meta)

	if current:
		var here := Label.new()
		here.name = "Here"
		here.theme_type_variation = &"WorldMeta"
		here.mouse_filter = Control.MOUSE_FILTER_IGNORE
		here.text = Loc.t("ui.world_map.here")
		box.add_child(here)
	return button


func _sector_name(id: String, discovered: int) -> String:
	if discovered < 1:
		return Loc.t("ui.world_map.unknown")
	var wm = load("res://scripts/world/world_map.gd")
	var key := str(wm.sector(id).get("name_key", ""))
	var text := Loc.t(key)
	return id.to_upper() if text == key else text


func _sector_meta(rec: Dictionary, discovered: int) -> String:
	if discovered < 1:
		return Loc.t("ui.world_map.unexplored")
	var parts: Array = []
	var tier := str(rec.get("tier", "hard"))
	parts.append(Loc.t("ui.world_map.tier." + tier))
	if bool(rec.get("capital", false)) or str(rec.get("capital_of", "")) != "":
		parts.append(Loc.t("ui.world_map.capital"))
	var owner := str(rec.get("owner", ""))
	if owner == "":
		parts.append(Loc.t("ui.world_map.contested"))
	else:
		parts.append(Loc.t("ui.world_map.faction." + owner))
	var outposts: Array = rec.get("outposts", []) as Array
	parts.append(Loc.f("ui.world_map.outposts", [outposts.size()]))
	if discovered < 2:
		parts.append(Loc.t("ui.world_map.scouted"))
	return " · ".join(parts)


func _tooltip(id: String, rec: Dictionary, discovered: int) -> String:
	var lines: Array = [_sector_name(id, discovered), _sector_meta(rec, discovered)]
	var wm = load("res://scripts/world/world_map.gd")
	var ns: Array = wm.neighbors(id)
	if not ns.is_empty():
		var names: Array = []
		for n in ns:
			var nid := str(n)
			var nrec: Dictionary = {}
			var bus = get_node_or_null("/root/WorldBus")
			if bus != null and "state" in bus and bus.state != null:
				nrec = bus.state.sector_state(nid)
			var nd := int(nrec.get("discovered", 0))
			names.append(_sector_name(nid, nd))
		lines.append(Loc.t("ui.world_map.neighbors") + ": " + ", ".join(names))
	return "\n".join(lines)
