extends CharacterBody2D
class_name Player

# Первичные характеристики (оригинальная система Allods 2)
@export var body: int = 10
@export var mind: int = 10
@export var agility: int = 10
@export var spirit: int = 10
# Навыки оружия и магии (0-100, пока базовые)
@export var blade_skill: int = 5
@export var axe_skill: int = 0
@export var bludgeon_skill: int = 0
@export var pike_skill: int = 0
@export var shooting_skill: int = 0
@export var fire_skill: int = 5
@export var water_skill: int = 5
@export var air_skill: int = 5
@export var earth_skill: int = 5
@export var astral_skill: int = 5

var max_hp: int = 100
var max_mana: int = 50
var current_hp: int
var current_mana: int
var state: String = "idle"
var attack_target: Node2D = null
var attack_cooldown: float = 0.0
var _impact_timer := -1.0            # отсчёт до кадра удара (замах); <0 = нет удара в полёте
var _pending_attack_damage := 0      # урон текущего замаха (применяется в момент удара)
var move_speed: float = 120.0
var _path: Array = []        # маршрут (мировые точки — центры клеток), без «льда»
var _stuck_frames := 0
var _repath_timer := 0.0

# --- Экономика (P0): золото и склад владений ---
var gold: int = 20
var inventory: Array = []   # ключи предметов item_db ("Common Iron Long Sword", "Potion ...")

# --- Опыт по навыкам (как у разработчиков UnityAllods/ROM2): ---
# навык растёт от опыта: exp = (1.1^skill - 1) * 1000; skill = log_1.1(exp/1000 + 1).
# Опыт даётся за удары оружием и применение магии (по сфере/навыку).
const SKILL_NAMES := [
	"blade", "axe", "bludgeon", "pike", "shooting",
	"fire", "water", "air", "earth", "astral",
]
var experience := {}        # name -> очки опыта по навыку
const UNIT_EXP_BASE := 100  # множитель опыта цели (Template.Experience у разработчиков)

## Очки опыта, соответствующие уровню навыка (обратная формула).
static func skill_to_exp(skill: int) -> int:
	return int((pow(1.1, float(skill)) - 1.0) * 1000.0)

## Уровень навыка из очков опыта: floor(log_1.1(exp/1000 + 1)).
static func exp_to_skill(e: int) -> int:
	if e <= 0:
		return 0
	return int(floor(log(float(e) / 1000.0 + 1.0) / log(1.1)))

## Суммарный опыт героя по всем навыкам (XP в панели).
func total_experience() -> int:
	var t := 0
	for name in SKILL_NAMES:
		t += int(experience.get(name, 0))
	return t

## Текущее значение навыка по имени (blade/axe/.../astral) — для урона/UI.
func skill_value(name: String) -> int:
	match name:
		"blade": return blade_skill
		"axe": return axe_skill
		"bludgeon": return bludgeon_skill
		"pike": return pike_skill
		"shooting": return shooting_skill
		"fire": return fire_skill
		"water": return water_skill
		"air": return air_skill
		"earth": return earth_skill
		"astral": return astral_skill
	return 0

func _set_skill_value(name: String, v: int) -> void:
	match name:
		"blade": blade_skill = v
		"axe": axe_skill = v
		"bludgeon": bludgeon_skill = v
		"pike": pike_skill = v
		"shooting": shooting_skill = v
		"fire": fire_skill = v
		"water": water_skill = v
		"air": air_skill = v
		"earth": earth_skill = v
		"astral": astral_skill = v

## Начислить опыт навыку; если уровень из опыта вырос — поднять навык.
func gain_skill_exp(skill_name: String, amount: int) -> void:
	if not SKILL_NAMES.has(skill_name) or amount <= 0:
		return
	var e := int(experience.get(skill_name, 0)) + amount
	experience[skill_name] = e
	var lvl := exp_to_skill(e)
	if lvl > skill_value(skill_name):
		_set_skill_value(skill_name, lvl)
		print("Навык %s повышен до %d!" % [skill_name, lvl])

## Навык из нанесённого урона (по типу оружия героя). "" — опыт не идёт.
func _weapon_skill_name() -> String:
	match weapon:
		"sword": return "blade"
		"axe": return "axe"
		"club": return "bludgeon"
		"pike": return "pike"
		"bow", "xbow": return "shooting"
	return ""

## Опыт за попадание: как у разработчиков MapUnit:
## exp = урон/HPмакс * Experience юнита * (1 + Mind/100); при убийстве x2.
func _apply_attack_experience(target: Node2D, damage: int) -> void:
	var ws := _weapon_skill_name()
	if ws == "" or not is_instance_valid(target):
		return
	var target_hp := 50
	if "max_hp" in target:
		target_hp = maxi(int(target.max_hp), 1)
	var f := float(damage) / float(target_hp) * UNIT_EXP_BASE * (1.0 + mind / 100.0)
	var target_cur := 0
	if "current_hp" in target:
		target_cur = int(target.current_hp)
	if target_cur <= damage:
		f *= 2.0  # убийство — вдвое больше опыта
	gain_skill_exp(ws, int(f))

