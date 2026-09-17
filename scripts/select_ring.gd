class_name SelectRing
extends Node2D
## Кольцо-индикатор цели: подсвечивает врага под курсором (ховер) и текущую
## цель атаки (красное). Ставится под юнитом, рисуется поверх мира.

var radius := 26.0
var color := Color(1, 0.3, 0.2, 0.9)

func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, color, 2.5)
	# лёгкое дно, чтобы кольцо «лежало» на земле
	draw_arc(Vector2.ZERO, radius, PI + 0.35, TAU + 0.35, 24, Color(color.r, color.g, color.b, 0.45), 2.0)