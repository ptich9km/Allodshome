extends Node2D
class_name Game

@onready var alm_map: Node2D = $Map
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var ui: CanvasLayer = $UI

static var is_paused: bool = false
static var player_target: Vector2 = Vector2.ZERO
static var enemies: Array = []
static var mana_regen_accum: float = 0.0
static var action_mode: String = "none"  # none, follow, attack, guard
static var action_target: Node2D = null

# --- Выбор героя на старте (сцена character_select) ---
static var hero_class: String = "warrior"   # warrior | mage
static var hero_gender: String = "male"     # male | female
static var hero_name: String = "Герой"
static var hero_character_id: String = "mfighter"  # id из character_select
static var hero_stats: Dictionary = {}      # стартовые характеристики

const PLAYER_SPEED: float = 120.0
const ATTACK_RANGE: float = 40.0
const ATTACK_COOLDOWN: float = 1.0
const AGGRO_RADIUS: float = 150.0
const DEAGGRO_RADIUS: float = 200.0

func _ready():
	process_mode = PROCESS_MODE_ALWAYS  # Работает даже на паузе

	# Страховка: если main.tscn запущен напрямую (F6, отладка) без выбора
	# персонажа на старте — уходим на экран выбора героя.
	if Game.hero_stats.is_empty():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/character_select.tscn")
		return

	# Спавним игрока на проходимом тайле в центре карты
	_spawn_player_on_walkable()

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

	if ui:
		ui.setup_ui(player)

func _spawn_player_on_walkable():
	var mw: int = int(alm_map.get("map_width"))
	var mh: int = int(alm_map.get("map_height"))
	if not alm_map or mw == 0:
		return
	# 1) Точка спавна, заданная в карте (тип «Спавн»)
	var spawn_pos: Vector2 = alm_map.call("get_spawn_pos")
	if alm_map.call("is_walkable_world", spawn_pos):
		player.global_position = spawn_pos
		return
	# 2) Запасной вариант — проходимый тайл от центра
	var cx := mw / 2
	var cy := mh / 2
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var tx := cx + dx
				var ty := cy + dy
				var ts: int = int(alm_map.get("tile_size"))
				var wx := tx * ts + ts / 2
				var wy := ty * ts + ts / 2
				if alm_map.call("is_walkable_world", Vector2(wx, wy)):
					player.global_position = Vector2(wx, wy)
					return

## Ищем проходимую клетку рядом со спавном, у которой есть проходимые соседи
## (минимум 2 из 4) — чтобы персонаж не оказался в тупике. Возвращаем центр
## клетки в мировых координатах или Vector2(-1,-1), если в радиусе 6 нет места.
func _find_open_spot(start: Vector2i, ts: int) -> Vector2:
	if _is_open_spot(start.x, start.y):
		return Vector2(start.x * ts + ts / 2, start.y * ts + ts / 2)
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue  # только кольцо на расстоянии r
				var tx := start.x + dx
				var ty := start.y + dy
				if _is_open_spot(tx, ty):
					return Vector2(tx * ts + ts / 2, ty * ts + ts / 2)
	return Vector2(-1, -1)

## Клетка проходима и имеет >=2 проходимых соседей (не закуток).
func _is_open_spot(tx: int, ty: int) -> bool:
	var ts: int = alm_map.tile_size
	var wx: int = tx * ts + ts / 2
	var wy: int = ty * ts + ts / 2
	if not alm_map.is_walkable_world(Vector2(wx, wy)):
		return false
	var open_neighbors := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = tx + d.x
		var ny: int = ty + d.y
		if nx < 0 or ny < 0 or nx >= alm_map.map_width or ny >= alm_map.map_height:
			continue
		if alm_map.is_walkable_world(Vector2(nx * ts + ts / 2, ny * ts + ts / 2)):
			open_neighbors += 1
	return open_neighbors >= 2

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

	# Toggle инвентаря по I
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		if ui:
			ui.toggle_inventory()

	# Toggle магий по B
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		if ui:
			ui.toggle_spells()

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