## Опыт за применение магии (по сфере заклинания).
func _apply_spell_experience(sphere: String) -> void:
	var ws := sphere.to_lower()
	if not SKILL_NAMES.has(ws):
		return
	# база ~20 * (1 + Mind/100), как «опыт юнита» у заклинаний
	gain_skill_exp(ws, int(20.0 * (1.0 + mind / 100.0)))

## --- Нагрузка: вес предметов в инвентаре, перегруз снижает скорость ---
func get_load() -> float:
	var w := 0.0
	for key in inventory:
		var it := ItemDB.find(str(key))
		w += float(it.get("weight", 0.0))
	return w

## Ёмкость до перегруза (Body даёт силу нести больше).
func load_capacity() -> float:
	return 30.0 + body * 10.0

## Множитель скорости от нагрузки: до ёмкости — 1.0, перегруз — до 0.5.
func _load_penalty() -> float:
	var cap := load_capacity()
	if cap <= 0.0:
		return 1.0
	var load := get_load()
	if load <= cap:
		return 1.0
	return clampf(cap / load, 0.5, 1.0)

## Магия героя: выученные заклинания (книги) и заряды свитков.
## known_spells: "Fire_Ball" -> {"charges": -1} — выучено навсегда (маг, из книги);
## "Fire_Arrow" -> {"charges": 2} — заряды свитков (каст тратит заряд, свиток
## в итоге исчезает). Воины не имеют маны (max_mana = 0) — только свитки.
var known_spells: Dictionary = {}
var sphere_books: Dictionary = {}   # "Fire" -> true (книга стихии изучена магом)
var cast_cooldowns: Dictionary = {} # имя -> оставшееся время кд
var has_mana: bool = true
var health_bar: HealthBar
var alm_map = null   # CustomMap или AlmMap из группы "alm_map"

# --- Экипировка героя (определяет набор анимаций) ---
var armor_kind: String = "heavy"   # "heavy" -> heroes/, "light" -> heroes_l/
var weapon: String = "unarmed"     # по умолчанию без оружия — отлаживаем его анимацию
var two_handed: bool = false
var has_shield: bool = false
var _anim: UnitAnim = null

func _ready():
	_apply_hero_choice()
	# Экономика (P0): стартовое золото и склад владений
	gold = 20
	inventory.clear()
	_grant_starter_set()
	# Только маги имеют ману и читают книги магии; воины — свитки (заряды).
	has_mana = Game.hero_class == "mage"
	max_hp = _calc_max_hp()
	max_mana = _calc_max_mana()
	current_hp = max_hp
	current_mana = max_mana
	move_speed = _calc_speed()
	alm_map = get_tree().get_first_node_in_group("alm_map")
	Game.configure_unit_body(self)
	_ensure_sprite()
	_create_health_bar()
	_init_experience()

## Начальный опыт из стартовых навыков (skill -> exp, как у разработчиков:
## exp = (1.1^skill - 1) * 1000). Дальше навык растёт от получаемого опыта.
func _init_experience() -> void:
	for name in SKILL_NAMES:
		var lvl := skill_value(name)
		if lvl > 0:
			experience[name] = skill_to_exp(lvl)

## Стартовая магия отключена: маг начинает БЕЗ заклинаний в панели магии.
## На старте он получает в склад книгу простейшего заклинания выбранной школы
## (см. _grant_starter_set) и учит её двойным кликом по ячейке склада.

## Применить выбор персонажа с экрана старта (character_select): характеристики,
## стартовая экипировка. Без выбора (запуск main.tscn напрямую) — значения по умолчанию.
func _apply_hero_choice() -> void:
	var st: Dictionary = Game.hero_stats
	if st.is_empty():
		return
	body = int(st.get("body", body))
	agility = int(st.get("agility", agility))
	mind = int(st.get("mind", mind))
	spirit = int(st.get("spirit", spirit))
	blade_skill = int(st.get("blade", blade_skill))
	axe_skill = int(st.get("axe", axe_skill))
	bludgeon_skill = int(st.get("bludgeon", bludgeon_skill))
	pike_skill = int(st.get("pike", pike_skill))
	shooting_skill = int(st.get("shooting", shooting_skill))
	fire_skill = int(st.get("fire", fire_skill))
	water_skill = int(st.get("water", water_skill))
	air_skill = int(st.get("air", air_skill))
	earth_skill = int(st.get("earth", earth_skill))
	astral_skill = int(st.get("astral", astral_skill))
	weapon = str(st.get("weapon", weapon))
	has_shield = bool(st.get("shield", false))
	armor_kind = str(st.get("armor", armor_kind))
	# Маг: стартовые заклинания уже в abilities (fireball/heal/lightning)

## Стартовое снаряжение по классу героя (в склад — можно одеть/продать сразу).
func _grant_starter_set() -> void:
	inventory.append("Common Iron Long Sword" if Game.hero_class != "mage" else "Common Wood Staff")
	if Game.hero_stats.get("shield", false):
		inventory.append("Common Iron Buckler")
	inventory.append("Common Leather Mail")
	# Маг на старте получает книгу простейшего заклинания выбранной школы
	# (учится двойным кликом по ячейке склада; книга расходуется).
	if Game.hero_class == "mage" and Game.hero_start_book != "":
		inventory.append(Game.hero_start_book)
	# ВРЕМЕННО (отладка магии): маг сразу знает все 24 книжные магии —
	# панель заливается иконками, кастуется всё без кликов по книгам.
	if Game.debug_magic and Game.hero_class == "mage":
		for spell in SpellDB.BOOK_SPELLS:
			known_spells[str(spell)] = {"charges": -1}
	for i in range(3):
		inventory.append("Potion Medium Healing")
	inventory.append("Potion Mana Regeneration")

