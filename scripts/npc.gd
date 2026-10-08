extends CharacterBody2D
class_name Npc
## Мирный житель (НПЦ): гуляет у своей точки, не отвлекается на игрока.
## role "citizen" — стоит на посту (мелкое шевеление); role "guard" —
## патрулирует город (is_patrol) и дерётся с Серыми (монстрами), героя не трогает.

@export var anim_set: String = "ork_mage_a52/t0"
@export var patrol_radius: int = 3           # клеток вокруг точки привязки
@export var walk_speed: float = 45.0
@export var pause_min: float = 1.2
@export var pause_max: float = 4.0
@export var max_hp: int = 30                 # здоровье жителя
@export var role: String = "citizen"         # citizen | guard
@export var is_patrol: bool = false          # патруль вокруг поста (стражи)
@export var damage: int = 0                  # урон стражи (граждане не бьют)
@export var aggro_radius: float = 190.0      # радиус агро стражи на Серых
@export var is_archmage: bool = false        # капитан = великий маг (клик → панель)

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
	_repath = randf() * 1.2
	# Мирные NPC не блокируют путь героя (слой 2). Иначе толпа жителей
	# в центре города превращает ходьбу в рывки: mask=1 у героя и layer=1
	# у NPC делали их физическими стенами.
	if role == "citizen" or is_archmage:
		var body := self as CharacterBody2D
		if body != null:
			body.collision_layer = 2
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
	# P5: далеко от героя — спим (патруль/бой не тикаем).
	if Game.hero != null and is_instance_valid(Game.hero) \
			and state != "dying" and state != "decay" and state != "corpse":
		if global_position.distance_squared_to(Game.hero.global_position) > 1600.0 * 1600.0:
			velocity = Vector2.ZERO
			return
	_apply_relief_stand()

	# Житель умер (его ударили монстры/герой): падение, разложение, исчезновение
	if state == "dying" or state == "decay" or state == "corpse":
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
		# Первый кадр смерти: снимаем коллизию, иначе труп блокирует героя.
		if state == "dying" and collision_layer != 0:
			collision_layer = 0
			collision_mask = 0
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
				_repath = 1.5 + randf() * 1.0
				if alm_map != null and alm_map.has_method("find_path"):
					_path = alm_map.find_path(global_position, _target)
		if not _path.is_empty():
			var wp: Vector2 = _path[0]
			if global_position.distance_to(wp) <= 8.0:
				_path.pop_front()
		if not _path.is_empty():
			_move_checked(Game.safe_dir(global_position, _path[0]), walk_speed, delta)
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
			attack_cooldown = GameConfig.getf("combat", "attack_cooldown")
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

## Погоня за Серыми. Перепланировка ~1.2 с + случайный старт (не в одном кадре).
func _chase_move(delta: float, target: Node2D) -> void:
	var tpos: Vector2 = target.global_position
	var dist := global_position.distance_to(tpos)
	if _path.is_empty() or dist > 400.0:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 1.2 + randf() * 0.6
			if alm_map != null and alm_map.has_method("find_path") and dist < 500.0:
				_path = alm_map.find_path(global_position, tpos)
	if _path.size() > 0:
		var wp: Vector2 = _path[0]
		if global_position.distance_to(wp) <= 8.0:
			_path.pop_front()
		if _path.size() > 0:
			wp = _path[0]
			_move_checked(Game.safe_dir(global_position, wp), walk_speed, delta)
			_anim.play(UnitAnim.Anim.MOVE)
			_anim.set_direction_vec(velocity)
			_anim.advance(delta)
		else:
			_move_checked(Game.safe_dir(global_position, tpos), walk_speed, delta)
			_anim.play(UnitAnim.Anim.MOVE)
			_anim.set_direction_vec(velocity)
			_anim.advance(delta)
	else:
		_move_checked(Game.safe_dir(global_position, tpos), walk_speed, delta)
		_anim.play(UnitAnim.Anim.MOVE)
		_anim.set_direction_vec(velocity)
		_anim.advance(delta)

