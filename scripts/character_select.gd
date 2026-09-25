extends Control
class_name CharacterSelect
## Старт игры: выбор одного из 4 персонажей (пол x класс), имя героя.
## Имя можно ввести вручную или взять из списка греческих имён (кнопка «🎲»).
## Выбор сохраняется в Game.hero_* и сцена переключается на main.tscn.

const CHARACTERS := [
	{
		"id": "mfighter",
		"title": "Воин",
		"gender": "male",
		"role": "warrior",
		"desc": "Мужчина-воин. Сила и выносливость, меч и щит.",
		"image": "res://assets/equipment/mfighter/1.png",
		"stats": {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
			"blade": 30, "bludgeon": 15, "pike": 10, "fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
			"weapon": "sword", "shield": true, "armor": "heavy"},
	},
	{
		"id": "ffighter",
		"title": "Воин",
		"gender": "female",
		"role": "warrior",
		"desc": "Женщина-воин. Быстрая и ловкая, лёгкий клинок.",
		"image": "res://assets/equipment/ffighter/1.png",
		"stats": {"body": 10, "agility": 13, "mind": 9, "spirit": 8,
			"blade": 30, "bludgeon": 15, "pike": 10, "fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
			"weapon": "sword", "shield": false, "armor": "heavy"},
	},
	{
		"id": "mmage",
		"title": "Маг",
		"gender": "male",
		"role": "mage",
		"desc": "Мужчина-маг. Могучий разум, владение школой магии (выберите её).",
		"image": "res://assets/equipment/mmage/1.png",
		"stats": {"body": 8, "agility": 9, "mind": 13, "spirit": 12,
			"blade": 5, "bludgeon": 5, "pike": 5,
			"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
			"weapon": "staff", "shield": false, "armor": "heavy"},
	},
	{
		"id": "fmage",
		"title": "Маг",
		"gender": "female",
		"role": "mage",
		"desc": "Женщина-маг. Дух и интуиция, владение школой магии (выберите её).",
		"image": "res://assets/equipment/fmage/1.png",
		"stats": {"body": 7, "agility": 10, "mind": 12, "spirit": 13,
			"blade": 5, "bludgeon": 5, "pike": 5,
			"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
			"weapon": "staff", "shield": false, "armor": "heavy"},
	},
]

# Греческие имена (по полу персонажа)
const MALE_NAMES := [
	"Адонис", "Александр", "Аристотель", "Ахилл", "Гектор", "Гелиос",
	"Геракл", "Гиперион", "Демосфен", "Дионис", "Евклид", "Зенон",
	"Икар", "Кирилл", "Леонид", "Ликург", "Милон", "Нестор",
	"Одиссей", "Орест", "Пан", "Парис", "Персей", "Платон",
	"Прокл", "Прометей", "Сократ", "Софокл", "Тезей", "Феникс", "Эдип", "Ясон",
]
const FEMALE_NAMES := [
	"Аглая", "Ариадна", "Артемида", "Аталанта", "Афина", "Галатея",
	"Геката", "Гелика", "Гермиона", "Деметра", "Елена", "Ирида",
	"Ифигения", "Кассандра", "Клеопатра", "Клио", "Кора", "Лаодамия",
	"Леда", "Медея", "Мегара", "Ника", "Олимпиада", "Пандора",
	"Пенелопа", "Персефона", "Рея", "Селена", "София", "Талия", "Хлоя", "Эвридика",
]

const CARD_SIZE := Vector2(210, 330)
const CARD_GAP := 24.0
## Ширина карточки фиксирована, высота — нет: на низком окне (1280×600) ряд карточек
## обязан сжиматься, иначе панель характеристик уезжает за нижний край.
const CARD_WIDTH := 210.0
const CARD_IMAGE_MIN := 120

var selected := 0
var name_input: LineEdit
var _name_btn: Button
var _cards: Array = []
var _name_idx := -1  # последнее сгенерированное имя (для повторной кнопки)
var _root: VBoxContainer   # корневая колонка-раскладка
var _start_btn: Button
var _name_row: HBoxContainer

# --- Настройка героя (как в оригинале): атрибуты и склонность навыка ---
var _edit: Dictionary = {}          # редактируемые статы (копия пресета)
var _stat_labels := {}              # "body" -> Label значения
var _pool_label: Label
var _affinity_buttons: Array[Button] = []   # кнопки склонности (field)
const AFFINITIES := [
	["Меч", "blade"], ["Топор", "axe"], ["Булава", "bludgeon"], ["Копьё", "pike"],
	["Стрельба", "shooting"], ["Огонь", "fire"], ["Вода", "water"],
	["Воздух", "air"], ["Земля", "earth"], ["Астрал", "astral"],
]
const STATS_ORDER := ["body", "agility", "mind", "spirit"]
const STAT_TITLES := {
	"body": "ТЕЛО", "agility": "ЛОВКОСТЬ", "mind": "РАЗУМ", "spirit": "ДУХ",
}

