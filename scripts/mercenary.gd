extends CharacterBody2D
class_name Mercenary
## Наёмник из таверны: следует за героем, атакует врагов (Game.enemies),
## не качается и не носит броню (как в оригинале). Смерть — из отряда.

@export var anim_set: String = "humans/swordsman"
@export var max_hp: int = 70
@export var damage: int = 6
@export var move_speed: float = 90.0
@export var spirit: int = 5                # базовое сопротивление магии

var current_hp: int
var attack_cooldown: float = 0.0
var _impact_timer := -1.0            # отсчёт до кадра удара (замах); <0 = нет удара в полёте
var _pending_target: Node2D = null   # цель текущего замаха (урон — на кадре удара)
var state: String = "idle"      # idle | dying | decay | corpse
var lifespan: float = 0.0       # >0 — призванный миньон: исчезает по истечении времени
var _lifetime: float = 0.0
var _corpse_timer := 0.0
var _anim: UnitAnim = null
var _path: Array = []
var _repath: float = 0.0

func _ready() -> void:
	add_to_group("mercenary")
	Game.configure_unit_body(self)
	current_hp = max_hp
	_anim = UnitAnim.new()
	_anim.name = "UnitAnim"
	add_child(_anim)
	_anim.setup(anim_set)
	_anim.play(UnitAnim.Anim.IDLE)

func _physics_process(delta: float) -> void:
	if Game.is_paused or _anim == null:
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if lifespan > 0.0:
		_lifetime += delta
		if _lifetime >= lifespan:
			Game.party.erase(self)
			queue_free()
			return
	_apply_relief_stand()

	# Наёмник умер: падение → разложение (если есть) → исчезновение
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

	var target := _nearest_enemy(240.0)
	# Кадр удара: урон наносится в момент соприкосновения, а не в начале замаха
	if _impact_timer >= 0.0:
		_impact_timer -= delta
		move_and_slide()
		if _impact_timer < 0.0:
			_impact_timer = -1.0
			if is_instance_valid(_pending_target) and Game.enemies.has(_pending_target) \
					and not Game.is_miss(self, _pending_target):
				Game.deal_damage(_pending_target, damage, "physical", "", self)
				SoundDB.play(5)
			_pending_target = null
		return
	if target != null:
		if global_position.distance_to(target.global_position) > 40.0:
			_move_toward(target.global_position, delta)
		else:
			velocity = Vector2.ZERO
			_attack(target)
	else:
		var hero: Node2D = Game.hero
		if hero != null and is_instance_valid(hero) \
				and global_position.distance_to(hero.global_position) > 64.0:
			_move_toward(hero.global_position, delta)
		else:
			velocity = Vector2.ZERO

	move_and_slide()
	if velocity.length_squared() > 1.0:
		_anim.play(UnitAnim.Anim.MOVE)
		_anim.set_direction_vec(velocity)
		_anim.advance(delta)
	else:
		_anim.play(UnitAnim.Anim.IDLE)

func _nearest_enemy(radius: float) -> Node2D:
	var best: Node2D = null
	var best_d := radius
	for e in Game.enemies:
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _move_toward(p: Vector2, delta: float) -> void:
	if _path.is_empty():
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.6
			var map_node := get_tree().get_first_node_in_group("alm_map")
			if map_node != null and map_node.has_method("find_path"):
				_path = map_node.find_path(global_position, p)
	if _path.is_empty():
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
		return
	var waypoint: Vector2 = _path[0]
	if global_position.distance_to(waypoint) <= 8.0:
		_path.pop_front()
		if _path.is_empty():
			velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
			return
		waypoint = _path[0]
	var direction := Game.movement_direction(self, (waypoint - global_position).normalized())
	var wanted := direction * (move_speed * StatusEffects.speed_mult(self))
	velocity = velocity.move_toward(wanted, 1100.0 * delta)

func _attack(target: Node2D) -> void:
	if attack_cooldown > 0.0 or _impact_timer >= 0.0:
		return
	if not Game.enemies.has(target):
		return
	attack_cooldown = 1.0
	# Замах: урон и звук — в момент удара (_impact_timer обрабатывается в _physics_process)
	_pending_target = target
	_impact_timer = UnitDB.attack_delay(anim_set)

func take_damage(dmg: int, _attacker: Node2D) -> int:
	# Мёртвый наёмник урона не получает
	if state == "dying" or state == "decay" or state == "corpse":
		return 0
	dmg = Game.shield_reduce(self, dmg)
	if dmg <= 0:
		SpellVFX.shield_hit(self)
		return 0
	current_hp -= dmg
	if current_hp <= 0:
		current_hp = 0
		SoundDB.play(4)
		Game.party.erase(self)
		velocity = Vector2.ZERO
		state = "dying"
	else:
		SoundDB.play_pain(UnitDB.unit_sound(anim_set))
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

## --- Производные характеристики (как у врагов/героя) для Game.deal_damage ---
func get_attack() -> int:
	return damage / 2 + max_hp / 30 + StatusEffects.stat_flat(self, "attack")

func get_defense() -> int:
	var base := max_hp / 25
	return int(round((base + StatusEffects.stat_flat(self, "defense")) * StatusEffects.defense_mult(self)))

func get_absorption() -> int:
	return max_hp / 40

## Сопротивление в процентах. Раньше все get_protection_* были жёстко 0 —
## наёмник получал полный урон магией по любой стихии.
func _resist(sphere: String) -> int:
	return spirit * 2 + StatusEffects.resist_bonus(self, sphere)

func get_protection_fire() -> int:   return _resist("Fire")
func get_protection_water() -> int:  return _resist("Water")
func get_protection_air() -> int:    return _resist("Air")
func get_protection_earth() -> int:  return _resist("Earth")
func get_protection_astral() -> int: return _resist("Astral")

func _apply_relief_stand() -> void:
	var h := 0.0
	var map_node: Node2D = Game.hero
	if map_node != null and is_instance_valid(map_node) \
			and map_node.is_in_group("alm_map") and map_node.has_method("relief_at_world"):
		h = float(map_node.call("relief_at_world", global_position))
	_anim.position = Vector2(_anim.position.x, -h)