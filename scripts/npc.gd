extends CharacterBody2D
class_name Npc
## Мирный житель (НПЦ): гуляет у своей точки, не атакует и не отвлекается
## на игрока. Набор анимаций — любой не-враждебный юнит из units_db
## (humans/*, мирные звери; агрессия в UnitDB.is_hostile).

@export var anim_set: String = "humans/unarmed"
@export var patrol_radius: int = 3           # клеток вокруг точки привязки
@export var walk_speed: float = 45.0
@export var pause_min: float = 1.2
@export var pause_max: float = 4.0
@export var max_hp: int = 30                 # здоровье мирного жителя

var current_hp: int
var state: String = "idle"                   # idle | move | dying | decay | corpse
var _corpse_timer := 0.0
var home := Vector2.ZERO       # мировая точка привязки (центр клетки)
var alm_map = null             # CustomMap или AlmMap из группы "alm_map"
var _anim: UnitAnim = null
var _target := Vector2.ZERO
var _moving := false
var _waiting := true
var _pause_timer := 0.0

func _ready() -> void:
	add_to_group("npcs")
	collision_mask = 0   # жители не толкают друг друга физикой
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
		var dir := (_target - global_position).normalized()
		_move_checked(dir, walk_speed, delta)
		_anim.play(UnitAnim.Anim.MOVE)
		_anim.set_direction_vec(velocity)
		_anim.advance(delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
		_waiting = true
		_pause_timer = randf_range(pause_min, pause_max)
		_anim.play(UnitAnim.Anim.IDLE)

## Случайная проходимая точка в радиусе патруля (или остаёмся дома).
func _pick_new_target() -> void:
	if alm_map == null:
		_target = home
		return
	for attempt in range(8):
		var off := Vector2(
			randf_range(-patrol_radius, patrol_radius),
			randf_range(-patrol_radius, patrol_radius))
		var p := home + off * 32.0
		if p.distance_to(home) <= float(patrol_radius) * 32.0 + 16.0 \
				and alm_map.has_method("is_walkable_world") \
				and bool(alm_map.call("is_walkable_world", p)):
			_target = p
			return
	_target = home

## Стоять на рельефе: поднять спрайт на высоту клетки (как у игрока/врагов).
func _apply_relief_stand() -> void:
	if _anim == null:
		return
	var h := 0.0
	if alm_map != null and alm_map.has_method("relief_at_world"):
		h = float(alm_map.call("relief_at_world", global_position))
	_anim.position = Vector2(_anim.position.x, -h)

## Получить урон (герой/монстры могут зацепить мирного жителя). При смерти —
## падение DYING → разложение DECAY (если есть) → исчезновение.
func take_damage(dmg: int, _attacker: Node2D) -> void:
	if state == "dying" or state == "decay" or state == "corpse":
		return
	current_hp -= dmg
	if current_hp > 0:
		SoundDB.play_pain(UnitDB.unit_sound(anim_set))
		return
	current_hp = 0
	SoundDB.play(240)  # units\dead1
	state = "dying"
	velocity = Vector2.ZERO
	Game.npcs.erase(self)

## Плавное движение с проверкой проходимости (без «льда» и «сквозь стены»).
func _move_checked(direction: Vector2, speed: float, delta: float) -> void:
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