func _ready():
	_apply_theme()
	_setup_background()
	_setup_layout()
	_setup_title()
	_setup_cards()
	_setup_name_row()
	_setup_start_button()
	_setup_editor()
	# Отложенный выбор: в _ready корень сцены занят, а звук создаёт шину в root
	_select.call_deferred(0)
	# Стартовый фокус — на кнопке старта: сцена управляется и с клавиатуры, и с геймпада
	if is_instance_valid(_start_btn):
		_start_btn.call_deferred("grab_focus")

## Единая тема экрана вместо разнобоя локальных override на каждом узле.
func _apply_theme() -> void:
	theme = UiKit.base_theme()
	UiKit.add_title(theme, &"CsTitle")
	UiKit.add_label(theme, &"CsSub", Color(0.75, 0.70, 0.60), 18)
	UiKit.add_label(theme, &"CsName", Color(0.95, 0.90, 0.80), 20)
	UiKit.add_label(theme, &"CsDesc", Color(0.85, 0.82, 0.75), 12)
	UiKit.add_label(theme, &"CsStatTitle", UiKit.SECTION_COLOR, 13)
	UiKit.add_gold_label(theme, &"CsPool")
	UiKit.add_panel(theme, &"CsCard", Color(0.12, 0.10, 0.09, 0.92), UiKit.SLOT_BORDER, 6)
	UiKit.add_panel(theme, &"CsEditor", Color(0.10, 0.09, 0.08, 0.94), UiKit.DIALOG_BORDER, 6)

func _setup_background() -> void:
	# Тёмный фон-панель на весь экран
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.05, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Горизонт-лента снизу (как каменный пол в оригинале)
	var floor := ColorRect.new()
	floor.color = Color(0.16, 0.12, 0.09, 1.0)
	floor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	floor.offset_top = -120.0
	floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor)

## Корневая раскладка экрана: одна колонка-контейнер вместо координат 1280×800.
func _setup_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.set_margins(margin, 28, 20, 28, 20)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	margin.add_child(_root)
	UiKit.bind_resize(get_window(), _fit_root)

## Подгонка под окно: карточки сжимаются по высоте, отступы не растут.
func _fit_root() -> void:
	if not is_instance_valid(_root):
		return
	var available: float = size.y - 40.0
	var wanted: float = float(CHARACTERS.size()) * 0.0
	# Высота карточек задаётся контейнером; ограничиваем только минимальную,
	# чтобы панель характеристик не уехала за экран на маленьком окне.
	_root.custom_minimum_size = Vector2(0.0, minf(available, 800.0) + wanted)

func _setup_title() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_root.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"CsTitle"
	title.text = "АЛЛОДЫ: ДОМ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"CsSub"
	sub.text = "Выберите героя"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

func _setup_cards() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(CARD_GAP))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(row)
	for i in range(CHARACTERS.size()):
		row.add_child(_make_card(CHARACTERS[i], i))

## Клик/фокус карточки выбирают персонажа (мышь, клавиатура, геймпад).
func _on_card_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(idx)

func _make_card(c: Dictionary, idx: int) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CsCard"
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.focus_mode = Control.FOCUS_ALL
	_cards.append(panel)

	# Единственный прямой потомок карточки: контейнер, который НЕ перехватывает
	# клик (у прямых детей должен быть IGNORE — на этом держится клик по карточке).
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	# Миниатюра персонажа (полноростовой спрайт)
	var img := TextureRect.new()
	img.texture = load(str(c["image"]))
	img.custom_minimum_size = Vector2(0, CARD_IMAGE_MIN)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.size_flags_vertical = Control.SIZE_EXPAND_FILL
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE  # не перехватывать клик
	box.add_child(img)

	# Подпись: класс + пол
	var label := Label.new()
	label.theme_type_variation = &"CsName"
	label.text = "%s\n%s" % [c["title"], "Мужчина" if c["gender"] == "male" else "Женщина"]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)

	# Описание (имя героя появится после выбора)
	var desc := Label.new()
	desc.name = "Desc"
	desc.theme_type_variation = &"CsDesc"
	desc.text = ""
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 40)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)

	panel.gui_input.connect(_on_card_input.bind(idx))
	panel.focus_entered.connect(func(): _select(idx))
	panel.mouse_entered.connect(func(): panel.modulate = Color(1.06, 1.06, 1.02))
	panel.mouse_exited.connect(func(): _update_card_style(panel))
	return panel

