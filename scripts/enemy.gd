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
var health_bar: HealthBar

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
	var sprite = get_node_or_null("Sprite")
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)

	if not sprite.texture:
		# Загружаем спрайт из файла или создаём заглушку
		var tex_path = ""
		var img_color = Color(0.2, 0.6, 0.15, 1.0)  # орк зелёный
		
		if max_hp >= 80:
			# Тролль — большой серый
			tex_path = ""
			img_color = Color(0.4, 0.4, 0.4, 1.0)
		elif max_hp >= 50:
			tex_path = "res://assets/sprites/orc.png"
		else:
			tex_path = "res://assets/sprites/slime.png"
		var tex = load(tex_path)
		if tex:
			sprite.texture = tex
		else:
			# Заглушка если файл не найден
			var img = Image.create(32, 48, false, Image.FORMAT_RGBA8)
			for y in range(48):
				for x in range(32):
					img.set_pixel(x, y, img_color)
			sprite.texture = ImageTexture.create_from_image(img)
		sprite.offset = Vector2(0, -20)

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
		queue_free()
