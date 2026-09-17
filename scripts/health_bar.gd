extends Node2D
class_name HealthBar

@export var max_hp: int = 100
@export var has_mana: bool = true
@export var max_mana: int = 50

var current_hp: int
var current_mana: int
var bar_bg: ColorRect
var bar_hp: ColorRect
var bar_mana: ColorRect = null

func _ready():
	current_hp = max_hp
	current_mana = max_mana

	# Фон — тонкая плашка 46x10 (под HP и ману) с центром на (0,0)
	bar_bg = ColorRect.new()
	bar_bg.size = Vector2(46, 10)
	bar_bg.color = Color(0.08, 0.08, 0.1, 0.85)
	bar_bg.position = Vector2(-23, -10)
	add_child(bar_bg)

	# HP бар — тонкая красная полоска 3px
	bar_hp = ColorRect.new()
	bar_hp.size = Vector2(42, 3)
	bar_hp.color = Color(0.85, 0.2, 0.16, 1.0)
	bar_hp.position = Vector2(-21, -9)
	add_child(bar_hp)

	# Mana бар — синяя полоска 3px под HP (только если есть мана)
	if has_mana:
		bar_mana = ColorRect.new()
		bar_mana.size = Vector2(42, 3)
		bar_mana.color = Color(0.3, 0.5, 0.95, 1.0)
		bar_mana.position = Vector2(-21, -5)
		add_child(bar_mana)

func update_bars(hp: int, mana: int = 0):
	current_hp = hp
	if bar_hp:
		var ratio = float(current_hp) / max_hp
		bar_hp.size.x = max(0, 42 * ratio)

	if has_mana and bar_mana:
		current_mana = mana
		var ratio = float(current_mana) / max_mana
		bar_mana.size.x = max(0, 42 * ratio)
