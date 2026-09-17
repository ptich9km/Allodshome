class_name SchoolPanel
extends CanvasLayer
## Школа тренировок (Training School): мгновенно поднять навык за золото.
## Цена растёт с уровнем навыка (как в оригинале — «цены становятся безрассудными»).

signal closed

const SKILLS := [
	["Меч", "blade_skill"], ["Топор", "axe_skill"], ["Булава", "bludgeon_skill"],
	["Копьё", "pike_skill"], ["Стрельба", "shooting_skill"],
	["Огонь", "fire_skill"], ["Вода", "water_skill"], ["Воздух", "air_skill"],
	["Земля", "earth_skill"], ["Астрал", "astral_skill"],
]

var player: Player
var _rows: Array = []
var _gold_label: Label

func setup(p: Player) -> void:
	player = p
	layer = 10

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(340, 90)
	panel.size = Vector2(600, 620)
	add_child(panel)

	var title := Label.new()
	title.text = "ШКОЛА ТРЕНИРОВОК"
	title.position = Vector2(20, 14)
	title.size = Vector2(400, 32)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	panel.add_child(title)

	_gold_label = Label.new()
	_gold_label.position = Vector2(430, 20)
	_gold_label.size = Vector2(150, 28)
	_gold_label.add_theme_font_size_override("font_size", 17)
	panel.add_child(_gold_label)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 60)
	scroll.size = Vector2(560, 480)
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# Шапка
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var hl1 := Label.new(); hl1.text = "Навык"; hl1.custom_minimum_size = Vector2(160, 30)
	var hl2 := Label.new(); hl2.text = "Уровень"; hl2.custom_minimum_size = Vector2(90, 30)
	var hl3 := Label.new(); hl3.text = "Цена"; hl3.custom_minimum_size = Vector2(90, 30)
	head.add_child(hl1); head.add_child(hl2); head.add_child(hl3)
	vbox.add_child(head)

	for s in SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_lbl := Label.new()
		name_lbl.text = str(s[0])
		name_lbl.custom_minimum_size = Vector2(160, 40)
		row.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = "0"
		val_lbl.custom_minimum_size = Vector2(90, 40)
		row.add_child(val_lbl)
		var cost_lbl := Label.new()
		cost_lbl.custom_minimum_size = Vector2(90, 40)
		row.add_child(cost_lbl)
		var btn := Button.new()
		btn.text = "Обучить"
		btn.custom_minimum_size = Vector2(120, 40)
		row.add_child(btn)
		vbox.add_child(row)
		var field := str(s[1])
		btn.pressed.connect(func(f=field, r=row): _train(f, r))
		_rows.append({"field": field, "val": val_lbl, "cost": cost_lbl, "btn": btn})

	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.position = Vector2(440, 560)
	close_btn.size = Vector2(130, 36)
	close_btn.pressed.connect(close)
	panel.add_child(close_btn)

	_refresh()

func _train_cost(level: int) -> int:
	return 20 + level * level * 5

func _refresh() -> void:
	if not is_instance_valid(player):
		return
	_gold_label.text = "Золото: %d" % player.gold
	for r in _rows:
		var level := int(player.get(r["field"]))
		var cost := _train_cost(level)
		(r["val"] as Label).text = str(level)
		(r["cost"] as Label).text = str(cost)
		(r["btn"] as Button).disabled = player.gold < cost

func _train(field: String, row: HBoxContainer) -> void:
	if not is_instance_valid(player):
		return
	var level := int(player.get(field))
	var cost := _train_cost(level)
	if player.gold < cost:
		print("Не хватает золота!")
		return
	player.gold -= cost
	player.set(field, level + 1)
	SoundDB.play(9)
	_refresh()
	print("Навык %s -> %d" % [field, level + 1])

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	closed.emit()
	queue_free()