## --- Склад владений ---

func has_item(key: String) -> bool:
	return inventory.has(key)

func add_item(key: String) -> void:
	if key != "":
		inventory.append(key)
		_recall_speed()

## Убрать предмет из склада; true — если он там был.
func remove_item(key: String) -> bool:
	var i := inventory.find(key)
	if i < 0:
		return false
	inventory.remove_at(i)
	_recall_speed()
	return true

## Пересчитать скорость после изменения веса (нагрузки).
func _recall_speed() -> void:
	move_speed = _calc_speed()

# --- Производные характеристики (связи из оригинального main.txt) ---
func _calc_max_hp() -> int:
	return 20 + body * 8          # Body -> здоровье; body=10 -> 100

func _calc_max_mana() -> int:
	if not has_mana:
		return 0                  # воины не имеют маны вовсе
	return 10 + spirit * 4        # Spirit -> мана (по манифесту); spirit=10 -> 50

func _calc_hp_regen() -> int:
	return 1 + body / 5           # реген HP от Body

func _calc_mana_regen() -> int:
	return 1 + spirit / 10        # реген маны от Spirit

func _calc_speed() -> float:
	# Скорость героя по формуле оригинала (UnityAllods MapHuman):
	# Speed = min(Reaction/5 + 12, 255); Реакция ≈ 2·Ловкость (производная).
	# В наших пикселях: base × 7.5 (при agility=10 — те же 120 px/с, что и раньше).
	var reaction := 2 * agility
	var base := clampf(float(reaction) / 5.0 + 12.0, 12.0, 255.0)
	var speed := base * 7.5
	# Нагрузка (вес предметов в инвентаре): перегруз замедляет до 0.5x
	speed *= _load_penalty()
	return speed

func get_damage_min() -> int:
	return body / 2 + blade_skill / 10     # Body + навык меча -> урон

func get_damage_max() -> int:
	return body + blade_skill / 5 + 5

func get_attack() -> int:
	return agility / 2 + blade_skill / 10  # Agility -> точность

func get_defense() -> int:
	return agility / 2 + body / 4          # Agility -> уклонение/защита

func get_absorption() -> int:
	return body / 4

func get_sight() -> int:
	return 6 + agility / 3                 # Agility -> обзор (по манифесту)

## Урон магии: Mind -> сила заклинаний (добавочный множитель).
func get_magic_power() -> int:
	return mind / 2

func get_protection_fire() -> int: return spirit / 2 + fire_skill / 10
func get_protection_water() -> int: return spirit / 2 + water_skill / 10
func get_protection_air() -> int: return spirit / 2 + air_skill / 10
func get_protection_earth() -> int: return spirit / 2 + earth_skill / 10
func get_protection_astral() -> int: return spirit / 4  # астрал почти не защищается

## Текущий набор анимаций по экипировке ("heroes/swordsman_").
func anim_set_name() -> String:
	var top := "heroes" if armor_kind == "heavy" else "heroes_l"
	var base := weapon
	match weapon:
		"unarmed": base = "unarmed"
		"sword":
			base = "swordsman2h" if two_handed else ("swordsman_" if has_shield else "swordsman")
		"axe":
			base = "axeman2h" if two_handed else ("axeman_" if has_shield else "axeman")
		"club":
			base = "clubman_" if has_shield else "clubman"
		"pike":
			base = "pikeman_" if has_shield else "pikeman"
		"bow": base = "archer"
		"xbow": base = "xbowman"
		"staff": base = "mage_st"
		"magic": base = "mage"
	if has_shield and base == "unarmed":
		base = "unarmed_"
	return "%s/%s" % [top, base]

## Пересоздать анимацию после смены экипировки.
func refresh_animation() -> void:
	if _anim == null:
		return
	var set := anim_set_name()
	_anim.setup(set)
	_anim.play(UnitAnim.Anim.MOVE, true)
	move_speed = _calc_speed()   # скорость обновляется вместе с экипировкой

## Множитель скорости с учётом высоты: подъём замедляет, спуск/равнина — норма.
## Дороги (tile4) — быстрее травы.
func _height_speed_factor(target_pos: Vector2) -> float:
	if not alm_map:
		return 1.0
	var cur_h: float = float(alm_map.call("height_at_world", global_position))
	var tgt_h: float = float(alm_map.call("height_at_world", target_pos))
	var f := 1.0
	var rise := maxf(0.0, tgt_h - cur_h)
	var penalty := rise * 0.08
	if rise > 0.0 and alm_map.has_method("cell_type_at"):
		var cell := Vector2i(int(target_pos.x) / 32, int(target_pos.y) / 32)
		if int(alm_map.call("cell_type_at", cell.x, cell.y)) == 1:
			penalty = rise * 0.16
	f = maxf(0.55, 1.0 - penalty)
	if alm_map.has_method("speed_factor_at_world"):
		f *= float(alm_map.call("speed_factor_at_world", target_pos))
	return f

