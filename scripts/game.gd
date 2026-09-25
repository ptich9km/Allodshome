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
static var _trauma: float = 0.0
static var _trauma_t: float = 0.0
static var action_mode: String = "none"  # none, follow, attack, guard
static var action_target: Node2D = null
static var pending_scroll: Dictionary = {}   # прицеливание свитка: {"spell","item_key"}
static var pending_spell: Dictionary = {}    # выбор заклинания из книги: {"name"}
static var hotbar: Dictionary = {}           # быстрый вызов: слот 0..8 (клавиши 1..9) -> имя заклинания
static var _spell_targeting_frame: int = -1  # кадр, когда начато прицеливание (защита от двойного каста)
static var debug_magic: bool = true  # ВРЕМЕННО: все заклинания + бесконечная мана

# --- Защитные баффы (книги/свитки защиты, Shield): уменьшение входящего урона ---
static func apply_shield(unit: Node2D, strength: int, seconds: float) -> void:
	if not is_instance_valid(unit):
		return
	unit.set_meta("shield_strength", int(unit.get_meta("shield_strength", 0)) + strength)
	unit.set_meta("shield_time", float(unit.get_meta("shield_time", 0.0)) + seconds)

static func shield_reduce(unit: Node2D, dmg: int) -> int:
	if not is_instance_valid(unit):
		return dmg
	var strength := int(unit.get_meta("shield_strength", 0))
	if strength <= 0:
		return dmg
	unit.set_meta("shield_strength", strength - dmg)
	var out := maxi(0, dmg - strength)
	if out == 0:
		print("%s: щит поглотил весь урон!" % unit.name)
	return out

## --- Общая математика боя: характеристики -> шанс/урон (для ЛЮБОГО юнита) ---

## Шанс попадания, %: 50 + атака − защита, кламп 5..95.
static func hit_chance(attack: int, defense: int) -> int:
	return clampi(50 + attack - defense, 5, 95)

## Промах? Юниты с методами get_attack()/get_defense() участвуют полностью.
static func is_miss(attacker: Node2D, defender: Node2D) -> bool:
	var atk := 0
	var dfs := 0
	if attacker != null and attacker.has_method("get_attack"):
		atk = int(attacker.call("get_attack"))
	if defender != null and defender.has_method("get_defense"):
		dfs = int(defender.call("get_defense"))
	return randi() % 100 >= hit_chance(atk, dfs)

## Точность юнита (если есть метод — иначе 0).
static func unit_attack(u: Node2D) -> int:
	return int(u.call("get_attack")) if u != null and u.has_method("get_attack") else 0

## Защита юнита (уклонение/броня).
static func unit_defense(u: Node2D) -> int:
	return int(u.call("get_defense")) if u != null and u.has_method("get_defense") else 0

## Поглощение (материал/броня): get_absorption() — есть у героя и врагов.
static func unit_absorption(u: Node2D) -> int:
	return int(u.call("get_absorption")) if u != null and u.has_method("get_absorption") else 0

## Сопротивление стихии в ПРОЦЕНТАХ: сколько процентов магического урона
## не пройдёт. Так в оригинале (main.txt: «shows the percentage of the
## magical effects… which will not affect the character») и это не ломается
## от больших чисел, в отличие от плоского вычитания.
static func unit_protection(u: Node2D, sphere: String) -> int:
	if u == null or sphere == "":
		return 0
	var m := "get_protection_%s" % sphere.to_lower()
	if u.has_method(m):
		return clampi(int(u.call(m)), 0, 95)
	return 0

## --- Сила магии: ОДИН стат на урон, лечение, щит и вампиризм ---
## Формула оригинала (Allods II): SP = навык сферы + разум - 30.
## Кламп в ноль обязателен: при навыке 5 и разуме 9 выходит -16, а оригинал
## на таких значениях ломается (SP>255 — баг переполнения байта).
static func spell_power(caster: Node2D, sphere: String) -> float:
	if caster == null or not is_instance_valid(caster):
		return 0.0
	var mind := 0.0
	if "mind" in caster:
		mind = float(caster.get("mind"))
	var skill := 0.0
	if caster.has_method("sphere_skill"):
		skill = float(caster.call("sphere_skill", sphere))
	return maxf(0.0, skill + mind - SP_OFFSET) + float(StatusEffects.stat_flat(caster, "power"))


