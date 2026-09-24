class_name InnPanel
extends CanvasLayer

signal closed

const MAX_PARTY := 4
const CANDIDATES := [
	"humans/swordsman", "humans/axeman", "humans/clubman", "humans/pikeman_",
	"humans/archer", "humans/xbowman", "humans/swordsman2", "humans/cavalrysword",
	"humans/mage_st", "monsters/orc_good",
]
const TALK_LINES := [
	"Говорят, на севере всё больше диких зверей... Охрана у ворот не справляется.",
	"В школе тренировок берут золотом за каждую ступень. Дорого, но быстро.",
	"Торговец в лавке скупает всё, что принесёшь из-за стен. Вещи — по полцены.",
	"Маги говорят, что настоящая сила — в книгах стихий. Остальным остаются свитки.",
	"Слышал, за воротами люди пропадают. Особенно те, кто идёт без отряда.",
	"Хороший наёмник стоит своих денег: сам себе и убийца, и щит.",
]
const _BG_PATH := "res://assets/taverna/taverna.jpeg"
const _DESIGN_SIZE := Vector2(1024, 1024)
const _RECRUIT_ORIGIN := Vector2(26, 136)
const _RECRUIT_CELL_SIZE := Vector2(96.5, 107.57)
const _RECRUIT_COLUMNS := 2
const _RECRUIT_ROWS := 7
const _TALK_PANEL_RECT := Rect2(250, 744, 744, 156)
const _PARTY_HINT_RECT := Rect2(250, 912, 560, 52)
const _CLOSE_SIZE := Vector2(170, 44)
const _CLOSE_MARGIN := Vector2(24, 24)

var player: Player
var _panel_root: Control
var _recruit_grid: GridContainer
var _gold_label: Label
var _party_label: Label
var _talk_label: Label
var _talk_button: Button
var _close_button: Button
var _previous_focus: Control
var _candidates: Array[Dictionary] = []

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
	_generate_candidates()
	_refresh()

func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
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
	title.theme_type_variation = &"InnTitle"
	title.text = tr("ТАВЕРНА")
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2(250, 18)
	title.size = Vector2(300, 46)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(title)

	_gold_label = Label.new()
	_gold_label.theme_type_variation = &"InnGoldLabel"
	_gold_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gold_label.position = Vector2(-280, 22)
	_gold_label.size = Vector2(250, 40)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_gold_label)

	_recruit_grid = GridContainer.new()
	_recruit_grid.name = "RecruitGrid"
	_recruit_grid.columns = _RECRUIT_COLUMNS
	_recruit_grid.position = _RECRUIT_ORIGIN
	_recruit_grid.size = Vector2(
		_RECRUIT_CELL_SIZE.x * _RECRUIT_COLUMNS,
		_RECRUIT_CELL_SIZE.y * _RECRUIT_ROWS
	)
	_recruit_grid.add_theme_constant_override("h_separation", 0)
	_recruit_grid.add_theme_constant_override("v_separation", 0)
	_panel_root.add_child(_recruit_grid)

	_build_talk_panel()
	_build_party_hint()
	_build_close_button()

func _build_talk_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "RecruiterPanel"
	panel.theme_type_variation = &"InnDialogPanel"
	panel.position = _TALK_PANEL_RECT.position
	panel.size = _TALK_PANEL_RECT.size
	_panel_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	_set_margins(margin, 14, 10, 14, 10)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var heading := Label.new()
	heading.name = "Heading"
	heading.theme_type_variation = &"InnSectionLabel"
	heading.text = tr("РЕКРУТЕР")
	content.add_child(heading)

	_talk_label = Label.new()
	_talk_label.name = "TalkText"
	_talk_label.text = tr("Спросите дорожные слухи перед наймом отряда.")
	_talk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talk_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_talk_label)

	_talk_button = Button.new()
	_talk_button.name = "Talk"
	_talk_button.text = tr("Поговорить")
	_talk_button.custom_minimum_size = Vector2(180, 38)
	_talk_button.pressed.connect(_talk)
	content.add_child(_talk_button)

func _build_party_hint() -> void:
	_party_label = Label.new()
	_party_label.name = "PartyHint"
	_party_label.theme_type_variation = &"InnHintLabel"
	_party_label.position = _PARTY_HINT_RECT.position
	_party_label.size = _PARTY_HINT_RECT.size
	_party_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_party_label)

func _build_close_button() -> void:
	_close_button = Button.new()
	_close_button.text = tr("Закрыть")
	_close_button.custom_minimum_size = _CLOSE_SIZE
	_close_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_close_button.position = _DESIGN_SIZE - _CLOSE_MARGIN - _CLOSE_SIZE
	_close_button.size = _CLOSE_SIZE
	_close_button.pressed.connect(close)
	_panel_root.add_child(_close_button)

