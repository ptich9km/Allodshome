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

var abilities = [
	{"name": "fireball", "damage": 12, "mana_cost": 8, "cooldown": 1.2, "range": 200},
	{"name": "heal", "heal": 15, "mana_cost": 10, "cooldown": 4.0},
	{"name": "lightning", "damage": 20, "mana_cost": 15, "cooldown": 2.5, "range": 150}
]
var ability_cooldowns = [0.0, 0.0, 0.0]
var health_bar: HealthBar
var alm_map = null   # CustomMap или AlmMap из группы "alm_map"

# --- Экипировка героя (определяет набор анимаций) ---
var armor_kind: String = "heavy"   # "heavy" -> heroes/, "light" -> heroes_l/
var weapon: String = "unarmed"     # по умолчанию без оружия — отлаживаем его анимацию
var two_handed: bool = false
var has_shield: bool = false
var _anim: UnitAnim = null

func _ready():
	max_hp = _calc_max_hp()
	max_mana = _calc_max_mana()
	current_hp = max_hp
	current_mana = max_mana
	move_speed = _calc_speed()
	alm_map = get_tree().get_first_node_in_group("alm_map")
	_ensure_sprite()
	_create_health_bar()

# --- Производные характеристики (связи из оригинального main.txt) ---
func _calc_max_hp() -> int:
	return 20 + body * 8          # Body -> здоровье; body=10 -> 100

func _calc_max_mana() -> int:
	return 10 + spirit * 4        # Spirit -> мана (по манифесту); spirit=10 -> 50

func _calc_hp_regen() -> int:
	return 1 + body / 5           # реген HP от Body

func _calc_mana_regen() -> int:
	return 1 + spirit / 10        # реген маны от Spirit

func _calc_speed() -> float:
	return float(100 + agility * 2)   # Agility -> скорость; agility=10 -> 120

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

## Множитель скорости с учётом высоты: подъём замедляет, спуск/равнина — норма.
## Дороги (tile4) — быстрее травы.
func _height_speed_factor(target_pos: Vector2) -> float:
	if not alm_map:
		return 1.0
	var cur_h: int = alm_map.height_at_world(global_position)
	var tgt_h: int = alm_map.height_at_world(target_pos)
	var f := 1.0
	if tgt_h > cur_h:
		# Подъём — замедление (каждый уровень -30%)
		f = maxf(0.4, 1.0 - 0.3 * (tgt_h - cur_h))
	if alm_map.has_method("speed_factor_at_world"):
		f *= float(alm_map.call("speed_factor_at_world", global_position))
	return f

## Можно ли двигаться в точку: проходимость (вода/барьер) + границы карты.
func _can_move_to(pos: Vector2) -> bool:
	if not alm_map:
		return true
	if not alm_map.is_walkable_world(pos):
		return false
	return alm_map.is_within_bounds(pos)

## Движение с проверкой проходимости: если цель непроходима — скользим вдоль.
func _move_checked(direction: Vector2, speed: float, delta: float):
	var step := direction * speed * delta
	var next := global_position + step
	if _can_move_to(next):
		velocity = direction * speed
	elif _can_move_to(global_position + Vector2(step.x, 0)):
		velocity = Vector2(direction.x, 0) * speed   # скользим по X
	elif _can_move_to(global_position + Vector2(0, step.y)):
		velocity = Vector2(0, direction.y) * speed   # скользим по Y
	else:
		velocity = Vector2.ZERO

