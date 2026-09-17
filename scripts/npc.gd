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
		velocity = dir * walk_speed
		move_and_slide()
		_anim.play(UnitAnim.Anim.MOVE)
		_anim.set_direction_vec(velocity)
		_anim.advance(delta)
	else:
		velocity = Vector2.ZERO
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