## Звуковой ID юнита по позиции массива Sound (attack/pain1/pain2/death).
func _unit_sound_at(idx: int) -> int:
	return SoundDB.sound_at(UnitDB.unit_sound(anim_set), idx)

## --- Статы (для Game.unit_*: атака->точность, защита->уклонение) ---
func get_attack() -> int:
	return damage / GameConfig.geti("combat", "enemy_attack_dmg_div") \
		+ max_hp / GameConfig.geti("combat", "enemy_attack_hp_div") \
		+ StatusEffects.stat_flat(self, "attack")

func get_defense() -> int:
	var base := max_hp / GameConfig.geti("combat", "enemy_defense_div")
	return int(round((base + StatusEffects.stat_flat(self, "defense")) * StatusEffects.defense_mult(self)))

func get_absorption() -> int:
	return max_hp / GameConfig.geti("combat", "enemy_absorption_div")

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
	_drop_loot()
	state = "dying"
	velocity = Vector2.ZERO
	Game.npcs.erase(self)
	return dmg


## Лут с NPC. Раньше NPC не роняли ничего: лут был только у врагов, поэтому
## убийство горожанина или стража не давало ничего. Содержимое зависит от роли:
## страж - в латах (steel), горожанин - попроще (bronze).
##
## Размер баночки зелья зависит от силы врага: max_hp у жителей 30, у стражей
## больше, поэтому сильный страж роняет большую баночку. Правило общее с
## enemy.gd:_make_loot, чтобы лут читался одинаково.
func _drop_loot() -> void:
	# Мешок убран (03.10): игрок сразу видит, что именно выпало.
	var drop_script: GDScript = load("res://scripts/loot_drop.gd")
	if drop_script == null:
		return
	var pool: Array = []
	var gold_base := 3 + maxi(1, max_hp / 8)
	var gold_mult := GameConfig.getf("economy", "loot_gold_multiplier")
	pool.append({"gold": int(round(float(gold_base + randi() % maxi(1, gold_base)) * gold_mult))})
	# жители щедры на зелья, стражей - реже: они вооружены
	var potion_chance := GameConfig.geti("loot", "npc_citizen_potion_chance") if role == "citizen" \
		else GameConfig.geti("loot", "npc_guard_potion_chance")
	if randi() % 100 < potion_chance:
		var potion := "Potion Medium Healing" if randi() % 2 == 0 \
			else "Potion Medium Mana"
		if not ItemDB.find(potion).is_empty():
			pool.append({"key": potion})
	# Снаряжение: страж и горожанин роняют его ВСЕГДА (шанс снят 07.10).
	#
	# С 07.10 NPC роняет СЛОМАННУЮ вещь, а не целую: металл в игре появляется
	# только так (убил НПЦ -> переплавка -> слиток -> рецепт). Целую вещь
	# роняют БОССЫ и драконы - с маленьким шансом, [craft] boss_intact_chance.
	var gear := _random_gear()
	if not gear.is_empty():
		pool.append(gear)
	var drop: LootDrop = drop_script.new()
	drop.items = pool
	drop.potion_size = _potion_size()
	drop.global_position = global_position
	# Родитель, а не get_tree().current_scene: current_scene равен null в
	# headless-скриптах и при добавлении узла из теста, добыча просто не появлялась.
	# Родитель всегда есть и в том, и в другом случае.
	var host := get_parent()
	if host == null:
		host = get_tree().current_scene
	if host != null:
		host.add_child(drop)


