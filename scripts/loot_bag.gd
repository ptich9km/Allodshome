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
	# Мешочек с добычей (как в оригинале): тёмный корпус со стянутым верхом и узелком
	draw_circle(Vector2(0, 4), 8.0, Color(0.1, 0.07, 0.05, 0.7))                       # тень
	draw_polygon(
		PackedVector2Array([
			Vector2(-6, 0), Vector2(-7, 4), Vector2(-4, 8), Vector2(4, 8),
			Vector2(7, 4), Vector2(6, 0), Vector2(3, -3), Vector2(-3, -3),
		]),
		PackedColorArray([Color(0.45, 0.34, 0.2, 1.0)]))                               # корпус
	draw_polyline(
		PackedVector2Array([
			Vector2(-6, 0), Vector2(-7, 4), Vector2(-4, 8), Vector2(4, 8),
			Vector2(7, 4), Vector2(6, 0), Vector2(3, -3), Vector2(-3, -3), Vector2(-6, 0),
		]),
		Color(0.28, 0.2, 0.12, 1.0), 1.2)
	draw_circle(Vector2(-2, 2), 2.0, Color(0.6, 0.48, 0.3, 1.0))                       # блик
	draw_line(Vector2(-5, -3), Vector2(5, -3), Color(0.33, 0.24, 0.14, 1.0), 2.0)      # завязка
	draw_line(Vector2(0, -4), Vector2(0, -8), Color(0.33, 0.24, 0.14, 1.0), 2.0)       # узелок
	draw_circle(Vector2(0, -8), 1.8, Color(0.85, 0.7, 0.35, 1.0))                      # золотой узел