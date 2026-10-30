class_name ModsPanel
extends CanvasLayer
## Mods panel: list, enable toggle, manual order, diagnostics.
##
## The load order is applied to the bases once, on their first access, so
## toggling does NOT change an already loaded game — the panel honestly says
## "after restart" instead of pretending the change is live (lesson from X4/SE:
## there enabling a mod requires a reload, and a lie costs more than the truth).
##
## Settings live in `user://mods.cfg` (ModLoader._save_config), not in the save:
## the mod set belongs to the installation, not to a savegame.

signal closed

const PANEL_MIN := Vector2(880, 0)
const LIST_HEIGHT := 340
const THUMB_SIZE := Vector2(56, 56)

## Own colours instead of the default Godot theme: without an explicit StyleBox
## the panel was fully transparent and the main menu showed through (verified by
## a screenshot on 2026-10-29).
const PANEL_BG := Color(0.10, 0.07, 0.05, 0.97)
const PANEL_BORDER := Color(0.70, 0.40, 0.14, 1.0)
const ROW_BG := Color(0.17, 0.11, 0.07, 0.95)
const ROW_BORDER := Color(0.42, 0.26, 0.12, 1.0)
const THUMB_BG := Color(0.05, 0.04, 0.03, 1.0)
const THUMB_BORDER := Color(0.30, 0.22, 0.12, 1.0)

var _root: Control
var _count: Label
var _hint: Label
var _global: Label
var _list: VBoxContainer
var _nav: Array[Button] = []
var _previous_focus: Control
var _closed := false
var _dirty := false
var _pending_focus := 0


func _ready() -> void:
	layer = 30
	_previous_focus = UiKit.save_focus(self)
	# Fresh scan on every open: the player may copy a mod while the panel is
	# closed, and the scan cache lives until restart (report of 2026-10-29:
	# "copied a mod, but the list is empty").
	ModLoader.reset()
	_build()
	_refresh(0)


func close() -> void:
	if _closed:
		return
	_closed = true
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()


# === building ===

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.base_theme()
	add_child(_root)
	_root.add_child(UiKit.make_dim(0.72))

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_MIN
	panel.add_theme_stylebox_override("panel",
		_card_style(PANEL_BG, PANEL_BORDER, 6, 0))
	center.add_child(panel)

	var margin := MarginContainer.new()
	UiKit.set_margins(margin, 16, 12, 16, 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.text = Loc.t("ui.mods.title")
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_count = Label.new()
	_count.name = "Count"
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_count)

	var order_hint := Label.new()
	order_hint.name = "OrderHint"
	order_hint.text = Loc.t("ui.mods.order_hint")
	order_hint.modulate = Color(1, 1, 1, 0.7)
	order_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(order_hint)

	_global = Label.new()
	_global.name = "GlobalNotes"
	_global.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_global.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	_global.visible = false
	column.add_child(_global)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.modulate = Color(1, 0.85, 0.5)
	_hint.visible = false
	column.add_child(_hint)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)

	var open_btn := _footer_button(Loc.t("ui.mods.open_folder"), _on_open_folder)
	footer.add_child(open_btn)

	var refresh_btn := _footer_button(Loc.t("ui.mods.refresh"), _on_refresh)
	footer.add_child(refresh_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close_btn := _footer_button(Loc.t("ui.common.close"), close)
	footer.add_child(close_btn)


func _footer_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 36)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b


# === list ===

func _refresh(focus_index: int = 0) -> void:
	UiKit.clear(_list)
	_nav.clear()
	var mods := ModLoader.all_mods()
	var enabled := 0
	for m in mods:
		if bool(m.get("enabled", true)):
			enabled += 1
	_count.text = Loc.f("ui.mods.count", [mods.size(), enabled])

	if mods.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		var text := Loc.t("ui.mods.none")
		var orphans := ModLoader.orphan_folders()
		if not orphans.is_empty():
			text += "\n\n%s\n%s" % [Loc.t("ui.mods.orphans"), "\n".join(orphans)]
		empty.text = text
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	else:
		for i in range(mods.size()):
			_list.add_child(_make_row(mods[i], i, mods.size()))

	_update_global_notes(mods)
	_hint.visible = _dirty
	_hint.text = Loc.t("ui.mods.hint_restart") if _dirty else ""
	UiKit.wire_grid_focus(_nav, 3)
	_pending_focus = focus_index
	_grab_pending.call_deferred()


## Focus is set in a separate deferred step with a liveness check: rebuilding the
## rows (`UiKit.clear`) frees the old buttons, and `grab_focus` on a Control that
## already left the tree prints an engine ERROR.
func _grab_pending() -> void:
	if _pending_focus < 0 or _pending_focus >= _nav.size():
		return
	var b := _nav[_pending_focus]
	if is_instance_valid(b) and b.is_inside_tree():
		b.grab_focus()


