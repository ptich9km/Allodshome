class_name DamageNumber
extends Node2D
## Летающее число урона/лечения. Поднимается вверх + fade out.
## Использование: DamageNumber.show_at(pos, value, type)

const COLORS := {
	"damage": Color(1.0, 0.2, 0.1),
	"heal": Color(0.2, 1.0, 0.3),
	"crit": Color(1.0, 0.8, 0.0),
	"miss": Color(0.6, 0.6, 0.6),
	"mana": Color(0.3, 0.5, 1.0),
}

var _label: Label
var _time := 0.0
var _duration := 1.2
var _rise_speed := 40.0
var _start_pos := Vector2.ZERO

func setup(pos: Vector2, value: int, type: String = "damage") -> void:
	_start_pos = pos + Vector2(randf_range(-8.0, 8.0), 0.0)
	global_position = _start_pos

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16 if type != "crit" else 22)
	_label.add_theme_color_override("font_color", COLORS.get(type, Color.WHITE))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 2)

	match type:
		"heal":
			_label.text = "+%d" % value
		"miss":
			_label.text = "Промах"
		"mana":
			_label.text = "+%d маны" % value
		_:
			_label.text = str(value)

	# Центрируем текст
	_label.position = Vector2(-_label.size.x / 2.0, -_label.size.y / 2.0)
	add_child(_label)

func _process(delta: float) -> void:
	_time += delta
	# Подъём вверх с замедлением
	global_position.y = _start_pos.y - _rise_speed * _time * (1.0 - _time / _duration)
	# Fade out
	var alpha := clampf(1.0 - _time / _duration, 0.0, 1.0)
	_label.modulate.a = alpha
	# Масштаб (pop-in эффект)
	var s := 1.0 + 0.3 * maxf(0.0, 1.0 - _time * 4.0)
	_label.scale = Vector2(s, s)

	if _time >= _duration:
		queue_free()

## Статический хелпер: показать число
static func show_at(pos: Vector2, value: int, type: String = "damage") -> void:
	var dn := DamageNumber.new()
	dn.setup(pos, value, type)
	var scene: Node = Engine.get_main_loop().current_scene as Node
	if scene:
		scene.add_child(dn)
