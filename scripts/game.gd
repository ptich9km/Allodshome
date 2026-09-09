extends Node2D
class_name Game

# Ссылки на ноды
@onready var tilemap: TileMapLayer = $TileMap
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var ui: CanvasLayer = $UI

# Состояние игры
static var is_paused: bool = false
static var player_target: Vector2 = Vector2.ZERO
static var enemies: Array = []

# Параметры баланса (из Unity проекта)
const PLAYER_SPEED: float = 120.0
const ATTACK_RANGE: float = 40.0
const ATTACK_COOLDOWN: float = 1.0
const AGGRO_RADIUS: float = 150.0
const DEAGGRO_RADIUS: float = 200.0

func _ready():
	# Настройка камеры
	if camera and player:
		camera.position = player.position
		camera.make_current()
	
	# Загружаем врагов после первого кадра
	await get_tree().process_frame
	enemies = get_tree().get_nodes_in_group("enemies")
	print("Найдено врагов: ", enemies.size())
	
	# Настраиваем UI
	if ui:
		ui.setup_ui(player)

func _input(event):
	# Клик мышью - движение или атака
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_position = get_global_mouse_position()
		handle_click(world_position)
	
	# Пауза
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		is_paused = !is_paused
		get_tree().paused = is_paused

func handle_click(world_position: Vector2):
	print("Клик в: ", world_position)
	
	# Проверяем есть ли враг в позиции клика
	var enemy = get_enemy_at_position(world_position)
	
	if enemy:
		# Атака врага
		print("Атака врага!")
		player.attack_target = enemy
		player.state = "chase"
	else:
		# Движение к точке
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
	
	# Обновляем камеру
	if is_instance_valid(player) and camera:
		camera.position = camera.position.lerp(player.position, 5.0 * delta)
	
	# Обновляем UI
	if is_instance_valid(ui):
		ui.update_ui(player)
