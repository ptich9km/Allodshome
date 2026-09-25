extends CharacterBody2D
class_name Npc
## Мирный житель (НПЦ): гуляет у своей точки, не отвлекается на игрока.
## role "citizen" — стоит на посту (мелкое шевеление); role "guard" —
## патрулирует город (is_patrol) и дерётся с Серыми (монстрами), героя не трогает.

@export var anim_set: String = "humans/unarmed"
@export var patrol_radius: int = 3           # клеток вокруг точки привязки
@export var walk_speed: float = 45.0
@export var pause_min: float = 1.2
@export var pause_max: float = 4.0
@export var max_hp: int = 30                 # здоровье жителя
@export var role: String = "citizen"         # citizen | guard
@export var is_patrol: bool = false          # патруль вокруг поста (стражи)
@export var damage: int = 0                  # урон стражи (граждане не бьют)
@export var aggro_radius: float = 190.0      # радиус агро стражи на Серых

var current_hp: int
var state: String = "idle"                   # idle | move | dying | decay | corpse
var _corpse_timer := 0.0
var home := Vector2.ZERO       # мировая точка привязки (центр клетки)
var post := Vector2.ZERO       # мировой пост (центр клетки) из sidecar
var alm_map = null             # CustomMap или AlmMap из группы "alm_map"
var _anim: UnitAnim = null
var _target := Vector2.ZERO
var _moving := false
var _waiting := true
var _pause_timer := 0.0
var attack_cooldown := 0.0
var _impact_timer := -1.0
var _path: Array = []
var _repath := 0.0

func _ready() -> void:
	add_to_group("npcs")
	Game.configure_unit_body(self)
	current_hp = max_hp
	alm_map = get_tree().get_first_node_in_group("alm_map")
	_anim = UnitAnim.new()
	_anim.name = "UnitAnim"
	add_child(_anim)
	_anim.setup(anim_set)
	_anim.play(UnitAnim.Anim.IDLE)
	_pick_new_target()

func _physics_process(delta: float) -> void:
	if Game.is_paused or _anim == null:
		return
	_apply_relief_stand()

	# Житель умер (его ударили монстры/герой): падение, разложение, исчезновение
	if state == "dying" or state == "decay" or state == "corpse":
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
		match state:
			"dying":
				_anim.play(UnitAnim.Anim.DYING)
				if _anim.advance(delta):
					if UnitDB.decay_phases(anim_set) > 0:
						state = "decay"
						_anim.play(UnitAnim.Anim.DECAY)
					else:
						state = "corpse"
						_anim.freeze_last_frame(UnitAnim.Anim.DYING)
						_corpse_timer = 5.0
			"decay":
				if _anim.advance(delta):
					state = "corpse"
					_anim.freeze_last_frame(UnitAnim.Anim.DECAY)
					_corpse_timer = 3.0
			"corpse":
				_corpse_timer -= delta
				if _corpse_timer <= 0.0:
					queue_free()
					return
		move_and_slide()
		return

	# Стража: Серые рядом — бой (граждане не дерутся)
	if role == "guard" and damage > 0 and _guard_combat(delta):
		return

	if _waiting:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_waiting = false
			_pick_new_target()
		_anim.play(UnitAnim.Anim.IDLE)
		return

	# Идём к выбранной точке патруля
	var d := global_position.distance_to(_target)
	if d > 4.0:
		if _path.is_empty():
			_repath -= delta
			if _repath <= 0.0:
				_repath = 0.6
				if alm_map != null and alm_map.has_method("find_path"):
					_path = alm_map.find_path(global_position, _target)
		if not _path.is_empty():
			var wp: Vector2 = _path[0]
			if global_position.distance_to(wp) <= 8.0:
				_path.pop_front()
		if not _path.is_empty():
			_move_checked((_path[0] - global_position).normalized(), walk_speed, delta)
			if velocity.length() > 10.0:
				_anim.play(_anim.Anim.MOVE)
				_anim.set_direction_vec(velocity)
				_anim.advance(delta)
			else:
				_anim.play(UnitAnim.Anim.IDLE)
			return
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
		_anim.play(UnitAnim.Anim.IDLE)
	else:
		_path.clear()
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
		_waiting = true
		_pause_timer = randf_range(pause_min, pause_max)
		_anim.play(UnitAnim.Anim.IDLE)

## Случайная проходимая точка у поста (патрульный — шире, остальные стоят).
func _pick_new_target() -> void:
	var anchor := post if post != Vector2.ZERO else home
	if alm_map == null:
		_target = anchor
		return
	var rad := 4 if is_patrol else 1   # патруль-страж гуляет по городу, стоящие — на месте
	for attempt in range(8):
		var off := Vector2(
			randf_range(-rad, rad),
			randf_range(-rad, rad))
		var p := anchor + off * 32.0
		if p.distance_to(anchor) <= float(rad) * 32.0 + 16.0 \
				and alm_map.has_method("is_walkable_world") \
				and bool(alm_map.call("is_walkable_world", p)):
			_target = p
			return
	_target = anchor

## Стоять на рельефе: поднять спрайт на высоту клетки (как у игрока/врагов).
func _apply_relief_stand() -> void:
	if _anim == null:
		return
	var h := 0.0
	if alm_map != null and alm_map.has_method("relief_at_world"):
		h = float(alm_map.call("relief_at_world", global_position))
	_anim.position = Vector2(_anim.position.x, -h)

