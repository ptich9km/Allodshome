class_name SaveMenu
extends CanvasLayer
## Меню сохранений (Esc): слоты, автосейв, выход в меню / из игры.
##
## Панель создаётся КОДОМ (не в main.tscn). Меню НИЧЕГО не сохраняет само:
## только сигналы. Сохраняет владелец (game.gd).
##
## Раскладка компактная: 6 слотов + автосейв в сетку 2 колонки, кнопки
## 100×28 — иначе при 7 строках панель уезжает за экран (замер 05.10).

signal closed
signal save_requested(slot: String)
signal load_requested(slot: String)
signal delete_requested(slot: String)
signal quit_requested          ## в главное меню
signal quit_app_requested      ## завершить процесс игры

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

	var dim := UiKit.make_dim(0.55)
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"SavePanel"
	panel.custom_minimum_size = Vector2(430, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	UiKit.set_margins(margin, 12, 10, 12, 10)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"SaveTitle"
	title.text = tr("СОХРАНЕНИЯ")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	# Сетка 2 колонки: слот | слот — высота ~4 ряда вместо 7.
	_slot_box = GridContainer.new()
	_slot_box.name = "Slots"
	_slot_box.columns = 2
	_slot_box.add_theme_constant_override("h_separation", 8)
	_slot_box.add_theme_constant_override("v_separation", 4)
	content.add_child(_slot_box)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"SaveStatus"
	_status.text = ""
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)

	var quit_row := HBoxContainer.new()
	quit_row.name = "QuitRow"
	quit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	quit_row.add_theme_constant_override("separation", 8)
	content.add_child(quit_row)

	_menu_btn = Button.new()
	_menu_btn.name = "QuitMenu"
	_menu_btn.text = tr("В главное меню")
	_menu_btn.custom_minimum_size = Vector2(150, 30)
	_menu_btn.pressed.connect(func() -> void: quit_requested.emit())
	quit_row.add_child(_menu_btn)

	_app_btn = Button.new()
	_app_btn.name = "QuitApp"
	_app_btn.text = tr("Выйти из игры")
	_app_btn.custom_minimum_size = Vector2(140, 30)
	_app_btn.pressed.connect(func() -> void: quit_app_requested.emit())
	quit_row.add_child(_app_btn)

	_apply_theme()


func _apply_theme() -> void:
	var theme := UiKit.base_theme({
		"font_size": 13,
		"margin": 4,
		"radius": 4,
	})
	UiKit.add_panel(theme, &"SavePanel", Color(0.08, 0.07, 0.06, 0.98),
		UiKit.GOLD_COLOR, 6)
	UiKit.add_slot(theme, &"SaveSlotRow")
	UiKit.add_title(theme, &"SaveTitle", UiKit.TITLE_COLOR, 18)
	UiKit.add_label(theme, &"SaveSlotName", Color(0.92, 0.89, 0.82), 12)
	UiKit.add_label(theme, &"SaveSlotEmpty", Color(0.62, 0.60, 0.56), 12)
	UiKit.add_label(theme, &"SaveStatus", Color(0.75, 0.72, 0.66), 12)
	UiKit.add_button(theme, &"SavePrimary", Color(0.16, 0.20, 0.14, 0.95),
		UiKit.GOLD_COLOR, Color(0.22, 0.28, 0.18), UiKit.GOLD_COLOR, 4, 3)
	UiKit.add_button(theme, &"SaveGhost", Color(0.12, 0.11, 0.10, 0.85),
		Color(0.45, 0.42, 0.36), Color(0.18, 0.17, 0.15), Color(0.60, 0.56, 0.48), 4, 3)
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
			title.text += tr(" (новее)")
	else:
		title.theme_type_variation = &"SaveSlotEmpty"
		title.text = _slot_title(slot, meta) + tr(" — пусто")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)

	var save_btn := Button.new()
	save_btn.theme_type_variation = &"SavePrimary"
	save_btn.text = tr("Сохр.")
	save_btn.custom_minimum_size = _BTN_SMALL
	save_btn.pressed.connect(func() -> void: save_requested.emit(slot))
	buttons.add_child(save_btn)
	_focusables.append(save_btn)

	var load_btn := Button.new()
	load_btn.theme_type_variation = &"SavePrimary"
	load_btn.text = tr("Загр.")
	load_btn.custom_minimum_size = _BTN_SMALL
	load_btn.disabled = not exists
	load_btn.pressed.connect(func() -> void: load_requested.emit(slot))
	buttons.add_child(load_btn)
	if not load_btn.disabled:
		_focusables.append(load_btn)

	if exists:
		var del_btn := Button.new()
		del_btn.theme_type_variation = &"SaveGhost"
		del_btn.text = tr("Удал.")
		del_btn.custom_minimum_size = _BTN_SMALL
		del_btn.pressed.connect(func() -> void: delete_requested.emit(slot))
		buttons.add_child(del_btn)
		_focusables.append(del_btn)
	return row


func _slot_title(slot: String, meta: Dictionary) -> String:
	if slot == SaveSystem.AUTOSAVE_SLOT:
		return tr("Автосейв")
	var idx := SaveSystem.PLAYER_SLOTS.find(slot)
	var head := tr("Слот %d") % (idx + 1)
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
