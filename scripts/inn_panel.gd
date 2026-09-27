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
## Сетка кандидатов: 3 колонки × 4 ряда = 12 ячеек (кандидатов 10).
## Раньше было 2 × 7 в узкой колонке 208 px: подпись «HP 100 · У 8 · 79 з» и имя
## наезжали на соседнюю колонку (замерено: 223 px текста в 94 px ячейки), а
## справа от сетки пустовало 774 × 608 px. Теперь ячейка широкая, а панель
## рекрутера переехала под сетку — вертикальный бюджет не изменился.
## Высота 150 — из содержимого ячейки: поля 6 + портрет 59 + имя 18 + статы 18
## + цена 20 + кнопка 24 + разделители 5. Меньше нельзя, иначе ячейка растёт и
## сетка наезжает на панель рекрутера.
## Геометрия панели — СТРОГО по разметке в assets/taverna/README.md:
## RECRUIT_PANEL (26, 136) — (219, 889), 7 рядов × 2 колонки.
## Размер ячейки берётся ТОЙ ЖЕ формулой, что в примере кода README:
## cell_h = (y2 - y1) / rows = 753 / 7 = 107.57, cell_w = 193 / 2 = 96.5.
##
## Раньше стояло 108, из-за чего сетка была на 3 px длиннее нарисованной зоны.
## Раскладку к тому же ломали ещё трижды: 3×4 по 240×126, потом ячейка 150 ради
## отдельной строки цены, потом кнопка «Нанять» высотой фактически 32 px вместо
## заданных 22 (content margin 6 из темы перебивает custom_minimum_size) — и
## семь рядов уезжали до y=941, за нарисованные рамки до 889.
## Содержимое теперь: поля 6 + портрет 40 + имя 16 + кнопка ~26 + разделители 3
## = 91, то есть 16 px запаса уходят в портрет.
const _ART_RECRUIT := Rect2(26, 136, 193, 753)     # зона из README
const _ART_ROWS := 7
const _ART_COLUMNS := 2
const _ART_CELL_SIZE := Vector2(
	192.0 / float(_ART_COLUMNS), _ART_RECRUIT.size.y / float(_ART_ROWS))
## Панель рекрутера и подсказка о составе — СПРАВА от сетки (сетка кончается
## на x = 218). Под сеткой им места нет: 2×7 занимает y 136..889.
const _TALK_PANEL_RECT := Rect2(300, 470, 690, 168)
const _PARTY_HINT_RECT := Rect2(300, 662, 690, 56)
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
## Карточка описания кандидата у курсора (одна на панель).
var _hover_card: PanelContainer = null
var _candidates: Array[Dictionary] = []

func setup(p: Player) -> void:
	player = p
	layer = 10
	_build_ui()

func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	UiKit.bind_resize(get_viewport(), _update_layout)
	_generate_candidates()
	_refresh()

func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)

func _build_hover_card() -> void:
	_hover_card = UiKit.make_hover_card(280.0)
	_panel_root.add_child(_hover_card)


## Описание кандидата по наведению (и по фокусу — иначе с геймпада не прочитать).
func _attach_hover(slot: Control, entry: Dictionary, set_name: String,
		display_name: String) -> void:
	if _hover_card == null or entry.is_empty():
		return
	var show_at := func() -> void:
		if not is_instance_valid(slot):
			return
		UiKit.show_hover_card(_hover_card,
			_hover_lines(entry, set_name, display_name),
			slot.global_position, _DESIGN_SIZE)
	slot.mouse_entered.connect(show_at)
	slot.mouse_exited.connect(func() -> void: UiKit.hide_hover_card(_hover_card))
	var btn: Button = slot.find_child("Hire", true, false) as Button
	if btn != null:
		btn.focus_entered.connect(show_at)
		btn.focus_exited.connect(func() -> void: UiKit.hide_hover_card(_hover_card))


