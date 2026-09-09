extends Node2D
class_name Game

@onready var tilemap: TileMapLayer = $TileMap
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var ui: CanvasLayer = $UI

static var is_paused: bool = false
static var player_target: Vector2 = Vector2.ZERO
static var enemies: Array = []
static var mana_regen_accum: float = 0.0
static var action_mode: String = "none"  # none, follow, attack, guard
static var action_target: Node2D = null

const PLAYER_SPEED: float = 120.0
const ATTACK_RANGE: float = 40.0
const ATTACK_COOLDOWN: float = 1.0
const AGGRO_RADIUS: float = 150.0
const DEAGGRO_RADIUS: float = 200.0

func _ready():
	process_mode = PROCESS_MODE_ALWAYS  # Работает даже на паузе
	if camera and player:
		camera.position = player.position
		camera.make_current()

	await get_tree().process_frame
	
	# Находим врагов и игрока
	for child in get_children():
		if child is CharacterBody2D and child != player:
			enemies.append(child)
			print("  Враг найден: ", child.name, " HP=", child.max_hp if "max_hp" in child else "?")

	print("Всего врагов: ", enemies.size())

	# Добавляем игрока в группу "player" для врагов
	player.add_to_group("player")
	
	# TileMap доступен через @onready — добавим в группу для миникарты
	tilemap.add_to_group("tilemap")

	if ui:
		ui.setup_ui(player)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_position = get_global_mouse_position()
		handle_click(world_position)

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		is_paused = !is_paused
		get_tree().paused = is_paused

	# Рестарт по Ctrl+R
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and event.ctrl_pressed:
		get_tree().reload_current_scene()

func handle_click(world_position: Vector2):
	print("Клик в: ", world_position)

	var enemy = get_enemy_at_position(world_position)
	if enemy:
		print("Атака врага!")
		player.attack_target = enemy
		player.state = "chase"
	else:
		print("Движение к: ", world_position)
		player_target = world_position
		player.state = "move"
		player.attack_target = null

func get_enemy_at_position(click_pos: Vector2) -> Node2D:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(click_pos) < 30.0:
			return enemy
	return null

func _process(delta):
	if is_paused:
		return
	if is_instance_valid(player) and camera:
		camera.position = camera.position.lerp(player.position, 5.0 * delta)
	if is_instance_valid(ui) and is_instance_valid(player):
		ui.update_ui(player)
	
	# Регенерация маны игрока — 1 мана в секунду
	if is_instance_valid(player) and player.current_mana < player.max_mana:
		mana_regen_accum += delta
		if mana_regen_accum >= 1.0:
			mana_regen_accum -= 1.0
			player.current_mana = min(player.max_mana, player.current_mana + 1)
	
	# Обработка режимов действий
	_process_action_mode()

func _process_action_mode():
	if action_mode == "none" or not is_instance_valid(player):
		return
	
	match action_mode:
		"follow":
			# Идти за ближайшим союзником (пока за ближайшим NPC)
			if action_target and is_instance_valid(action_target):
				player.attack_target = action_target
				player.state = "chase"
		"attack":
			# Атаковать ближайшего врага
			if enemies.size() > 0:
				var nearest = null
				var min_dist = 9999.0
				for e in enemies:
					if is_instance_valid(e):
						var d = e.global_position.distance_to(player.global_position)
						if d < min_dist:
							min_dist = d
							nearest = e
				if nearest:
					player.attack_target = nearest
					player.state = "chase"
		"guard":
			# Стоять на месте и атаковать врагов в радиусе
			if player.state == "idle":
				for e in enemies:
					if is_instance_valid(e) and e.global_position.distance_to(player.global_position) < 150:
						player.attack_target = e
						player.state = "chase"
						break