func _update_card_style(panel: Control) -> void:
	var idx: int = _cards.find(panel)
	if idx == selected:
		panel.modulate = Color(1.10, 1.10, 1.0)
		panel.add_theme_stylebox_override("panel",
			UiKit.panel_style(Color(0.21, 0.15, 0.09, 0.96), UiKit.DIALOG_BORDER, 6, 3))
	else:
		panel.modulate = Color.WHITE
		panel.remove_theme_stylebox_override("panel")

func _setup_name_row() -> void:
	# Имя и кнопка старта — в одной строке: на невысоком окне отдельная строка
	# на кнопку съедала высоту и выдавливала панель характеристик за край.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_root.add_child(row)
	_name_row = row

	var lab := Label.new()
	lab.text = "Имя героя:"
	lab.add_theme_font_size_override("font_size", 18)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lab)

	name_input = LineEdit.new()
	name_input.custom_minimum_size = Vector2(320, 40)
	name_input.max_length = 20
	name_input.add_theme_font_size_override("font_size", 18)
	name_input.placeholder_text = "Введите имя..."
	row.add_child(name_input)

	# Кнопка случайного греческого имени
	_name_btn = Button.new()
	_name_btn.text = "🎲 Случайное греческое имя"
	_name_btn.custom_minimum_size = Vector2(240, 40)
	_name_btn.pressed.connect(_random_name)
	row.add_child(_name_btn)

	if name_input.text == "":
		_random_name()

func _random_name() -> void:
	var c: Dictionary = CHARACTERS[selected]
	var pool: Array = FEMALE_NAMES if c["gender"] == "female" else MALE_NAMES
	# не повторяем подряд
	var i := randi() % pool.size()
	if pool.size() > 1 and i == _name_idx:
		i = (i + 1) % pool.size()
	_name_idx = i
	name_input.text = str(pool[i])

func _setup_start_button() -> void:
	var row: HBoxContainer = _name_row if is_instance_valid(_name_row) else HBoxContainer.new()
	if not is_instance_valid(_name_row):
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		_root.add_child(row)
	_start_btn = Button.new()
	_start_btn.text = "В ПУТЬ!"
	_start_btn.custom_minimum_size = Vector2(220, 48)
	_start_btn.add_theme_font_size_override("font_size", 24)
	_start_btn.pressed.connect(_start_game)
	row.add_child(_start_btn)

## Панель настройки внизу: атрибуты (очки) и склонность навыка (+20).
func _setup_editor() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CsEditor"
	_root.add_child(panel)

	var margin := MarginContainer.new()
	UiKit.set_margins(margin, 12, 8, 12, 8)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	# --- Строка 1: заголовок, четыре характеристики, остаток очков ---
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	col.add_child(row1)

	var lab := Label.new()
	lab.text = "Характеристики:"
	lab.add_theme_font_size_override("font_size", 15)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(lab)

	for stat in STATS_ORDER:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		row1.add_child(box)

		var title := Label.new()
		title.theme_type_variation = &"CsStatTitle"
		title.text = str(STAT_TITLES[stat])
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)

		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 4)
		box.add_child(line)

		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(30, 30)
		minus.pressed.connect(_change_stat.bind(stat, -1))
		line.add_child(minus)

		var val := Label.new()
		val.text = "10"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.custom_minimum_size = Vector2(40, 30)
		line.add_child(val)
		_stat_labels[stat] = val

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(30, 30)
		plus.pressed.connect(_change_stat.bind(stat, 1))
		line.add_child(plus)

	_pool_label = Label.new()
	_pool_label.theme_type_variation = &"CsPool"
	_pool_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pool_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_pool_label)

	# --- Строка 2: склонность (+20 к навыку) ---
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	col.add_child(row2)

	var alab := Label.new()
	alab.text = "Склонность (+20 к навыку):"
	alab.add_theme_font_size_override("font_size", 13)
	alab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row2.add_child(alab)

	for i in range(AFFINITIES.size()):
		var b := Button.new()
		b.text = str(AFFINITIES[i][0])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(92, 30)
		b.pressed.connect(_pick_affinity.bind(i))
		row2.add_child(b)
		_affinity_buttons.append(b)
	# Сквозная навигация по ряду кнопок (мышь/клавиатура/геймпад)
	UiKit.wire_grid_focus(_affinity_buttons, AFFINITIES.size())

