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
var move_speed: float = 120.0
var _path: Array = []        # маршрут (мировые точки — центры клеток), без «льда»
var _stuck_frames := 0
var _repath_timer := 0.0

# --- Экономика (P0): золото и склад владений ---
var gold: int = 20
var inventory: Array = []   # ключи предметов item_db ("Common Iron Long Sword", "Potion ...")

## Магия героя: выученные заклинания (книги) и заряды свитков.
## known_spells: "Fire_Ball" -> {"charges": -1} — выучено навсегда (маг, из книги);
## "Heal" -> {"charges": 2} — заряды свитков (может кастовать, тратя свиток).
## Воины не имеют маны (max_mana = 0) и не читают книги — только свитки.
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
	collision_mask = 0   # юниты не толкают друг друга физикой — ходят по сетке проходимости
	_ensure_sprite()
	_create_health_bar()
	_setup_starter_magic()

## Стартовая магия: маг уже знает по одному заклинанию сферы (по книге), воин — ничего.
## У магов шт обеспечить базовые заклинания для старта игры.
func _setup_starter_magic() -> void:
	if not has_mana:
		return
	# Книги стихий у мага изначально: Огонь, Вода, Воздух, Земля, Астрал
	for sphere in ["Fire", "Water", "Air", "Earth", "Astral"]:
		sphere_books[sphere] = true
	# Базовые заклинания доступны сразу (как в оригинале — из стартовых книг)
	for sphere in sphere_books:
		for spell in SpellDB.spells_of_sphere(sphere):
			if not known_spells.has(spell):
				known_spells[spell] = {"charges": -1}

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
	for i in range(3):
		inventory.append("Potion Medium Healing")
	inventory.append("Potion Mana Regeneration")

## --- Склад владений ---

func has_item(key: String) -> bool:
	return inventory.has(key)

func add_item(key: String) -> void:
	if key != "":
		inventory.append(key)

## Убрать предмет из склада; true — если он там был.
func remove_item(key: String) -> bool:
	var i := inventory.find(key)
	if i < 0:
		return false
	inventory.remove_at(i)
	return true

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
	return base * 7.5

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
	var cur_h: int = alm_map.height_at_world(global_position)
	var tgt_h: int = alm_map.height_at_world(target_pos)
	var f := 1.0
	if tgt_h > cur_h:
		# Подъём — замедление (каждый уровень -30%, минимум 0.45 — «ползёт», а не стоит)
		f = maxf(0.45, 1.0 - 0.3 * (tgt_h - cur_h))
	if alm_map.has_method("speed_factor_at_world"):
		f *= float(alm_map.call("speed_factor_at_world", global_position))
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

	# Быстрые клавиши каста (зар-1/2/3 — первые известные атакующие заклинания)
	var cast_keys := ["cast_1", "cast_2", "cast_3"]
	var castable := _attack_spells()
	for i in range(cast_keys.size()):
		if Input.is_action_just_pressed(cast_keys[i]):
			if i < castable.size():
				cast_spell(castable[i], get_global_mouse_position())

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
				_anim.speed_scale = clampf(velocity.length() / maxf(move_speed * 0.85, 1.0), 0.5, 2.0)
				_anim.advance(delta)
		"chase":
			chase_target(delta)
			if _anim:
				_anim.play(UnitAnim.Anim.MOVE)
				_anim.set_direction_vec(velocity)
				_anim.speed_scale = clampf(velocity.length() / maxf(move_speed * 0.85, 1.0), 0.5, 2.0)
				_anim.advance(delta)
		"attack":
			attack_enemy(delta)
			if _anim:
				_anim.play(UnitAnim.Anim.ATTACK)
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

func move_to_target(delta):
	if _path.size() > 0:
		_follow_path(delta)
		if _path.is_empty():
			# Маршрут пройден — цель достигнута (не скользим дальше)
			state = "idle"
			velocity = Vector2.ZERO
		return
	if Game.player_target.distance_to(global_position) > 5.0:
		var direction = (Game.player_target - global_position).normalized()
		var speed_factor = _height_speed_factor(Game.player_target)
		_move_checked(direction, move_speed * speed_factor, delta)
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

func attack_enemy(_delta):
	if attack_target and is_instance_valid(attack_target):
		# Враг убежал из радиуса — догоняем, а не бьём в пустоту
		if Game.units_range(self, attack_target) > Game.ATTACK_RANGE + 12.0:
			state = "chase"
			return
		if attack_cooldown <= 0:
			var damage = get_damage_min() + randi() % (get_damage_max() - get_damage_min() + 1)
			print("Атакуем! Урон: ", damage)
			_sound_weapon_attack()
			attack_target.take_damage(damage, self)
			attack_cooldown = Game.ATTACK_COOLDOWN
	else:
		state = "idle"

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

