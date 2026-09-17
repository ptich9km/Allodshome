extends CharacterBody2D
class_name Mercenary
## Наёмник из таверны: следует за героем, атакует врагов (Game.enemies),
## не качается и не носит броню (как в оригинале). Смерть — из отряда.

@export var anim_set: String = "humans/swordsman"
@export var max_hp: int = 70
@export var damage: int = 6
@export var move_speed: float = 90.0

var current_hp: int
var attack_cooldown: float = 0.0
var _anim: UnitAnim = null

func _ready() -> void:
	add_to_group("mercenary")
	collision_mask = 0   # юниты не толкают друг друга физикой
	current_hp = max_hp
	_anim = UnitAnim.new()
	_anim.name = "UnitAnim"
	add_child(_anim)
	_anim.setup(anim_set)
	_anim.play(UnitAnim.Anim.IDLE)

func _physics_process(delta: float) -> void:
	if Game.is_paused or _anim == null:
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	_apply_relief_stand()

	var target := _nearest_enemy(240.0)
	if target != null:
		if global_position.distance_to(target.global_position) > 40.0:
			_move_toward(target.global_position, delta)
		else:
			velocity = Vector2.ZERO
			_attack(target)
	else:
		var hero: Node2D = Game.hero
		if hero != null and is_instance_valid(hero) \
				and global_position.distance_to(hero.global_position) > 64.0:
			_move_toward(hero.global_position, delta)
		else:
			velocity = Vector2.ZERO

	move_and_slide()
	if velocity.length_squared() > 1.0:
		_anim.play(UnitAnim.Anim.MOVE)
		_anim.set_direction_vec(velocity)
		_anim.advance(delta)
	else:
		_anim.play(UnitAnim.Anim.IDLE)

func _nearest_enemy(radius: float) -> Node2D:
	var best: Node2D = null
	var best_d := radius
	for e in Game.enemies:
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _move_toward(p: Vector2, delta: float) -> void:
	var dir := (p - global_position).normalized()
	var wanted := dir * move_speed
	var map_node := get_tree().get_first_node_in_group("alm_map")
	if map_node != null and map_node.has_method("is_walkable_world") \
			and not map_node.is_walkable_world(global_position + wanted * delta):
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)   # упёрлись — стоп
		return
	velocity = velocity.move_toward(wanted, 1100.0 * delta)

func _attack(target: Node2D) -> void:
	if attack_cooldown > 0.0:
		return
	attack_cooldown = 1.0
	if target.has_method("take_damage"):
		target.call("take_damage", damage, self)
	SoundDB.play(5)

func take_damage(dmg: int, _attacker: Node2D) -> void:
	current_hp -= dmg
	if current_hp <= 0:
		SoundDB.play(4)
		Game.party.erase(self)
		queue_free()
	else:
		SoundDB.play_pain(UnitDB.unit_sound(anim_set))

func _apply_relief_stand() -> void:
	var h := 0.0
	var map_node: Node2D = Game.hero
	if map_node != null and is_instance_valid(map_node) \
			and map_node.is_in_group("alm_map") and map_node.has_method("relief_at_world"):
		h = float(map_node.call("relief_at_world", global_position))
	_anim.position = Vector2(_anim.position.x, -h)