## Порог «минус 30» из оригинала: ниже него заклинание почти ничего не делает.
const SP_OFFSET := 30.0


## Урон заклинания с учётом силы кастера и множителя заклинания.
## final = base * power_coef * (1 + spell_power/100)
static func spell_damage(caster: Node2D, spell_name: String, sphere: String, base_damage: int) -> int:
	var coef := SpellDB.power_coef_of(spell_name)
	var power := spell_power(caster, sphere)
	var raw := float(base_damage) * coef * (1.0 + power / 100.0)
	return maxi(SpellDB.min_damage_of(spell_name), int(round(raw)))


## ЕДИНАЯ точка урона: физика -> поглощение; магия -> защиты стихий; далее щит и HP.
## Возвращает фактически нанесённый урон (0 — если всё поглощён/промах).
static func deal_damage(target: Node2D, dmg: int, kind: String, sphere: String, attacker: Node2D) -> int:
	if not is_instance_valid(target) or dmg <= 0:
		return 0
	var final := dmg
	if kind == "magic":
		# Сопротивление — процент от урона (как в оригинале)
		var prot := unit_protection(target, sphere)
		final = maxi(0, int(round(float(dmg) * (1.0 - float(prot) / 100.0))))
	else:
		final = maxi(0, final - unit_absorption(target))
	if final <= 0:
		print("%s: урон поглощён полностью (%s)." % [target.name,
			"защита стихии" if kind == "magic" else "броня"])
		DamageNumber.show_at(target.global_position, 0, "absorb")
		return 0
	var dealt := 0
	if target.has_method("take_damage"):
		dealt = target.call("take_damage", final, attacker)
		if dealt is int and int(dealt) > 0:
			final = int(dealt)
	# Единственное место, где рисуется урон: иначе числа дублировались
	# в projectile.gd и enemy.gd, и показывали сырое, а не фактическое значение.
	DamageNumber.show_at(target.global_position, final, "damage")
	SpellVFX.hit_flash(target)
	if kind == "magic" and is_instance_valid(attacker):
		_apply_vampirism(attacker, final)
	return final


## Вампиризм (Drain_Life): часть нанесённого магией урона возвращается кастеру.
static func _apply_vampirism(caster: Node2D, dealt: int) -> void:
	var ratio := StatusEffects.vampirism_ratio(caster)
	if ratio <= 0.0 or dealt <= 0:
		return
	var amount := maxi(1, int(float(dealt) * ratio))
	if caster.has_method("heal_amount"):
		caster.call("heal_amount", amount)


## Нанести урон всем целям в радиусе (для областных заклинаний/взрывов).
static func deal_damage_area(targets: Array, dmg: int, kind: String, sphere: String, attacker: Node2D) -> void:
	for t in targets:
		if is_instance_valid(t):
			deal_damage(t, dmg, kind, sphere, attacker)

static func tick_shields(delta: float) -> void:
	var units: Array = [Game.hero]
	units.append_array(Game.enemies)
	units.append_array(Game.npcs)
	units.append_array(Game.party)
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		if not u.has_meta("shield_time"):
			continue
		var t := float(u.get_meta("shield_time", 0.0)) - delta
		if t > 0.0:
			u.set_meta("shield_time", t)
		else:
			u.set_meta("shield_time", 0.0)
			u.set_meta("shield_strength", 0)

