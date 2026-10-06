class_name SaveMenu
extends CanvasLayer
## Меню сохранений (Esc): слоты, автосейв, выход в меню / из игры.
##
## Панель создаётся КОДОМ (не в main.tscn). Меню НИЧЕГО не сохраняет само:
## только сигналы. Сохраняет владелец (game.gd).
##
## ## Раскладка
##
## Компактная: 6 слотов + автосейв в сетку 2 колонки, кнопки 72x28 — иначе при
## 7 строках панель уезжает за экран (замер 05.10). Решение игрока сохранено.
##
## ## Прозрачность
##
## Раньше на весь экран шёл `UiKit.make_dim(0.55)`. Игрок потребовал «без
## прозрачности, но по краям видно игру»: теперь затемнения нет вообще, панель
## непрозрачная и вписана с отступом `UiTheme.SCREEN_INSET`, так что мир
## остаётся виден вокруг неё. Мир под меню живой — интерьеры рисуются поверх
## симулирующейся карты (`ui.gd:_enter_interior` прячет только героя и HUD).

signal closed
signal save_requested(slot: String)
signal load_requested(slot: String)
signal delete_requested(slot: String)
signal quit_requested          ## в главное меню
signal quit_app_requested      ## завершить процесс игры

const FRAME_WINDOW := "res://assets/ui/frames/window_frame.png"

const _BTN := Vector2(92, 28)
const _BTN_SMALL := Vector2(72, 28)

var _previous_focus: Control
var _root: Control
var _slot_box: GridContainer
var _status: Label
var _menu_btn: Button
var _app_btn: Button
var _focusables: Array[Button] = []


func setup() -> void:
	layer = 20


