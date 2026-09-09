extends CharacterBody2D
class_name Enemy

@export var max_hp: int = 50
@export var damage: int = 8
@export var move_speed: float = 80.0
@export var aggro_radius: float = 150.0
@export var deaggro_radius: float = 200.0
@export var home_position: Vector2

var current_hp: int
var state: String = "idle"
var attack_target: Node2D = null
var attack_cooldown: float = 0.0
var can_flee: bool = true

func _ready():
	current_hp = max_hp
	home_position = global_position
	_create_sprite()

func _create_sprite():
	# Создаём спрайт программно если нет дочернего Sprite2D
	var sprite = get_node_or_null("Sprite")
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	
	# Если текстура не задана — создаём заглушку
	if not sprite.texture:
		var img = Image.create(32, 48, false, Image.FORMAT_RGBA8)
		
		# Определяем тип врага по HP
		if max_hp >= 50:
			# Орк — зелёный
			for y in range(48):
				for x in range(32):
					img.set_pixel(x, y, Color(0.2, 0.6, 0.15, 1.0))
		else:
			# Слизень — розовый
			for y in range(48):
				for x in range(32):
					img.set_pixel(x, y, Color(0.9, 0.3, 0.6, 1.0))
		
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.offset = Vector2(0, -20)

func _physics_process(delta):
	if Game.is_paused:
		return

	attack_cooldown = max(0, attack_cooldown - delta)

	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return

	var distance_to_player = global_position.distance_to(player.global_position)
	var hp_percent = float(current_hp) / max_hp

	match state:
		"idle":
			if distance_to_player < aggro_radius:
				state = "chase"
				attack_target = player
		"chase":
			if distance_to_player > deaggro_radius:
				state = "idle"
				attack_target = null
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

func move_toward_target(target: Vector2, _delta):
	var direction = (target - global_position).normalized()
	velocity = direction * move_speed

func take_damage(_damage: int, _attacker: Node2D):
	current_hp -= _damage
	if current_hp <= 0:
		queue_free()