## Можно ли двигаться в точку: проходимость (вода/барьер) + границы карты.
## Исключение: выход ИЗ непроходимой клетки (герой «в дереве») разрешён — шаг
## внутри своей клетки допускается, чтобы дойти до границы и выйти наружу.
func _can_move_to(pos: Vector2) -> bool:
	if not alm_map:
		return true
	if alm_map.is_walkable_world(pos):
		return alm_map.is_within_bounds(pos)
	var cur := Vector2i(int(global_position.x) / 32, int(global_position.y) / 32)
	var nxt := Vector2i(int(pos.x) / 32, int(pos.y) / 32)
	return nxt == cur

# --- Физика движения тела (плавный разгон/торможение, без «льда») ---
const MOVE_ACCEL := 1100.0   # px/s² — разгон до 120 px/s за ~0.11 с
const MOVE_DECEL := 1800.0   # px/s² — тормоз с 120 px/s за ~0.07 с

## Движение с проверкой проходимости: если цель непроходима — мягкий стоп
## (без «скольжения вдоль стен», которое выглядело как лёд).
func _move_checked(direction: Vector2, speed: float, delta: float):
	direction = Game.movement_direction(self, direction)
	var wanted := direction * speed
	var next := global_position + wanted * delta
	if _can_move_to(next):
		velocity = velocity.move_toward(wanted, MOVE_ACCEL * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, MOVE_DECEL * delta)

func _create_health_bar():
	health_bar = preload("res://scripts/health_bar.gd").new()
	health_bar.max_hp = max_hp
	health_bar.max_mana = max_mana
	health_bar.has_mana = has_mana
	add_child(health_bar)

func _ensure_sprite():
	var old_sprite = get_node_or_null("Sprite")
	if old_sprite:
		old_sprite.queue_free()

	_anim = UnitAnim.new()
	_anim.name = "UnitAnim"
	add_child(_anim)
	refresh_animation()

func _physics_process(delta):
	if Game.is_paused:
		return

	attack_cooldown = max(0, attack_cooldown - delta)
	# Кулдауны заклинаний
	for spell in cast_cooldowns:
		cast_cooldowns[spell] = max(0.0, float(cast_cooldowns[spell]) - delta)

	# Обновляем бар здоровья
	if health_bar:
		health_bar.update_bars(current_hp, current_mana)

	match state:
		"idle":
			velocity = Vector2.ZERO
			if _anim:
				_anim.play(UnitAnim.Anim.IDLE)
		"move":
			move_to_target(delta)
			if _anim:
				_anim.play(UnitAnim.Anim.MOVE)
				_anim.set_direction_vec(velocity)
				# Темп шагов — по КОМАНДНОЙ скорости (разгон/торможение не «перекачивают» каденс)
				_anim.speed_scale = clampf(_height_speed_factor(Game.player_target) / 0.85, 0.5, 2.0)
				_anim.advance(delta)
		"chase":
			chase_target(delta)
			if _anim:
				_anim.play(UnitAnim.Anim.MOVE)
				_anim.set_direction_vec(velocity)
				var walk_f := 1.0
				if attack_target and is_instance_valid(attack_target):
					walk_f = _height_speed_factor(attack_target.global_position)
				_anim.speed_scale = clampf(walk_f / 0.85, 0.5, 2.0)
				_anim.advance(delta)
		"attack":
			attack_enemy(delta)
			if _anim:
				_anim.play(UnitAnim.Anim.ATTACK)
				_anim.speed_scale = 1.0
				_anim.advance(delta)
		"dead":
			velocity = Vector2.ZERO
			if _anim:
				# Падение: DYING один раз, затем разложение DECAY (1-2-3), потом пауза
				_anim.play(UnitAnim.Anim.DYING)
				if _anim.advance(delta):
					if UnitDB.decay_phases(anim_set_name()) > 0:
						state = "decay"
						_anim.play(UnitAnim.Anim.DECAY)
					else:
						get_tree().paused = true
		"decay":
			velocity = Vector2.ZERO
			if _anim:
				_anim.play(UnitAnim.Anim.DECAY)
				if _anim.advance(delta):
					get_tree().paused = true

	move_and_slide()
	_apply_relief_stand()

## Стоять на рельефе: поднять спрайт на высоту клетки (как в Allods16).
func _apply_relief_stand() -> void:
	if _anim == null:
		return
	var h := 0.0
	if alm_map != null and alm_map.has_method("relief_at_world"):
		h = float(alm_map.call("relief_at_world", global_position))
	_anim.position = Vector2(_anim.position.x, -h)
	if health_bar:
		health_bar.position.y = -(h + _anim.sprite_height() + 6.0)  # над головой

## Точка фокуса камеры: визуальный центр персонажа (середина фигурки), а не его
## «ноги» (global_position). Спрайт рисуется от подошв вверх — если центрировать
## на global_position, герой всегда будет выше середины экрана.
func camera_focus() -> Vector2:
	if _anim == null:
		return global_position
	return global_position + Vector2(0, _anim.position.y - _anim.visual_height() * 0.5)

## Точка старта снаряда заклинания: чуть выше середины фигурки (на уровне рук/
## груди). Не «ноги» — иначе снаряд вылетает из-под ступней.
func cast_origin() -> Vector2:
	if _anim == null:
		return global_position
	return global_position + Vector2(0, _anim.position.y - _anim.visual_height() * 0.62)

