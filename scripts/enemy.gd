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
var _impact_timer := -1.0            # отсчёт до кадра удара (замах); <0 = нет удара в полёте
var can_flee: bool = false        # по умолчанию монстр дерётся до конца, не убегает
var _path: Array = []             # маршрут к игроку (обход препятствий)
var _repath := 0.0
var _corpse_timer := 0.0          # сколько труп лежит до удаления (без разложения)
var health_bar: HealthBar
var _anim: UnitAnim = null

func _ready():
	add_to_group("enemy")
	Game.configure_unit_body(self)
	# Стартовый разброс репаса: иначе все враги зовут find_path в одном кадре.
	_repath = randf() * 1.2
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
	# P5: далеко от героя — AI спит (контент не трогаем, только CPU).
	if Game.hero != null and is_instance_valid(Game.hero):
		if global_position.distance_squared_to(Game.hero.global_position) > 1600.0 * 1600.0:
			velocity = Vector2.ZERO
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
		velocity = velocity.move_toward(Vector2.ZERO, GameConfig.getf("movement", "decel") * delta)
		move_and_slide()
		_apply_relief_stand()
		return

	# Обновляем бар здоровья
	if health_bar:
		health_bar.update_bars(current_hp)

	# Единая цель боя: игрок (приоритет) или страж города, что в радиусе агро.
	var target: Node2D = _combat_target()
	if target == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	attack_target = target

	var distance_to_target = Game.units_range(self, target)
	var hp_percent = float(current_hp) / max_hp

	match state:
		"idle":
			if distance_to_target < aggro_radius:
				state = "chase"
		"chase":
			if distance_to_target > deaggro_radius:
				state = "idle"
				velocity = Vector2.ZERO
			elif distance_to_target < 40.0:
				state = "attack"
				velocity = Vector2.ZERO   # остановиться и бить, а не проскакивать мимо
			elif hp_percent < 0.15 and can_flee:
				state = "flee"
			else:
				_chase_move(delta, target)
		"attack":
			if distance_to_target > 50.0:
				state = "chase"
				_impact_timer = -1.0
			else:
				# Держим стоп между ударами: без этого инерция от погони
				# несёт монстра мимо игрока — он «бегает вокруг, то туда, то сюда»
				velocity = velocity.move_toward(Vector2.ZERO, GameConfig.getf("movement", "decel") * delta)
				if attack_cooldown <= 0.0 and _impact_timer < 0.0:
					attack_cooldown = GameConfig.getf("combat", "attack_cooldown")
					# Единая точка урона (промах + поглощение бронёй) — на кадре удара,
					# а не в начале замаха: удар звучит по анимации.
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
		"flee":
			var flee_direction = Game.safe_dir(target.global_position, global_position)
			_move_checked(flee_direction, effective_speed() * 1.5, delta)
			if distance_to_target > deaggro_radius * 1.5:
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
				_anim.speed_scale = 1.0
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
## Разгон/торможение - в GameConfig [movement] accel/decel.

## Движение с проверкой проходимости карты (летающие игнорируют землю).
## Как у игрока: полный вектор -> X-only -> Y-only. Иначе, упираясь в стену или
## дерево, враг гасил скорость целиком и «прилипал» — скользить вдоль препятствия
## он не умел вовсе.
func _move_checked(direction: Vector2, speed: float, delta: float) -> void:
	direction = Game.movement_direction(self, direction)
	var wanted := direction * speed
	var step := wanted * delta
	if _can_step(step):
		velocity = velocity.move_toward(wanted, GameConfig.getf("movement", "accel") * delta)
		return
	if delta <= 0.0:
		velocity = Vector2.ZERO
		return
	var slide := Vector2.ZERO
	# Обе оси пробуем всегда, а не «X, иначе Y»: выбор по близости к желаемому
	# направлению (Game.choose_slide) убирает дёрганье у деревьев и углов.
	var slide_axis := Game.choose_slide(direction,
		_can_step(Vector2(step.x, 0.0)), _can_step(Vector2(0.0, step.y)))
	slide = Vector2(slide_axis.x * step.x, slide_axis.y * step.y)
	if slide == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, GameConfig.getf("movement", "decel") * delta)
	else:
		velocity = velocity.move_toward(slide / delta, GameConfig.getf("movement", "accel") * delta)

## Разрешён ли сдвиг: проходимая клетка (летающие игнорируют землю). Выход из
## СВОЕЙ непроходимой клетки разрешаем — иначе враг не сможет выбраться сам.
func _can_step(step: Vector2) -> bool:
	var map_node = get_tree().get_first_node_in_group("alm_map")
	if UnitDB.fly_z(anim_set) > 0 or map_node == null or not map_node.has_method("is_walkable_world"):
		return true
	var next := global_position + step
	return bool(map_node.is_walkable_world(next)) \
		or Vector2i(int(global_position.x) / 32, int(global_position.y) / 32) \
			== Vector2i(int(next.x) / 32, int(next.y) / 32)

