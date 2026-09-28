class_name SaveMenu
extends CanvasLayer
## Меню сохранений: слоты, автосейв, выход.
##
## Панель создаётся КОДОМ и в main.tscn не живёт - так же, как ShopPanel,
## InnPanel, AlchemyPanel. Причина не только в том, что так принято:
## добавление узла в сцену задевает main.tscn, который трогает работа над
## правой панелью интерфейса.
##
## Меню НИЧЕГО не сохраняет само: оно только сообщает, что нажато
## (save_requested / load_requested / quit_requested). Сохранять обязан
## владелец (game.gd) - только у него есть живой игрок и WorldBus, и
## загрузка требует пересборки сцены.
##
## Раскладка целиком на контейнерах (VBox/HBox/Grid), без position/size
## у каждого узла: у панели нет фонового арта, под который подгонялись бы
## координаты, а по AGENTS §10.2 ручная раскладка запрещена.

signal closed
signal save_requested(slot: String)
signal load_requested(slot: String)
signal delete_requested(slot: String)
signal quit_requested

const _DESIGN_SIZE := Vector2(1024, 640)
const _BTN_MIN := Vector2(120, 34)

var _previous_focus: Control
var _root: Control
var _slot_box: VBoxContainer
var _status: Label
var _quit_button: Button
var _focusables: Array[Button] = []


func setup() -> void:
	layer = 20


func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	UiKit.bind_resize(get_viewport(), _update_layout)
	_build()
	_refresh()
	_update_layout()
	# Стартовый фокус - на первую доступную кнопку, иначе геймпадом
	# меню не открыть.
	if not _focusables.is_empty():
		_focusables[0].call_deferred("grab_focus")


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := UiKit.make_dim(0.6)
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
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	UiKit.set_margins(margin, 16, 14, 16, 14)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"SaveTitle"
	title.text = tr("СОХРАНЕНИЯ")
	content.add_child(title)

	_slot_box = VBoxContainer.new()
	_slot_box.name = "Slots"
	_slot_box.add_theme_constant_override("separation", 6)
	content.add_child(_slot_box)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = &"SaveStatus"
	_status.text = ""
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)

	_quit_button = Button.new()
	_quit_button.name = "Quit"
	_quit_button.text = tr("Выйти в главное меню")
	_quit_button.custom_minimum_size = _BTN_MIN
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	content.add_child(_quit_button)

	_apply_theme()


func _apply_theme() -> void:
	var theme := UiKit.base_theme()
	UiKit.add_panel(theme, &"SavePanel", Color(0.08, 0.07, 0.06, 0.98),
		UiKit.GOLD_COLOR, 6)
	UiKit.add_slot(theme, &"SaveSlotRow")
	UiKit.add_title(theme, &"SaveTitle", UiKit.TITLE_COLOR, 20)
	UiKit.add_label(theme, &"SaveSlotName", Color(0.92, 0.89, 0.82))
	UiKit.add_label(theme, &"SaveSlotEmpty", Color(0.62, 0.60, 0.56))
	UiKit.add_label(theme, &"SaveStatus", Color(0.75, 0.72, 0.66))
	UiKit.add_button(theme, &"SavePrimary", Color(0.16, 0.20, 0.14, 0.95),
		UiKit.GOLD_COLOR, Color(0.22, 0.28, 0.18), UiKit.GOLD_COLOR)
	UiKit.add_button(theme, &"SaveGhost", Color(0.12, 0.11, 0.10, 0.85),
		Color(0.45, 0.42, 0.36), Color(0.18, 0.17, 0.15), Color(0.60, 0.56, 0.48))
	_root.theme = theme


func _refresh() -> void:
	# UiKit.clear() делает только remove_child, без queue_free - при пересборке
	# списка слотов это утечка узлов на каждом обновлении. Поэтому чистим сами.
	for child in _slot_box.get_children():
		_slot_box.remove_child(child)
		child.queue_free()
	_focusables.clear()
	var entries := SaveSystem.list_slots()
	for entry in entries:
		_slot_box.add_child(_make_slot_row(entry))
	# Сетка фокуса: кнопки каждого слота в одной строке, 3 колонки.
	UiKit.wire_grid_focus(_focusables, 3)
	_focusables.append(_quit_button)


func _make_slot_row(entry: Dictionary) -> Control:
	var slot := str(entry.get("slot", ""))
	var exists := bool(entry.get("exists", false))
	var meta: Dictionary = entry.get("meta", {})
	var version := int(entry.get("version", -1))

	var row := PanelContainer.new()
	row.theme_type_variation = &"SaveSlotRow"
	row.name = "Slot_" + slot
	var margin := MarginContainer.new()
	UiKit.set_margins(margin, 8, 6, 8, 6)
	row.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var title := Label.new()
	title.theme_type_variation = &"SaveSlotName"
	if exists:
		title.text = _slot_title(slot, meta)
		if version > SaveSystem.VERSION:
			title.text += tr("  (сохранение новее игры)")
	else:
		title.theme_type_variation = &"SaveSlotEmpty"
		title.text = _slot_title(slot, meta) + tr(" — пусто")
	box.add_child(title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)

	var save_btn := Button.new()
	save_btn.theme_type_variation = &"SavePrimary"
	save_btn.text = tr("Сохранить")
	save_btn.custom_minimum_size = _BTN_MIN
	save_btn.pressed.connect(func() -> void: save_requested.emit(slot))
	buttons.add_child(save_btn)
	_focusables.append(save_btn)

	var load_btn := Button.new()
	load_btn.theme_type_variation = &"SavePrimary"
	load_btn.text = tr("Загрузить")
	load_btn.custom_minimum_size = _BTN_MIN
	load_btn.disabled = not exists
	load_btn.pressed.connect(func() -> void: load_requested.emit(slot))
	buttons.add_child(load_btn)
	if not load_btn.disabled:
		_focusables.append(load_btn)

	if exists:
		var del_btn := Button.new()
		del_btn.theme_type_variation = &"SaveGhost"
		del_btn.text = tr("Удалить")
		del_btn.custom_minimum_size = _BTN_MIN
		del_btn.pressed.connect(func() -> void: delete_requested.emit(slot))
		buttons.add_child(del_btn)
		_focusables.append(del_btn)
	return row


func _slot_title(slot: String, meta: Dictionary) -> String:
	if slot == SaveSystem.AUTOSAVE_SLOT:
		return tr("Автосохранение")
	var idx := SaveSystem.PLAYER_SLOTS.find(slot)
	var head := tr("Слот %d") % (idx + 1)
	if meta.is_empty():
		return head
	var who := str(meta.get("hero_name", ""))
	if who == "":
		return head
	return "%s — %s" % [head, who]


## Показать строку статуса (результат сохранения/загрузки).
func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _update_layout() -> void:
	UiKit.fit_design_root(_root, _DESIGN_SIZE)


func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
