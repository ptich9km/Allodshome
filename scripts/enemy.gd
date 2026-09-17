extends CharacterBody2D
class_name Enemy

@export var max_hp: int = 50
@export var damage: int = 8
@export var move_speed: float = 80.0
@export var aggro_radius: float = 150.0
@export var deaggro_radius: float = 200.0
@export var home_position: Vector2
@export var anim_set: String = "monsters/orc"   # набор анимаций из units_db.json

var current_hp: int
var state: String = "idle"
var attack_target: Node2D = null
var attack_cooldown: float = 0.0
var can_flee: bool = true
var health_bar: HealthBar
var _anim: UnitAnim = null

func _ready():
	add_to_group("enemy")
	current_hp = max_hp
	home_position = global_position
	_create_sprite()
	_create_health_bar()

func _create_health_bar():
	health_bar = preload("res://scripts/health_bar.gd").new()
	health_bar.max_hp = max_hp
	health_bar.has_mana = false  # У врагов нет маны
	add_child(health_bar)

func _create_sprite():
	var old_sprite = get_node_or_null("Sprite")
	if old_sprite:
		old_sprite.queue_free()

	_anim = UnitAnim.new()
	_anim.name = "UnitAnim"
	add_child(_anim)
	_anim.setup(anim_set)
	_anim.play(UnitAnim.Anim.IDLE)

func _physics_process(delta):
	if Game.is_paused:
		return

	attack_cooldown = max(0, attack_cooldown - delta)

	# Обновляем бар здоровья
	if health_bar:
		health_bar.update_bars(current_hp)

	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance_to_player = global_position.distance_to(player.global_position)
	var hp_percent = float(current_hp) / max_hp

	match state:
		"idle":
			if distance_to_player < aggro_radius:
				state = "chase"
				attack_target = player
			else:
				velocity = Vector2.ZERO
		"chase":
			if distance_to_player > deaggro_radius:
				state = "idle"
				attack_target = null
				velocity = Vector2.ZERO
			elif distance_to_player < 40.0:
				state = "attack"
			elif hp_percent < 0.15 and can_flee:
				state = "flee"
			else:
				move_toward_target(player.global_position, delta)
		"attack":
			if distance_to_player > 50.0:
				state = "chase"
			elif attack_cooldown <= 0:
				player.take_damage(damage, self)
				attack_cooldown = 1.0
				SoundDB.play(_unit_sound_at(0))
		"flee":
			var flee_direction = (global_position - player.global_position).normalized()
			velocity = flee_direction * move_speed * 1.5
			if distance_to_player > deaggro_radius * 1.5:
				queue_free()

	# Анимация монстра по состоянию
	if _anim:
		match state:
			"chase", "flee":
				_anim.play(UnitAnim.Anim.MOVE)
				_anim.set_direction_vec(velocity)
				_anim.advance(delta)
			"attack":
				_anim.play(UnitAnim.Anim.ATTACK)
				_anim.advance(delta)
			_:
				_anim.play(UnitAnim.Anim.IDLE)

	move_and_slide()
	_apply_relief_stand()

## Стоять на рельефе: поднять спрайт на высоту клетки (как в Allods16).
## Летающие юниты (Z, монстры bat/dragon/succubus) парят над землёй.
func _apply_relief_stand() -> void:
	if _anim == null:
		return
	var h := 0.0
	var map_node = get_tree().get_first_node_in_group("alm_map")
	if map_node != null and map_node.has_method("relief_at_world"):
		h = float(map_node.call("relief_at_world", global_position))
	# Высота полёта юнита (Z из units.txt; обычно 0 = ходит по земле)
	var z := UnitDB.fly_z(anim_set)
	_anim.position = Vector2(_anim.position.x, -(h + z))
	if health_bar:
		health_bar.position.y = -(h + z + 60.0)  # бар выше головы

func move_toward_target(target: Vector2, _delta):
	var direction = (target - global_position).normalized()
	velocity = direction * move_speed

func take_damage(dmg: int, attacker: Node2D):
	current_hp -= dmg
	# При получении урона — сразу начинаем погоню
	if is_instance_valid(attacker):
		state = "chase"
		attack_target = attacker
	if current_hp <= 0:
		SoundDB.play(_unit_sound_at(4))  # смерть
		_drop_loot()
		queue_free()
	else:
		SoundDB.play_pain(UnitDB.unit_sound(anim_set))  # боль

## Звуковой ID юнита по позиции массива Sound (attack/pain1/pain2/death).
func _unit_sound_at(idx: int) -> int:
	return SoundDB.sound_at(UnitDB.unit_sound(anim_set), idx)

func _drop_loot():
	var bag_prefab := load("res://scripts/loot_bag.gd")
	if bag_prefab == null:
		return
	var bag: LootBag = bag_prefab.new()
	bag.items = _make_loot()
	bag.global_position = global_position + Vector2(randf_range(-22, 22), randf_range(-16, 16))
	get_tree().current_scene.add_child(bag)

## Добыча: золото по силе врага + шанс зелья и снаряжения (как «надето на нём»).
func _make_loot() -> Array:
	var pool: Array = []
	var gold_base := 4 + max_hp / 5
	pool.append({"gold": gold_base + randi() % gold_base})
	if randi() % 100 < 45:
		pool.append({"key": "Potion Medium Healing" if randi() % 2 == 0 else "Potion Mana Regeneration"})
	if randi() % 100 < 35:
		var item := _random_gear()
		if not item.is_empty():
			pool.append(item)
	return pool

## Случайное снаряжение «по силе врага» (бюджет = HP × 12), из настоящей базы.
func _random_gear() -> Dictionary:
	var budget := maxi(20, max_hp * 12)
	var pool: Array = []
	for it in ItemDB.all():
		if not ItemDB.is_equippable(it):
			continue
		var p := int(it.get("price", 0))
		if p > 0 and p <= budget:
			pool.append(it)
	if pool.is_empty():
		return {}
	return {"key": str((pool[randi() % pool.size()] as Dictionary).get("key", ""))}
