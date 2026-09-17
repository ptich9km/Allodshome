class_name LootBag
extends Node2D
## Мешок с добычей (лут) на месте смерти врага. Подбирается, когда герой
## подходит вплотную: золото в казну, предметы — в склад героя.

var items: Array = []   # [{"gold": N}] / [{"key": "item_db key"}, ...]
var _player: Node2D = null
var _pick_radius := 26.0

func _ready() -> void:
	z_index = 10
	_player = get_tree().get_first_node_in_group("player")
	add_to_group("loot")

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	if global_position.distance_to(_player.global_position) < _pick_radius:
		_collect()

func _collect() -> void:
	for it in items:
		if it is Dictionary:
			if it.has("gold"):
				var gold := int(it.get("gold", 0))
				if _player.has_method("add_gold"):
					_player.call("add_gold", gold)
				else:
					_player.gold += gold
				print("+%d золота" % gold)
			elif it.has("key"):
				var key := str(it.get("key", ""))
				if _player.has_method("add_item"):
					_player.call("add_item", key)
				print("+%s" % key)
	SoundDB.play(1)  # click00
	queue_free()

func _draw() -> void:
	# Золотой мешок: ромб с тенью
	draw_circle(Vector2.ZERO, 10.0, Color(0.1, 0.08, 0.05, 0.9))
	draw_polygon(
		PackedVector2Array([Vector2(0, -10), Vector2(9, 0), Vector2(0, 10), Vector2(-9, 0)]),
		PackedColorArray([Color(1.0, 0.8, 0.2, 1.0)]))
	draw_polyline(
		PackedVector2Array([Vector2(0, -10), Vector2(9, 0), Vector2(0, 10), Vector2(-9, 0), Vector2(0, -10)]),
		Color(0.4, 0.3, 0.05, 1.0), 1.5)