# ============================================================================
# PortalConfirm — окно «покинуть карту?» перед переходом через портал.
#
# Игра на паузе (ставит Game), окно PROCESS_MODE_ALWAYS. Каждый вход в портал
# спрашивает заново; Esc = «Остаться». Без class_name: load-по-пути.
# ============================================================================
extends CanvasLayer

signal answered(travel: bool)

var _from_name := ""
var _to_name := ""
var _answered := false


func setup(from_name: String, to_name: String) -> void:
	_from_name = from_name
	_to_name = to_name
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiTheme.BG_DEEP.r, UiTheme.BG_DEEP.g, UiTheme.BG_DEEP.b, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var root := MarginContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.set_margins(root, UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET,
		UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET)
	add_child(root)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme = _make_theme()
	panel.theme_type_variation = &"PortalPanel"
	panel.custom_minimum_size = Vector2(560, 230)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var margin := MarginContainer.new()
	UiKit.set_margins(margin, UiTheme.SPACE_5, UiTheme.SPACE_4,
		UiTheme.SPACE_5, UiTheme.SPACE_4)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.SPACE_3)
	margin.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"PortalTitle"
	title.text = Loc.f("ui.portal.title", [_from_name])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var body := Label.new()
	body.name = "Body"
	body.theme_type_variation = &"PortalBody"
	body.text = Loc.f("ui.portal.body", [_to_name])
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)

	var hint := Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"PortalHint"
	hint.text = Loc.t("ui.portal.hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiTheme.SPACE_3)
	box.add_child(row)

	var stay := Button.new()
	stay.name = "Stay"
	stay.theme_type_variation = &"PortalButton"
	stay.text = Loc.t("ui.portal.stay")
	stay.custom_minimum_size = Vector2(180, 36)
	stay.pressed.connect(_answer.bind(false))
	row.add_child(stay)

	var go := Button.new()
	go.name = "Go"
	go.theme_type_variation = &"PortalButton"
	go.text = Loc.t("ui.portal.go")
	go.custom_minimum_size = Vector2(180, 36)
	go.pressed.connect(_answer.bind(true))
	row.add_child(go)

	stay.call_deferred("grab_focus")


func _make_theme() -> Theme:
	var theme := UiTheme.app_theme()
	UiKit.add_frame(theme, &"PortalPanel", "res://assets/ui/frames/panel_frame.png")
	UiKit.add_label(theme, &"PortalTitle", UiTheme.ACCENT, UiTheme.FONT_TITLE)
	UiKit.add_label(theme, &"PortalBody", UiTheme.TEXT, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"PortalHint", UiTheme.TEXT_MUTED, UiTheme.FONT_MICRO)
	UiKit.add_button(theme, &"PortalButton",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE,
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	return theme


func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		_answer(false)
		get_viewport().set_input_as_handled()


func _answer(travel: bool) -> void:
	# Защита от двойного нажатия/повторного сигнала.
	if _answered or not is_inside_tree():
		return
	_answered = true
	answered.emit(travel)
	queue_free()
