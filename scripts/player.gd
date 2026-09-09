extends CharacterBody2D
class_name Player

@export var max_hp: int = 100
@export var max_mana: int = 50
@export var strength: int = 10
@export var agility: int = 10
@export var intellect: int = 10
@export var endurance: int = 10
@export var spirit: int = 10

var current_hp: int
var current_mana: int
var state: String = "idle"
var attack_target: Node2D = null
var attack_cooldown: float = 0.0
var move_speed: float = 120.0

var abilities = [
	{"name": "fireball", "damage": 12, "mana_cost": 8, "cooldown": 1.2, "range": 200},
	{"name": "heal", "heal": 15, "mana_cost": 10, "cooldown": 4.0},
	{"name": "lightning", "damage": 20, "mana_cost": 15, "cooldown": 2.5, "range": 150}
]
var ability_cooldowns = [0.0, 0.0, 0.0]

func _ready():
	current_hp = max_hp
	current_mana = max_mana
	_ensure_sprite()

func _ensure_sprite():
	var sprite = get_node_or_null("Sprite")
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	
	if not sprite.texture:
		var img = Image.create(32, 48, false, Image.FORMAT_RGBA8)
		# Синий воин
		for y in range(48):
			for x in range(32):
				img.set_pixel(x, y, Color(0.2, 0.4, 0.9, 1.0))
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.offset = Vector2(0, -20)

func _physics_process(delta):
	if Game.is_paused:
		return

	attack_cooldown = max(0, attack_cooldown - delta)
	for i in range(ability_cooldowns.size()):
		ability_cooldowns[i] = max(0, ability_cooldowns[i] - delta)

	match state:
		"idle":
			velocity = Vector2.ZERO
		"move":
			move_to_target(delta)
		"chase":
			chase_target(delta)
		"attack":
			attack_enemy(delta)

	move_and_slide()

func move_to_target(_delta):
	if Game.player_target.distance_to(global_position) > 5.0:
		var direction = (Game.player_target - global_position).normalized()
		velocity = direction * move_speed
	else:
		state = "idle"
		velocity = Vector2.ZERO

func chase_target(_delta):
	if attack_target and is_instance_valid(attack_target):
		var distance = global_position.distance_to(attack_target.global_position)
		if distance > Game.ATTACK_RANGE:
			var direction = (attack_target.global_position - global_position).normalized()
			velocity = direction * move_speed
		else:
			state = "attack"
			velocity = Vector2.ZERO
	else:
		state = "idle"
		velocity = Vector2.ZERO

func attack_enemy(_delta):
	if attack_target and is_instance_valid(attack_target):
		if attack_cooldown <= 0:
			var damage = strength + randi() % 5
			print("Атакуем! Урон: ", damage)
			attack_target.take_damage(damage, self)
			attack_cooldown = Game.ATTACK_COOLDOWN
	else:
		state = "idle"

func cast_ability(index: int, target_position: Vector2):
	if index < 0 or index >= abilities.size():
		return

	var ability = abilities[index]
	if ability_cooldowns[index] > 0 or current_mana < ability.mana_cost:
		return

	current_mana -= ability.mana_cost
	ability_cooldowns[index] = ability.cooldown

	match ability.name:
		"fireball":
			create_projectile(global_position, target_position, ability.damage)
		"heal":
			current_hp = min(max_hp, current_hp + ability.heal)
		"lightning":
			var enemy = get_nearest_enemy(target_position, ability.range)
			if enemy:
				enemy.take_damage(ability.damage, self)

func create_projectile(from: Vector2, to: Vector2, damage: int):
	var projectile_scene = preload("res://scenes/projectile.tscn")
	if projectile_scene:
		var projectile = projectile_scene.instantiate()
		projectile.start_pos = from
		projectile.target_pos = to
		projectile.damage = damage
		projectile.projectile_owner = self
		get_tree().root.add_child(projectile)

func get_nearest_enemy(click_pos: Vector2, attack_range: float) -> Node2D:
	var nearest = null
	var min_dist = attack_range

	for enemy in Game.enemies:
		if is_instance_valid(enemy):
			var dist = enemy.global_position.distance_to(click_pos)
			if dist < min_dist:
				min_dist = dist
				nearest = enemy

	return nearest

func take_damage(damage: int, _attacker: Node2D):
	current_hp -= damage
	if current_hp <= 0:
		queue_free()
