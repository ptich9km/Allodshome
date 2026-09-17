class_name InnPanel
extends CanvasLayer
## Таверна (Inn): наём наёмников за золото и разговоры/слухи (как в town.txt).
## Наёмник: Mercenary, следует за героем, атакует врагов; не качается.

signal closed

const MAX_PARTY := 4

# Наборы, которых можно нанять (люди + дружелюбные монстры)
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

var player: Player
var _list: Array = []
var _rows: Array = []
var _gold_label: Label
var _talk_label: Label

func setup(p: Player) -> void:
	player = p
	layer = 10

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(260, 80)
	panel.size = Vector2(760, 640)
	add_child(panel)

	var title := Label.new()
	title.text = "ТАВЕРНА"
	title.position = Vector2(20, 14)
	title.size = Vector2(300, 32)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	panel.add_child(title)

	_gold_label = Label.new()
	_gold_label.position = Vector2(330, 20)
	_gold_label.size = Vector2(220, 28)
	_gold_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(_gold_label)

	var hint := Label.new()
	hint.text = "Отряд: %d/%d — наём на одну прогулку, герой не делится опытом."
	hint.position = Vector2(20, 56)
	hint.size = Vector2(720, 24)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	panel.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 88)
	scroll.size = Vector2(720, 440)
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	_rows = [vbox]

	_talk_label = Label.new()
	_talk_label.position = Vector2(20, 536)
	_talk_label.size = Vector2(720, 60)
	_talk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talk_label.add_theme_font_size_override("font_size", 14)
	_talk_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	panel.add_child(_talk_label)

	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.position = Vector2(610, 596)
	close_btn.size = Vector2(130, 36)
	close_btn.pressed.connect(close)
	panel.add_child(close_btn)

	_refresh()
	_generate_candidates()

## Три случайных кандидата на найм (без повторов).
func _generate_candidates() -> void:
	var pool: Array = CANDIDATES.duplicate()
	while not pool.is_empty() and _list.size() < 3:
		var idx := randi() % pool.size()
		_add_candidate(str(pool[idx]))
		pool.remove_at(idx)

func _refresh() -> void:
	if not is_instance_valid(player):
		return
	_gold_label.text = "Золото: %d" % player.gold
	_talk_label.text = ""
	# Обновить доступность кнопок найма
	for row in _rows:
		for child in row.get_children():
			if child is Button and child.name == "HireBtn":
				child.disabled = Game.party.size() >= MAX_PARTY

func _add_candidate(set_name: String) -> void:
	var o := UnitDB.get_set(set_name)
	var hp := 45 + randi() % 45
	var dmg := 4 + randi() % 5
	var cost := 30 + randi() % 50

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var tex: Texture2D = UnitDB.preview_frame(set_name)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(72, 72)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = tex
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(300, 72)
	var name_lbl := Label.new()
	name_lbl.text = str(o.get("desc", set_name))
	name_lbl.add_theme_font_size_override("font_size", 16)
	info.add_child(name_lbl)
	var stat_lbl := Label.new()
	stat_lbl.text = "HP %d  ·  урон %d  ·  %s" % [hp, dmg, _hostile_note(set_name)]
	stat_lbl.add_theme_font_size_override("font_size", 13)
	stat_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	info.add_child(stat_lbl)
	row.add_child(info)

	var hire := Button.new()
	hire.name = "HireBtn"
	hire.text = "Нанять (%d)" % cost
	hire.custom_minimum_size = Vector2(130, 40)
	row.add_child(hire)
	var talk := Button.new()
	talk.text = "Поговорить"
	talk.custom_minimum_size = Vector2(130, 40)
	row.add_child(talk)

	(_rows[0] as VBoxContainer).add_child(row)
	_list.append({"set": set_name, "hp": hp, "dmg": dmg, "cost": cost, "row": row, "hire": hire})

	hire.pressed.connect(func():
		_hire(set_name, hp, dmg, cost))
	talk.pressed.connect(func():
		_talk_label.text = "%s: «%s»" % [o.get("desc", set_name), TALK_LINES[randi() % TALK_LINES.size()]])

func _hostile_note(set_name: String) -> String:
	return "мирный" if not UnitDB.is_hostile(set_name) else "дикий"

func _hire(set_name: String, hp: int, dmg: int, cost: int) -> void:
	if not is_instance_valid(player):
		return
	if Game.party.size() >= MAX_PARTY:
		return
	if player.gold < cost:
		_talk_label.text = "Не хватает золота на наём (%d)!" % cost
		return
	player.gold -= cost
	var m := Mercenary.new()
	m.anim_set = set_name
	m.max_hp = hp
	m.damage = dmg
	m.position = player.global_position + Vector2(34, 8)
	get_tree().current_scene.add_child(m)
	Game.party.append(m)
	SoundDB.play(1)
	# Кандидат уходит из списка
	for i in range(_list.size() - 1, -1, -1):
		var cand: Dictionary = _list[i]
		if str(cand["set"]) == set_name:
			(_list[i]["row"] as HBoxContainer).queue_free()
			_list.remove_at(i)
	_refresh()
	print("Нанят наёмник: %s" % set_name)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	closed.emit()
	queue_free()