## Цель боя: игрок (приоритет; в агро или в погоне — до deaggro) или
## ближайший страж-НПЦ города в радиусе агро.
## Невидимого героя враг «не замечает» дальше 40 px, но видит вплотную.
func _combat_target() -> Node2D:
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		var dp := Game.units_range(self, player)
		var committed := state == "chase" or state == "attack" or state == "flee"
		var lim := deaggro_radius if committed else aggro_radius
		lim *= StatusEffects.vision_mult(self)   # Darkness сужает обзор
		if StatusEffects.is_invisible(player) and not committed:
			lim = 40.0
		if dp < lim:
			return player
	var best: Node2D = null
	var bd := deaggro_radius * StatusEffects.vision_mult(self)
	for n in Game.npcs:
		if n == null or not is_instance_valid(n):
			continue
		if not (n is Npc) or n.role != "guard":
			continue
		if StatusEffects.is_invisible(n):
			continue
		var d := Game.units_range(self, n)
		if d < bd:
			bd = d
			best = n
	return best

## Погоня с обходом препятствий. Перепланировка раз в ~1.2 с + случайный
## старт, чтобы 75 врагов не звали find_path в одном кадре (тормоза).
func _chase_move(delta: float, target: Node2D) -> void:
	var tpos: Vector2 = target.global_position
	var dist := global_position.distance_to(tpos)
	# Дальняя цель — напрямую; путь только когда реально есть препятствия.
	if _path.is_empty() or dist > 400.0:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 1.2 + randf() * 0.6
			var map_node = get_tree().get_first_node_in_group("alm_map")
			if map_node != null and map_node.has_method("find_path") and dist < 500.0:
				_path = map_node.find_path(global_position, tpos)
	if _path.size() > 0:
		var wp: Vector2 = _path[0]
		if global_position.distance_to(wp) <= 8.0:
			_path.pop_front()
		if _path.size() > 0:
			wp = _path[0]
			_move_checked(Game.safe_dir(global_position, wp), effective_speed(), delta)
		else:
			# Путь кончился — идём напрямую к цели (не замираем).
			_move_checked(Game.safe_dir(global_position, tpos), effective_speed(), delta)
	else:
		_move_checked(Game.safe_dir(global_position, tpos), effective_speed(), delta)

## --- Производные характеристики (по данным монстра, как у героя) ---
## Применяются через Game.unit_*: атака->точность, защита->уклонение,
## поглощение->броня, защиты -> защита от стихий (для магии).

func get_attack() -> int:
	return damage / GameConfig.geti("combat", "enemy_attack_dmg_div") \
		+ max_hp / GameConfig.geti("combat", "enemy_attack_hp_div") \
		+ StatusEffects.stat_flat(self, "attack")

func get_defense() -> int:
	var base := max_hp / GameConfig.geti("combat", "enemy_defense_div")
	return int(round((base + StatusEffects.stat_flat(self, "defense")) * StatusEffects.defense_mult(self)))

func get_absorption() -> int:
	return max_hp / GameConfig.geti("combat", "enemy_absorption_div")

## Сопротивление стихии — из данных набора (assets/units/units_db.json, поле
## "resist"). Раньше было max_hp/60, из-за чего босс с большим HP становился
## почти неуязвимым к одной стихии.
func _resist(sphere: String) -> int:
	return UnitDB.resist_of(anim_set, sphere) + StatusEffects.resist_bonus(self, sphere)

func get_protection_fire() -> int:   return _resist("Fire")
func get_protection_water() -> int:  return _resist("Water")
func get_protection_air() -> int:    return _resist("Air")
func get_protection_earth() -> int:  return _resist("Earth")
func get_protection_astral() -> int: return _resist("Astral")

## Скорость с учётом Haste/Slow (move_speed — база, кэшировать нельзя).
func effective_speed() -> float:
	return move_speed * StatusEffects.speed_mult(self)

## Обзор с учётом Darkness (Vision ×0.5 и т.п.).
func effective_sight() -> int:
	return maxi(1, int(get_sight() * StatusEffects.vision_mult(self)))

## Обзор в клетках (влияет на радиус агро — как просили: «обзор -> агро»).
func get_sight() -> int:
	return maxi(1, int(move_speed / 8.0) + max_hp / 60)

