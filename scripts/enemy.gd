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
var can_flee: bool = false        # по умолчанию монстр дерётся до конца, не убегает
var _path: Array = []             # маршрут к игроку (обход препятствий)
var _repath := 0.0
var _corpse_timer := 0.0          # сколько труп лежит до удаления (без разложения)
var health_bar: HealthBar
var _anim: UnitAnim = null

func _ready():
	add_to_group("enemy")
	collision_mask = 0   # юниты не толкают друг друга физикой
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

	# Монстр умер — играем анимацию падения, потом труп остаётся на земле
	if state == "dying" or state == "decay" or state == "corpse":
		if _anim:
			match state:
				"dying":
					_anim.play(UnitAnim.Anim.DYING)
					if _anim.advance(delta):
						velocity = Vector2.ZERO
						if UnitDB.decay_phases(anim_set) > 0:
							state = "decay"          # есть разложение (скелет)
							_anim.play(UnitAnim.Anim.DECAY)
						else:
							state = "corpse"
							_anim.freeze_last_frame(UnitAnim.Anim.DYING)
							_corpse_timer = 5.0      # труп лежит 5 сек, потом исчезает
				"decay":
					if _anim.advance(delta):
						_corpse_timer = 3.0         # разложился — ещё немного лежит
						state = "corpse"
						_anim.freeze_last_frame(UnitAnim.Anim.DECAY)
				"corpse":
					if _corpse_timer > 0.0:
						_corpse_timer -= delta
						if _corpse_timer <= 0.0:
							queue_free()
							return
		velocity = velocity.move_toward(Vector2.ZERO, MOVE_DECEL * delta)
		move_and_slide()
		_apply_relief_stand()
		return

	# Обновляем бар здоровья
	if health_bar:
		health_bar.update_bars(current_hp)

	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance_to_player = Game.units_range(self, player)
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
				velocity = Vector2.ZERO   # остановиться и бить, а не проскакивать мимо
			elif hp_percent < 0.15 and can_flee:
				state = "flee"
			else:
				_chase_move(delta)
		"attack":
			if distance_to_player > 50.0:
				state = "chase"
			else:
				# Держим стоп между ударами: без этого инерция от погони
				# несёт монстра мимо игрока — он «бегает вокруг, то туда, то сюда»
				velocity = velocity.move_toward(Vector2.ZERO, MOVE_DECEL * delta)
				if attack_cooldown <= 0:
					player.take_damage(damage, self)
					attack_cooldown = 1.0
					SoundDB.play(_unit_sound_at(0))
		"flee":
			var flee_direction = (global_position - player.global_position).normalized()
			_move_checked(flee_direction, move_speed * 1.5, delta)
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
		health_bar.position.y = -(h + z + _anim.sprite_height() + 6.0)  # над головой

# --- Физика движения (плавный разгон/торможение + проходимость) ---
const MOVE_ACCEL := 1100.0
const MOVE_DECEL := 1800.0

## Движение с проверкой проходимости карты (летающие игнорируют землю).
func _move_checked(direction: Vector2, speed: float, delta: float) -> void:
	var wanted := direction * speed
	var next := global_position + wanted * delta
	var can_step := true
	var map_node = get_tree().get_first_node_in_group("alm_map")
	if UnitDB.fly_z(anim_set) <= 0 and map_node != null and map_node.has_method("is_walkable_world"):
		# Разрешаем шаг внутри СВОЕЙ непроходимой клетки (выход из застревания)
		can_step = map_node.is_walkable_world(next) \
			or Vector2i(int(global_position.x) / 32, int(global_position.y) / 32) \
				== Vector2i(int(next.x) / 32, int(next.y) / 32)
	if can_step:
		velocity = velocity.move_toward(wanted, MOVE_ACCEL * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, MOVE_DECEL * delta)

## Погоня с обходом препятствий (как у героя): перепланировка пути раз в 0.7 с.
func _chase_move(delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p):
		return
	var target: Vector2 = p.global_position
	if _path.is_empty():
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.7
			var map_node = get_tree().get_first_node_in_group("alm_map")
			if map_node != null and map_node.has_method("find_path"):
				_path = map_node.find_path(global_position, target)
	if _path.size() > 0:
		var wp: Vector2 = _path[0]
		if global_position.distance_to(wp) <= 8.0:
			_path.pop_front()
		if _path.size() > 0:
			wp = _path[0]
			_move_checked((wp - global_position).normalized(), move_speed, delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, MOVE_DECEL * delta)
	else:
		_move_checked((target - global_position).normalized(), move_speed, delta)

func take_damage(dmg: int, attacker: Node2D):
	# Труп не получает урон: иначе на каждый удар по телу падает новый мешок
	if state == "dying" or state == "decay" or state == "corpse":
		return
	current_hp -= dmg
	# При получении урона — сразу начинаем погоню
	if is_instance_valid(attacker):
		state = "chase"
		attack_target = attacker
	if current_hp <= 0:
		SoundDB.play(_unit_sound_at(4))  # смерть
		# Убираем из списка врагов: герой перестаёт выбирать труп целью
		Game.enemies.erase(self)
		_drop_loot()
		state = "dying"
		attack_target = null
		velocity = Vector2.ZERO
		if health_bar:
			health_bar.visible = false  # труп не показывает шкалу
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
	# Мешок на высоте рельефа (юнит поднят на высоту холма; без этого мешок
	# «тонет» ниже уровня земли на высоту рельефа)
	var h := _relief_here()
	bag.global_position = global_position + Vector2(randf_range(-22, 22), randf_range(-16, 16) - h)
	get_tree().current_scene.add_child(bag)

## Высота рельефа под юнитом (0, если карты нет).
func _relief_here() -> float:
	var map_node := get_tree().get_first_node_in_group("alm_map")
	if map_node != null and map_node.has_method("relief_at_world"):
		return float(map_node.call("relief_at_world", global_position))
	return 0.0

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