## Строки описания: всё, что не поместилось в ячейку 96×108.
func _hover_lines(entry: Dictionary, set_name: String, display_name: String) -> Array:
	var lines: Array = [display_name]
	var sub: Array[String] = []
	var desc := str(UnitDB.get_set(set_name).get("desc", set_name))
	if desc != display_name and not desc.is_empty():
		sub.append(desc)
	sub.append(tr("HP %d") % int(entry.get("hp", 0)))
	sub.append(tr("Урон %d") % int(entry.get("dmg", 0)))
	lines.append(" · ".join(sub))
	var note := _hostile_note(set_name)
	if not note.is_empty():
		lines.append(note)
	lines.append(tr("Цена найма: %d з") % int(entry.get("cost", 0)))
	return lines

func _build_ui() -> void:
	var dim := UiKit.make_dim(0.58)
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
	_recruit_grid.columns = _ART_COLUMNS
	_recruit_grid.position = _ART_RECRUIT.position
	_recruit_grid.size = Vector2(
		_ART_CELL_SIZE.x * _ART_COLUMNS,
		_ART_CELL_SIZE.y * _ART_ROWS
	)
	_recruit_grid.add_theme_constant_override("h_separation", 0)
	_recruit_grid.add_theme_constant_override("v_separation", 0)
	_panel_root.add_child(_recruit_grid)

	_build_hover_card()
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
	# После PRESET_BOTTOM_RIGHT Position/size задавать нельзя: якорь уже привязан
	# к правому нижнему углу, и присваивание position уводило кнопку за экран
	# (замерено: 1426 x 1160 при окне 1280x600). После якоря — только offset_*.
	_close_button.offset_left = -(_CLOSE_MARGIN.x + _CLOSE_SIZE.x)
	_close_button.offset_top = -(_CLOSE_MARGIN.y + _CLOSE_SIZE.y)
	_close_button.offset_right = -_CLOSE_MARGIN.x
	_close_button.offset_bottom = -_CLOSE_MARGIN.y
	_close_button.pressed.connect(close)
	_panel_root.add_child(_close_button)

func _update_layout() -> void:
	UiKit.fit_design_root(_panel_root, _DESIGN_SIZE)

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
	for row in range(_ART_ROWS):
		for column in range(_ART_COLUMNS):
			var index := row * _ART_COLUMNS + column
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
	slot.custom_minimum_size = _ART_CELL_SIZE

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
	portrait.custom_minimum_size = Vector2(40, 40)
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(portrait)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.tooltip_text = display_name
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(0, 16)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)

	# Цены отдельной строкой больше НЕТ: 18 px высоты выталкивали содержимое за
	# пределы ячейки 107.57, ряд рос, и семь рядов уезжали с y=136 на y=941 —
	# то есть за нарисованные рамки зоны, которая кончается на 889. Именно это
	# игрок и видел как «сползли все клетки». Цена теперь на кнопке, а полное
	# описание — в карточке по наведению (UiKit.make_hover_card).
	var hire := Button.new()
	hire.name = "Hire"
	hire.theme_type_variation = &"InnHireButton"
	# Текст кнопки короткий: ячейка по разметке даёт 90 px на кнопку, минус
	# content margin 2 и рамку 2 — то есть на текст остаётся ~82 px. «Нанять · 57 з»
	# впритык, поэтому разделитель убран: «Нанять 57 з» — 10 символов.
	hire.text = tr("Нанять %d з") % int(entry["cost"])
	hire.tooltip_text = "%s — %s\n%s" % [display_name, _hostile_note(set_name),
		tr("Нанять за %d з") % int(entry["cost"])]
	# Минимальная высота кнопки ЗАДАЁТСЯ ЗДЕСЬ и должна быть реальной: content
	# margin из темы (6) плюс рамка дают кнопке ~32 px, и проигнорировать это
	# нельзя — иначе ряд снова вырастет.
	hire.custom_minimum_size = Vector2(0, 26)
	hire.focus_mode = Control.FOCUS_ALL
	hire.pressed.connect(_hire.bind(entry))
	content.add_child(hire)
	_attach_hover(slot, entry, set_name, display_name)
	return slot

func _configure_focus(buttons: Array[Button]) -> void:
	for index in range(buttons.size()):
		var button := buttons[index]
		var row := index / _ART_COLUMNS
		var column := index % _ART_COLUMNS
		var left_index := row * _ART_COLUMNS + maxi(column - 1, 0)
		var right_index := mini(row * _ART_COLUMNS + mini(column + 1, _ART_COLUMNS - 1), buttons.size() - 1)
		var top_index := maxi(index - _ART_COLUMNS, 0)
		var bottom_index := mini(index + _ART_COLUMNS, buttons.size() - 1)
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
	UiKit.set_margins(container, left, top, right, bottom)