func move_to_target(delta):
	if _path.size() > 0:
		_follow_path(delta)
		if _path.is_empty():
			# Маршрут пройден — цель достигнута (не скользим дальше)
			state = "idle"
			velocity = Vector2.ZERO
		return
	if Game.player_target.distance_to(global_position) > 5.0:
		state = "idle"
		velocity = Vector2.ZERO
		Game.player_target = global_position
	else:
		state = "idle"
		velocity = Vector2.ZERO

## Начать движение по маршруту (центры клеток из alm_map.find_path).
func begin_path(path: Array) -> void:
	_path = path
	_stuck_frames = 0

## Полная остановка (используется при входе в здание/паузах).
func stop_movement() -> void:
	state = "idle"
	velocity = Vector2.ZERO
	_path.clear()
	Game.player_target = global_position

## Идти по маршруту: к очередной точке; при упоре 12 кадров — остановиться.
func _follow_path(delta: float) -> void:
	if _path.is_empty():
		return
	var wp: Vector2 = _path[0]
	if global_position.distance_to(wp) <= 6.0:
		_path.pop_front()
		if _path.is_empty():
			return
		wp = _path[0]
	var dir := (wp - global_position).normalized()
	var speed_factor := _height_speed_factor(wp)
	_move_checked(dir, move_speed * speed_factor, delta)
	if velocity.length_squared() < 1.0:
		_stuck_frames += 1
		if _stuck_frames > 20:
			_path.clear()
			state = "idle"
	else:
		_stuck_frames = 0

func chase_target(delta):
	if attack_target and is_instance_valid(attack_target):
		# Цель умерла (падение/разложение) — прекращаем погоню
		if attack_target.is_in_group("enemy") and not Game.enemies.has(attack_target):
			attack_target = null
			state = "idle"
			velocity = Vector2.ZERO
			return
		# Дистанция боя — между корпусами (хит-боксами), а не точками «пола»
		var range_to_enemy := Game.units_range(self, attack_target)
		if range_to_enemy <= Game.ATTACK_RANGE:
			_path.clear()
			state = "attack"
			velocity = Vector2.ZERO
			return
		# Путь к врагу (обход препятствий), перепланировка раз в 0.6 с
		if _path.is_empty():
			_repath_timer -= delta
			if _repath_timer <= 0.0:
				_repath_timer = 0.6
				if alm_map != null and alm_map.has_method("find_path"):
					begin_path(alm_map.find_path(global_position, attack_target.global_position))
		if _path.size() > 0:
			_follow_path(delta)
		else:
			var direction = (attack_target.global_position - global_position).normalized()
			var speed_factor = _height_speed_factor(attack_target.global_position)
			_move_checked(direction, move_speed * speed_factor, delta)
	else:
		state = "idle"
		velocity = Vector2.ZERO

func attack_enemy(delta):
	if attack_target and is_instance_valid(attack_target):
		# Враг убежал из радиуса — догоняем, а не бьём в пустоту
		if Game.units_range(self, attack_target) > Game.ATTACK_RANGE + 12.0:
			state = "chase"
			_impact_timer = -1.0
			return
		# Цель мертва (труп/разложение) — прекращаем махать по трупу
		if not Game.enemies.has(attack_target):
			attack_target = null
			state = "idle"
			velocity = Vector2.ZERO
			_impact_timer = -1.0
			return
		if attack_cooldown <= 0.0 and _impact_timer < 0.0:
			var damage = get_damage_min() + randi() % (get_damage_max() - get_damage_min() + 1)
			# МАГ с посохом: удар — это сфера (мгновенная магия выбранной стихии),
			# без задержки замаха — как и раньше, срабатывает сразу.
			if Game.hero_class == "mage" and weapon == "staff":
				var sphere := _active_sphere()
				if Game.is_miss(self, attack_target):
					print("Промах! Шанс был %d%%." % Game.hit_chance(Game.unit_attack(self), Game.unit_defense(attack_target)))
				else:
					Game.deal_damage(attack_target, magic_damage(damage, sphere), "magic", sphere, self)
					_sound_weapon_attack()
				_apply_spell_experience(sphere)
				attack_cooldown = Game.ATTACK_COOLDOWN
				return
			# Старт замаха: урон и звук — в момент удара (_impact_timer),
			# чтобы контакт ощущался по анимации, а не в начале движения.
			print("Атакуем! Урон: ", damage)
			_pending_attack_damage = damage
			_impact_timer = UnitDB.attack_delay(anim_set_name())
			attack_cooldown = Game.ATTACK_COOLDOWN
		elif _impact_timer >= 0.0:
			_impact_timer -= delta
			if _impact_timer < 0.0:
				_impact_timer = -1.0
				# Единая точка: промах по hit_chance(атака, защита), далее Game.deal_damage
				# (поглощение бронёй → take_damage → щит → HP).
				if Game.is_miss(self, attack_target):
					print("Промах! Шанс был %d%%." % Game.hit_chance(Game.unit_attack(self), Game.unit_defense(attack_target)))
				else:
					Game.deal_damage(attack_target, _pending_attack_damage, "physical", "", self)
					_sound_weapon_attack()
				_apply_attack_experience(attack_target, _pending_attack_damage)
	else:
		state = "idle"
		_impact_timer = -1.0

