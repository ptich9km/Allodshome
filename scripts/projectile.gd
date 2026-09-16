extends Node2D
class_name Projectile

var start_pos: Vector2
var target_pos: Vector2
var damage: int = 10
var speed: float = 200.0
var projectile_owner: Node2D  # Переименовали чтобы не конфликтовало с owner из Node

func _ready():
	global_position = start_pos
	look_at(target_pos)

func _process(delta):
	var direction = (target_pos - global_position).normalized()
	global_position += direction * speed * delta
	
	# Проверяем достижение цели
	if global_position.distance_to(target_pos) < 5.0:
		explode()

func explode():
	SoundDB.play(513)  # magic\explosion
	for enemy in Game.enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) < 30.0:
			enemy.take_damage(damage, projectile_owner)
	# Урон по объектам карты (разрушаемые деревья/камни)
	var map_node = get_tree().get_first_node_in_group("alm_map")
	if map_node and map_node.has_method("damage_area"):
		map_node.damage_area(global_position, 40.0, damage)
	queue_free()
