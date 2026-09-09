extends CanvasLayer
class_name GameUI

# Правая панель
@onready var minimap_viewport: SubViewport = $MinimapBorder/MinimapViewport

# Нижняя панель
@onready var hp_bar: ProgressBar = $BottomPanel/HpBar
@onready var mana_bar: ProgressBar = $BottomPanel/ManaBar
@onready var spell_panel: HBoxContainer = $BottomPanel/SpellPanel
@onready var pause_label: Label = $PauseLabel

# Правая панель
@onready var stats_label: Label = $StatsBorder/StatsLabel
@onready var portrait_texture: TextureRect = $PortraitBorder/PortraitTexture

# Миникарта
var minimap_camera: Camera2D
var minimap_tilemap: TileMapLayer
const MINIMAP_SIZE = 160
const MINIMAP_SCALE = 0.25

var player: Player

func setup_ui(p: Player):
	player = p

	# HP/Mana
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.current_hp
	mana_bar.max_value = player.max_mana
	mana_bar.value = player.current_mana

	# Заклинания
	for i in range(player.abilities.size()):
		var ability = player.abilities[i]
		var button = Button.new()
		button.text = "%d. %s" % [i + 1, ability.name.capitalize()]
		button.custom_minimum_size = Vector2(80, 28)
		button.pressed.connect(func(): cast_ability(i))
		spell_panel.add_child(button)

	# Портрет
	var tex = load("res://assets/sprites/hero.png")
	if tex:
		portrait_texture.texture = tex

	# Миникарта — находим TileMap
	minimap_tilemap = get_tree().get_first_node_in_group("tilemap")
	if minimap_tilemap:
		_setup_minimap()

	# Обновляем характеристики
	_update_stats()

func _setup_minimap():
	# Создаём камеру для миникарты
	minimap_camera = Camera2D.new()
	minimap_camera.zoom = Vector2(MINIMAP_SCALE, MINIMAP_SCALE)
	minimap_camera.ignore_rotation = true
	minimap_tilemap.add_child(minimap_camera)

func _update_stats():
	if not is_instance_valid(player):
		return
	var p = player
	var stats = "ИМЯ: ГЕРОЙ\n"
	stats += "═══════════════\n"
	stats += "СИЛА:        %d\n" % p.strength
	stats += "ЛОВКОСТЬ:    %d\n" % p.agility
	stats += "ИНТЕЛЛЕКТ:   %d\n" % p.intellect
	stats += "ВЫНОСЛИВОСТЬ:%d\n" % p.endurance
	stats += "ДУХ:         %d\n" % p.spirit
	stats += "═══════════════\n"
	stats += "УРОН:        %d-%d\n" % [p.strength, p.strength + 5]
	stats += "БРОНЯ:       %d\n" % (p.endurance / 2)
	stats += "ЗАЩИЩА:      %d\n" % (p.endurance / 3)
	stats += "ОПЫТ:        0\n"
	stats += "СКОРОСТЬ:    %d\n" % int(p.move_speed)
	stats_label.text = stats

func update_ui(p: Player):
	if not is_instance_valid(p):
		return
	hp_bar.value = p.current_hp
	mana_bar.value = p.current_mana

	for i in range(spell_panel.get_child_count()):
		if i < p.abilities.size():
			var button = spell_panel.get_child(i) as Button
			var ability = p.abilities[i]
			var ability_ready = p.ability_cooldowns[i] <= 0 and p.current_mana >= ability.mana_cost
			button.disabled = not ability_ready
			if p.ability_cooldowns[i] > 0:
				button.text = "%s (%.1fs)" % [ability.name.capitalize(), p.ability_cooldowns[i]]
			else:
				button.text = "%d. %s" % [i + 1, ability.name.capitalize()]

	# Обновляем миникарту
	if minimap_camera and is_instance_valid(p):
		minimap_camera.global_position = p.global_position

func cast_ability(index: int):
	if player:
		var target_pos = get_viewport().get_mouse_position()
		player.cast_ability(index, target_pos)

func _process(_delta):
	if Game.is_paused:
		pause_label.visible = true
		pause_label.text = "ТАКТИЧЕСКАЯ ПАУЗА"
	else:
		pause_label.visible = false