## Звук удара оружием героя (Sfx100-160: units\sword|axe|club|bow|cbow|pike|sling).
func _sound_weapon_attack() -> void:
	var id := 0
	match weapon:
		"sword": id = 100
		"axe": id = 110
		"club": id = 120
		"bow": id = 130
		"xbow": id = 140
		"pike": id = 150
		"staff": id = 160
		_:
			var s := UnitDB.unit_sound(anim_set_name())
			id = SoundDB.sound_at(s, 0)
	SoundDB.play(id)

## Магический урон: база + Mind + навык сферы (как в Allods2).
## Урон растёт с Mind (разумом) и навыком соответствующей сферы магии.
func magic_damage(base: int, sphere: String) -> int:
	var skill := 0
	match sphere:
		"Fire": skill = fire_skill
		"Water": skill = water_skill
		"Air": skill = air_skill
		"Earth": skill = earth_skill
		"Astral": skill = astral_skill
	return base + get_magic_power() + skill * 2 / 5

## Активная сфера мага (для удара посохом/панели сфер): сфера стартовой книги,
## иначе первая уже изученная. Fallback — Fire (на старте всегда есть книга сферы).
func _active_sphere() -> String:
	if Game.hero_start_book != "":
		var b := SpellDB.sphere_of_book(Game.hero_start_book)
		if b != "":
			return b
	for sp in ["Fire", "Water", "Air", "Earth", "Astral"]:
		if sphere_books.get(sp, false):
			return sp
	return "Fire"

## Навык сферы (для UI/урона): 0-100.
func sphere_skill(sphere: String) -> int:
	match sphere:
		"Fire": return fire_skill
		"Water": return water_skill
		"Air": return air_skill
		"Earth": return earth_skill
		"Astral": return astral_skill
	return 0

## Заклинания героя (для книги заклинаний): выученные + свитки с зарядами.
func known_spell_list() -> Array:
	var out: Array = []
	for name in known_spells:
		out.append(name)
	out.sort()
	return out

## Атакующие заклинания (для быстрых клавиш) в порядке базы.
func _attack_spells() -> Array:
	var out: Array = []
	for name in known_spell_list():
		var kind := SpellDB.kind_of(name)
		if kind in ["attack", "area"]:
			out.append(name)
	return out

## Есть ли у героя заклинание (книга/свиток) и можно ли кастовать сейчас.
func has_spell(name: String) -> bool:
	return known_spells.has(name)

## Заряды заклинания: -1 = выучено навсегда (маг, из книги), 0 = нет, N = свитки.
func spell_charges(name: String) -> int:
	if not known_spells.has(name):
		return 0
	return int(known_spells[name].get("charges", 0))

## Стоимость каста: маг платит ману, воин — заряд свитка.
func can_cast(name: String) -> bool:
	if not known_spells.has(name):
		return false
	if float(cast_cooldowns.get(name, 0.0)) > 0.0:
		return false
	var charges := spell_charges(name)
	if charges > 0:
		return true       # есть заряд свитка
	if charges == -1 and has_mana:
		return current_mana >= SpellDB.mana_cost(name)   # маг за ману
	return false

## Использовать заклинание по имени. Возвращает true, если кастован.
## Панель/быстрый вызов: маг платит ману, свитковая ячейка — заряд.
## target_node — выбранная цель (для лечения/защиты); иначе герой.
func cast_spell(name: String, target_position: Vector2, target_node: Node2D = null) -> bool:
	if not can_cast(name):
		return false
	var spell: Dictionary = SpellDB.get_spell(name)
	if spell.is_empty():
		return false
	# Стоимость: заряд свитка тратится; когда заряды кончаются, свитковое
	# заклинание навсегда исчезает из панели магии (маг платит ману).
	var charges := spell_charges(name)
	if charges > 0:
		var left := charges - 1
		if left <= 0:
			known_spells.erase(name)   # свиток израсходован — ячейка гаснет
		else:
			known_spells[name]["charges"] = left
	elif has_mana:
		current_mana = maxi(0, current_mana - SpellDB.mana_cost(name))
	cast_cooldowns[name] = 0.8  # универсальный КД ~0.8 с

	_cast_spell_effect(name, spell, target_position, target_node if is_instance_valid(target_node) else self)
	_apply_spell_experience(str(spell.get("sphere", "")))
	return true

## Свиток мага, прочитанный из склада: применить заклинание 1 РАЗ по выбранной
## цели (враг / себя / союзник). НЕ тратит ману и НЕ появляется в панели магии.
func apply_scroll_to_target(name: String, target: Node2D) -> void:
	var spell: Dictionary = SpellDB.get_spell(name)
	if spell.is_empty():
		return
	_cast_spell_effect(name, spell, target.global_position, target)
	_apply_spell_experience(str(spell.get("sphere", "")))

## Звук заклинания (magic\*.wav): из поля sound базы, по сфере на запас.
func _play_spell_sound(name: String, sphere: String) -> void:
	var sid := SpellDB.sound_of(name)
	if sid <= 0:
		match sphere:
			"Fire": sid = 512    # fireball
			"Water": sid = 518   # icemissile
			"Air": sid = 528     # lightning
			"Earth": sid = 546   # pearth
			"Astral": sid = 556  # heal
	if sid > 0:
		SoundDB.play(sid)