## Заряды заклинания: -1 = выучено (маг, из книги), 0 = нет, N = свитки.
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
	if charges != 0:
		return true  # есть заряд свитка
	if has_mana and current_mana >= SpellDB.mana_cost(name):
		return true  # маг за ману
	return false

## Использовать заклинание по имени. Возвращает true, если кастован.
func cast_spell(name: String, target_position: Vector2) -> bool:
	if not can_cast(name):
		return false
	var spell: Dictionary = SpellDB.get_spell(name)
	if spell.is_empty():
		return false
	# Стоимость: заряды свитка тратятся первыми; маг платит ману.
	var charges := spell_charges(name)
	if charges > 0:
		known_spells[name]["charges"] = charges - 1
	elif has_mana:
		current_mana = maxi(0, current_mana - SpellDB.mana_cost(name))
	cast_cooldowns[name] = 0.8  # универсальный КД ~0.8 с

	var sphere := str(spell.get("sphere", ""))
	var kind := str(spell.get("kind", "buff"))
	var dmg := int(spell.get("damage", 0))
	var area := float(spell.get("area", 0))
	var range_f := float(spell.get("range", 0))

	# Звук заклинания по сфере (magic\*.wav)
	match sphere:
		"Fire": SoundDB.play(512)      # fireball
		"Water": SoundDB.play(518)     # icemissile
		"Air": SoundDB.play(528)       # lightning
		"Earth": SoundDB.play(546)     # pearth
		"Astral": SoundDB.play(556)    # heal
		_: SoundDB.play(512)

	match kind:
		"attack", "area":
			_fire_spell_projectile(name, sphere, dmg, area, range_f, target_position)
		"heal":
			_apply_heal(name, dmg, sphere)
		"buff":
			_apply_buff(sphere, target_position)
		"wall":
			_create_wall(target_position)
		"self":
			match name:
				"Teleport": _teleport_to(target_position)
				"Light": print("Свет")
				"Shield": print("Щит (задел)")
				"Summon": print("Призыв (задел)")
	return true

## Снаряд заклинания (с анимацией из assets/projectiles/<folder>/).
func _fire_spell_projectile(name: String, sphere: String, dmg: int, area: float, range_f: float, target_position: Vector2) -> void:
	var final_dmg := magic_damage(dmg, sphere)
	if area > 0.0:
		# Областное: летит к точке, взрывается (урон по радиусу)
		create_spell_projectile(name, global_position, target_position, final_dmg, area)
		if range_f <= 0.0:
			_damage_area_at(target_position, area, final_dmg)
	else:
		# Одиночная цель: снаряд летит до врага у точки прицела
		var enemy := get_nearest_enemy(target_position, 200.0)
		var to := enemy.global_position if enemy != null else target_position
		create_spell_projectile(name, global_position, to, final_dmg, 0.0)

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

## Лечение: восстановить HP герою (максимум).
func _apply_heal(name: String, dmg: int, _sphere: String) -> void:
	var heal_amount := -dmg + mind / 5
	current_hp = mini(max_hp, current_hp + heal_amount)
	print("Лечение: +%d HP (итого %d/%d)" % [heal_amount, current_hp, max_hp])

## Бафф: пока просто накладываем положительный эффект и печатаем.
func _apply_buff(sphere: String, _target_position: Vector2) -> void:
	print("Бафф сферы %s применён (задел)" % sphere)

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

## Телепорт к точке (в пределах карты).
func _teleport_to(target_position: Vector2) -> void:
	if alm_map and alm_map.has_method("is_walkable_world") and not alm_map.is_walkable_world(target_position):
		return
	global_position = target_position
	if health_bar:
		health_bar.update_bars(current_hp, current_mana)

## Урон по области вокруг точки (объектам карты и врагам).
func _damage_area_at(pos: Vector2, radius: float, dmg: int) -> void:
	if alm_map and alm_map.has_method("damage_area"):
		alm_map.damage_area(pos, radius, dmg)
	for enemy in Game.enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(pos) <= radius:
			enemy.take_damage(dmg, self)

## Изучить книгу стихии (только маг): открывает все заклинания сферы.
func learn_sphere_book(item_name: String) -> bool:
	if not has_mana:
		return false  # воин не может читать книги магии
	var sphere := SpellDB.sphere_of_book(item_name)
	if sphere == "":
		return false
	sphere_books[sphere] = true
	var gained: Array = []
	for spell in SpellDB.spells_of_sphere(sphere):
		if not known_spells.has(spell):
			known_spells[spell] = {"charges": -1}
			gained.append(spell)
	print("Изучена книга %s: +%d заклинаний" % [sphere, gained.size()])
	return true

## Прочитать свиток: +1 заряд заклинания (любой персонаж).
func read_scroll(item_name: String) -> bool:
	var spell := SpellDB.spell_from_scroll(item_name)
	if spell == "":
		return false
	if not known_spells.has(spell):
		known_spells[spell] = {"charges": 0}
	known_spells[spell]["charges"] = int(known_spells[spell]["charges"]) + 1
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