## Случайная СЛОМАННАЯ вещь.
##
## Категория зависит от роли: страж носит броню и оружие, горожанин - одежду
## мага. Это не украшение: кузнец перерабатывает броню и оружие в слитки,
## портной - одежду в ткань и эссенцию. Если бы все роняли одно и то же,
## одна из профессий осталась бы без сырья.
##
## Качество сломанной вещи выбирается весом: обычный мусор падает чаще
## добротного, а редкий почти не встречается. Порядок - от обычного к
## редкому, иначе случайный выбор дал бы «редкий» в третьих случаях.
func _random_gear() -> Dictionary:
	var categories := ["Armor", "Weapon"] if role == "guard" else ["Garment"]
	var material := _gear_material()
	var category: String = categories[randi() % categories.size()]
	var quality := _roll_broken_quality()
	var key := ItemDB.broken_key(material, category, quality)
	if key == "" and ItemDB.has_broken(material, category):
		# Записи этого качества нет - берём любое, что есть.
		for q in ItemDB.BROKEN_QUALITIES:
			key = ItemDB.broken_key(material, category, q)
			if key != "":
				break
	if key == "":
		return {}
	return {"key": key}


## Металл сломанной вещи по роли. Страж - сталь, горожанин - бронза (то же,
## что и до 07.10 в _random_gear).
func _gear_material() -> String:
	return "steel" if role == "guard" else "bronze"


## Взвешенный выбор качества сломанной вещи: 60 / 25 / 15.
func _roll_broken_quality() -> String:
	var roll := randi() % 100
	if roll < 60:
		return "Broken"
	if roll < 85:
		return "Broken Fine"
	return "Broken Rare"


func _potion_size() -> String:
	## small/medium/large по силе юнита. Пороги взяты по реальным max_hp:
	## горожане 30, стражь ~60-120, элитные твари выше.
	if max_hp >= 100:
		return "large"
	if max_hp >= 55:
		return "medium"
	return "small"


## Старый выбор ЦЕЛОГО снаряжения по бюджету. С 07.10 не используется:
## NPC роняют сломанные вещи (_random_gear без аргументов), а целое
## снаряжение осталось только у боссов в enemy.gd. Удаление функции - отдельная
## задача: сначала убедиться, что на неё не ссылается ни один тест.
func _random_intact_gear(mat: String) -> Dictionary:
	var budget := maxi(15, max_hp * 6)
	var pool: Array = []
	for it in ItemDB.all():
		var d: Dictionary = it
		if not ItemDB.is_equippable(d):
			continue
		if str(d.get("material", "")) != mat:
			continue
		var p := int(d.get("price", 0))
		if p > 0 and p <= budget:
			pool.append(d)
	if pool.is_empty():
		return {}
	return {"key": str((pool[randi() % pool.size()] as Dictionary).get("key", ""))}

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
	var step := wanted * delta
	var can_step := true
	var can_x := false
	var can_y := false
	if alm_map != null and alm_map.has_method("is_walkable_world"):
		# Разрешаем шаг внутри СВОЕЙ непроходимой клетки (выход из застревания)
		var here := Vector2i(int(global_position.x) / 32, int(global_position.y) / 32)
		can_step = alm_map.is_walkable_world(global_position + step) \
			or here == Vector2i(int((global_position.x + step.x) / 32),
				int((global_position.y + step.y) / 32))
		if can_step:
			velocity = velocity.move_toward(wanted, 1100.0 * delta)
			return
		can_x = alm_map.is_walkable_world(global_position + Vector2(step.x, 0.0)) \
			or here == Vector2i(int((global_position.x + step.x) / 32), int(global_position.y / 32))
		can_y = alm_map.is_walkable_world(global_position + Vector2(0.0, step.y)) \
			or here == Vector2i(int(global_position.x / 32), int((global_position.y + step.y) / 32))
		# Скольжение по ближайшей к движению оси. Раньше его не было вовсе:
		# страж, упёршийся в угол, просто останавливался, и патруль мог
		# зависнуть на месте.
		var axis := Game.choose_slide(direction, can_x, can_y)
		if axis != Vector2.ZERO:
			var slide := Vector2(axis.x * step.x, axis.y * step.y)
			velocity = velocity.move_toward(slide / maxf(delta, 0.0001), 1100.0 * delta)
			return
	if can_step:
		velocity = velocity.move_toward(wanted, 1100.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)