## Общий порядок применения заклинания (книга на панели ИЛИ свиток с прицелом).
## target_node — выбранная цель (для лечения/защиты); при панельном касте — герой.
func _cast_spell_effect(name: String, spell: Dictionary, target_position: Vector2, target_node: Node2D) -> void:
	var sphere := str(spell.get("sphere", ""))
	var kind := str(spell.get("kind", "buff"))
	var dmg := int(spell.get("damage", 0))
	var area := float(spell.get("area", 0))
	var range_f := float(spell.get("range", 0))
	_play_spell_sound(name, sphere)

	match kind:
		"attack", "area":
			_fire_spell_projectile(name, sphere, dmg, area, range_f, target_position)
		"heal":
			_heal_target(target_node, maxi(1, -dmg + mind / 5))
		"buff":
			_apply_buff_target(target_node, sphere, name)
		"wall":
			_create_wall(target_position)
		"self":
			match name:
				"Teleport": _teleport_to(target_position)
				"Light": _cast_light()
				"Summon": _cast_summon()
				_: _apply_buff_target(target_node, sphere, name)   # напр. Shield

## Снаряд заклинания (с анимацией из assets/projectiles/<folder>/).
## Если папки снаряда нет (эффект отсутствует — Haste/Invisibility/Summon...),
## применяем заклинание мгновенно без летящего снаряда.
func _fire_spell_projectile(name: String, sphere: String, dmg: int, area: float, range_f: float, target_position: Vector2) -> void:
	var final_dmg := magic_damage(dmg, sphere)
	if SpellDB.projectile_folder(name) == "":
		# Эффекта-снаряда нет: мгновенный урон по цели/точке (напр. Animate_Dead).
		var enemy := get_nearest_enemy(target_position, 120.0)
		if enemy != null:
					Game.deal_damage(enemy, final_dmg, "magic", sphere, self)
		return
	if area > 0.0:
		# Областное: летит к точке, взрывается (урон по радиусу из projectile.gd)
		create_spell_projectile(name, cast_origin(), target_position, final_dmg, area)
	else:
		# Одиночная цель: снаряд летит до врага у точки прицела
		var enemy := get_nearest_enemy(target_position, 200.0)
		var to := enemy.global_position if enemy != null else target_position
		create_spell_projectile(name, cast_origin(), to, final_dmg, 0.0)

## Создать снаряд с анимацией фаз из папки снаряда.
func create_spell_projectile(name: String, from: Vector2, to: Vector2, damage: int, area: float) -> void:
	var scene := preload("res://scenes/projectile.tscn")
	if scene == null:
		return
	var p: Projectile = scene.instantiate()
	p.start_pos = from
	p.target_pos = to
	p.damage = damage
	p.projectile_owner = self
	p.spell_name = name
	p.spell_area = area
	get_tree().root.add_child(p)
	if p.has_method("set_spell_anim"):
		p.set_spell_anim(name)

## Лечение выбранной цели (герой по умолчанию): HP, но не выше максимума.
func _heal_target(target: Node2D, amount: int) -> void:
	if target == null or not is_instance_valid(target):
		target = self
	var maxhp := int(target.get("max_hp") if "max_hp" in target else 0)
	var cur := int(target.get("current_hp") if "current_hp" in target else 0)
	if maxhp <= 0 or cur >= maxhp:
		return
	var healed := mini(maxhp, cur + amount) - cur
	if healed <= 0:
		return
	target.set("current_hp", cur + healed)
	print("Лечение: +%d HP у %s (итого %d/%d)" % [healed, target.name, cur + healed, maxhp])
	if target == self and health_bar:
		health_bar.update_bars(current_hp, current_mana)

## Защитный бафф цели (герой или союзник): поглощение урона на время.
## Protection_from_<Сфера> / Bless — слабее, Shield — сильнее.
func _apply_buff_target(target: Node2D, sphere: String, name: String) -> void:
	if target == null or not is_instance_valid(target):
		target = self
	var strength := 2 + sphere_skill(sphere) / 10
	var seconds := 90.0
	if name == "Shield":
		strength = 18
		seconds = 60.0
	Game.apply_shield(target, strength, seconds)
	print("Защита %s +%d у %s на %.0f с" % [sphere, strength, target.name, seconds])

## Стена (Wall of Fire / Wall of Earth): метка у точки прицела в радиусе.
func _create_wall(target_position: Vector2) -> void:
	var marker := ColorRect.new()
	marker.color = Color(0.9, 0.3, 0.1, 0.35)
	marker.position = target_position - Vector2(16, 16)
	marker.size = Vector2(32, 32)
	get_tree().root.add_child(marker)
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if is_instance_valid(marker):
			marker.queue_free())

## Свет (Astral, self): мягкая светлая сфера вокруг героя на несколько секунд.
## Визуальный маркер-вспышка (системы освещения в проекте нет).
func _cast_light() -> void:
	var marker := ColorRect.new()
	marker.color = Color(1.0, 0.95, 0.7, 0.25)
	var r := 90.0
	marker.position = global_position - Vector2(r, r)
	marker.size = Vector2(r * 2, r * 2)
	get_tree().root.add_child(marker)
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(func():
		if is_instance_valid(marker):
			marker.queue_free())

