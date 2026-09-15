extends CharacterBody2D
class_name Enemy

@export var max_hp: int = 50
@export var damage: int = 8
@export var move_speed: float = 80.0
@export var aggro_radius: float = 150.0
@export var deaggro_radius: float = 200.0
@export var home_position: Vector2
@export var anim_set: String = "monsters/orc"   # набор анимаций из units_db.json

var current_hp: int
var state: String = "idle"
var attack_target: Node2D = null
var attack_cooldown: float = 0.0
var can_flee: bool = true
var health_bar: HealthBar
var _anim: UnitAnim = null

func _ready():
	current_hp = max_hp
	home_position = global_position
	_create_sprite()
	_create_health_bar()

func _create_health_bar():
	health_bar = preload("res://scripts/health_bar.gd").new()
	health_bar.max_hp = max_hp
	health_bar.has_mana = false  # У врагов нет маны
	add_child(health_bar)

func _create_sprite():
	var old_sprite = get_node_or_null("Sprite")
	if old_sprite:
		old_sprite.queue_free()

	_anim = UnitAnim.new()
	_anim.name = "UnitAnim"
	add_child(_anim)
	_anim.setup(anim_set)
	_anim.play(UnitAnim.Anim.IDLE)

func _physics_process(delta):
	if Game.is_paused:
		return

	attack_cooldown = max(0, attack_cooldown - delta)

	# Обновляем бар здоровья
	if health_bar:
		health_bar.update_bars(current_hp)

	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance_to_player = global_position.distance_to(player.global_position)
	var hp_percent = float(current_hp) / max_hp

	match state:
		"idle":
			if distance_to_player < aggro_radius:
				state = "chase"
				attack_target = player
			else:
				velocity = Vector2.ZERO
		"chase":
			if distance_to_player > deaggro_radius:
				state = "idle"
				attack_target = null
				velocity = Vector2.ZERO
			elif distance_to_player < 40.0:
				state = "attack"
			elif hp_percent < 0.15 and can_flee:
				state = "flee"
			else:
				move_toward_target(player.global_position, delta)
		"attack":
			if distance_to_player > 50.0:
				state = "chase"
			elif attack_cooldown <= 0:
				player.take_damage(damage, self)
				attack_cooldown = 1.0
		"flee":
			var flee_direction = (global_position - player.global_position).normalized()
			velocity = flee_direction * move_speed * 1.5
			if distance_to_player > deaggro_radius * 1.5:
				queue_free()

	# Анимация монстра по состоянию
	if _anim:
		match state:
			"chase", "flee":
				_anim.play(UnitAnim.Anim.MOVE)
				_anim.set_direction_vec(velocity)
				_anim.advance(delta)
			"attack":
				_anim.play(UnitAnim.Anim.ATTACK)
				_anim.advance(delta)
			_:
				_anim.play(UnitAnim.Anim.IDLE)

	move_and_slide()

func move_toward_target(target: Vector2, _delta):
	var direction = (target - global_position).normalized()
	velocity = direction * move_speed

func take_damage(dmg: int, attacker: Node2D):
	current_hp -= dmg
	# При получении урона — сразу начинаем погоню
	if is_instance_valid(attacker):
		state = "chase"
		attack_target = attacker
	if current_hp <= 0:
		_drop_loot()
		queue_free()

func _drop_loot():
	var num_items = 1
	if max_hp >= 80:
		num_items = 5
	elif max_hp >= 50:
		num_items = 3
	elif max_hp >= 30:
		num_items = 2
	
	var items = []
	for i in range(num_items):
		var roll = randi() % 4
		match roll:
			0: items.append({"name": "Золото", "amount": randi() % 10 + 1})
			1: items.append({"name": "Зелье HP", "amount": 1})
			2: items.append({"name": "Зелье маны", "amount": 1})
			3: items.append({"name": "Руда", "amount": randi() % 3 + 1})

	# Лут пока отключён - вернём когда создадим систему инвентаря
	# var loot_scene = preload("res://scenes/loot_bag.tscn")
	# if loot_scene:
	# 	var bag = loot_scene.instantiate()
	# 	bag.items = items
	# 	bag.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	# 	get_tree().root.add_child(bag)