# --- Бой стражи с Серыми ---

## Один кадр боя стражи. Возвращает true, если страж занят (дерётся/преследует).
func _guard_combat(delta: float) -> bool:
	var target: Node2D = _nearest_enemy()
	if target == null:
		_impact_timer = -1.0
		return false
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	var dist := Game.units_range(self, target)
	# Не уходим далеко от города — граница обороны поста
	if dist > 380.0:
		_impact_timer = -1.0
		return false
	velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
	if dist > 30.0:
		_chase_move(delta, target)
	else:
		if attack_cooldown <= 0.0 and _impact_timer < 0.0:
			attack_cooldown = 1.0
			_impact_timer = UnitDB.attack_delay(anim_set)
		elif _impact_timer >= 0.0:
			_impact_timer -= delta
			if _impact_timer < 0.0:
				_impact_timer = -1.0
				if Game.is_miss(self, target):
					print("%s промахнулся по %s!" % [name, target.name])
				else:
					Game.deal_damage(target, damage, "physical", "", self)
				SoundDB.play(_unit_sound_at(0))
		_anim.play(UnitAnim.Anim.ATTACK)
		_anim.speed_scale = 1.0
		_anim.advance(delta)
	move_and_slide()
	return true

## Ближайший Серый в радиусе агро.
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var bd := aggro_radius
	for e in Game.enemies:
		if e == null or not is_instance_valid(e):
			continue
		var d := Game.units_range(self, e)
		if d < bd:
			bd = d
			best = e
	return best

## Погоня с обходом препятствий (перепланировка пути раз в 0.6 с).
func _chase_move(delta: float, target: Node2D) -> void:
	var tpos: Vector2 = target.global_position
	if _path.is_empty():
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.6
			if alm_map != null and alm_map.has_method("find_path"):
				_path = alm_map.find_path(global_position, tpos)
	if _path.size() > 0:
		var wp: Vector2 = _path[0]
		if global_position.distance_to(wp) <= 8.0:
			_path.pop_front()
		if _path.size() > 0:
			wp = _path[0]
			_move_checked((wp - global_position).normalized(), walk_speed, delta)
			_anim.play(UnitAnim.Anim.MOVE)
			_anim.set_direction_vec(velocity)
			_anim.advance(delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
			_anim.play(UnitAnim.Anim.IDLE)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)

## Звуковой ID юнита по позиции массива Sound (attack/pain1/pain2/death).
func _unit_sound_at(idx: int) -> int:
	return SoundDB.sound_at(UnitDB.unit_sound(anim_set), idx)

## --- Статы (для Game.unit_*: атака->точность, защита->уклонение) ---
func get_attack() -> int:
	return damage / 2 + max_hp / 30 + StatusEffects.stat_flat(self, "attack")

func get_defense() -> int:
	var base := max_hp / 25
	return int(round((base + StatusEffects.stat_flat(self, "defense")) * StatusEffects.defense_mult(self)))

func get_absorption() -> int:
	return max_hp / 40

func _resist(sphere: String) -> int:
	return UnitDB.resist_of(anim_set, sphere) + StatusEffects.resist_bonus(self, sphere)

func get_protection_fire() -> int:   return _resist("Fire")
func get_protection_water() -> int:  return _resist("Water")
func get_protection_air() -> int:    return _resist("Air")
func get_protection_earth() -> int:  return _resist("Earth")
func get_protection_astral() -> int: return _resist("Astral")

## Получить урон (герой/монстры могут зацепить мирного жителя). При смерти —
## падение DYING → разложение DECAY (если есть) → исчезновение.
func take_damage(dmg: int, _attacker: Node2D) -> int:
	if state == "dying" or state == "decay" or state == "corpse":
		return 0
	dmg = Game.shield_reduce(self, dmg)
	if dmg <= 0:
		SpellVFX.shield_hit(self)
		return 0
	current_hp -= dmg
	if current_hp > 0:
		SoundDB.play_pain(UnitDB.unit_sound(anim_set))
		return dmg
	current_hp = 0
	SoundDB.play(240)  # units\dead1
	state = "dying"
	velocity = Vector2.ZERO
	Game.npcs.erase(self)
	return dmg

## Восстановить HP (лечение, вампиризм). Возвращает реально восстановленное.
func heal_amount(amount: int) -> int:
	if amount <= 0 or current_hp >= max_hp:
		return 0
	if state == "dying" or state == "decay" or state == "corpse":
		return 0
	var healed := mini(max_hp, current_hp + amount) - current_hp
	current_hp += healed
	DamageNumber.show_at(global_position, healed, "heal")
	return healed

## Плавное движение с проверкой проходимости (без «льда» и «сквозь стены»).
func _move_checked(direction: Vector2, speed: float, delta: float) -> void:
	direction = Game.movement_direction(self, direction)
	var wanted := direction * speed
	var can_step := true
	if alm_map != null and alm_map.has_method("is_walkable_world"):
		var next := global_position + wanted * delta
		# Разрешаем шаг внутри СВОЕЙ непроходимой клетки (выход из застревания)
		can_step = alm_map.is_walkable_world(next) \
			or Vector2i(int(global_position.x) / 32, int(global_position.y) / 32) \
				== Vector2i(int(next.x) / 32, int(next.y) / 32)
	if can_step:
		velocity = velocity.move_toward(wanted, 1100.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)