func _change_stat(name: String, delta: int) -> void:
	if not _edit.has(name):
		return
	var v := int(_edit[name])
	var total := 0
	for n in STATS_ORDER:
		total += int(_edit[n])
	var preset: int = int(_edit.get("_preset_total", total))
	var pool: int = preset - total
	if delta < 0:
		if v <= 4:
			return
		_edit[name] = v - 1
	elif delta > 0:
		if v >= 20 or pool <= 0:
			return
		_edit[name] = v + 1
	_refresh_editor()

func _pick_affinity(idx: int) -> void:
	for i in range(_affinity_buttons.size()):
		(_affinity_buttons[i] as Button).button_pressed = (i == idx)
	if idx < 0 or idx >= AFFINITIES.size():
		return
	var skill := str(AFFINITIES[idx][1])
	_edit[skill] = 20   # выбранная склонность
	# Маг: выбранная сфера магии — его «школа» (даёт стартовую книгу заклинания).
	if str(CHARACTERS[selected]["role"]) == "mage":
		var sphere := _magic_sphere_of(skill)
		if sphere != "":
			_edit["_school"] = sphere
	_refresh_editor()

## Сфера магии по имени навыка (для выбора школы мага); "" — не магия.
func _magic_sphere_of(skill: String) -> String:
	match skill:
		"fire": return "Fire"
		"water": return "Water"
		"air": return "Air"
		"earth": return "Earth"
		"astral": return "Astral"
	return ""

## Обновить подписи статов/очков после правок.
func _refresh_editor() -> void:
	if _edit.is_empty():
		return
	var total := 0
	for n in STATS_ORDER:
		(_stat_labels[n] as Label).text = str(_edit[n])
		total += int(_edit[n])
	var preset := int(_edit.get("_preset_total", total))
	_pool_label.text = "Очки: %d" % (preset - total)

func _select(idx: int) -> void:
	if idx < 0 or idx >= CHARACTERS.size():
		return
	selected = idx
	# Редактируемая копия статов пресета + фиксированная сумма («очки»)
	var base: Dictionary = CHARACTERS[idx]["stats"]
	_edit = base.duplicate(true)
	_edit.erase("_school")   # сброс выбора школы мага при смене персонажа
	var total := 0
	for n in STATS_ORDER:
		total += int(_edit.get(n, 0))
	_edit["_preset_total"] = total
	_refresh_editor()
	# Сброс склонности
	for i in range(_affinity_buttons.size()):
		(_affinity_buttons[i] as Button).button_pressed = false
	for i in range(_cards.size()):
		_update_card_style(_cards[i])
		var desc: Label = _cards[i].get_node_or_null("Desc")
		if desc:
			desc.text = CHARACTERS[i]["desc"] if i == idx else ""
	SoundDB.play(1)  # click00 — выбор персонажа
	# При смене пола — новое греческое имя
	if name_input.text == "" or _name_idx >= 0:
		_random_name()

func _start_game() -> void:
	var c: Dictionary = CHARACTERS[selected]
	var st: Dictionary = _edit.duplicate(true)
	if st.is_empty():
		st = c["stats"]
	st.erase("_preset_total")
	st.erase("_school")
	Game.hero_class = str(c["role"])
	Game.hero_gender = str(c["gender"])
	Game.hero_name = name_input.text.strip_edges()
	if Game.hero_name == "":
		Game.hero_name = "Герой"
	# Маг: выбранная школа магии развита до 20 очков, в склад кладётся книга
	# простейшего заклинания этой школы (учится двойным кликом по ячейке).
	Game.hero_start_book = ""
	if Game.hero_class == "mage":
		var school := str(_edit.get("_school", ""))
		if school == "":
			school = _default_mage_school(st)
		st[school.to_lower()] = 20
		var starter := SpellDB.simplest_spell_of_sphere(school)
		Game.hero_start_book = SpellDB.book_key_for_spell(starter)
	Game.hero_stats = st
	Game.hero_character_id = str(c["id"])
	# Новая игра — новая карта: случайный сид, карта генерируется в user://maps/.
	# Продолжение сохранения (пакет B) переставит сид ДО этого вызова.
	Game.new_random_map()
	SoundDB.play(2)  # click_ok
	get_tree().change_scene_to_file("res://scenes/main.tscn")

## Школа по умолчанию, если склонность не трогали: первая сфера с навыком >= 20
## в пресете; иначе — Огонь.
func _default_mage_school(st: Dictionary) -> String:
	for sk in ["fire", "water", "air", "earth", "astral"]:
		if int(st.get(sk, 0)) >= 20:
			return _magic_sphere_of(sk)
	return "Fire"