func _update_layout() -> void:
	if not is_instance_valid(_panel_root):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor := minf(viewport_size.x / _DESIGN_SIZE.x, viewport_size.y / _DESIGN_SIZE.y)
	_panel_root.scale = Vector2.ONE * factor
	_panel_root.position = (viewport_size - _DESIGN_SIZE * factor) * 0.5

func _generate_candidates() -> void:
	_candidates.clear()
	var pool: Array = CANDIDATES.duplicate()
	while not pool.is_empty():
		var index := randi() % pool.size()
		var set_name := str(pool[index])
		pool.remove_at(index)
		_candidates.append({
			"set": set_name,
			"hp": 45 + randi() % 45,
			"dmg": 4 + randi() % 5,
			"cost": 30 + randi() % 50,
		})

func _refresh() -> void:
	_clear_grid(_recruit_grid)
	if not is_instance_valid(player):
		return
	_gold_label.text = tr("Золото: %d") % player.gold
	_party_label.text = tr("Отряд: %d/%d · наём на одну прогулку, опыт не делится") % [Game.party.size(), MAX_PARTY]
	var action_buttons: Array[Button] = []
	for row in range(_RECRUIT_ROWS):
		for column in range(_RECRUIT_COLUMNS):
			var index := row * _RECRUIT_COLUMNS + column
			var entry: Dictionary = _candidates[index] if index < _candidates.size() else {}
			var slot := _make_recruit_slot(entry)
			_recruit_grid.add_child(slot)
			var hire_button := slot.find_child("Hire", true, false) as Button
			if hire_button != null:
				hire_button.disabled = Game.party.size() >= MAX_PARTY or player.gold < int(entry.get("cost", 0))
				action_buttons.append(hire_button)
	_configure_focus(action_buttons)
	if not action_buttons.is_empty():
		action_buttons[0].call_deferred("grab_focus")
	else:
		_talk_button.call_deferred("grab_focus")

func _make_recruit_slot(entry: Dictionary) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"InnRecruitSlot"
	slot.custom_minimum_size = _RECRUIT_CELL_SIZE

	var margin := MarginContainer.new()
	_set_margins(margin, 3, 3, 3, 3)
	slot.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	margin.add_child(content)

	if entry.is_empty():
		return slot

	var set_name := str(entry["set"])
	var unit := UnitDB.get_set(set_name)
	var display_name := str(unit.get("desc", set_name))
	var portrait := TextureRect.new()
	portrait.texture = UnitDB.preview_frame(set_name)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(42, 42)
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(portrait)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.tooltip_text = display_name
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(0, 18)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)

	var stats := Label.new()
	stats.theme_type_variation = &"InnCandidateStats"
	stats.text = "HP %d · У %d · %d з" % [int(entry["hp"]), int(entry["dmg"]), int(entry["cost"])]
	stats.tooltip_text = "%s — %s" % [display_name, _hostile_note(set_name)]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.custom_minimum_size = Vector2(0, 16)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(stats)

	var hire := Button.new()
	hire.name = "Hire"
	hire.text = tr("Нанять")
	hire.custom_minimum_size = Vector2(0, 24)
	hire.focus_mode = Control.FOCUS_ALL
	hire.pressed.connect(_hire.bind(entry))
	content.add_child(hire)
	return slot

func _configure_focus(buttons: Array[Button]) -> void:
	for index in range(buttons.size()):
		var button := buttons[index]
		var row := index / _RECRUIT_COLUMNS
		var column := index % _RECRUIT_COLUMNS
		var left_index := row * _RECRUIT_COLUMNS + maxi(column - 1, 0)
		var right_index := mini(row * _RECRUIT_COLUMNS + mini(column + 1, _RECRUIT_COLUMNS - 1), buttons.size() - 1)
		var top_index := maxi(index - _RECRUIT_COLUMNS, 0)
		var bottom_index := mini(index + _RECRUIT_COLUMNS, buttons.size() - 1)
		button.focus_neighbor_left = buttons[left_index].get_path()
		button.focus_neighbor_right = buttons[right_index].get_path()
		button.focus_neighbor_top = buttons[top_index].get_path()
		button.focus_neighbor_bottom = buttons[bottom_index].get_path()
		button.focus_previous = buttons[maxi(index - 1, 0)].get_path()
		button.focus_next = buttons[mini(index + 1, buttons.size() - 1)].get_path()
	if not buttons.is_empty():
		buttons[0].focus_next = _talk_button.get_path()
		buttons[-1].focus_previous = _talk_button.get_path()
		_talk_button.focus_previous = buttons[-1].get_path()
		_talk_button.focus_next = buttons[0].get_path()
		_close_button.focus_previous = _talk_button.get_path()
		_close_button.focus_next = buttons[0].get_path() if not buttons.is_empty() else _talk_button.get_path()
		_talk_button.focus_neighbor_bottom = _close_button.get_path()