static func configure_unit_body(unit: Node2D, radius: float = 12.0) -> void:
	if not (unit is CharacterBody2D):
		return
	var body := unit as CharacterBody2D
	body.collision_mask = 1
	var shape_node: CollisionShape2D = null
	for child in body.get_children():
		if child is CollisionShape2D:
			shape_node = child as CollisionShape2D
			break
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "Collision"
		body.add_child(shape_node)
	if shape_node.shape == null:
		var shape := CircleShape2D.new()
		shape.radius = radius
		shape_node.shape = shape

static func movement_direction(unit: Node2D, desired: Vector2) -> Vector2:
	if desired.length_squared() <= 0.0001:
		return Vector2.ZERO
	var units: Array = [Game.hero]
	units.append_array(Game.enemies)
	units.append_array(Game.npcs)
	units.append_array(Game.party)
	var separation := Vector2.ZERO
	for other in units:
		if other == unit or other == null or not is_instance_valid(other):
			continue
		if not (other is Node2D):
			continue
		var delta := unit.global_position - (other as Node2D).global_position
		var distance := delta.length()
		if distance > 0.1 and distance < 24.0:
			separation += delta / distance * (24.0 - distance) / 24.0
	var result := desired.normalized() + separation * 1.5
	return result.normalized() if result.length_squared() > 0.0001 else desired.normalized()

var _select_ring: SelectRing = null       # подсветка цели (ховер/атака)
var _pending_building := ""               # здание, к которому герой подходит («вход»)
var _pending_s: Dictionary = {}           # структура-цель ожидающего входа
var _pending_herb: HerbNode = null

# --- Выбор героя на старте (сцена character_select) ---
static var hero_class: String = "warrior"   # warrior | mage
static var hero_gender: String = "male"     # male | female
static var hero_name: String = "Герой"
static var hero_character_id: String = "mfighter"  # id из character_select
static var hero_stats: Dictionary = {}      # стартовые характеристики
static var hero_start_book: String = ""     # книга простейшего заклинания школы мага

# --- Выбор карты ---
## Явно запрошенный путь к .alm. Не пусто только когда путь задан вручную:
## редактор карт (F9 «Назад в игру») или загрузка сохранения. Имеет приоритет над сидом.
static var pending_map_path: String = ""
## Сид карты новой игры. 0 = карта не запрошена, AlmMap берёт запасной путь из main.tscn
## (детерминированный dev-режим и автотесты — им случайная карта мешала бы).
static var map_seed: int = 0
static var map_zone: String = "mid"   # start | mid | hard | faction

## Новая карта со случайным сидом. Вызывается из character_select перед стартом.
static func new_random_map(zone: String = "mid") -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	map_seed = rng.randi()
	map_zone = zone
	pending_map_path = ""

## Конкретная карта по сиду (загрузка сохранения, тесты).
static func request_map_by_seed(seed_value: int, zone: String = "mid") -> void:
	map_seed = seed_value
	map_zone = zone
	pending_map_path = ""

## Явно заданный файл карты (редактор, отладочные сцены).
static func request_map_by_path(path: String) -> void:
	pending_map_path = path
	map_seed = 0

const PLAYER_SPEED: float = 120.0
const ATTACK_RANGE: float = 40.0
const ATTACK_COOLDOWN: float = 1.0
const AGGRO_RADIUS: float = 150.0
const DEAGGRO_RADIUS: float = 200.0

func _ready():  # Инициализация мира и боя
	process_mode = PROCESS_MODE_ALWAYS  # Работает даже на паузе

	# Сброс режимов прицеливания (статика переживает перезапуск сцены)
	pending_scroll = {}
	pending_spell = {}
	_spell_targeting_frame = -1

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
		camera.position = player.camera_focus()
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

	_select_ring = SelectRing.new()
	_select_ring.name = "SelectRing"
	_select_ring.z_index = 9
	add_child(_select_ring)
	_select_ring.visible = false

