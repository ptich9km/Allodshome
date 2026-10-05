extends Control
class_name MainMenu
## Главное меню Mirotokhome (классическое RPG).
##
## Кнопки: Новая игра / Загрузить игру (6 слотов) / Моды / Сетевая игра /
## Об авторах / Выйти (с подтверждением).
## «Продолжить» живёт только здесь — на character_select его больше нет.
##
## Вёрстка: UiKit + контейнеры (не абсолютные координаты).
## Esc в меню не выходит из игры — только возвращает фокус на кнопки.

const GAME_VERSION := "0.1.0"
const GAME_AUTHOR := "ptich9km"
const GAME_LORE := """Mirotokhome — песочница и тактический RPG.

Мир, где фракции спорят о земле и ресурсах,
герой ищет своё место, а за горизонтом
ждут тайны забытых эпох.

Мир не ждёт героя — он просто продолжается."""

const MENU_PATH := "res://scenes/main_menu.tscn"
const CHAR_SELECT_PATH := "res://scenes/character_select.tscn"
const GAME_PATH := "res://scenes/main.tscn"

var _menu_box: VBoxContainer
var _overlay: Control
var _overlay_title: Label
var _overlay_body: VBoxContainer
var _menu_buttons: Array[Button] = []
var _quit_confirm: bool = false
var _fit_root: Control

func _ready() -> void:
	_apply_theme()
	_setup_background()
	_setup_layout()
	_setup_title()
	_setup_menu()
	_setup_footer()
	_setup_overlay()
	if _menu_buttons.size() > 0:
		_menu_buttons[0].call_deferred("grab_focus")
	UiKit.bind_resize(get_window(), _update_layout)
	call_deferred("_update_layout")

func _apply_theme() -> void:
	var theme := UiKit.base_theme({
		"font_size": 16,
		"normal_bg": Color(0.10, 0.07, 0.05, 0.92),
		"normal_border": Color(0.45, 0.28, 0.12),
		"hover_bg": Color(0.18, 0.12, 0.07, 0.96),
		"hover_border": Color(0.85, 0.55, 0.18),
		"focus_border": Color(1.0, 0.82, 0.28),
		"pressed_bg": Color(0.08, 0.05, 0.03, 1.0),
	})
	UiKit.add_label(theme, &"MmTitle", UiKit.TITLE_COLOR, 42)
	UiKit.add_label(theme, &"MmSub", Color(0.78, 0.68, 0.50), 15)
	UiKit.add_label(theme, &"MmFooter", Color(0.55, 0.48, 0.38), 13)
	UiKit.add_label(theme, &"MmAbout", Color(0.90, 0.84, 0.68), 15)
	UiKit.add_panel(theme, &"MmOverlay", Color(0.06, 0.05, 0.04, 0.97), Color(0.70, 0.42, 0.16), 8)
	UiKit.add_button(theme, &"MmMenuBtn",
		Color(0.12, 0.08, 0.05, 0.90), Color(0.50, 0.32, 0.14),
		Color(0.22, 0.14, 0.08, 0.96), Color(0.95, 0.65, 0.22))
	UiKit.add_button(theme, &"MmSlotBtn",
		Color(0.08, 0.06, 0.05, 0.90), Color(0.40, 0.28, 0.14),
		Color(0.16, 0.11, 0.07, 0.96), Color(0.85, 0.58, 0.20))
	theme = theme

func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _setup_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.set_margins(margin, 40, 28, 40, 24)
	add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)
	_fit_root = CenterContainer.new()
	_fit_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_fit_root)
	_menu_box = VBoxContainer.new()
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 10)
	_menu_box.custom_minimum_size = Vector2(320, 0)
	_fit_root.add_child(_menu_box)

func _update_layout() -> void:
	if not is_instance_valid(_menu_box):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	# Не тянем выше 640 — на 1280×600 кнопки не должны уезжать.
	_menu_box.custom_minimum_size = Vector2(minf(340.0, vs.x * 0.35), 0)

func _setup_title() -> void:
	var title := Label.new()
	title.theme_type_variation = &"MmTitle"
	title.text = "MIROTOKHOME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"MmSub"
	sub.text = "Песочница и тактический RPG"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	_menu_box.add_child(spacer)