func _make_row(m: Dictionary, index: int, total: int) -> Control:
	var id := str(m["id"])
	var on := bool(m.get("enabled", true))

	var card := PanelContainer.new()
	card.name = "Row_" + id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(ROW_BG, ROW_BORDER, 4, 8))

	var row := HBoxContainer.new()
	row.name = "Line"
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var check := CheckButton.new()
	check.name = "Enabled"
	check.button_pressed = on
	check.tooltip_text = Loc.t("ui.mods.toggle")
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	check.toggled.connect(func(pressed: bool) -> void: _on_toggled(id, pressed, index))
	row.add_child(check)
	_nav.append(check)

	row.add_child(_make_thumb(id, str(m.get("thumb", ""))))

	var column := VBoxContainer.new()
	column.name = "Info"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)

	var line := Label.new()
	line.name = "Name"
	var tail := "" if on else "  (%s)" % Loc.t("ui.mods.disabled")
	line.text = "%s  ·  v%s%s" % [str(m.get("name", id)), str(m.get("version", "?")), tail]
	line.modulate = Color(1, 1, 1, 1.0) if on else Color(1, 1, 1, 0.5)
	column.add_child(line)

	var sub := Label.new()
	sub.name = "Meta"
	var author := str(m.get("author", ""))
	sub.text = "%s%s" % [id, "" if author == "" else " · " + author]
	sub.modulate = Color(1, 1, 1, 0.6)
	column.add_child(sub)

	var notes := _notes_for(id)
	if notes != "":
		var err := Label.new()
		err.name = "Notes"
		err.text = notes
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
		column.add_child(err)

	var up := _arrow_button("▲", Loc.t("ui.mods.move_up"), index > 0)
	up.pressed.connect(func() -> void: _on_move(id, -1, index))
	row.add_child(up)
	_nav.append(up)

	var down := _arrow_button("▼", Loc.t("ui.mods.move_down"), index < total - 1)
	down.pressed.connect(func() -> void: _on_move(id, 1, index))
	row.add_child(down)
	_nav.append(down)

	return card


## Flat "card" with explicit inner padding: `UiKit.panel_style` has none, and
## without it the rows collapse into one solid strip.
func _card_style(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var style := UiKit.panel_style(bg, border, radius, 1)
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	return style


func _arrow_button(glyph: String, tip: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = glyph
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(34, 34)
	b.disabled = not enabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _make_thumb(id: String, path: String) -> Control:
	var box := PanelContainer.new()
	box.name = "ThumbBox"
	box.custom_minimum_size = THUMB_SIZE
	box.add_theme_stylebox_override("panel",
		_card_style(THUMB_BG, THUMB_BORDER, 3, 0))

	var rect := TextureRect.new()
	rect.name = "Thumb"
	rect.custom_minimum_size = THUMB_SIZE - Vector2(8, 8)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.add_child(rect)
	if path != "" and FileAccess.file_exists(path):
		# `load()` is not an option here: a PNG in user:// is not imported.
		var img := Image.new()
		if img.load(path) == OK:
			rect.texture = ImageTexture.create_from_image(img)
			return box
	# No preview — first letter of the mod id instead of an empty black square.
	var letter := Label.new()
	letter.name = "Letter"
	letter.text = id.substr(0, 1).to_upper()
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.modulate = Color(1, 1, 1, 0.35)
	box.add_child(letter)
	return box


# === actions ===

func _on_toggled(id: String, pressed: bool, index: int) -> void:
	ModLoader.set_enabled(id, pressed)
	_dirty = true
	_refresh(index * 3)


func _on_move(id: String, delta: int, index: int) -> void:
	ModLoader.move(id, delta)
	_dirty = true
	_refresh(clampi(index + delta, 0, 999) * 3)


func _on_open_folder() -> void:
	var dir := ModLoader.user_mods_dir()
	OS.shell_open(ProjectSettings.globalize_path(dir))


## "Refresh" means rescan the folder, not just repaint the rows.
func _on_refresh() -> void:
	ModLoader.reset()
	_refresh(0)


# === diagnostics ===

## Error/warning lines that belong to this mod.
func _notes_for(id: String) -> String:
	var lines: Array[String] = []
	for e in ModLoader.errors():
		if e.contains("'%s'" % id):
			lines.append(e)
	for w in ModLoader.warnings():
		if w.contains("'%s'" % id):
			lines.append(w)
	return "\n".join(lines)


## Errors not tied to any concrete mod (a dependency cycle, for example).
func _update_global_notes(mods: Array[Dictionary]) -> void:
	var ids: Array[String] = []
	for m in mods:
		ids.append(str(m["id"]))
	var lines: Array[String] = []
	for e in ModLoader.errors():
		var owned := false
		for id in ids:
			if e.contains("'%s'" % id):
				owned = true
				break
		if not owned:
			lines.append(e)
	_global.visible = not lines.is_empty()
	_global.text = "\n".join(lines)
