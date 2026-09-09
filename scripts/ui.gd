extends CanvasLayer
class_name GameUI

@onready var hp_bar: ProgressBar = $HPBar
@onready var mana_bar: ProgressBar = $ManaBar
@onready var spell_panel: HBoxContainer = $SpellPanel
@onready var pause_label: Label = $PauseLabel

var player: Player

func setup_ui(p: Player):
	player = p
	
	# Настраиваем полоски HP/Mana с фоном
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.current_hp
	hp_bar.modulate = Color.RED
	
	mana_bar.max_value = player.max_mana
	mana_bar.value = player.current_mana
	mana_bar.modulate = Color.BLUE
	
	# Создаём кнопки заклинаний
	for i in range(player.abilities.size()):
		var ability = player.abilities[i]
		var button = Button.new()
		button.text = "%d. %s" % [i + 1, ability.name.capitalize()]
		button.custom_minimum_size = Vector2(100, 30)
		button.pressed.connect(func(): cast_ability(i))
		spell_panel.add_child(button)

func update_ui(p: Player):
	if not is_instance_valid(p):
		return
	hp_bar.value = p.current_hp
	mana_bar.value = p.current_mana
	
	# Обновляем доступность кнопок заклинаний
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