func _make_theme() -> Theme:
	# Тёплая палитра интерьера. Отличия от магазина сохранены (кнопка чуть
	# светлее, диалог чуть прозрачнее) — UiKit убирает копипаст, а не разницу.
	var theme := UiKit.base_theme({
		"font_size": 14,
		"font_color": Color(0.96, 0.88, 0.70),
		"radius": 6, "margin": 5,
		"normal_bg": Color(0.24, 0.13, 0.07, 0.96),
		"normal_border": Color(0.70, 0.40, 0.14),
		"hover_bg": Color(0.36, 0.19, 0.08, 0.98),
		"hover_border": Color(1.0, 0.74, 0.26),
		"pressed_bg": Color(0.15, 0.08, 0.04, 1.0),
		"pressed_border": Color(0.66, 0.36, 0.12),
		"disabled_bg": Color(0.16, 0.14, 0.13, 0.88),
		"disabled_border": Color(0.35, 0.30, 0.26),
		"focus_border": Color(1.0, 0.78, 0.20),
		"scrollbar": true,
	})
	UiKit.add_title(theme, &"InnTitle")
	UiKit.add_gold_label(theme, &"InnGoldLabel")
	UiKit.add_label(theme, &"InnSectionLabel", UiKit.SECTION_COLOR, UiKit.SECTION_SIZE)
	UiKit.add_label(theme, &"InnHintLabel", Color(0.88, 0.82, 0.68), 16)
	UiKit.add_label(theme, &"InnCandidateStats", Color(0.82, 0.82, 0.74), 12)
	# Кнопка найма: content margin 2 вместо 6, иначе текст «Нанять · 79 з» шире
	# 90 px (96 минус поля ячейки) и ячейка растёт вширь — клетки снова поедут.
	UiKit.add_button(theme, &"InnHireButton", Color(0.20, 0.16, 0.10, 0.96),
		Color(0.78, 0.60, 0.26, 0.96), Color(0.30, 0.24, 0.14, 0.98),
		Color(1.0, 0.86, 0.42, 1.0), 4, 2)
	theme.set_font_size("font_size", &"InnHireButton", 13)
	theme.set_color("font_color", &"InnHireButton", Color(0.98, 0.90, 0.72))
	UiKit.add_hover_card_styles(theme)
	UiKit.add_hover_card_styles(theme)
	UiKit.add_slot(theme, &"InnRecruitSlot")
	UiKit.add_panel(theme, &"InnDialogPanel",
		Color(0.10, 0.08, 0.07, 0.86), UiKit.DIALOG_BORDER, 5)
	return theme

func _clear_grid(grid: GridContainer) -> void:
	UiKit.clear(grid)

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
	mercenary.position = _spawn_spot()
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

## Точка появления наёмника рядом с героем.
## Раньше было фиксированное смещение Vector2(34, 8) от позиции игрока, и это давало
## два бага: (1) точка не проверялась на проходимость — у двери здания игрок может
## стоять на непроходимой клетке, и наёмник появлялся ВНУТРИ здания (его не было
## видно даже после закрытия панели); (2) все наёмники вставали в одну точку друг на
## друга. Теперь — кольцо вокруг игрока с проверкой проходимости.
func _spawn_spot() -> Vector2:
	var map_node = get_tree().get_first_node_in_group("alm_map")
	var count: int = Game.party.size()
	for attempt in range(12):
		# Раскладываем по кольцу: каждый следующий наёмник — на другой стороне.
		var angle := TAU * float(count) / float(MAX_PARTY) + float(attempt) * 0.5
		var radius := 40.0 + 12.0 * float(attempt % 3)
		var p: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * radius
		if map_node == null or not map_node.has_method("is_walkable_world"):
			return p
		if bool(map_node.call("is_walkable_world", p)):
			return p
	# Ни одна точка не прошла — берём ту, что точно проходима: позиция игрока.
	return player.global_position

func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()