func _spawn_player_on_walkable():
	var mw: int = int(alm_map.get("map_width"))
	var mh: int = int(alm_map.get("map_height"))
	if not alm_map or mw == 0:
		return
	# 1) Точка спавна, заданная в карте (тип «Спавн»)
	var spawn_pos: Vector2 = alm_map.call("get_spawn_pos")
	if alm_map.call("is_walkable_world", spawn_pos):
		player.global_position = spawn_pos
		player.reset_physics_interpolation()
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
					player.reset_physics_interpolation()
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
		var raw_cell := Vector2i(int(rec.get("x", 0)), int(rec.get("y", 0)))
		var open_pos := _find_open_spot(raw_cell, int(alm_map.get("tile_size")))
		if open_pos.x < 0.0:
			continue
		if UnitDB.is_hostile(set_name):
			_spawn_monster(set_name, open_pos, rec)
		else:
			_spawn_npc(set_name, open_pos, rec)
		spawned += 1
	print("Карта: спавн юнитов %d" % spawned)

func _spawn_monster(set_name: String, pos: Vector2, rec: Dictionary) -> void:
	var e := Enemy.new()
	e.name = "Monster_" + set_name.get_file()
	e.anim_set = set_name
	var hp := int(rec.get("hp_max", 0))
	if hp > 0:
		e.max_hp = hp
	var dmg := int(rec.get("damage", 0))
	if dmg > 0:
		e.damage = dmg
	e.position = pos
	e.home_position = pos
	add_child(e)
	enemies.append(e)

func _spawn_npc(set_name: String, pos: Vector2, rec: Dictionary) -> void:
	var n := Npc.new()
	n.name = "Npc_" + set_name.get_file()
	n.anim_set = set_name
	n.position = pos
	n.home = pos
	var role := str(rec.get("role", "citizen"))
	n.role = role
	n.is_patrol = bool(rec.get("patrol", false))
	var post: Array = rec.get("post", [])
	if post.size() >= 2:
		var post_cell := Vector2i(int(post[0]), int(post[1]))
		var post_pos := _find_open_spot(post_cell, int(alm_map.get("tile_size")))
		n.post = post_pos if post_pos.x >= 0.0 else pos
	var hp := int(rec.get("hp_max", 0))
	if hp > 0:
		n.max_hp = hp
	var dmg := int(rec.get("damage", 0))
	if dmg > 0:
		n.damage = dmg
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
	# Прицеливание (свиток или заклинание книги): ПКМ или ESC отменяет.
	# Свиток НЕ тратится, мана/заряд НЕ списываются.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not Game.pending_scroll.is_empty() or not Game.pending_spell.is_empty():
			cancel_targeting()
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not Game.pending_scroll.is_empty() or not Game.pending_spell.is_empty():
			cancel_targeting()
			return

	# Быстрые клавиши заклинаний (как у разработчиков): во время выбора магии
	# Ctrl+1..9 назначает её на цифровую клавишу; 1..9 (без Ctrl) входит в
	# прицеливание назначенной магии.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var slot: int = event.keycode - KEY_1
			if event.ctrl_pressed and not Game.pending_spell.is_empty():
				var sn := str(Game.pending_spell.get("name", ""))
				if sn != "":
					Game.hotbar[slot] = sn
					print("Быстрая клавиша %d -> %s" % [slot + 1, sn])
					if ui != null and ui.has_method("_notify_hotbar_assigned"):
						ui._notify_hotbar_assigned(slot, sn)
				return
			if not event.ctrl_pressed:
				var fast := str(Game.hotbar.get(slot, ""))
				if fast != "":
					if ui != null and ui.has_method("_quick_cast"):
						ui._quick_cast(fast)
					return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Клики по интерфейсу (книга заклинаний, инвентарь, панели, магазин/таверна)
		# не должны двигать/атаковать героя по карте
		if ui != null and ui.has_method("is_editor_open") and ui.is_editor_open():
			return
		if ui != null and ui.has_method("is_pointer_over_ui") and ui.is_pointer_over_ui(event.position):
			return
		var world_position = get_global_mouse_position()
		# Чтение свитка мага: клик выбирает цель (врага или себя/союзника)
		if not Game.pending_scroll.is_empty():
			_resolve_scroll_click(world_position)
			return
		# Заклинание из книги: клик выбирает цель для выбранной магии
		if not Game.pending_spell.is_empty():
			_resolve_spell_click(world_position)
			return
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
	# Герой мёртв (падение/разложение) — управление не работает
	if is_instance_valid(player) and player.state in ["dead", "decay"]:
		return
	print("Клик в: ", world_position)
	_pending_herb = null

	# Клик по функциональному зданию: магазин / таверна / школа (подход к двери)
	var cell := Vector2i(int(world_position.x) / 32, int(world_position.y) / 32)
	if alm_map != null and alm_map.has_method("structure_at"):
		var s: Dictionary = alm_map.call("structure_at", cell)
		if not s.is_empty():
			var kind := _structure_kind(int(s.get("type_id", 0)))
			if kind != "":
				_building_click(kind, s)
				return
	if alm_map != null and alm_map.has_method("herb_at_position"):
		var herb := alm_map.call("herb_at_position", world_position) as HerbNode
		if herb != null:
			_herb_click(herb)
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
	if folder.contains("druidshop"):
		return "alchemy"
	if folder.contains("shop"):
		return "shop"
	if folder.contains("inn"):
		return "inn"
	if folder.contains("train") or folder.contains("school"):
		return "school"
	if folder.contains("blacksmith"):
		return "blacksmith"
	return ""

