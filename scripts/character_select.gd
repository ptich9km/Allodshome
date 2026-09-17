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
		"desc": "Мужчина-маг. Могучий разум, владение огнём и водой.",
		"image": "res://assets/equipment/mmage/1.png",
		"stats": {"body": 8, "agility": 9, "mind": 13, "spirit": 12,
			"blade": 5, "bludgeon": 5, "pike": 5, "fire": 30, "water": 25, "air": 15, "earth": 10, "astral": 10,
			"weapon": "staff", "shield": false, "armor": "heavy"},
	},
	{
		"id": "fmage",
		"title": "Маг",
		"gender": "female",
		"role": "mage",
		"desc": "Женщина-маг. Дух и интуиция, целительная сила.",
		"image": "res://assets/equipment/fmage/1.png",
		"stats": {"body": 7, "agility": 10, "mind": 12, "spirit": 13,
			"blade": 5, "bludgeon": 5, "pike": 5, "fire": 25, "water": 25, "air": 15, "earth": 10, "astral": 10,
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

var selected := 0
var name_input: LineEdit
var _name_btn: Button
var _cards: Array = []
var _name_idx := -1  # последнее сгенерированное имя (для повторной кнопки)

# --- Настройка героя (как в оригинале): атрибуты и склонность навыка ---
var _edit: Dictionary = {}          # редактируемые статы (копия пресета)
var _stat_labels := {}              # "body" -> Label значения
var _pool_label: Label
var _affinity_buttons: Array = []   # кнопки склонности (field)
const AFFINITIES := [
	["Меч", "blade"], ["Топор", "axe"], ["Булава", "bludgeon"], ["Копьё", "pike"],
	["Стрельба", "shooting"], ["Огонь", "fire"], ["Вода", "water"],
	["Воздух", "air"], ["Земля", "earth"], ["Астрал", "astral"],
]
const STATS_ORDER := ["body", "agility", "mind", "spirit"]

func _ready():
	_setup_background()
	_setup_title()
	_setup_cards()
	_setup_name_row()
	_setup_start_button()
	_setup_editor()
	# Отложенный выбор: в _ready корень сцены занят, а звук создаёт шину в root
	_select.call_deferred(0)

func _setup_background() -> void:
	# Тёмный фон-панель на весь экран
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.05, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Горизонт-лента снизу (как каменный пол в оригинале)
	var floor := ColorRect.new()
	floor.color = Color(0.16, 0.12, 0.09, 1.0)
	floor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	floor.offset_top = -120.0
	add_child(floor)

func _setup_title() -> void:
	var title := Label.new()
	title.text = "АЛЛОДЫ: ДОМ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	title.position = Vector2(0, 26)
	title.size = Vector2(1280, 56)
	add_child(title)

	var sub := Label.new()
	sub.text = "Выберите героя"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	sub.position = Vector2(0, 84)
	sub.size = Vector2(1280, 28)
	add_child(sub)

func _setup_cards() -> void:
	var total_w := CARD_SIZE.x * CHARACTERS.size() + CARD_GAP * (CHARACTERS.size() - 1)
	var x0 := (1280.0 - total_w) / 2.0
	var y := 130.0
	for i in range(CHARACTERS.size()):
		var c: Dictionary = CHARACTERS[i]
		var card := _make_card(c, Vector2(x0 + i * (CARD_SIZE.x + CARD_GAP), y))
		_cards.append(card)
		add_child(card)

func _make_card(c: Dictionary, pos: Vector2) -> Control:
	var panel := Panel.new()
	panel.position = pos
	panel.size = CARD_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Миниатюра персонажа (полноростовой спрайт)
	var tex := load(str(c["image"]))
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE  # не перехватывать клик
	img.set_anchors_preset(Control.PRESET_TOP_WIDE)
	img.offset_top = 8.0
	img.offset_bottom = 250.0
	panel.add_child(img)

	# Подпись: класс + пол
	var label := Label.new()
	label.text = "%s\n%s" % [c["title"], "Мужчина" if c["gender"] == "male" else "Женщина"]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -64.0
	label.offset_bottom = -20.0
	panel.add_child(label)

	# Описание (имя героя появится после выбора)
	var desc := Label.new()
	desc.name = "Desc"
	desc.text = ""
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	desc.offset_top = -18.0
	desc.offset_bottom = 0.0
	panel.add_child(desc)

	# Клик по карточке. idx фиксируем на момент создания (в GDScript default-аргументы
	# лямбды пересчитываются на каждый вызов — _cards.size() к моменту клика уже 4).
	var card_idx := _cards.size()
	panel.gui_input.connect(func(event: InputEvent, idx := card_idx):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select(idx))
	panel.mouse_entered.connect(func(idx := card_idx):
		panel.modulate = Color(1.06, 1.06, 1.02))
	panel.mouse_exited.connect(func():
		_update_card_style(panel))
	return panel

func _update_card_style(panel: Control) -> void:
	var idx := _cards.find(panel)
	var selected_idx := int(idx == selected)
	if idx == selected:
		panel.modulate = Color(1.12, 1.12, 1.0)
	else:
		panel.modulate = Color.WHITE

func _setup_name_row() -> void:
	var y := 505.0
	var lab := Label.new()
	lab.text = "Имя героя:"
	lab.position = Vector2(360, y + 6)
	lab.add_theme_font_size_override("font_size", 18)
	add_child(lab)

	name_input = LineEdit.new()
	name_input.position = Vector2(480, y)
	name_input.size = Vector2(360, 40)
	name_input.max_length = 20
	name_input.add_theme_font_size_override("font_size", 18)
	name_input.placeholder_text = "Введите имя..."
	add_child(name_input)

	# Кнопка случайного греческого имени
	_name_btn = Button.new()
	_name_btn.text = "🎲 Случайное греческое имя"
	_name_btn.position = Vector2(860, y)
	_name_btn.size = Vector2(240, 40)
	_name_btn.pressed.connect(_random_name)
	add_child(_name_btn)

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
	var btn := Button.new()
	btn.text = "В ПУТЬ!"
	btn.position = Vector2(540, 610)
	btn.size = Vector2(200, 60)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(_start_game)
	add_child(btn)

## Панель настройки внизу: атрибуты (очки) и склонность навыка (+20).
func _setup_editor() -> void:
	var panel := Panel.new()
	panel.position = Vector2(12, 676)
	panel.size = Vector2(1256, 116)
	add_child(panel)

	var lab := Label.new()
	lab.text = "Характеристики:"
	lab.position = Vector2(14, 10)
	lab.add_theme_font_size_override("font_size", 15)
	panel.add_child(lab)

	var x := 130.0
	for name in STATS_ORDER:
		var title := Label.new()
		title.text = {"body": "ТЕЛО", "agility": "ЛОВКОСТЬ", "mind": "РАЗУМ", "spirit": "ДУХ"}[name]
		title.position = Vector2(x, 8)
		title.size = Vector2(90, 22)
		title.add_theme_font_size_override("font_size", 13)
		panel.add_child(title)

		var minus := Button.new()
		minus.text = "−"
		minus.position = Vector2(x, 32)
		minus.size = Vector2(26, 26)
		minus.pressed.connect(func(n=name): _change_stat(n, -1))
		panel.add_child(minus)

		var val := Label.new()
		val.text = "10"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.position = Vector2(x + 28, 32)
		val.size = Vector2(44, 26)
		val.add_theme_font_size_override("font_size", 17)
		panel.add_child(val)
		_stat_labels[name] = val

		var plus := Button.new()
		plus.text = "+"
		plus.position = Vector2(x + 74, 32)
		plus.size = Vector2(26, 26)
		plus.pressed.connect(func(n=name): _change_stat(n, 1))
		panel.add_child(plus)
		x += 118.0

	_pool_label = Label.new()
	_pool_label.position = Vector2(640, 12)
	_pool_label.size = Vector2(240, 28)
	_pool_label.add_theme_font_size_override("font_size", 15)
	_pool_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	panel.add_child(_pool_label)

	var alab := Label.new()
	alab.text = "Склонность (+20 к навыку):"
	alab.position = Vector2(14, 64)
	alab.size = Vector2(220, 26)
	alab.add_theme_font_size_override("font_size", 13)
	panel.add_child(alab)
	var ax := 240.0
	for i in range(AFFINITIES.size()):
		var b := Button.new()
		b.text = str(AFFINITIES[i][0])
		b.toggle_mode = true
		b.position = Vector2(ax, 62)
		b.size = Vector2(88, 28)
		b.pressed.connect(func(idx=i): _pick_affinity(idx))
		panel.add_child(b)
		_affinity_buttons.append(b)
		ax += 96.0

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
	_edit[str(AFFINITIES[idx][1])] = 20   # выбранная склонность
	_refresh_editor()

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
	Game.hero_class = str(c["role"])
	Game.hero_gender = str(c["gender"])
	Game.hero_name = name_input.text.strip_edges()
	if Game.hero_name == "":
		Game.hero_name = "Герой"
	Game.hero_stats = st
	Game.hero_character_id = str(c["id"])
	SoundDB.play(2)  # click_ok
	get_tree().change_scene_to_file("res://scenes/main.tscn")