func _setup_menu() -> void:
	var items := [
		["Новая игра", _on_new_game],
		["Загрузить игру", _on_load_game],
		["Моды и дополнения", _on_mods],
		["Сетевая игра", _on_network],
		["Об авторах", _on_about],
		["Выйти", _on_quit_pressed],
	]
	for item in items:
		var b := Button.new()
		b.theme_type_variation = &"MmMenuBtn"
		b.text = str(item[0])
		b.custom_minimum_size = Vector2(300, 42)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(item[1])
		_menu_box.add_child(b)
		_menu_buttons.append(b)
	UiKit.wire_grid_focus(_menu_buttons, 1)

func _setup_footer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 36)
	_menu_box.add_child(spacer)
	var foot := Label.new()
	foot.theme_type_variation = &"MmFooter"
	foot.text = "v%s · %s" % [GAME_VERSION, GAME_AUTHOR]
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(foot)

# --- Навигация ---

func _set_menu_visible(on: bool) -> void:
	if is_instance_valid(_menu_box):
		_menu_box.visible = on

func _open_overlay(title: String, build_body: Callable) -> void:
	_quit_confirm = false
	_set_menu_visible(false)
	if is_instance_valid(_overlay):
		_overlay.visible = true
	_overlay_title.text = title
	UiKit.clear(_overlay_body)
	build_body.call(_overlay_body)
	# Фокус на первую кнопку панели
	var first := _first_button(_overlay_body)
	if first != null:
		first.grab_focus()

func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.visible = false
	_set_menu_visible(true)
	if _menu_buttons.size() > 0:
		_menu_buttons[0].grab_focus()

func _first_button(node: Node) -> Button:
	if node is Button:
		return node
	for c in node.get_children():
		var b := _first_button(c)
		if b != null:
			return b
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_instance_valid(_overlay) and _overlay.visible:
			get_viewport().set_input_as_handled()
			_close_overlay()
			return
		if _menu_buttons.size() > 0:
			_menu_buttons[0].grab_focus()

# --- Действия ---

func _on_new_game() -> void:
	SoundDB.play(1)
	get_tree().change_scene_to_file(CHAR_SELECT_PATH)

func _on_load_game() -> void:
	SoundDB.play(1)
	_open_overlay("Загрузить игру", _build_load_body)

func _on_mods() -> void:
	SoundDB.play(1)
	_open_overlay("Моды и дополнения", _build_mods_body)

func _on_network() -> void:
	SoundDB.play(1)
	_open_overlay("Сетевая игра", _build_network_body)

func _on_about() -> void:
	SoundDB.play(1)
	_open_overlay("Об авторах", _build_about_body)

func _on_quit_pressed() -> void:
	SoundDB.play(1)
	_quit_confirm = true
	_open_overlay("Выход", _build_quit_body)

func _build_back_button(parent: VBoxContainer) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"MmMenuBtn"
	b.text = "Назад"
	b.custom_minimum_size = Vector2(200, 36)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_close_overlay)
	parent.add_child(b)
	return b

# --- Загрузить игру (6 слотов) ---

func _build_load_body(parent: VBoxContainer) -> void:
	var slots: Array = SaveSystem.list_slots()
	var player_slots: Array = []
	for s in slots:
		if str(s.get("slot", "")).begins_with("slot_"):
			player_slots.append(s)
	# Сортировка по номеру слота
	player_slots.sort_custom(func(a, b): return str(a.get("slot")) < str(b.get("slot")))
	if player_slots.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MmAbout"
		empty.text = "Сохранений нет.\nНачните новую игру."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parent.add_child(empty)
		_build_back_button(parent)
		return
	var btns: Array[Button] = []
	for s in player_slots:
		var slot := str(s.get("slot", ""))
		var exists := bool(s.get("exists", false))
		var meta: Dictionary = s.get("meta", {})
		var b := Button.new()
		b.theme_type_variation = &"MmSlotBtn"
		b.custom_minimum_size = Vector2(360, 40)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if exists:
			var n := int(slot.get_slice("_", 1)) + 1
			b.text = "Слот %d — %s, день %d" % [
				n, str(meta.get("hero_name", "Герой")), int(meta.get("day", 0)),
			]
			b.pressed.connect(_on_load_slot.bind(slot))
		else:
			var n := int(slot.get_slice("_", 1)) + 1
			b.text = "Слот %d — пусто" % n
			b.disabled = true
		parent.add_child(b)
		btns.append(b)
	var back := _build_back_button(parent)
	btns.append(back)
	UiKit.wire_grid_focus(btns, 1)