## Клик по функциональному зданию: если герой далеко — сначала идёт к двери,
## открыть панель («войти») только при подходе.
func _building_click(kind: String, s: Dictionary) -> void:
	if ui == null:
		return
	var door := _door_point(s)
	if player.global_position.distance_to(door) <= 90.0:
		_pending_building = ""
		match kind:
			"shop": ui.open_shop()
			"alchemy": ui.open_alchemy()
			"inn": ui.open_inn()
			"school": ui.open_school()
			"blacksmith": ui.open_blacksmith()
		return
	_pending_building = kind
	_pending_s = s
	player_target = door
	player.state = "move"
	player.attack_target = null
	if alm_map != null and alm_map.has_method("find_path"):
		player.begin_path(alm_map.find_path(player.global_position, door))

func _herb_click(herb: HerbNode) -> void:
	if not is_instance_valid(herb) or not herb.is_available():
		return
	_pending_building = ""
	player.attack_target = null
	if player.global_position.distance_to(herb.global_position) <= 52.0:
		_harvest_herb(herb)
		return
	_pending_herb = herb
	player_target = herb.global_position
	player.state = "move"
	if alm_map != null and alm_map.has_method("find_path"):
		player.begin_path(alm_map.find_path(player.global_position, herb.global_position))

func _process_pending_herb() -> void:
	if _pending_herb == null:
		return
	if not is_instance_valid(_pending_herb) or not _pending_herb.is_available():
		_pending_herb = null
		return
	if player.global_position.distance_to(_pending_herb.global_position) <= 52.0:
		var herb := _pending_herb
		_pending_herb = null
		_harvest_herb(herb)

func _harvest_herb(herb: HerbNode) -> void:
	if not is_instance_valid(herb) or not herb.harvest():
		return
	player.add_item(herb.item_key)
	if is_instance_valid(ui):
		ui.refresh_inventory()
	SoundDB.play(1)
	print("Собрана трава: %s" % herb.item_key)