## Призыв (Astral, self): союзный миньон (наёмник с монстрячьим сетом),
## следует за героем и атакует врагов, исчезает через 45 секунд (или при смерти).
func _cast_summon() -> void:
	var m := Mercenary.new()
	m.anim_set = "monsters/orc"
	m.max_hp = 60
	m.damage = 8
	m.move_speed = 110.0
	m.lifespan = 45.0
	m.position = global_position + Vector2(30, 6)
	get_tree().current_scene.add_child(m)
	Game.party.append(m)
	SoundDB.play(1)
	print("Призыв: союзный монстр")

## Телепорт к точке (в пределах карты).
func _teleport_to(target_position: Vector2) -> void:
	if alm_map and alm_map.has_method("is_walkable_world") and not alm_map.is_walkable_world(target_position):
		return
	global_position = target_position
	reset_physics_interpolation()
	if health_bar:
		health_bar.update_bars(current_hp, current_mana)

## Урон по области вокруг точки (объектам карты и врагам) через Game.deal_damage_area.
func _damage_area_at(pos: Vector2, radius: float, dmg: int, sphere: String = "") -> void:
	if alm_map and alm_map.has_method("damage_area"):
		alm_map.damage_area(pos, radius, dmg)
	var targets: Array = []
	for enemy in Game.enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(pos) <= radius:
			targets.append(enemy)
	Game.deal_damage_area(targets, dmg, "magic", sphere, self)

## Изучить книгу магии (только маг, навсегда): книга стихии открывает всю
## сферу ("Book Fire"), книга одного заклинания — только его ("Book Fire Arrow").
## Книга расходуется (уходит из склада). true — если что-то выучено.
func learn_book(item_name: String) -> bool:
	if not has_mana:
		return false   # воин не может читать книги магии
	var sphere := SpellDB.sphere_of_book(item_name)
	var gained: Array = []
	if sphere != "":
		sphere_books[sphere] = true
		for spell in SpellDB.spells_of_sphere(sphere):
			if not known_spells.has(spell):
				known_spells[spell] = {"charges": -1}
				gained.append(spell)
		if gained.is_empty():
			return false   # вся сфера уже выучена — книгу не тратим
		print("Изучена книга стихии %s: +%d заклинаний" % [sphere, gained.size()])
	else:
		var spell := SpellDB.spell_of_book(item_name)
		if spell == "":
			return false
		if known_spells.has(spell) and spell_charges(spell) == -1:
			return false   # уже выучено навсегда — книгу не тратим
		known_spells[spell] = {"charges": -1}
		gained.append(spell)
		print("Выучено заклинание из книги: %s" % spell)
	remove_item(item_name)
	return true

## Прочитать свиток (НЕ-маг): +1 заряд заклинания за свиток, который при этом
## расходуется. Маг читает свитки ПРИЦЕЛЬНО из склада (см. apply_scroll_to_target),
## заряды в панели магии ему не копятся.
func read_scroll(item_name: String) -> bool:
	if has_mana:
		print("Маг читает свиток прицельно из склада (заряды не копятся).")
		return false
	var spell := SpellDB.spell_from_scroll(item_name)
	if spell == "":
		return false
	if known_spells.has(spell) and spell_charges(spell) == -1:
		print("Это заклинание уже выучено навсегда — свиток не нужен.")
		return false
	if not known_spells.has(spell):
		known_spells[spell] = {"charges": 0}
	known_spells[spell]["charges"] = int(known_spells[spell]["charges"]) + 1
	remove_item(item_name)
	print("Прочитан свиток: %s, зарядов: %d" % [spell, known_spells[spell]["charges"]])
	return true

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

func _create_lightning_effect(from: Vector2, to: Vector2):
	var line = Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.3, 0.6, 1.0, 1.0)
	line.add_point(from)
	
	# Зигзаг молнии
	var steps = 8
	for i in range(1, steps):
		var t = float(i) / steps
		var mid = from.lerp(to, t)
		mid.x += randf_range(-20, 20)
		mid.y += randf_range(-20, 20)
		line.add_point(mid)
	
	line.add_point(to)
	get_tree().root.add_child(line)
	
	# Вспышка в точке попадания
	var flash = ColorRect.new()
	flash.color = Color(0.5, 0.7, 1.0, 0.8)
	flash.position = to - Vector2(15, 15)
	flash.size = Vector2(30, 30)
	get_tree().root.add_child(flash)
	
	# Удаляем через 0.3 секунды
	var timer = get_tree().create_timer(0.3)
	timer.timeout.connect(func():
		if is_instance_valid(line): line.queue_free()
		if is_instance_valid(flash): flash.queue_free()
	)

func take_damage(damage: int, _attacker: Node2D):
	# Мёртвый герой больше не получает урон
	if state == "dead" or state == "decay":
		return
	damage = Game.shield_reduce(self, damage)
	if damage <= 0:
		return
	current_hp -= damage
	SoundDB.play_pain([0, 0, 220, 221, 240])  # боль человека (easy1/easy2)
	if current_hp <= 0:
		# Смерть: играем падение DYING + разложение DECAY, затем пауза
		velocity = Vector2.ZERO
		state = "dead"
		_path.clear()
		Game.player_target = global_position
		SoundDB.play(240)  # units\dead1
		if health_bar:
			health_bar.visible = false
