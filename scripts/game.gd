extends Node2D
class_name Game

@onready var alm_map: Node2D = $Map
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var ui: CanvasLayer = $UI

static var is_paused: bool = false
static var player_target: Vector2 = Vector2.ZERO
static var enemies: Array = []
static var npcs: Array = []               # мирные жители (Npc) вне Game.enemies
static var hero: Node2D = null            # игрок (для наёмников/лута)
static var party: Array = []              # наёмники (Mercenary) из таверны
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
	Game.hero = player
	Game.party.clear()
	# НПЦ и монстры из карты (.alm секция units или sidecar .npcs.json)
	_spawn_map_units()

	if camera and player:
		camera.position = player.position
		camera.make_current()

	await get_tree().process_frame

	# Находим врагов (группа "enemy": враг из сцены + спавн из карты)
	enemies.clear()
	for child in get_children():
		if child.is_in_group("enemy"):
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

## Спавн НПЦ/монстров из данных карты: .alm секция units (type_id) или
## sidecar .npcs.json (set). Агрессия — UnitDB.is_hostile (монстры palette=5).
func _spawn_map_units() -> void:
	if alm_map == null or not alm_map.has_method("get_units"):
		return
	var recs: Array = alm_map.call("get_units")
	var spawned := 0
	for rec in recs:
		var set_name := ""
		if rec.has("set"):
			set_name = str(rec["set"])
		elif rec.has("type_id"):
			set_name = UnitDB.set_name_for_id(int(rec["type_id"]))
		if set_name == "" or not UnitDB.has(set_name):
			continue
		var pos := Vector2(float(rec["x"]) * 32.0 + 16.0, float(rec["y"]) * 32.0 + 16.0)
		if UnitDB.is_hostile(set_name):
			_spawn_monster(set_name, pos, rec)
		else:
			_spawn_npc(set_name, pos)
		spawned += 1
	print("Карта: спавн юнитов %d" % spawned)

func _spawn_monster(set_name: String, pos: Vector2, rec: Dictionary) -> void:
	var e := Enemy.new()
	e.name = "Monster_" + set_name.get_file()
	e.anim_set = set_name
	var hp := int(rec.get("hp_max", 0))
	if hp > 0:
		e.max_hp = hp
	e.position = pos
	e.home_position = pos
	add_child(e)
	enemies.append(e)

func _spawn_npc(set_name: String, pos: Vector2) -> void:
	var n := Npc.new()
	n.name = "Npc_" + set_name.get_file()
	n.anim_set = set_name
	n.position = pos
	n.home = pos
	add_child(n)
	npcs.append(n)

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

	# Клик по функциональному зданию: магазин / таверна / школа (без движения)
	var cell := Vector2i(int(world_position.x) / 32, int(world_position.y) / 32)
	if alm_map != null and alm_map.has_method("structure_at"):
		var s: Dictionary = alm_map.call("structure_at", cell)
		if not s.is_empty():
			var kind := _structure_kind(int(s.get("type_id", 0)))
			match kind:
				"shop":
					if ui: ui.open_shop()
					return
				"inn":
					if ui: ui.open_inn()
					return
				"school":
					if ui: ui.open_school()
					return

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
		# Маршрут с обходом препятствий (pathfinding по клеткам), не «по прямой»
		if alm_map != null and alm_map.has_method("find_path"):
			player.begin_path(alm_map.find_path(player.global_position, world_position))

## Функциональная роль здания по папке структуры (StructureDB).
func _structure_kind(type_id: int) -> String:
	var def := StructureDB.get_by_id(type_id)
	var folder := str(def.get("folder", "")).to_lower()
	if folder.contains("shop"):
		return "shop"
	if folder.contains("inn"):
		return "inn"
	if folder.contains("train") or folder.contains("school"):
		return "school"
	return ""

func get_enemy_at_position(click_pos: Vector2) -> Node2D:
	for enemy in enemies:
		if is_instance_valid(enemy) and unit_hit_rect(enemy).grow(8.0).has_point(click_pos):
			return enemy
	return null

## Хит-бокс юнита в мире: по sel_box спрайта — кликабельная ВИДИМАЯ область
## (раньше цель считалась в точке пола — «враг был ниже, чем его видно»).
static func unit_hit_rect(u: Node2D) -> Rect2:
	if not is_instance_valid(u):
		return Rect2()
	var set_name := ""
	if "anim_set" in u:
		set_name = str(u.get("anim_set"))
	if set_name == "" and u is Player:
		set_name = (u as Player).anim_set_name()
	var w := 128
	var h := 128
	var sel := Rect2i(16, 16, 96, 96)
	if set_name != "":
		var o := UnitDB.get_set(set_name)
		w = int(o.get("w", 128))
		h = int(o.get("h", 128))
		sel = UnitDB.sel_box(set_name)
	var base := u.global_position + Vector2(-w / 2.0, -h)
	return Rect2(base + Vector2(sel.position.x, sel.position.y), Vector2(sel.size.x, sel.size.y))

## Расстояние между КОРПУСАМИ юнитов (хит-бокс к хит-боксу; 0 при пересечении).
## Для боя: юниты встают вплотную телами и атакуют, а не «издалека по центру».
static func units_range(a: Node2D, b: Node2D) -> float:
	var ra := unit_hit_rect(a)
	var rb := unit_hit_rect(b)
	if ra.intersects(rb):
		return 0.0
	var dx := maxf(0.0, maxf(ra.position.x - (rb.position.x + rb.size.x),
		rb.position.x - (ra.position.x + ra.size.x)))
	var dy := maxf(0.0, maxf(ra.position.y - (rb.position.y + rb.size.y),
		rb.position.y - (ra.position.y + ra.size.y)))
	return sqrt(dx * dx + dy * dy)

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