func _create_health_bar():
	health_bar = preload("res://scripts/health_bar.gd").new()
	health_bar.max_hp = max_hp
	health_bar.max_mana = max_mana
	health_bar.has_mana = true
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
	for i in range(ability_cooldowns.size()):
		ability_cooldowns[i] = max(0, ability_cooldowns[i] - delta)

	# Обновляем бар здоровья
	if health_bar:
		health_bar.update_bars(current_hp, current_mana)

	# Обработка заклинаний
	if Input.is_action_just_pressed("cast_1"):
		cast_ability(0, get_global_mouse_position())
	elif Input.is_action_just_pressed("cast_2"):
		cast_ability(1, get_global_mouse_position())
	elif Input.is_action_just_pressed("cast_3"):
		cast_ability(2, get_global_mouse_position())

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
				_anim.advance(delta)
		"chase":
			chase_target(delta)
			if _anim:
				_anim.play(UnitAnim.Anim.MOVE)
				_anim.set_direction_vec(velocity)
				_anim.advance(delta)
		"attack":
			attack_enemy(delta)
			if _anim:
				_anim.play(UnitAnim.Anim.ATTACK)
				_anim.advance(delta)
		"dead":
			velocity = Vector2.ZERO
			if _anim:
				_anim.play(UnitAnim.Anim.DYING)

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
		health_bar.position.y = -(h + 60.0)  # бар выше головы

func move_to_target(delta):
	if Game.player_target.distance_to(global_position) > 5.0:
		var direction = (Game.player_target - global_position).normalized()
		var speed_factor = _height_speed_factor(Game.player_target)
		_move_checked(direction, move_speed * speed_factor, delta)
	else:
		state = "idle"
		velocity = Vector2.ZERO

func chase_target(delta):
	if attack_target and is_instance_valid(attack_target):
		var distance = global_position.distance_to(attack_target.global_position)
		if distance > Game.ATTACK_RANGE:
			var direction = (attack_target.global_position - global_position).normalized()
			var speed_factor = _height_speed_factor(attack_target.global_position)
			_move_checked(direction, move_speed * speed_factor, delta)
		else:
			state = "attack"
			velocity = Vector2.ZERO
	else:
		state = "idle"
		velocity = Vector2.ZERO

func attack_enemy(_delta):
	if attack_target and is_instance_valid(attack_target):
		if attack_cooldown <= 0:
			var damage = get_damage_min() + randi() % (get_damage_max() - get_damage_min() + 1)
			print("Атакуем! Урон: ", damage)
			attack_target.take_damage(damage, self)
			attack_cooldown = Game.ATTACK_COOLDOWN
	else:
		state = "idle"

## Магический урон (Mind -> сила магии) для заклинаний.
func magic_damage(base: int) -> int:
	return base + get_magic_power()

func cast_ability(index: int, target_position: Vector2):
	if index < 0 or index >= abilities.size():
		return

	var ability = abilities[index]
	if ability_cooldowns[index] > 0 or current_mana < ability.mana_cost:
		return

	current_mana -= ability.mana_cost
	ability_cooldowns[index] = ability.cooldown

	match ability.name:
		"fireball":
			create_projectile(global_position, target_position, magic_damage(ability.damage))
		"heal":
			current_hp = min(max_hp, current_hp + ability.heal + mind / 5)
		"lightning":
			var enemy = get_nearest_enemy(target_position, ability.range)
			if enemy:
				_create_lightning_effect(global_position, enemy.global_position)
				enemy.take_damage(magic_damage(ability.damage), self)
			# Урон по объектам карты в радиусе удара
			if alm_map and alm_map.has_method("damage_area"):
				alm_map.damage_area(target_position, 60.0, ability.damage)

func create_projectile(from: Vector2, to: Vector2, damage: int):
	var projectile_scene = preload("res://scenes/projectile.tscn")
	if projectile_scene:
		var projectile = projectile_scene.instantiate()
		projectile.start_pos = from
		projectile.target_pos = to
		projectile.damage = damage
		projectile.projectile_owner = self
		get_tree().root.add_child(projectile)

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
	current_hp -= damage
	if current_hp <= 0:
		# Смерть — не удаляем а показываем экран
		velocity = Vector2.ZERO
		state = "dead"
		get_tree().paused = true
		print("=== ВЫ ПОГИБЛИ! Нажмите R для рестарта ===")