## Единая точка входящего урона: вызывается из Game.deal_damage
## (там уже применены промах, поглощение брони и защиты стихий).
## Возвращает фактически снятое HP (после щита) — его рисует Game.deal_damage.
func take_damage(dmg: int, attacker) -> int:
	# Мёртвый монстр (труп/разложение) урона не получает — иначе повторный
	# лут/звуки при махах по трупу
	if state == "dying" or state == "decay" or state == "corpse":
		return 0
	if dmg <= 0:
		return 0
	# Раньше щит на враге не работал: shield_reduce здесь не вызывался
	var shielded := Game.shield_reduce(self, dmg)
	if shielded <= 0:
		SpellVFX.shield_hit(self)
		return 0
	current_hp -= shielded
	# При получении урона — сразу начинаем погоню (но не прерываем текущую атаку,
	# иначе после каждого попадания монстр сбрасывает замах)
	if is_instance_valid(attacker):
		if state != "attack":
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
		# Труп не блокирует движение (жалоба: «спотыкаюсь о лут» — это труп
		# держал collision_layer=1 ещё 5–8 секунд).
		collision_layer = 0
		collision_mask = 0
		if health_bar:
			health_bar.visible = false  # труп не показывает шкалу
	else:
		SoundDB.play_pain(UnitDB.unit_sound(anim_set))  # боль
	return shielded

## Звуковой ID юнита по позиции массива Sound (attack/pain1/pain2/death).
func _unit_sound_at(idx: int) -> int:
	return SoundDB.sound_at(UnitDB.unit_sound(anim_set), idx)

func _drop_loot():
	# Мешок убран (03.10): игрок сразу видит, что именно выпало. Класс переименован
	# loot_bag.gd -> loot_drop.gd, поэтому здесь новый путь и новое имя.
	var drop_script: GDScript = load("res://scripts/loot_drop.gd")
	if drop_script == null:
		return
	var drop: LootDrop = drop_script.new()
	drop.items = _make_loot()
	# Размер баночки зелья по силе врага: труп муравья и труп босса не должны
	# выглядеть одинаково. Пороги те же, что в npc.gd:_potion_size.
	drop.potion_size = "large" if max_hp >= 100 else ("medium" if max_hp >= 55 else "small")
	# Добыча на высоте рельефа (юнит поднят на высоту холма; без этого иконки
	# «тонут» ниже уровня земли на высоту рельефа)
	var h := _relief_here()
	drop.global_position = global_position + Vector2(randf_range(-22, 22), randf_range(-16, 16) - h)
	# Родитель, а не get_tree().current_scene: последний равен null в
	# headless-скриптах и при спавне юнита из теста.
	var host := get_parent()
	if host == null:
		host = get_tree().current_scene
	if host != null:
		host.add_child(drop)

## Высота рельефа под юнитом (0, если карты нет).
func _relief_here() -> float:
	var map_node := get_tree().get_first_node_in_group("alm_map")
	if map_node != null and map_node.has_method("relief_at_world"):
		return float(map_node.call("relief_at_world", global_position))
	return 0.0

## Добыча по семейству юнита (loot_tables.json + units_db.loot_family).
## Звери/насекомые: золото + трава, БЕЗ оружия/брони (решение игрока 07.10).
func _make_loot() -> Array:
	var family := UnitDB.loot_family(anim_set)
	if family == "":
		family = "default"
	var table := _loot_table(family)
	var pool: Array = []
	var gold_mult := float(table.get("gold_mult", 0.6)) * GameConfig.getf("economy", "loot_gold_multiplier")
	var gold_base := 4 + max_hp / 5
	var gold := int(round(float(gold_base + randi() % gold_base) * gold_mult))
	if gold > 0:
		pool.append({"gold": gold})
	if randi() % 100 < int(table.get("potion_chance", 20)):
		pool.append({"key": "Potion Medium Healing" if randi() % 2 == 0 else "Potion Mana Regeneration"})
	if randi() % 100 < int(table.get("gear_chance", 10)):
		var item := _random_gear()
		if not item.is_empty():
			pool.append(item)
	# Босс и дракон с маленьким шансом роняют ЦЕЛУЮ вещь: сломанное
	# роняют NPC (у них есть снаряжение), а из Серых лут и так идёт целым.
	if UnitDB.is_boss(anim_set) \
			and randi() % 100 < GameConfig.geti("craft", "boss_intact_chance"):
		var intact := _random_gear()
		if not intact.is_empty():
			pool.append(intact)
	# Магическая эссенция - второй источник наряду с портной (07.10).
	if randi() % 100 < int(table.get("essence_chance", 0)):
		pool.append({"key": CraftDB.ESSENCE_KEY})
	if randi() % 100 < int(table.get("herb_chance", 0)):
		var herbs: Array = table.get("herbs", [])
		if herbs.size() > 0:
			pool.append({"key": str(herbs[randi() % herbs.size()])})
	return pool


## Таблица лута из assets/config/loot_tables.json (кэш на процесс).
static var _loot_tables_cache: Dictionary = {}
static var _loot_tables_loaded: bool = false


static func _loot_table(family: String) -> Dictionary:
	if not _loot_tables_loaded:
		_loot_tables_loaded = true
		var path := "res://assets/config/loot_tables.json"
		if ResourceLoader.exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_loot_tables_cache = parsed as Dictionary
	var t: Dictionary = _loot_tables_cache.get(family, {})
	if t.is_empty():
		t = _loot_tables_cache.get("default", {})
	return t

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