## Точка входа (дверь): проходимая клетка под южным краем корпуса здания.
func _door_point(s: Dictionary) -> Vector2:
	var def := StructureDB.get_by_id(int(s.get("type_id", 0)))
	var fw := int(def.get("tile_width", 1))
	var th := int(def.get("tile_height", 1))
	var x := int(s.get("ax", 0))
	var y := int(s.get("ay", 0))
	var base := Vector2i(x + fw / 2, y + th)
	for r in range(3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var c := base + Vector2i(dx, dy)
				var p := Vector2(c.x * 32.0 + 16.0, c.y * 32.0 + 16.0)
				if alm_map != null and alm_map.has_method("is_walkable_world") \
						and alm_map.is_walkable_world(p):
					return p
	return Vector2(x * 32.0 + fw * 16.0, (y + th) * 32.0)

## Когда герой подошёл к двери — «входим»: открываем панель здания.
func _process_pending_building() -> void:
	if _pending_building == "" or not is_instance_valid(player) or not is_instance_valid(ui):
		return
	var door := _door_point(_pending_s)
	if player.global_position.distance_to(door) <= 80.0:
		var k := _pending_building
		_pending_building = ""
		_pending_s = {}
		match k:
			"shop": ui.open_shop()
			"alchemy": ui.open_alchemy()
			"inn": ui.open_inn()
			"school": ui.open_school()
			"blacksmith": ui.open_blacksmith()

## Юнит под курсором (враг ИЛИ мирный НПЦ) по видимой области корпуса.
func _hover_unit() -> Node2D:
	if not is_instance_valid(player):
		return null
	var mouse := player.get_global_mouse_position()
	for e in enemies:
		if is_instance_valid(e) and unit_hit_rect(e).grow(6.0).has_point(mouse):
			return e
	for e in npcs:
		if is_instance_valid(e) and unit_hit_rect(e).grow(6.0).has_point(mouse):
			return e
	return null

## Размер спрайта юнита (w, h).
func _unit_metrics(u: Node2D) -> Array:
	var set_name := ""
	if "anim_set" in u:
		set_name = str(u.get("anim_set"))
	if set_name == "" and u is Player:
		set_name = (u as Player).anim_set_name()
	var w := 128
	var h := 128
	if set_name != "":
		var o := UnitDB.get_set(set_name)
		w = int(o.get("w", 128))
		h = int(o.get("h", 128))
	return [w, h]

## Точка кольца выделения: центр тела юнита. Спрайт рисуется вверх от точки
## «пола» и поднимается на рельефе — без учёта этого кольцо «висит в пустоте».
func _target_ring_pos(u: Node2D) -> Vector2:
	var m := _unit_metrics(u)
	var rise := 0.0
	if alm_map != null and alm_map.has_method("relief_at_world"):
		rise = float(alm_map.call("relief_at_world", u.global_position))
	return Vector2(u.global_position.x, u.global_position.y - float(m[1]) * 0.55 - rise)

## Подсветка цели: враг под курсором / текущая цель атаки (красное кольцо)
## или мирный НПЦ под курсором (жёлтое кольцо).
func _update_target_ring() -> void:
	var target: Node2D = null
	var hostile := false
	if is_instance_valid(player) and is_instance_valid(player.attack_target) \
			and player.state in ["chase", "attack"]:
		target = player.attack_target
		hostile = true
	else:
		target = _hover_unit()
		hostile = target != null and enemies.has(target)
	if _select_ring == null:
		return
	if is_instance_valid(target):
		_select_ring.visible = true
		_select_ring.color = Color(1, 0.3, 0.2, 0.9) if hostile else Color(0.95, 0.85, 0.35, 0.9)
		_select_ring.global_position = _target_ring_pos(target)
		var m := _unit_metrics(target)
		_select_ring.radius = maxf(22.0, float(m[0]) / 2.0 + 8.0)
	else:
		_select_ring.visible = false

func get_enemy_at_position(click_pos: Vector2) -> Node2D:
	for enemy in enemies:
		if is_instance_valid(enemy) and unit_hit_rect(enemy).grow(8.0).has_point(click_pos):
			return enemy
	return null

## Свиток мага: клик выбрал цель. Враг — для урона/области/стены,
## герой или союзник (НПЦ/наёмник) — для лечения/защиты/баффа.
func _resolve_scroll_click(world_position: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var spell := str(Game.pending_scroll.get("spell", ""))
	if spell == "":
		return
	var target_kind := SpellDB.target_of(spell)
	var target: Node2D = null
	if target_kind == "enemy":
		target = get_enemy_at_position(world_position)
		if target == null:
			target = player.get_nearest_enemy(world_position, 220.0)
		if target == null:
			_flash_cast_error("Нет врага под курсором — укажите противника.")
			return
	elif target_kind == "point":
		var under := get_enemy_at_position(world_position)
		if under != null:
			world_position = under.global_position
	else:
		target = _ally_at_position(world_position)
		if target == null:
			# Аналогично книгам: щит/бафф накладывается на героя по умолчанию
			if SpellDB.kind_of(spell) == "buff":
				target = player
			else:
				_flash_cast_error("Укажите героя или союзника для этого заклинания.")
				return

	# Дальность из базы (раньше не проверялась вообще)
	var max_range := SpellDB.range_of(spell)
	if max_range > 0.0 and target_kind != "self" \
			and player.cast_origin().distance_to(world_position) > max_range:
		_flash_cast_error("Слишком далеко: «%s» достаёт на %d м." % [spell, int(max_range / 32.0)])
		return

	# Предмет списывается ТОЛЬКО если эффект применился: раньше remove_item
	# вызывался безусловно, и свитки «Scroll Fire Wall» просто исчезали.
	var applied := false
	if target != null:
		applied = player.apply_scroll_to_target(spell, target)
	else:
		applied = player.apply_scroll_to_target_point(spell, world_position)
	if not applied:
		_flash_cast_error("Заклинание не сработало — предмет не потрачен.")
		return
	player.remove_item(str(Game.pending_scroll.get("item_key", "")))
	Game.pending_scroll = {}
	if ui != null and ui.has_method("_finish_scroll_targeting"):
		ui._finish_scroll_targeting()


func _flash_cast_error(msg: String) -> void:
	print(msg)
	if ui != null and ui.has_method("_flash_targeting_error"):
		ui._flash_targeting_error(msg)

## Заклинание из книги: клик выбрал цель. Атака/область/стена — по врагу или
## точке, лечение/защита/бафф — по герою или союзнику. Мана/заряд списываются
## только при успешном касте.
func _resolve_spell_click(world_position: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var name := str(Game.pending_spell.get("name", ""))
	if name == "":
		return
	# Защита: не кастовать в тот же кадр, что и выбор магии из книги
	if Engine.get_process_frames() == Game._spell_targeting_frame:
		return
	var target_kind := SpellDB.target_of(name)
	var target_position := world_position
	var target_node: Node2D = null
	var ok := true
	var enemy := get_enemy_at_position(world_position)

	match target_kind:
		"enemy":
			if enemy != null:
				target_node = enemy
				target_position = enemy.global_position
			else:
				enemy = player.get_nearest_enemy(world_position, 220.0)
				if enemy == null:
					ok = false
				else:
					target_node = enemy
					target_position = enemy.global_position
		"point":
			if enemy != null:
				target_position = enemy.global_position
		"ally":
			var ally := _ally_at_position(world_position)
			if ally == null:
				# Щиты/баффи удобно накладывать на себя, не целясь точно
				if SpellDB.kind_of(name) == "buff":
					ally = player
				else:
					ok = false
			if ally != null:
				target_position = ally.global_position
				target_node = ally
		_:
			target_node = player
			target_position = player.global_position

	if not ok:
		var msg := "Укажите ВРАГА для «%s» (ПКМ/ESC — отмена)." % name \
			if target_kind == "enemy" else "Укажите ГЕРОЯ или СОЮЗНИКА для «%s»." % name
		print(msg)
		if ui != null and ui.has_method("_flash_targeting_error"):
			ui._flash_targeting_error(msg)
		return

	# Дальность из базы: раньше поле range вообще не читалось, поэтому можно
	# было кастовать через полкарты (включая телепорт).
	var max_range := SpellDB.range_of(name)
	if max_range > 0.0 and target_kind != "self":
		var origin: Vector2 = player.cast_origin()
		if origin.distance_to(target_position) > max_range:
			var rmsg := "Слишком далеко: «%s» достаёт на %d м." % [name, int(max_range / 32.0)]
			if ui != null and ui.has_method("_flash_targeting_error"):
				ui._flash_targeting_error(rmsg)
			return

	if not player.cast_spell(name, target_position, target_node):
		print("Не удалось кастовать: " + name)
	if ui != null and ui.has_method("_finish_spell_targeting"):
		ui._finish_spell_targeting()

## Цель-союзник под курсором: сам герой, мирный НПЦ или наёмник.
func _ally_at_position(world_position: Vector2) -> Node2D:
	if is_instance_valid(player) and unit_hit_rect(player).grow(8.0).has_point(world_position):
		return player
	for n in npcs:
		if is_instance_valid(n) and unit_hit_rect(n).grow(8.0).has_point(world_position):
			return n
	for m in party:
		if is_instance_valid(m) and unit_hit_rect(m).grow(8.0).has_point(world_position):
			return m
	return null

## Отмена прицеливания (свиток или заклинание книги). НЕ тратится.
func cancel_targeting() -> void:
	Game.pending_scroll = {}
	Game.pending_spell = {}
	Game._spell_targeting_frame = -1
	if ui != null and ui.has_method("_cancel_targeting"):
		ui._cancel_targeting()

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

## Добавить травму камере (экранная тряска). amount: 0.0–1.0.
static func camera_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(delta):
	if is_paused:
		return
	if is_instance_valid(player) and camera:
		camera.position = camera.position.lerp(player.camera_focus(), 5.0 * delta)
		# Camera shake (trauma-based)
		if _trauma > 0.0:
			_trauma = maxf(_trauma - 1.2 * delta, 0.0)
			var shake := _trauma * _trauma
			_trauma_t += delta * 30.0
			camera.offset = Vector2(
				8.0 * shake * sin(_trauma_t * 1.7),
				6.0 * shake * sin(_trauma_t * 2.3)
			)
		else:
			camera.offset = Vector2.ZERO
	if is_instance_valid(ui) and is_instance_valid(player):
		ui.update_ui(player, delta)
	
	# Регенерация героя: HP и мана по статам, а не жёсткая «+1 мана/с».
	# Раньше мана качалась 1/с независимо от Spirit, а HP не регенерировался.
	_regen_hero(delta)
	
	# Обработка режимов действий
	_process_action_mode()
	_update_target_ring()
	_process_pending_building()
	_process_pending_herb()
	Game.tick_shields(delta)
	StatusEffects.tick(delta)
	_check_portal()


## Регенерация героя раз в секунду: HP = 1 + Body/5, мана = 1 + Spirit/10.
func _regen_hero(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if player.state == "dead" or player.state == "decay":
		return
	mana_regen_accum += delta
	if mana_regen_accum < 1.0:
		return
	mana_regen_accum -= 1.0
	if player.current_hp < player.max_hp:
		player.heal_amount(player._calc_hp_regen())
	if player.has_mana and player.current_mana < player.max_mana:
		var gain: int = player._calc_mana_regen()
		player.current_mana = mini(player.max_mana, player.current_mana + gain)
		DamageNumber.show_at(player.global_position, gain, "mana")

func _check_portal() -> void:
	# Проверка: игрок на клетке портала?
	if not is_instance_valid(player) or not is_instance_valid(alm_map):
		return
	var cells: Array = alm_map.call("get_portal_cells")
	if cells.is_empty():
		return
	var TILE: int = 32
	var cell := Vector2i(int(player.global_position.x) / TILE, int(player.global_position.y) / TILE)
	for pc in cells:
		if cell == pc:
			_on_portal_enter()
			return

func _on_portal_enter() -> void:
	# Placeholder: телепорт обратно на спавн
	print("TELEPORT! → spawn")
	if is_instance_valid(alm_map) and is_instance_valid(player):
		var sp: Vector2 = alm_map.call("get_spawn_pos")
		player.global_position = sp
		player.reset_physics_interpolation()

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