func _on_load_slot(slot: String) -> void:
	var res := SaveSystem.load_slot(slot)
	var err := str(res.get("error", ""))
	if err == "version":
		_flash_overlay_status("Сохранение из более новой версии игры.")
		return
	if err == "corrupt":
		_flash_overlay_status("Файл сохранения повреждён.")
		return
	if res.is_empty():
		_flash_overlay_status("Слот пуст.")
		return
	var data: Dictionary = res.get("data", {})
	SaveSystem.apply_payload(data, null)
	_restore_world(data.get("world", {}))
	SoundDB.play(2)
	get_tree().change_scene_to_file(GAME_PATH)

func _restore_world(world_data: Variant) -> void:
	if not (world_data is Dictionary) or (world_data as Dictionary).is_empty():
		return
	var ws_script: GDScript = load("res://scripts/world/world_state.gd")
	var restored = ws_script.from_json_text(JsonSafe.dump(world_data))
	if restored == null:
		return
	var bus = get_tree().root.get_node_or_null("WorldBus")
	if bus == null:
		return
	bus.state = restored
	if "sim" in bus and bus.sim != null and "state" in bus.sim:
		bus.sim.state = restored

func _flash_overlay_status(msg: String) -> void:
	var lab := _overlay_body.get_node_or_null("Status")
	if lab == null:
		lab = Label.new()
		lab.name = "Status"
		lab.theme_type_variation = &"MmFooter"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay_body.add_child(lab)
	(lab as Label).text = msg

# --- Моды / сеть / об авторах / выход ---

func _build_mods_body(parent: VBoxContainer) -> void:
	var lab := Label.new()
	lab.theme_type_variation = &"MmAbout"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size = Vector2(420, 0)
	var found: Array = []
	for base in ["user://mods", "res://mods"]:
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if dir.current_is_dir() and not fn.begins_with("."):
				found.append("%s/%s" % [base.get_file(), fn])
			fn = dir.get_next()
		dir.list_dir_end()
	if found.is_empty():
		lab.text = "Моды и дополнения\n\nКаталог mods пуст.\nСюда будут складываться папки модов."
	else:
		lab.text = "Моды и дополнения\n\nНайдено папок: %d\n%s\n\nРаспознавание модов появится позже." % [
			found.size(), "\n".join(found),
		]
	parent.add_child(lab)
	_build_back_button(parent)

func _build_network_body(parent: VBoxContainer) -> void:
	var lab := Label.new()
	lab.theme_type_variation = &"MmAbout"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.text = "Сетевая игра\n\nСоздание игры — скоро\nПоиск игр для присоединения — скоро"
	parent.add_child(lab)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	for t in ["Создать игру", "Найти игру"]:
		var b := Button.new()
		b.theme_type_variation = &"MmMenuBtn"
		b.text = t
		b.custom_minimum_size = Vector2(160, 36)
		b.disabled = true
		row.add_child(b)
	_build_back_button(parent)

func _build_about_body(parent: VBoxContainer) -> void:
	var lab := Label.new()
	lab.theme_type_variation = &"MmAbout"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size = Vector2(460, 0)
	lab.text = GAME_LORE + "\n\nВерсия: %s\nАвтор: %s" % [GAME_VERSION, GAME_AUTHOR]
	parent.add_child(lab)
	_build_back_button(parent)

func _build_quit_body(parent: VBoxContainer) -> void:
	var lab := Label.new()
	lab.theme_type_variation = &"MmAbout"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.text = "Выйти из игры?"
	parent.add_child(lab)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var yes := Button.new()
	yes.theme_type_variation = &"MmMenuBtn"
	yes.text = "Да"
	yes.custom_minimum_size = Vector2(120, 40)
	yes.pressed.connect(_on_quit_yes)
	row.add_child(yes)
	var no := Button.new()
	no.theme_type_variation = &"MmMenuBtn"
	no.text = "Нет"
	no.custom_minimum_size = Vector2(120, 40)
	no.pressed.connect(_close_overlay)
	row.add_child(no)
	yes.grab_focus()

func _on_quit_yes() -> void:
	get_tree().quit()

func _setup_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var dim := UiKit.make_dim(0.62)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MmOverlay"
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	UiKit.set_margins(margin, 24, 20, 24, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_overlay_title = Label.new()
	_overlay_title.theme_type_variation = &"MmTitle"
	_overlay_title.add_theme_font_size_override("font_size", 28)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overlay_title)
	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 8)
	_overlay_body.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_overlay_body)
