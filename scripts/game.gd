extends Node2D
class_name Game

@onready var tilemap: TileMapLayer = $TileMap
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var ui: CanvasLayer = $UI

static var is_paused: bool = false
static var player_target: Vector2 = Vector2.ZERO
static var enemies: Array = []

const PLAYER_SPEED: float = 120.0
const ATTACK_RANGE: float = 40.0
const ATTACK_COOLDOWN: float = 1.0
const AGGRO_RADIUS: float = 150.0
const DEAGGRO_RADIUS: float = 200.0

func _ready():
	if camera and player:
		camera.position = player.position
		camera.make_current()

	await get_tree().process_frame
	
	# Находим врагов — все CharacterBody2D кроме игрока
	for child in get_children():
		if child is CharacterBody2D and child != player:
			enemies.append(child)
			print("  Враг найден: ", child.name, " HP=", child.max_hp if "max_hp" in child else "?")
	
	print("Всего врагов: ", enemies.size())

	if ui:
		ui.setup_ui(player)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_position = get_global_mouse_position()
		handle_click(world_position)

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		is_paused = !is_paused
		get_tree().paused = is_paused

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
	if is_instance_valid(ui):
		ui.update_ui(player)