func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)

func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", Color(0.96, 0.88, 0.70))
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.92, 0.62))
	theme.set_color("font_pressed_color", "Button", Color(1.0, 1.0, 0.90))
	theme.set_color("font_focus_color", "Button", Color(1.0, 0.90, 0.48))
	theme.set_color("font_disabled_color", "Button", Color(0.60, 0.55, 0.48))
	theme.set_stylebox("normal", "Button", _button_style(Color(0.24, 0.13, 0.07, 0.96), Color(0.70, 0.40, 0.14)))
	theme.set_stylebox("hover", "Button", _button_style(Color(0.36, 0.19, 0.08, 0.98), Color(1.0, 0.74, 0.26)))
	theme.set_stylebox("pressed", "Button", _button_style(Color(0.15, 0.08, 0.04, 1.0), Color(0.66, 0.36, 0.12)))
	theme.set_stylebox("disabled", "Button", _button_style(Color(0.16, 0.14, 0.13, 0.88), Color(0.35, 0.30, 0.26)))
	theme.set_stylebox("focus", "Button", _button_style(Color(0.24, 0.13, 0.07, 0.0), Color(1.0, 0.78, 0.20), 3))
	theme.set_type_variation(&"InnTitle", &"Label")
	theme.set_color("font_color", &"InnTitle", Color(1.0, 0.78, 0.36))
	theme.set_font_size("font_size", &"InnTitle", 28)
	theme.set_type_variation(&"InnGoldLabel", &"Label")
	theme.set_color("font_color", &"InnGoldLabel", Color(1.0, 0.88, 0.42))
	theme.set_font_size("font_size", &"InnGoldLabel", 19)
	theme.set_type_variation(&"InnSectionLabel", &"Label")
	theme.set_color("font_color", &"InnSectionLabel", Color(1.0, 0.76, 0.36))
	theme.set_font_size("font_size", &"InnSectionLabel", 18)
	theme.set_type_variation(&"InnHintLabel", &"Label")
	theme.set_color("font_color", &"InnHintLabel", Color(0.88, 0.82, 0.68))
	theme.set_font_size("font_size", &"InnHintLabel", 16)
	theme.set_type_variation(&"InnCandidateStats", &"Label")
	theme.set_color("font_color", &"InnCandidateStats", Color(0.82, 0.82, 0.74))
	theme.set_font_size("font_size", &"InnCandidateStats", 12)
	theme.set_type_variation(&"InnRecruitSlot", &"PanelContainer")
	theme.set_stylebox("panel", &"InnRecruitSlot", _panel_style(Color(0.08, 0.07, 0.08, 0.80), Color(0.58, 0.36, 0.16, 0.96)))
	theme.set_type_variation(&"InnDialogPanel", &"PanelContainer")
	theme.set_stylebox("panel", &"InnDialogPanel", _panel_style(Color(0.10, 0.08, 0.07, 0.86), Color(0.72, 0.46, 0.18, 0.96)))
	return theme

func _button_style(background: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	return style

func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	return style

func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

func _talk() -> void:
	if not is_instance_valid(_talk_label):
		return
	var lines: Array = TALK_LINES.duplicate()
	var line := str(lines[randi() % lines.size()])
	_talk_label.text = tr("Рекрутер: «%s»") % line

func _hostile_note(set_name: String) -> String:
	return tr("мирный") if not UnitDB.is_hostile(set_name) else tr("дикий")

func _hire(candidate: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	if Game.party.size() >= MAX_PARTY:
		_talk_label.text = tr("Отряд уже заполнен: максимум %d бойца.") % MAX_PARTY
		return
	var cost := int(candidate.get("cost", 0))
	if player.gold < cost:
		_talk_label.text = tr("Не хватает золота на наём: нужно %d.") % cost
		return
	player.gold -= cost
	var mercenary := Mercenary.new()
	mercenary.anim_set = str(candidate["set"])
	mercenary.max_hp = int(candidate["hp"])
	mercenary.damage = int(candidate["dmg"])
	mercenary.position = player.global_position + Vector2(34, 8)
	get_tree().current_scene.add_child(mercenary)
	Game.party.append(mercenary)
	SoundDB.play(1)
	var set_name := str(candidate["set"])
	for index in range(_candidates.size() - 1, -1, -1):
		if str(_candidates[index].get("set", "")) == set_name:
			_candidates.remove_at(index)
			break
	_talk_label.text = tr("%s завербован. Удачной охоты!") % str(UnitDB.get_set(set_name).get("desc", set_name))
	_refresh()
	print("Нанят наёмник: %s" % set_name)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _previous_focus != null and is_instance_valid(_previous_focus):
		_previous_focus.call_deferred("grab_focus")
	closed.emit()
	queue_free()