func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	UiKit.bind_resize(get_viewport(), _update_layout)
	_build()
	_refresh()
	_update_layout()
	if not _focusables.is_empty():
		_focusables[0].call_deferred("grab_focus")


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Затемнения нет: панель непрозрачная, мир виден вокруг.
	var inset := MarginContainer.new()
	inset.name = "Inset"
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.set_margins(inset, UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET,
		UiTheme.SCREEN_INSET, UiTheme.SCREEN_INSET)
	_root.add_child(inset)

	var center := CenterContainer.new()
	center.name = "Center"
	inset.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"SavePanel"
	panel.custom_minimum_size = Vector2(430, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	UiKit.set_margins(margin, UiTheme.SPACE_4, UiTheme.SPACE_3,
		UiTheme.SPACE_4, UiTheme.SPACE_3)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", UiTheme.SPACE_2)
	margin.add_child(content)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"SaveTitle"
	title.text = Loc.t("ui.save.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	# Сетка 2 колонки: слот | слот — высота ~4 ряда вместо 7.
	_slot_box = GridContainer.new()
	_slot_box.name = "Slots"
	_slot_box.columns = 2
	_slot_box.add_theme_constant_override("h_separation", UiTheme.SPACE_2)
	_slot_box.add_theme_constant_override("v_separation", UiTheme.SPACE_1)
	content.add_child(_slot_box)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"SaveStatus"
	_status.text = ""
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)

	var quit_row := HBoxContainer.new()
	quit_row.name = "QuitRow"
	quit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	quit_row.add_theme_constant_override("separation", UiTheme.SPACE_2)
	content.add_child(quit_row)

	_menu_btn = Button.new()
	_menu_btn.name = "QuitMenu"
	_menu_btn.text = Loc.t("ui.save.to_main")
	_menu_btn.custom_minimum_size = Vector2(150, 30)
	_menu_btn.pressed.connect(func() -> void: quit_requested.emit())
	quit_row.add_child(_menu_btn)

	_app_btn = Button.new()
	_app_btn.name = "QuitApp"
	_app_btn.text = Loc.t("ui.save.exit")
	_app_btn.custom_minimum_size = Vector2(140, 30)
	_app_btn.pressed.connect(func() -> void: quit_app_requested.emit())
	quit_row.add_child(_app_btn)

	_apply_theme()


func _apply_theme() -> void:
	var theme := UiKit.base_theme({
		"font_size": UiTheme.FONT_BODY,
		"margin": UiTheme.SPACE_1,
		"radius": UiTheme.RADIUS_SLOT,
		"scrollbar": true,
	})
	# Без 9-slice: window_frame при растяжении давал толстые золотые полосы.
	UiKit.add_panel(theme, &"SavePanel",
		UiTheme.PANEL_BG, UiTheme.ACCENT_DIM, UiTheme.RADIUS_FRAME)
	UiKit.add_slot(theme, &"SaveSlotRow")
	UiTheme.add_display_label(theme, &"SaveTitle", UiTheme.FONT_SECTION, UiTheme.ACCENT)
	UiKit.add_label(theme, &"SaveSlotName", UiTheme.TEXT, UiTheme.FONT_MICRO)
	UiKit.add_label(theme, &"SaveSlotEmpty", UiTheme.TEXT_OFF, UiTheme.FONT_MICRO)
	UiKit.add_label(theme, &"SaveStatus", UiTheme.TEXT_MUTED, UiTheme.FONT_MICRO)
	UiKit.add_button(theme, &"SavePrimary", UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE,
		UiTheme.PANEL_INNER.lightened(0.14), UiTheme.ACCENT_DIM,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_1)
	UiKit.add_button(theme, &"SaveGhost", UiTheme.BG_DEEP,
		UiTheme.PANEL_EDGE.darkened(0.25), UiTheme.PANEL_INNER, UiTheme.PANEL_EDGE,
		UiTheme.RADIUS_SLOT, UiTheme.SPACE_1)
	_root.theme = theme


func _refresh() -> void:
	for child in _slot_box.get_children():
		_slot_box.remove_child(child)
		child.queue_free()
	_focusables.clear()
	var entries := SaveSystem.list_slots()
	# Игрок: slot_0..N, автосейв — последним.
	var player: Array = []
	var auto: Dictionary = {}
	for e in entries:
		var s := str(e.get("slot", ""))
		if s == SaveSystem.AUTOSAVE_SLOT:
			auto = e
		elif s.begins_with("slot_"):
			player.append(e)
	player.sort_custom(func(a, b): return str(a.get("slot")) < str(b.get("slot")))
	if not auto.is_empty():
		player.append(auto)
	for entry in player:
		_slot_box.add_child(_make_slot_row(entry))
	_focusables.append(_menu_btn)
	_focusables.append(_app_btn)
	# Сетка фокуса по 2 колонки; выходные кнопки — после сетки.
	var grid_btns: Array[Button] = []
	for c in _slot_box.get_children():
		for b in _buttons_in(c):
			grid_btns.append(b)
	UiKit.wire_grid_focus(grid_btns, 2)
	# Связать последний ряд сетки с кнопками выхода
	if not grid_btns.is_empty():
		grid_btns[-1].focus_neighbor_bottom = _menu_btn.get_path()
		_menu_btn.focus_neighbor_top = grid_btns[-1].get_path()
		_menu_btn.focus_neighbor_right = _app_btn.get_path()
		_app_btn.focus_neighbor_left = _menu_btn.get_path()
		_app_btn.focus_neighbor_top = grid_btns[-1].get_path()


func _buttons_in(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_buttons_in(c))
	return out


func _make_slot_row(entry: Dictionary) -> Control:
	var slot := str(entry.get("slot", ""))
	var exists := bool(entry.get("exists", false))
	var meta: Dictionary = {}
	if entry.has("meta") and entry["meta"] is Dictionary:
		meta = entry["meta"]
	var version := int(entry.get("version", -1))

	var row := PanelContainer.new()
	row.theme_type_variation = &"SaveSlotRow"
	row.name = "Slot_" + slot
	var margin := MarginContainer.new()
	UiKit.set_margins(margin, 6, 4, 6, 4)
	row.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)

	var title := Label.new()
	title.theme_type_variation = &"SaveSlotName"
	if exists:
		title.text = _slot_title(slot, meta)
		if version > SaveSystem.VERSION:
			title.text += Loc.t("ui.save.newer_suffix")
	else:
		title.theme_type_variation = &"SaveSlotEmpty"
		title.text = _slot_title(slot, meta) + Loc.t("ui.save.empty_suffix")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)

	var save_btn := Button.new()
	save_btn.theme_type_variation = &"SavePrimary"
	save_btn.text = Loc.t("ui.save.save_short")
	save_btn.custom_minimum_size = _BTN_SMALL
	save_btn.pressed.connect(func() -> void: save_requested.emit(slot))
	buttons.add_child(save_btn)
	_focusables.append(save_btn)

	var load_btn := Button.new()
	load_btn.theme_type_variation = &"SavePrimary"
	load_btn.text = Loc.t("ui.save.load_short")
	load_btn.custom_minimum_size = _BTN_SMALL
	load_btn.disabled = not exists
	load_btn.pressed.connect(func() -> void: load_requested.emit(slot))
	buttons.add_child(load_btn)
	if not load_btn.disabled:
		_focusables.append(load_btn)

	if exists:
		var del_btn := Button.new()
		del_btn.theme_type_variation = &"SaveGhost"
		del_btn.text = Loc.t("ui.save.delete_short")
		del_btn.custom_minimum_size = _BTN_SMALL
		del_btn.pressed.connect(func() -> void: delete_requested.emit(slot))
		buttons.add_child(del_btn)
		_focusables.append(del_btn)
	return row


func _slot_title(slot: String, meta: Dictionary) -> String:
	if slot == SaveSystem.AUTOSAVE_SLOT:
		return Loc.t("ui.save.autosave")
	var idx := SaveSystem.PLAYER_SLOTS.find(slot)
	var head := Loc.f("ui.save.slot_n", [idx + 1])
	if meta.is_empty():
		return head
	var who := str(meta.get("hero_name", ""))
	if who == "":
		return head
	return "%s · %s" % [head, who]


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _update_layout() -> void:
	# Не растягиваем по design1024 — панель сама по контенту, только центр.
	pass


func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
