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
	
	# Фон
	bar_bg = ColorRect.new()
	bar_bg.size = Vector2(50, 8)
	bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	bar_bg.position = Vector2(-25, -65)
	add_child(bar_bg)

	# HP бар (красный)
	bar_hp = ColorRect.new()
	bar_hp.size = Vector2(48, 6)
	bar_hp.color = Color(0.9, 0.2, 0.2, 1.0)
	bar_hp.position = Vector2(-24, -64)
	add_child(bar_hp)

	# Mana бар (синий) — только если есть мана
	if has_mana:
		bar_mana = ColorRect.new()
		bar_mana.size = Vector2(48, 6)
		bar_mana.color = Color(0.2, 0.4, 0.9, 1.0)
		bar_mana.position = Vector2(-24, -55)
		add_child(bar_mana)
		
		var mana_bg = ColorRect.new()
		mana_bg.size = Vector2(50, 8)
		mana_bg.color = Color(0.1, 0.1, 0.1, 0.8)
		mana_bg.position = Vector2(-25, -56)
		add_child(mana_bg)

func update_bars(hp: int, mana: int = 0):
	current_hp = hp
	if bar_hp:
		var ratio = float(current_hp) / max_hp
		bar_hp.size.x = max(0, 48 * ratio)
	
	if has_mana and bar_mana:
		current_mana = mana
		var ratio = float(current_mana) / max_mana
		bar_mana.size.x = max(0, 48 * ratio)
