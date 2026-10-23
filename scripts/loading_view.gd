# ============================================================================
# LoadingView — экран загрузки: фон-затемнение, заголовок, фаза, полоса.
#
# Один и тот же вид используется сценой новой игры (loading.tscn) и оверлеем
# перехода внутри Game. Без class_name: грузится load()-по-пути.
# ============================================================================
extends Control

signal back_requested

const PANEL_WIDTH := 680

var _title: Label
var _status: Label
var _bar: ProgressBar
var _percent: Label
var _hint: Label
var _back: Button
var _target := 0.0
var _shown := 0.0
var _failed := false


func setup(title: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build(title)
	set_process(true)


func _build(title: String) -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiTheme.BG_DEEP.r, UiTheme.BG_DEEP.g, UiTheme.BG_DEEP.b, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme = _make_theme()
	panel.theme_type_variation = &"LoadPanel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 210)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var margin := MarginContainer.new()
	UiKit.set_margins(margin, UiTheme.SPACE_5, UiTheme.SPACE_4,
		UiTheme.SPACE_5, UiTheme.SPACE_4)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.SPACE_2)
	margin.add_child(box)

	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"LoadTitle"
	_title.text = title
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"LoadStatus"
	_status.text = Loc.t("ui.loading.preparing")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 22)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_bar)

	_percent = Label.new()
	_percent.name = "Percent"
	_percent.theme_type_variation = &"LoadStatus"
	_percent.text = "0%"
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_percent)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = &"LoadHint"
	_hint.text = Loc.t("ui.loading.hint")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)

	_back = Button.new()
	_back.name = "Back"
	_back.theme_type_variation = &"LoadBack"
	_back.text = Loc.t("ui.loading.back")
	_back.custom_minimum_size = Vector2(160, 34)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.visible = false
	_back.pressed.connect(func() -> void: back_requested.emit())
	box.add_child(_back)


func _make_theme() -> Theme:
	var theme := UiTheme.app_theme()
	UiKit.add_frame(theme, &"LoadPanel", "res://assets/ui/frames/panel_frame.png")
	UiKit.add_label(theme, &"LoadTitle", UiTheme.ACCENT, UiTheme.FONT_TITLE)
	UiKit.add_label(theme, &"LoadStatus", UiTheme.TEXT, UiTheme.FONT_BODY)
	UiKit.add_label(theme, &"LoadHint", UiTheme.TEXT_MUTED, UiTheme.FONT_MICRO)
	UiKit.add_button(theme, &"LoadBack",
		UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE,
		UiTheme.PANEL_INNER.lightened(0.12), UiTheme.ACCENT,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_2)
	theme.set_stylebox("background", "ProgressBar",
		UiKit.panel_style(UiTheme.BG_DEEP, UiTheme.PANEL_EDGE.darkened(0.25),
			UiTheme.RADIUS_SLOT, 1))
	theme.set_stylebox("fill", "ProgressBar",
		UiKit.panel_style(UiTheme.ACCENT_DIM, UiTheme.ACCENT,
			UiTheme.RADIUS_SLOT, 1))
	return theme


func _process(delta: float) -> void:
	# Полоса догоняет цель, но никогда не откатывается назад.
	_shown = move_toward(_shown, _target, maxf(8.0, absf(_target - _shown) * 6.0) * delta)
	if _bar != null:
		_bar.value = _shown
	if _percent != null:
		_percent.text = "%d%%" % int(round(_shown))


func set_progress(percent: int, status: String) -> void:
	_target = maxf(_target, clampf(float(percent), 0.0, 100.0))
	if status != "" and _status != null:
		_status.text = status


func set_error(text: String) -> void:
	_failed = true
	if _status != null:
		_status.text = text
	if _hint != null:
		_hint.text = Loc.t("ui.loading.error_hint")
	if _back != null:
		_back.visible = true
		_back.call_deferred("grab_focus")


## Esc не должен открывать меню сохранений поверх загрузки. На ошибке Esc
## работает как «Назад».
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if _failed:
			back_requested.emit()
		get_viewport().set_input_as_handled()
