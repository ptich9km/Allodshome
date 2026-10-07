extends Node2D
class_name Game

@onready var alm_map: Node2D = $Map
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var ui: CanvasLayer = $UI

## Единое направление между двумя точками. Vector2.normalized() на НУЛЕВОМ векторе
## (юнит стоит ровно на вейпоинте) печатает в консоль C++-предупреждение
## «Vector2 cannot be normalized, the elements must be finite», поэтому нормализуем
## только вектор длиной больше порога.
static func safe_dir(from: Vector2, to: Vector2, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var d := to - from
	if d.length_squared() < 0.0001:
		return fallback
	return d.normalized()

## Разрешён ли шаг юнита по карте (общая проходимость для игрока и NPC).
static var is_paused: bool = false
static var player_target: Vector2 = Vector2.ZERO
static var enemies: Array = []
static var npcs: Array = []               # мирные жители (Npc) вне Game.enemies
static var hero: Node2D = null            # игрок (для наёмников/лута)
static var party: Array = []              # наёмники (Mercenary) из таверны
static var mana_regen_accum: float = 0.0
static var _trauma: float = 0.0
static var _trauma_t: float = 0.0
static var action_mode: String = "none"  # none, follow, attack, guard
static var action_target: Node2D = null
static var pending_scroll: Dictionary = {}   # прицеливание свитка: {"spell","item_key"}
static var pending_spell: Dictionary = {}    # выбор заклинания из книги: {"name"}
static var hotbar: Dictionary = {}           # быстрый вызов: слот 0..8 (клавиши 1..9) -> имя заклинания
## Авто-каст мага (пакет C, 07.10): ПКМ по заклинанию в книге.
## auto_spell — имя заклинания по умолчанию (обычно Heal).
## auto_heal_targets: ally | party | neutral.
## auto_buff_tier: none | light (Haste) | medium (Haste+Bless+резисты) | advanced (+Invis).
static var auto_spell: String = ""
static var auto_heal_targets: String = "party"
static var auto_buff_tier: String = "none"
static var auto_buff_targets: String = "party"
static var _spell_targeting_frame: int = -1  # кадр, когда начато прицеливание (защита от двойного каста)
## Отладочные переключатели. Источник правды — game.cfg [debug], чтобы не
## править код ради каждой отладки. Значение читается ОДИН раз при старте;
## тесты и дебаг присваивают переменную напрямую как раньше (перекрытие).
static var debug_magic: bool = GameConfig.geti("debug", "all_magic") != 0

# --- Защитные баффы (книги/свитки защиты, Shield): уменьшение входящего урона ---
static func apply_shield(unit: Node2D, strength: int, seconds: float) -> void:
	if not is_instance_valid(unit):
		return
	unit.set_meta("shield_strength", int(unit.get_meta("shield_strength", 0)) + strength)
	unit.set_meta("shield_time", float(unit.get_meta("shield_time", 0.0)) + seconds)

static func shield_reduce(unit: Node2D, dmg: int) -> int:
	if not is_instance_valid(unit):
		return dmg
	var strength := int(unit.get_meta("shield_strength", 0))
	if strength <= 0:
		return dmg
	unit.set_meta("shield_strength", strength - dmg)
	var out := maxi(0, dmg - strength)
	if out == 0:
		print("%s: щит поглотил весь урон!" % unit.name)
	return out

## --- Общая математика боя: характеристики -> шанс/урон (для ЛЮБОГО юнита) ---

## Шанс попадания, % — ОТНОСИТЕЛЬНАЯ формула.
##
## Раньше было `50 + атака − защита` (кламп 5..95). Это абсолютная разность, и
## она ломалась, как только в бой включилась экипировка: тяжёлая броня даёт
## defence 14, щит ещё 4, и герой с бронёй держал 50 + 8 − 23 = 35 %, а гоблин
## с атакой 4 — 5 % (нижний кламп). Вся броня мира упиралась в пол, и
## «статы экипировки не работают» выглядело как «работает, но незаметно».
##
## Теперь шанс — отношение силы атаки к силе защиты, поэтому одинаково
## работает и для гоблина (атака 4), и для тролля (атака 30), и для брони.
##   равные статы            -> BASE (70 %)
##   защита вдвое выше       -> примерно вдвое ниже
##   атака вдвое выше        -> упёрётся в MAX
## Константы комбат-формул перенесены в GameConfig (assets/config/game.cfg),
## чтобы их можно было крутить без правки кода. Значения по умолчанию равны
## прежним константам, поэтому поведение игры не меняется.
static func hit_chance(attack: int, defense: int) -> int:
	var soften := GameConfig.geti("combat", "hit_soften")
	var a := float(attack) + soften
	var d := float(defense) + soften
	if d <= 0.0:
		return GameConfig.geti("combat", "hit_max")
	return clampi(int(round(float(GameConfig.geti("combat", "hit_base")) * a / d)),
		GameConfig.geti("combat", "hit_min"), GameConfig.geti("combat", "hit_max"))

## Промах? Юниты с методами get_attack()/get_defense() участвуют полностью.
static func is_miss(attacker: Node2D, defender: Node2D) -> bool:
	var atk := 0
	var dfs := 0
	if attacker != null and attacker.has_method("get_attack"):
		atk = int(attacker.call("get_attack"))
	if defender != null and defender.has_method("get_defense"):
		dfs = int(defender.call("get_defense"))
	return randi() % 100 >= hit_chance(atk, dfs)

## Точность юнита (если есть метод — иначе 0).
static func unit_attack(u: Node2D) -> int:
	return int(u.call("get_attack")) if u != null and u.has_method("get_attack") else 0

## Защита юнита (уклонение/броня).
static func unit_defense(u: Node2D) -> int:
	return int(u.call("get_defense")) if u != null and u.has_method("get_defense") else 0

## Поглощение (материал/броня): get_absorption() — есть у героя и врагов.
static func unit_absorption(u: Node2D) -> int:
	return int(u.call("get_absorption")) if u != null and u.has_method("get_absorption") else 0

## Сопротивление стихии в ПРОЦЕНТАХ: сколько процентов магического урона
## не пройдёт. Так в оригинале (main.txt: «shows the percentage of the
## magical effects… which will not affect the character») и это не ломается
## от больших чисел, в отличие от плоского вычитания.
static func unit_protection(u: Node2D, sphere: String) -> int:
	if u == null or sphere == "":
		return 0
	var m := "get_protection_%s" % sphere.to_lower()
	if u.has_method(m):
		return clampi(int(u.call(m)), 0, GameConfig.geti("combat", "protection_max"))
	return 0

## --- Сила магии: ОДИН стат на урон, лечение, щит и вампиризм ---
## Формула оригинала (Allods II): SP = навык сферы + разум - 30.
## Кламп в ноль обязателен: при навыке 5 и разуме 9 выходит -16, а оригинал
## на таких значениях ломается (SP>255 — баг переполнения байта).
static func spell_power(caster: Node2D, sphere: String) -> float:
	if caster == null or not is_instance_valid(caster):
		return 0.0
	var mind := 0.0
	if "mind" in caster:
		mind = float(caster.get("mind"))
	var skill := 0.0
	if caster.has_method("sphere_skill"):
		skill = float(caster.call("sphere_skill", sphere))
	return maxf(0.0, skill + mind - GameConfig.getf("magic", "sp_offset")) + float(StatusEffects.stat_flat(caster, "power"))


## Порог силы магии: SP = навык сферы + разум - offset.
## offset лежит в GameConfig: [magic] sp_offset.
##
## В оригинале Allods II здесь стоит 30, и константа верная ДЛЯ ОРИГИНАЛЬНЫХ
## статов: у мага 6-го уровня разум ~84. Наши статы в 7–10 раз меньше
## (маг на старте mind = 13, навык сферы = 5), и при смещении 30 получалось
## 5 + 13 - 30 = -12, то есть SP ноль на всю раннюю игру: заклинания не
## росли с уровнем вообще, и Fire_Ball (база 26) бил ровно базой. Это подтвердил
## ручной аудит.
## Смещение 15 выбрано игроком: на старте мага SP = 3, при прокачке навыка
## сферы 5 -> 15 получаем SP = 13 (+13 % урона), к 30 — SP = 28. Форма
## оригинала сохранена, масштаб приведён к нашим числам.
## Урон заклинания с учётом силы кастера и множителя заклинания.
## final = base * power_coef * (1 + spell_power/100)
static func spell_damage(caster: Node2D, spell_name: String, sphere: String, base_damage: int) -> int:
	var coef := SpellDB.power_coef_of(spell_name)
	var power := spell_power(caster, sphere)
	var raw := float(base_damage) * coef * (1.0 + power / 100.0)
	return maxi(SpellDB.min_damage_of(spell_name), int(round(raw)))


## ЕДИНАЯ точка урона: физика -> поглощение; магия -> защиты стихий; далее щит и HP.
## Возвращает фактически нанесённый урон (0 — если всё поглощён/промах).
static func deal_damage(target: Node2D, dmg: int, kind: String, sphere: String, attacker: Node2D) -> int:
	if not is_instance_valid(target) or dmg <= 0:
		return 0
	# Глобальный множитель урона - главный рычаг баланса (идея из AION).
	# Применяется здесь, в ЕДИНОЙ точке урона, поэтому множитель одинаков
	# для ближнего боя, магии, снарядов и AoE.
	var final := int(round(float(dmg) * GameConfig.getf("combat", "damage_multiplier")))
	if kind == "magic":
		# Сопротивление — процент от урона (как в оригинале)
		var prot := unit_protection(target, sphere)
		final = maxi(0, int(round(float(dmg) * (1.0 - float(prot) / 100.0))))
	else:
		final = maxi(0, final - unit_absorption(target))
	if final <= 0:
		# Полное поглощение ДО take_damage. Причина важна игроку: «стойкость» —
		# защита стихии, «броня» — физический удар. Раньше обе подписи были
		# «щит», и щит тут ни при чём (щиты считаются внутри take_damage).
		DamageNumber.show_at(target.global_position, 0,
			"resist" if kind == "magic" else "armor")
		return 0
	var dealt := 0
	if target.has_method("take_damage"):
		dealt = target.call("take_damage", final, attacker)
	# take_damage вернул 0 — урон съел ЩИТ внутри юнита. Показывать полное
	# число было прямой ложью: игрок видел «40» там, где не пришлось ни одного
	# урона. Теперь показываем, что удар дошёл, но его закрыл щит.
	if not (dealt is int) or int(dealt) <= 0:
		DamageNumber.show_at(target.global_position, 0, "absorb")
		return 0
	final = int(dealt)
	# Единственное место, где рисуется урон: иначе числа дублировались
	# в projectile.gd и enemy.gd, и показывали сырое, а не фактическое значение.
	DamageNumber.show_at(target.global_position, final, "damage")
	SpellVFX.hit_flash(target)
	if kind == "magic" and is_instance_valid(attacker):
		_apply_vampirism(attacker, final)
	return final


## Вампиризм (Drain_Life): часть нанесённого магией урона возвращается кастеру.
static func _apply_vampirism(caster: Node2D, dealt: int) -> void:
	var ratio := StatusEffects.vampirism_ratio(caster)
	if ratio <= 0.0 or dealt <= 0:
		return
	var amount := maxi(1, int(float(dealt) * ratio))
	if caster.has_method("heal_amount"):
		caster.call("heal_amount", amount)


## Нанести урон всем целям в радиусе (для областных заклинаний/взрывов).
static func deal_damage_area(targets: Array, dmg: int, kind: String, sphere: String, attacker: Node2D) -> void:
	for t in targets:
		if is_instance_valid(t):
			deal_damage(t, dmg, kind, sphere, attacker)

static func tick_shields(delta: float) -> void:
	var units: Array = [Game.hero]
	units.append_array(Game.enemies)
	units.append_array(Game.npcs)
	units.append_array(Game.party)
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		if not u.has_meta("shield_time"):
			continue
		var t := float(u.get_meta("shield_time", 0.0)) - delta
		if t > 0.0:
			u.set_meta("shield_time", t)
		else:
			u.set_meta("shield_time", 0.0)
			u.set_meta("shield_strength", 0)

static func configure_unit_body(unit: Node2D, radius: float = 12.0) -> void:
	if not (unit is CharacterBody2D):
		return
	var body := unit as CharacterBody2D
	# Слой 1 = стены/здания/боевые юниты. Маска 1 = чувствуем layer 1.
	# Мирные NPC (жители, маг города) после этого вызова переезжают на слой 2 —
	# герой через них ходит, иначе в городе 30+ NPC «упираются» в толпу.
	body.collision_layer = 1
	body.collision_mask = 1
	# motion_mode НЕ трогаем: в top-down интуитивно хочется MOTION_MODE_FLOATING,
	# но это проверено и отвергнуто — на dev-карте герой застревал в кармане между
	# двумя препятствиями (fuzz_edge: 1 застревание из 62 вместо 0), потому что
	# в GROUNDED скользящая поверхность классифицируется как «пол» и выталкивает
	# героя из узкого места, а в FLOATING любая коллизия — глухая стена.
	# Настоящая причина «езды по рельсам» была не в этом, а в гашении скорости
	# целиком — починено раздельным скольжением по осям в player/enemy.
	var shape_node: CollisionShape2D = null
	for child in body.get_children():
		if child is CollisionShape2D:
			shape_node = child as CollisionShape2D
			break
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "Collision"
		body.add_child(shape_node)
	if shape_node.shape == null:
		var shape := CircleShape2D.new()
		shape.radius = radius
		shape_node.shape = shape

## Разделение юнитов, чтобы не слипались. Раньше здесь каждый кадр
## аллоцировал Array из ВСЕХ юнитов и мерил дистанцию до каждого —
## на 75 врагах это O(n²) в физике. Теперь: буфер без аллокации,
## ранний выход, мирные NPC (слой 2) не толкают друг друга.
const SEP_DIST := 24.0
const SEP_DIST_SQ := SEP_DIST * SEP_DIST
const SEP_SKIP_SQ := 40.0 * 40.0
static var _sep_acc := Vector2.ZERO
## P4: пространственная сетка для separation — раз в кадр строим вёдра 64px,
## ищем только соседей. Без этого NPC×2 снова даст O(n²) в физике.
const SEP_GRID_CELL := 64.0
static var _sep_grid: Dictionary = {}
static var _sep_grid_frame: int = -1


static func _sep_bucket_key(pos: Vector2) -> String:
	return "%d,%d" % [int(floor(pos.x / SEP_GRID_CELL)), int(floor(pos.y / SEP_GRID_CELL))]


static func _sep_insert(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var key := _sep_bucket_key(unit.global_position)
	var arr: Array = _sep_grid.get(key, [])
	arr.append(unit)
	_sep_grid[key] = arr


static func _sep_rebuild_grid() -> void:
	var f := Engine.get_physics_frames()
	if f == _sep_grid_frame:
		return
	_sep_grid_frame = f
	_sep_grid.clear()
	if is_instance_valid(Game.hero):
		_sep_insert(Game.hero)
	for other in Game.enemies:
		_sep_insert(other)
	for other in Game.npcs:
		_sep_insert(other)
	for other in Game.party:
		_sep_insert(other)


static func _sep_neighbors(pos: Vector2) -> Array:
	var out: Array = []
	var cx := int(floor(pos.x / SEP_GRID_CELL))
	var cy := int(floor(pos.y / SEP_GRID_CELL))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key := "%d,%d" % [cx + dx, cy + dy]
			var arr: Array = _sep_grid.get(key, [])
			for u in arr:
				out.append(u)
	return out


static func movement_direction(unit: Node2D, desired: Vector2) -> Vector2:
	if desired.length_squared() <= 0.0001:
		return Vector2.ZERO
	_sep_acc = Vector2.ZERO
	var my_pos: Vector2 = unit.global_position
	var my_layer: int = 1
	if unit is CollisionObject2D:
		my_layer = (unit as CollisionObject2D).collision_layer
	_sep_rebuild_grid()
	var found := 0
	for other in _sep_neighbors(my_pos):
		if found >= 6:
			break
		if other == unit or not is_instance_valid(other):
			continue
		found += _sep_push(my_pos, my_layer, other)
	var separation := _sep_acc
	var result := desired.normalized() + separation * 1.5
	return result.normalized() if result.length_squared() > 0.0001 else desired.normalized()


## Один юнит: если рядом — добавить вклад в _sep_acc. Возвращает 0/1.
static func _sep_push(my_pos: Vector2, my_layer: int, other: Node) -> int:
	if other == null or not is_instance_valid(other) or not (other is Node2D):
		return 0
	if other is CollisionObject2D and my_layer == 2 \
			and (other as CollisionObject2D).collision_layer == 2:
		return 0
	var opos: Vector2 = (other as Node2D).global_position
	var dx := my_pos.x - opos.x
	var dy := my_pos.y - opos.y
	var dist_sq := dx * dx + dy * dy
	if dist_sq > SEP_SKIP_SQ or dist_sq < 0.01:
		return 0
	var distance := sqrt(dist_sq)
	if distance >= SEP_DIST:
		return 0
	var w := (SEP_DIST - distance) / SEP_DIST
	_sep_acc.x += dx / distance * w
	_sep_acc.y += dy / distance * w
	return 1


## Лучшее скольжение, когда полный шаг заблокирован.
##
## Зачем. Раньше одно и то же было продублировано в трёх местах, и все три
## варианта выбирали ось ПО ПОРЯДКУ (`if can_x ... elif can_y ...`), а не по
## близости к направлению движения. При перекрытом диагональном шаге (дерево,
## угол здания) юнит шёл строго по X, даже если «правильным» было Y. Звери у
## деревьев дёргались лошадью: шаг в диагональ превращался в шаг по одной оси.
## Замер 03.10 показал, что при свободном движении по диагонали 179 кадров
## из 179 были диагональными (угол 0.998) — то есть ломало именно СКОЛЬЖЕНИЕ,
## а не сама походка.
##
## Возвращает единичную ось (или ZERO, если нельзя ни туда, ни сюда).
static func choose_slide(desired: Vector2, can_x: bool, can_y: bool) -> Vector2:
	if can_x and can_y:
		# Обе свободны — берём ту, что вносит большую часть движения.
		var wx := absf(desired.x)
		var wy := absf(desired.y)
		var total := wx + wy
		if total <= 0.0:
			return Vector2.ZERO
		return Vector2(signf(desired.x), 0.0) if wx >= wy else Vector2(0.0, signf(desired.y))
	if can_x:
		return Vector2(signf(desired.x), 0.0)
	if can_y:
		return Vector2(0.0, signf(desired.y))
	return Vector2.ZERO

var _select_ring: SelectRing = null       # подсветка цели (ховер/атака)
var _pending_building := ""               # здание, к которому герой подходит («вход»)
var _pending_s: Dictionary = {}           # структура-цель ожидающего входа
var _pending_herb: HerbNode = null
var _pending_archmage: Node2D = null      # капитан-маг, к которому подходим
var _save_menu: SaveMenu = null
var _autosave_accum: float = 0.0
## Интервал автосейва. 60 с - компромисс: чаще - лишний ввод-вывод, реже -
## можно потерять минуты прогресса при аварии. Первый автосейв приходит
## через 60 с после старта, а не сразу, поэтому отдельного "минимального
## времени" не нужно.
const AUTOSAVE_INTERVAL := 60.0

## Интервал автосейва — из конфига [autosave] interval. Константа выше
## осталась как запасное значение и как перекрытие для тестов.
static func autosave_interval() -> float:
	var v := GameConfig.getf("autosave", "interval")
	return AUTOSAVE_INTERVAL if v <= 0.0 else v

# --- Выбор героя на старте (сцена character_select) ---
static var hero_class: String = "warrior"   # warrior | mage
static var hero_gender: String = "male"     # male | female
static var hero_name: String = "Герой"
static var hero_character_id: String = "human_m_war"  # id портрета расы
static var hero_portrait: String = ""       # res:// путь к портрету
static var hero_race: String = "human"      # human | necro | druid | ork
static var hero_stats: Dictionary = {}      # стартовые характеристики
static var hero_start_book: String = ""     # книга простейшего заклинания школы мага

## Позиция героя из сохранения. Кладёт SaveSystem.apply_payload; применяет
## _spawn_player_on_walkable после пересборки сцены (иначе герой всегда на спавне).
static var load_position: Vector2 = Vector2.ZERO
static var load_position_valid: bool = false

## Runtime-состояние героя из сейва (gold/inventory/equipped/HP/spells/...).
## change_scene пересоздаёт Player, и _ready выдавал стартовый набор —
## золото и инвентарь «терялись», хотя лежали в файле. Пустой словарь =
## новая игра (стартовый gold/starter set).
static var hero_save: Dictionary = {}

static func clear_load_position() -> void:
	load_position = Vector2.ZERO
	load_position_valid = false


static func clear_hero_save() -> void:
	hero_save = {}

## Путь портрета: явный hero_portrait или сборка из character_id (с легаси-маппингом).
static func hero_portrait_path() -> String:
	if hero_portrait != "" and ResourceLoader.exists(hero_portrait):
		return hero_portrait
	var cid := hero_character_id
	var legacy := {
		"mfighter": "human_m_war", "ffighter": "human_f_war",
		"mmage": "human_m_mage", "fmage": "human_f_mage",
	}
	if legacy.has(cid):
		cid = str(legacy[cid])
	return "res://assets/hero_portraits/%s.png" % cid

# --- Выбор карты ---
## Явно запрошенный путь к .alm. Не пусто только когда путь задан вручную:
## редактор карт (F9 «Назад в игру») или загрузка сохранения. Имеет приоритет над сидом.
static var pending_map_path: String = ""
## Сид карты новой игры. 0 = карта не запрошена, AlmMap берёт запасной путь из main.tscn
## (детерминированный dev-режим и автотесты — им случайная карта мешала бы).
static var map_seed: int = 0
static var map_zone: String = "mid"   # start | mid | hard | faction

## Новая карта со случайным сидом. Вызывается из character_select перед стартом.
static func new_random_map(zone: String = "mid") -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	map_seed = rng.randi()
	map_zone = zone
	pending_map_path = ""
	clear_load_position()
	clear_hero_save()

## Конкретная карта по сиду (загрузка сохранения, тесты).
static func request_map_by_seed(seed_value: int, zone: String = "mid") -> void:
	map_seed = seed_value
	map_zone = zone
	pending_map_path = ""
	clear_load_position()
	clear_hero_save()

## Явно заданный файл карты (редактор, отладочные сцены).
static func request_map_by_path(path: String) -> void:
	pending_map_path = path
	map_seed = 0
	clear_load_position()
	clear_hero_save()

const PLAYER_SPEED: float = 120.0
const ATTACK_RANGE: float = 40.0
const AGGRO_RADIUS: float = 150.0
const DEAGGRO_RADIUS: float = 200.0

const POSTFX_SHADER := """shader_type canvas_item;
render_mode unshaded, blend_mix;

// Виньетка и зерно. В Environment в Godot 4 таких полей нет ни в одной версии.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.34;
uniform float vignette_softness : hint_range(0.05, 1.5) = 0.62;
uniform float grain : hint_range(0.0, 0.15) = 0.022;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = SCREEN_UV - vec2(0.5);
	// Учитываем соотношение сторон, иначе виньетка овальная на широком окне.
	c.x *= 0.62;
	float v = 1.0 - vignette_strength * smoothstep(0.18, 0.72, length(c) * vignette_softness * 2.0);
	vec3 col = textureLod(screen_texture, SCREEN_UV, 0.0).rgb * v;
	col += (hash21(SCREEN_UV * 1024.0 + fract(TIME) * 91.7) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}"""

# --- Свет и пост-обработка 2D ---

## Приглушение окружения. Почти нейтральное.
## Первая версия была 0.88 — и игрок пожаловался, что «все объекты, НПЦ и
## строения стали тёмные». Причина в том, что у рельефа своя яркость от солнца
## зашита в вершинные цвета (`AlmMap._brightness`), а спрайты её не имеют и
## живут в средних тонах — там AgX сажает яркость вниз сильнее всего.
## Свет заклинаний при 0.97 не гаснет: он кратковременный и идёт с энергией
## 1.5–2.2, запаса хватает.
const AMBIENT := Color(0.97, 0.98, 1.0, 1.0)

func _setup_rendering() -> void:
	_setup_ambient()
	_setup_environment()
	_setup_post_pass()


## CanvasModulate — базовая яркость всего холста. Без него аддитивные
## источники света не могут ничего добавить: холст и так рисуется в полную
## яркость. Действует ТОЛЬКО на свой слой, поэтому UI на своём CanvasLayer
## не затрагивается.
func _setup_ambient() -> void:
	if get_node_or_null("Ambient") != null:
		return
	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = AMBIENT
	add_child(ambient)


## WorldEnvironment: glow + тональная компрессия для 2D.
##
## background_mode ОБЯЗАН быть BG_CANVAS (3). Со значением по умолчанию
## (BG_CLEAR_COLOR) Environment влияет ТОЛЬКО на 3D, а в чисто 2D-проекте это
## значит «ничего не делает» — самая частая потеря времени при настройке.
##
## Цвета каналов > 1.0 в шейдерах заклинаний дают избирательное свечение:
## раньше 2D был RGBA8 и значения обрезались до 1.0, то есть «ярче белого»
## было невозможно в принципе. Теперь работает hdr_2d.
func _setup_environment() -> void:
	if get_node_or_null("WorldEnvironment") != null:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.glow_strength = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Порог чуть ниже 1.0: с hdr_2d в кадре почти нет по-настоящему белых
	# пикселей, и при 1.0 не светилось бы ничего.
	env.glow_hdr_threshold = 0.92
	# Имена уровней glow содержат «/», к таким свойствам нельзя обращаться
	# присваиванием (только через set()) — прямой доступ не парсится.
	env.set("glow_levels/4", 0.2)
	env.set("glow_levels/5", 0.35)
	env.set("glow_levels/6", 0.18)
	# AgX оставлен: он даёт «цветную» землю, которая понравилась. Но он же
	# сажает средние тона вниз, а спрайты живут именно в них — компенсируем
	# экспозицией и убираем лишний контраст теней.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.tonemap_agx_contrast = 0.85
	# UI на CanvasLayer с layer > 0 и так исключён из пост-обработки.
	env.background_canvas_max_layer = 0

	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = env
	add_child(node)


## Пост-пасс: виньетка + зерно. В Environment в Godot 4 виньетки НЕТ ни в одной
## версии — её всегда делают своим шейдером.
##
## Кладётся ПЕРВЫМ потомком UI-CanvasLayer: тогда HUD рисуется поверх и не
## затемняется, а сам слой (layer 1) не попадает под glow.
func _setup_post_pass() -> void:
	# Узел UI в main.tscn НЕ состоит в группе "ui" (там нет строки groups = [...]),
	# поэтому искать его по группе нельзя — берём уже сохранённую ссылку `ui`.
	var ui_node: Node = ui
	if ui_node == null:
		ui_node = get_tree().get_first_node_in_group("ui")
	if ui_node == null:
		ui_node = find_child("UI", true, false)
	if ui_node == null:
		return
	if ui_node.get_node_or_null("PostFX") != null:
		return
	var layer: CanvasLayer = ui_node as CanvasLayer
	if layer == null:
		return
	var rect := ColorRect.new()
	rect.name = "PostFX"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = POSTFX_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	rect.color = Color(1, 1, 1, 1)
	layer.add_child(rect)
	# Переносим наверх списка детей, чтобы HUD был ПОВЕРХ пост-обработки.
	layer.move_child(rect, 0)


func _ready():  # Инициализация мира и боя
	process_mode = PROCESS_MODE_ALWAYS  # Работает даже на паузе

	# Свет и пост-обработка 2D. Без них эффекты рисуются «как есть» и выглядят
	# наклейками: правило VFX — эффект должен излучать и освещать мир.
	_setup_rendering()

	# Сброс режимов прицеливания (статика переживает перезапуск сцены)
	pending_scroll = {}
	pending_spell = {}
	_spell_targeting_frame = -1
	# Авто-каст НЕ сбрасываем: игрок задал его в книге и ждёт, что маг лечит.

	# Страховка: если main.tscn запущен напрямую (F6, отладка) без выбора
	# персонажа на старте — уходим на экран выбора героя.
	if Game.hero_stats.is_empty():
		get_tree().call_deferred("change_scene_to_file", "res://scenes/character_select.tscn")
		return

	# Спавним игрока на проходимом тайле в центре карты
	_spawn_player_on_walkable()
	Game.hero = player
	Game.party.clear()
	# НПЦ и монстры из карты (.alm секция units или sidecar .npcs.json)
	_spawn_map_units()

	if camera and player:
		camera.position = player.camera_focus()
		camera.make_current()

	await get_tree().process_frame

	# Находим врагов (группа "enemy": враг из сцены + спавн из карты)
	enemies.clear()
	for child in get_children():
		if child.is_in_group("enemy"):
			enemies.append(child)
			print("  Враг найден: ", child.name, " HP=", child.max_hp if "max_hp" in child else "?")

	print("Всего врагов: ", enemies.size())

	# Добавляем игрока в группу "player" для врагов
	player.add_to_group("player")

	if ui:
		ui.setup_ui(player)

	_select_ring = SelectRing.new()
	_select_ring.name = "SelectRing"
	_select_ring.z_index = 9
	add_child(_select_ring)
	_select_ring.visible = false

	# Сохранения: троттл автосейва. Первый автосейв не раньше, чем
	# AUTOSAVE_MIN_SECONDS от старта, иначе он сработал бы на пустой партии
	# сразу при входе в игру.
	_autosave_accum = 0.0
	set_process_unhandled_input(true)

func _spawn_player_on_walkable():
	var mw: int = int(alm_map.get("map_width"))
	var mh: int = int(alm_map.get("map_height"))
	if not alm_map or mw == 0:
		return
	# 0) Позиция из сохранения (одноразово): герой встаёт туда, где сохранился.
	if load_position_valid:
		var lp: Vector2 = load_position
		if alm_map.call("is_walkable_world", lp):
			player.global_position = lp
			player.reset_physics_interpolation()
			clear_load_position()
			return
		clear_load_position()
	# 1) Точка спавна, заданная в карте (тип «Спавн»)
	var spawn_pos: Vector2 = alm_map.call("get_spawn_pos")
	if alm_map.call("is_walkable_world", spawn_pos):
		player.global_position = spawn_pos
		player.reset_physics_interpolation()
		return
	# 2) Запасной вариант — проходимый тайл от центра
	var cx := mw / 2
	var cy := mh / 2
	for r in range(0, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var tx := cx + dx
				var ty := cy + dy
				var ts: int = int(alm_map.get("tile_size"))
				var wx := tx * ts + ts / 2
				var wy := ty * ts + ts / 2
				if alm_map.call("is_walkable_world", Vector2(wx, wy)):
					player.global_position = Vector2(wx, wy)
					player.reset_physics_interpolation()
					return

## Спавн НПЦ/монстров из данных карты: .alm секция units (type_id) или
## sidecar .npcs.json (set). Агрессия — UnitDB.is_hostile (монстры palette=5).
func _spawn_map_units() -> void:
	if alm_map == null or not alm_map.has_method("get_units"):
		return
	var recs: Array = alm_map.call("get_units")
	var spawned := 0
	for rec in recs:
		var set_name := ""
		if rec.has("set"):
			set_name = str(rec["set"])
		elif rec.has("type_id"):
			set_name = UnitDB.set_name_for_id(int(rec["type_id"]))
		if set_name == "" or not UnitDB.has(set_name):
			continue
		var raw_cell := Vector2i(int(rec.get("x", 0)), int(rec.get("y", 0)))
		var open_pos := _find_open_spot(raw_cell, int(alm_map.get("tile_size")))
		if open_pos.x < 0.0:
			continue
		if UnitDB.is_hostile(set_name):
			_spawn_monster(set_name, open_pos, rec)
		else:
			_spawn_npc(set_name, open_pos, rec)
		spawned += 1
	print("Карта: спавн юнитов %d" % spawned)

func _spawn_monster(set_name: String, pos: Vector2, rec: Dictionary) -> void:
	var e := Enemy.new()
	e.name = "Monster_" + set_name.get_file()
	e.anim_set = set_name
	var hp := int(rec.get("hp_max", 0))
	if hp > 0:
		e.max_hp = hp
	var dmg := int(rec.get("damage", 0))
	if dmg > 0:
		e.damage = dmg
	e.position = pos
	e.home_position = pos
	add_child(e)
	enemies.append(e)

func _spawn_npc(set_name: String, pos: Vector2, rec: Dictionary) -> void:
	var n := Npc.new()
	n.name = "Npc_" + set_name.get_file()
	n.anim_set = set_name
	n.position = pos
	n.home = pos
	var role := str(rec.get("role", "citizen"))
	n.role = role
	n.is_patrol = bool(rec.get("patrol", false))
	n.is_archmage = bool(rec.get("archmage", false))
	var post: Array = rec.get("post", [])
	if post.size() >= 2:
		var post_cell := Vector2i(int(post[0]), int(post[1]))
		var post_pos := _find_open_spot(post_cell, int(alm_map.get("tile_size")))
		n.post = post_pos if post_pos.x >= 0.0 else pos
	var hp := int(rec.get("hp_max", 0))
	if hp > 0:
		n.max_hp = hp
	var dmg := int(rec.get("damage", 0))
	if dmg > 0:
		n.damage = dmg
	add_child(n)
	npcs.append(n)

## Ищем проходимую клетку рядом со спавном, у которой есть проходимые соседи
## (минимум 2 из 4) — чтобы персонаж не оказался в тупике. Возвращаем центр
## клетки в мировых координатах или Vector2(-1,-1), если в радиусе 6 нет места.
func _find_open_spot(start: Vector2i, ts: int) -> Vector2:
	if _is_open_spot(start.x, start.y):
		return Vector2(start.x * ts + ts / 2, start.y * ts + ts / 2)
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue  # только кольцо на расстоянии r
				var tx := start.x + dx
				var ty := start.y + dy
				if _is_open_spot(tx, ty):
					return Vector2(tx * ts + ts / 2, ty * ts + ts / 2)
	return Vector2(-1, -1)

## Клетка проходима и имеет >=2 проходимых соседей (не закуток).
func _is_open_spot(tx: int, ty: int) -> bool:
	var ts: int = alm_map.tile_size
	var wx: int = tx * ts + ts / 2
	var wy: int = ty * ts + ts / 2
	if not alm_map.is_walkable_world(Vector2(wx, wy)):
		return false
	var open_neighbors := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = tx + d.x
		var ny: int = ty + d.y
		if nx < 0 or ny < 0 or nx >= alm_map.map_width or ny >= alm_map.map_height:
			continue
		if alm_map.is_walkable_world(Vector2(nx * ts + ts / 2, ny * ts + ts / 2)):
			open_neighbors += 1
	return open_neighbors >= 2

func _input(event):
	# Прицеливание (свиток или заклинание книги): ПКМ или ESC отменяет.
	# Свиток НЕ тратится, мана/заряд НЕ списываются.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not Game.pending_scroll.is_empty() or not Game.pending_spell.is_empty():
			cancel_targeting()
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not Game.pending_scroll.is_empty() or not Game.pending_spell.is_empty():
			cancel_targeting()
			return
		# Открытое меню сохранений само перехватывает Esc и закрывается.
		if _save_menu != null and is_instance_valid(_save_menu):
			return
		open_save_menu()
		return

	# Быстрые клавиши (как у разработчиков): Ctrl+1..9 назначает на цифровую
	# клавишу либо выбранную магию, либо расходник под курсором; 1..9 (без Ctrl)
	# применяет назначенное: заклинание — с прицеливанием, зелье — сразу,
	# свиток — с выбором цели кликом.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var slot: int = event.keycode - KEY_1
			if event.ctrl_pressed:
				var sn := str(Game.pending_spell.get("name", ""))
				if sn != "":
					Game.hotbar[slot] = {"kind": "spell", "name": sn}
					print("Быстрая клавиша %d -> %s" % [slot + 1, sn])
					if ui != null and ui.has_method("_notify_hotbar_assigned"):
						ui._notify_hotbar_assigned(slot, sn)
					return
				var iu := hovered_item_key()
				if iu != "":
					var item := ItemDB.find(iu)
					if not item.is_empty():
						Game.hotbar[slot] = {"kind": "item", "key": iu}
						print("Быстрая клавиша %d -> %s" % [slot + 1, iu])
						if ui != null and ui.has_method("_notify_item_assigned"):
							ui._notify_item_assigned(slot, iu)
						return
				return
			if not event.ctrl_pressed:
				var entry: Dictionary = Game.hotbar.get(slot, {})
				match str(entry.get("kind", "")):
					"spell":
						if ui != null and ui.has_method("_quick_cast"):
							ui._quick_cast(str(entry.get("name", "")))
					"item":
						_use_hotbar_item(str(entry.get("key", "")))
				return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Клики по интерфейсу (книга заклинаний, инвентарь, панели, магазин/таверна)
		# не должны двигать/атаковать героя по карте
		if ui != null and ui.has_method("is_editor_open") and ui.is_editor_open():
			return
		if ui != null and ui.has_method("is_pointer_over_ui") and ui.is_pointer_over_ui(event.position):
			return
		var world_position = get_global_mouse_position()
		# Чтение свитка мага: клик выбирает цель (врага или себя/союзника)
		if not Game.pending_scroll.is_empty():
			_resolve_scroll_click(world_position)
			return
		# Заклинание из книги: клик выбирает цель для выбранной магии
		if not Game.pending_spell.is_empty():
			_resolve_spell_click(world_position)
			return
		handle_click(world_position)

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		is_paused = !is_paused
		get_tree().paused = is_paused

	# Рестарт по Ctrl+R
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and event.ctrl_pressed:
		get_tree().reload_current_scene()

	# Открыть инвентарь по I
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		if ui:
			ui.open_inventory_panel()

	# Toggle магий по B
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		if ui:
			ui.toggle_spells()

func handle_click(world_position: Vector2):
	# Герой мёртв (падение/разложение) — управление не работает
	if is_instance_valid(player) and player.state in ["dead", "decay"]:
		return
	print("Клик в: ", world_position)
	_pending_herb = null
	_pending_building = ""
	_pending_s = {}
	_pending_archmage = null

	# Клик по зданию (функциональному или декоративному): всегда к двери.
	# Функциональное — при подходе меню + герой «внутри»; декоративное — только подход.
	var cell := Vector2i(int(world_position.x) / 32, int(world_position.y) / 32)
	if alm_map != null and alm_map.has_method("structure_at"):
		var s: Dictionary = alm_map.call("structure_at", cell)
		if not s.is_empty():
			_building_click(_structure_kind(int(s.get("type_id", 0))), s)
			return
	if alm_map != null and alm_map.has_method("herb_at_position"):
		var herb := alm_map.call("herb_at_position", world_position) as HerbNode
		if herb != null:
			_herb_click(herb)
			return
	# Клик по великому магу (капитан): подходим / открываем панель.
	var mage = _archmage_at_position(world_position)
	if mage != null:
		_archmage_click(mage)
		return

	var enemy = get_enemy_at_position(world_position)
	if enemy:
		print("Атака врага!")
		player.attack_target = enemy
		player.state = "chase"
	else:
		print("Движение к: ", world_position)
		player_target = world_position
		player.state = "move"
		player.attack_target = null
		# Маршрут с обходом препятствий (pathfinding по клеткам), не «по прямой»
		if alm_map != null and alm_map.has_method("find_path"):
			player.begin_path(alm_map.find_path(player.global_position, world_position))

## Функциональная роль здания по папке структуры (StructureDB).
func _structure_kind(type_id: int) -> String:
	var def := StructureDB.get_by_id(type_id)
	var folder := str(def.get("folder", "")).to_lower()
	if folder.contains("druidshop") or folder.contains("hive"):
		return "alchemy"
	if folder.contains("shop"):
		return "shop"
	if folder.contains("inn"):
		return "inn"
	if folder.contains("train") or folder.contains("school"):
		return "school"
	if folder.contains("blacksmith"):
		return "blacksmith"
	return ""

## Клик по зданию: подходим к двери (южный край футпринта).
## kind != "" — функциональное (магазин/таверна/…): при подходе меню.
## kind == "" — декоративное: только подход, герой остаётся на карте.
func _building_click(kind: String, s: Dictionary) -> void:
	if ui == null or not is_instance_valid(player):
		return
	var door := _door_point(s)
	if kind != "" and player.global_position.distance_to(door) <= 90.0:
		_pending_building = ""
		_pending_s = {}
		_open_building_kind(kind)
		return
	_pending_building = kind
	_pending_s = s
	player.stop_movement()
	player_target = door
	player.state = "move"
	player.attack_target = null
	if alm_map != null and alm_map.has_method("find_path"):
		player.begin_path(alm_map.find_path(player.global_position, door))

func _open_building_kind(kind: String) -> void:
	if ui == null:
		return
	match kind:
		"shop": ui.open_shop()
		"alchemy": ui.open_alchemy()
		"inn": ui.open_inn()
		"school": ui.open_school()
		"blacksmith": ui.open_blacksmith()

func _herb_click(herb: HerbNode) -> void:
	if not is_instance_valid(herb) or not herb.is_available():
		return
	_pending_building = ""
	player.attack_target = null
	if player.global_position.distance_to(herb.global_position) <= 52.0:
		_harvest_herb(herb)
		return
	_pending_herb = herb
	player_target = herb.global_position
	player.state = "move"
	if alm_map != null and alm_map.has_method("find_path"):
		player.begin_path(alm_map.find_path(player.global_position, herb.global_position))

func _process_pending_herb() -> void:
	if _pending_herb == null:
		return
	if not is_instance_valid(_pending_herb) or not _pending_herb.is_available():
		_pending_herb = null
		return
	if player.global_position.distance_to(_pending_herb.global_position) <= 52.0:
		var herb := _pending_herb
		_pending_herb = null
		_harvest_herb(herb)

func _harvest_herb(herb: HerbNode) -> void:
	if not is_instance_valid(herb) or not herb.harvest():
		return
	player.add_item(herb.item_key)
	if is_instance_valid(ui):
		ui.refresh_inventory()
	SoundDB.play(1)
	print("Собрана трава: %s" % herb.item_key)

## Великий маг города (капитан) под курсором.
func _archmage_at_position(click_pos: Vector2) -> Node2D:
	for n in npcs:
		if not is_instance_valid(n):
			continue
		if not ("is_archmage" in n) or not bool(n.is_archmage):
			continue
		if unit_hit_rect(n).grow(8.0).has_point(click_pos):
			return n
	return null

## Клик по магу: если рядом — панель, иначе подходим.
func _archmage_click(mage: Node2D) -> void:
	if ui == null or not is_instance_valid(player) or not is_instance_valid(mage):
		return
	_pending_building = ""
	_pending_s = {}
	_pending_herb = null
	player.attack_target = null
	if player.global_position.distance_to(mage.global_position) <= 90.0:
		ui.open_archmage()
		return
	_pending_archmage = mage
	player_target = mage.global_position
	player.state = "move"
	if alm_map != null and alm_map.has_method("find_path"):
		player.begin_path(alm_map.find_path(player.global_position, mage.global_position))

func _process_pending_archmage() -> void:
	if _pending_archmage == null:
		return
	if not is_instance_valid(_pending_archmage) or ui == null:
		_pending_archmage = null
		return
	if player.global_position.distance_to(_pending_archmage.global_position) <= 90.0:
		_pending_archmage = null
		ui.open_archmage()

## Точка входа (дверь): проходимая клетка под южным краем корпуса здания.
func _door_point(s: Dictionary) -> Vector2:
	var def := StructureDB.get_by_id(int(s.get("type_id", 0)))
	var fw := int(def.get("tile_width", 1))
	var th := int(def.get("tile_height", 1))
	var x := int(s.get("ax", 0))
	var y := int(s.get("ay", 0))
	var base := Vector2i(x + fw / 2, y + th)
	for r in range(3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var c := base + Vector2i(dx, dy)
				var p := Vector2(c.x * 32.0 + 16.0, c.y * 32.0 + 16.0)
				if alm_map != null and alm_map.has_method("is_walkable_world") \
						and alm_map.is_walkable_world(p):
					return p
	return Vector2(x * 32.0 + fw * 16.0, (y + th) * 32.0)

## Когда герой подошёл к двери — «входим»: меню (функциональное) или остановка.
func _process_pending_building() -> void:
	if _pending_s.is_empty() or not is_instance_valid(player):
		return
	var door := _door_point(_pending_s)
	if player.global_position.distance_to(door) > 80.0:
		return
	var k := _pending_building
	_pending_building = ""
	_pending_s = {}
	player.stop_movement()
	# Декоративное (k==""): герой остаётся видимым у стены, меню нет.
	if k != "":
		_open_building_kind(k)

## Юнит под курсором (враг ИЛИ мирный НПЦ) по видимой области корпуса.
func _hover_unit() -> Node2D:
	if not is_instance_valid(player):
		return null
	var mouse := player.get_global_mouse_position()
	for e in enemies:
		if is_instance_valid(e) and unit_hit_rect(e).grow(6.0).has_point(mouse):
			return e
	for e in npcs:
		if is_instance_valid(e) and unit_hit_rect(e).grow(6.0).has_point(mouse):
			return e
	return null

## ВЫСОТА спрайта юнита над его основанием (px) — то, насколько высоко надо
## поднять эффект, чтобы он оказался над головой, а не внутри тела.
##
## Берётся из UnitAnim.visual_height(): это реальная высота кадра с учётом
## масштаба. Нельзя брать _unit_metrics() — это ФУТПРИНТ (сколько клеток
## занимает юнит): для героя с tile_size 1 это 32 px, тогда как спрайт выше, и
## эффект по этой высоте оказывался у персонажа внутри (жалоба игрока).
##
## У всех четырёх типов юнитов (player/enemy/npc/mercenary) узел анимации
## называется "UnitAnim".
static func unit_visual_height(u: Node2D) -> float:
	if not is_instance_valid(u):
		return 32.0
	var anim: Node = u.get_node_or_null("UnitAnim")
	if anim == null:
		return 32.0
	if anim.has_method("visual_height"):
		var h := float(anim.call("visual_height"))
		if h > 0.0:
			return h
	return 32.0

## Размер спрайта юнита (w, h). static: считается только по anim_set, своего
## состояния не читает — вызывается и из Game, и из SpellAura.
##
## ВНИМАНИЕ: это ФУТПРИНТ (сколько клеток занимает юнит), а НЕ высота спрайта.
## Для высоты (куда вешать эффекты над головой) есть unit_visual_height().
static func _unit_metrics(u: Node2D) -> Array:
	var set_name := ""
	if "anim_set" in u:
		set_name = str(u.get("anim_set"))
	if set_name == "" and u is Player:
		set_name = (u as Player).anim_set_name()
	# Размер спрайта юнита в пикселях. Раньше читались поля "w"/"h" из units_db.json,
	# но их там НЕТ — срабатывала заглушка 128, и кольцо выделения было шириной 144 px
	# независимо от юнита (для гнома — круг втрое шире него самого).
	var w := 32
	var h := 32
	if set_name != "":
		var ts: int = maxi(1, UnitDB.tile_size(set_name))
		w = ts * 32
		h = ts * 32
	return [w, h]

## Точка кольца выделения: центр тела юнита. Спрайт рисуется вверх от точки
## «пола» и поднимается на рельефе — без учёта этого кольцо «висит в пустоте».
func _target_ring_pos(u: Node2D) -> Vector2:
	var m := _unit_metrics(u)
	var rise := 0.0
	if alm_map != null and alm_map.has_method("relief_at_world"):
		rise = float(alm_map.call("relief_at_world", u.global_position))
	return Vector2(u.global_position.x, u.global_position.y - float(m[1]) * 0.55 - rise)

## Подсветка цели: враг под курсором / текущая цель атаки (красное кольцо)
## или мирный НПЦ под курсором (жёлтое кольцо).
func _update_target_ring() -> void:
	var target: Node2D = null
	var hostile := false
	if is_instance_valid(player) and is_instance_valid(player.attack_target) \
			and player.state in ["chase", "attack"]:
		target = player.attack_target
		hostile = true
	else:
		target = _hover_unit()
		hostile = target != null and enemies.has(target)
	if _select_ring == null:
		return
	if is_instance_valid(target):
		_select_ring.visible = true
		_select_ring.color = Color(1, 0.3, 0.2, 0.9) if hostile else Color(0.95, 0.85, 0.35, 0.9)
		_select_ring.global_position = _target_ring_pos(target)
		var m := _unit_metrics(target)
		_select_ring.radius = maxf(22.0, float(m[0]) / 2.0 + 8.0)
	else:
		_select_ring.visible = false

func get_enemy_at_position(click_pos: Vector2) -> Node2D:
	for enemy in enemies:
		if is_instance_valid(enemy) and unit_hit_rect(enemy).grow(8.0).has_point(click_pos):
			return enemy
	return null

## Свиток мага: клик выбрал цель. Враг — для урона/области/стены,
## герой или союзник (НПЦ/наёмник) — для лечения/защиты/баффа.
## Ключ предмета под курсором в открытом инвентаре ("" = панель закрыта или
## курсор не над ячейкой). Нужен для назначения расходника на хоткей.
func hovered_item_key() -> String:
	if ui == null or not is_instance_valid(ui):
		return ""
	var panel = ui.get("_inventory_panel")
	if panel == null or not is_instance_valid(panel):
		return ""
	return str(panel.get("hovered_item_key"))


## Применение расходника с хоткея. Зелье выпивается сразу, свиток входит в
## прицеливание — ровно как клик по нему в инвентаре.
func _use_hotbar_item(item_key: String) -> void:
	if item_key == "":
		return
	var item := ItemDB.find(item_key)
	if item.is_empty():
		Game.hotbar.erase(_hotbar_slot_of(item_key))
		return
	if not is_instance_valid(player) or not player.has_item(item_key):
		_flash_cast_error("Нет такого расходника в инвентаре.")
		return
	match str(item.get("quality", "")):
		"Potion":
			if player.use_potion(item_key):
				if ui != null and ui.has_method("refresh_inventory"):
					ui.refresh_inventory()
				if ui != null and ui.has_method("refresh_inventory"):
					ui.refresh_inventory()
				if ui != null and ui.has_method("_update_gold") and player != null:
					ui._update_gold(int(player.gold))
		"Scroll", "SuperScroll":
			var spell_name := str(item.get("type", ""))
			Game.pending_scroll = {"spell": spell_name, "item_key": item_key}
			_flash_cast_error("Выберите цель для свитка.")
		_:
			_flash_cast_error("Этот предмет нельзя применить с хоткея.")


func _hotbar_slot_of(item_key: String) -> int:
	for slot in Game.hotbar:
		var entry: Dictionary = Game.hotbar.get(slot, {})
		if str(entry.get("kind", "")) == "item" and str(entry.get("key", "")) == item_key:
			return int(slot)
	return -1


func _resolve_scroll_click(world_position: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var spell := str(Game.pending_scroll.get("spell", ""))
	if spell == "":
		return
	var target_kind := SpellDB.target_of(spell)
	var target: Node2D = null
	if target_kind == "enemy":
		target = get_enemy_at_position(world_position)
		if target == null:
			target = player.get_nearest_enemy(world_position, 220.0)
		if target == null:
			_flash_cast_error("Нет врага под курсором — укажите противника.")
			return
	elif target_kind == "point":
		var under := get_enemy_at_position(world_position)
		if under != null:
			world_position = under.global_position
	else:
		target = _ally_at_position(world_position)
		if target == null:
			# Аналогично книгам: щит/бафф накладывается на героя по умолчанию
			if SpellDB.kind_of(spell) == "buff":
				target = player
			else:
				_flash_cast_error("Укажите героя или союзника для этого заклинания.")
				return

	# Дальность из базы (раньше не проверялась вообще)
	var max_range := SpellDB.range_of(spell)
	if max_range > 0.0 and target_kind != "self" \
			and player.cast_origin().distance_to(world_position) > max_range:
		_flash_cast_error("Слишком далеко: «%s» достаёт на %d м." % [spell, int(max_range / 32.0)])
		return

	# Предмет списывается ТОЛЬКО если эффект применился: раньше remove_item
	# вызывался безусловно, и свитки «Scroll Fire Wall» просто исчезали.
	var applied := false
	if target != null:
		applied = player.apply_scroll_to_target(spell, target)
	else:
		applied = player.apply_scroll_to_target_point(spell, world_position)
	if not applied:
		_flash_cast_error("Заклинание не сработало — предмет не потрачен.")
		return
	player.remove_item(str(Game.pending_scroll.get("item_key", "")))
	Game.pending_scroll = {}
	if ui != null and ui.has_method("_finish_scroll_targeting"):
		ui._finish_scroll_targeting()


func _flash_cast_error(msg: String) -> void:
	print(msg)
	if ui != null and ui.has_method("_flash_targeting_error"):
		ui._flash_targeting_error(msg)

## Заклинание из книги: клик выбрал цель. Атака/область/стена — по врагу или
## точке, лечение/защита/бафф — по герою или союзнику. Мана/заряд списываются
## только при успешном касте.
func _resolve_spell_click(world_position: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var name := str(Game.pending_spell.get("name", ""))
	if name == "":
		return
	# Защита: не кастовать в тот же кадр, что и выбор магии из книги
	if Engine.get_process_frames() == Game._spell_targeting_frame:
		return
	var target_kind := SpellDB.target_of(name)
	var target_position := world_position
	var target_node: Node2D = null
	var ok := true
	var enemy := get_enemy_at_position(world_position)

	match target_kind:
		"enemy":
			if enemy != null:
				target_node = enemy
				target_position = enemy.global_position
			else:
				enemy = player.get_nearest_enemy(world_position, 220.0)
				if enemy == null:
					ok = false
				else:
					target_node = enemy
					target_position = enemy.global_position
		"point":
			if enemy != null:
				target_position = enemy.global_position
		"ally":
			var ally := _ally_at_position(world_position)
			if ally == null:
				# Щиты/баффи удобно накладывать на себя, не целясь точно
				if SpellDB.kind_of(name) == "buff":
					ally = player
				else:
					ok = false
			if ally != null:
				target_position = ally.global_position
				target_node = ally
		_:
			target_node = player
			target_position = player.global_position

	if not ok:
		var msg := "Укажите ВРАГА для «%s» (ПКМ/ESC — отмена)." % name \
			if target_kind == "enemy" else "Укажите ГЕРОЯ или СОЮЗНИКА для «%s»." % name
		print(msg)
		if ui != null and ui.has_method("_flash_targeting_error"):
			ui._flash_targeting_error(msg)
		return

	# Дальность из базы: раньше поле range вообще не читалось, поэтому можно
	# было кастовать через полкарты (включая телепорт).
	var max_range := SpellDB.range_of(name)
	if max_range > 0.0 and target_kind != "self":
		var origin: Vector2 = player.cast_origin()
		if origin.distance_to(target_position) > max_range:
			var rmsg := "Слишком далеко: «%s» достаёт на %d м." % [name, int(max_range / 32.0)]
			if ui != null and ui.has_method("_flash_targeting_error"):
				ui._flash_targeting_error(rmsg)
			return

	if not player.cast_spell(name, target_position, target_node):
		print("Не удалось кастовать: " + name)
	if ui != null and ui.has_method("_finish_spell_targeting"):
		ui._finish_spell_targeting()

## Цель-союзник под курсором: сам герой, мирный НПЦ или наёмник.
func _ally_at_position(world_position: Vector2) -> Node2D:
	if is_instance_valid(player) and unit_hit_rect(player).grow(8.0).has_point(world_position):
		return player
	for n in npcs:
		if is_instance_valid(n) and unit_hit_rect(n).grow(8.0).has_point(world_position):
			return n
	for m in party:
		if is_instance_valid(m) and unit_hit_rect(m).grow(8.0).has_point(world_position):
			return m
	return null

## Отмена прицеливания (свиток или заклинание книги). НЕ тратится.
func cancel_targeting() -> void:
	Game.pending_scroll = {}
	Game.pending_spell = {}
	Game._spell_targeting_frame = -1
	if ui != null and ui.has_method("_cancel_targeting"):
		ui._cancel_targeting()

## Хит-бокс юнита в мире.
##
## Раньше строился из units_db w/h (почти всегда 128) + sel_box. У heroes/*
## sel_box отсутствовал → заглушка 96×96 → melee «долетал» на 4–5 клеток
## (жалоба игрока 07.10: «меч, а НПЦ в 5 шагах умирает»).
##
## Теперь: если sel_box «настоящий» (не дефолт 96×96 при w=128) — берём его.
## Иначе — визуальный бокс по tile_size / UnitAnim.visual_height (как кольцо).
static func unit_hit_rect(u: Node2D) -> Rect2:
	if not is_instance_valid(u):
		return Rect2()
	var set_name := ""
	if "anim_set" in u:
		set_name = str(u.get("anim_set"))
	if set_name == "" and u is Player:
		set_name = (u as Player).anim_set_name()
	var o := {}
	if set_name != "":
		o = UnitDB.get_set(set_name)
	var w := int(o.get("w", 128))
	var sel := UnitDB.sel_box(set_name) if set_name != "" else Rect2i(16, 16, 96, 96)
	var ts := maxi(1, UnitDB.tile_size(set_name)) if set_name != "" else 1
	# Дефолт sel_box (96×96) при легаси-канвасе 128 = данные отсутствуют.
	var sel_missing := w >= 128 and sel.size.x >= 90 and sel.size.y >= 90
	if sel_missing:
		# Визуальный корпус: ширина ~24 px на тайл, высота — реальный спрайт.
		var vw := 24.0 * float(ts)
		var vh := 40.0 * float(ts)
		if u.has_node("UnitAnim"):
			var anim = u.get_node("UnitAnim")
			if anim != null and anim.has_method("visual_height"):
				vh = maxf(28.0, float(anim.call("visual_height")) * 0.92)
		return Rect2(u.global_position + Vector2(-vw * 0.5, -vh), Vector2(vw, vh))
	var base := u.global_position + Vector2(-w / 2.0, -float(o.get("h", 128)))
	return Rect2(base + Vector2(sel.position.x, sel.position.y), Vector2(sel.size.x, sel.size.y))

## Расстояние между КОРПУСАМИ юнитов (хит-бокс к хит-боксу; 0 при пересечении).
## Для боя: юниты встают вплотную телами и атакуют, а не «издалека по центру».
static func units_range(a: Node2D, b: Node2D) -> float:
	var ra := unit_hit_rect(a)
	var rb := unit_hit_rect(b)
	if ra.intersects(rb):
		return 0.0
	var dx := maxf(0.0, maxf(ra.position.x - (rb.position.x + rb.size.x),
		rb.position.x - (ra.position.x + ra.size.x)))
	var dy := maxf(0.0, maxf(ra.position.y - (rb.position.y + rb.size.y),
		rb.position.y - (ra.position.y + ra.size.y)))
	return sqrt(dx * dx + dy * dy)

## Добавить травму камере (экранная тряска). amount: 0.0–1.0.
static func camera_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _physics_process(delta):
	# Камера в том же тике, что и герой: иначе на high-refresh
	# lerp в _process «дёргает» картинку относительно physics-interpolated
	# позиции юнита (жалоба игрока 07.10).
	if is_instance_valid(player) and camera:
		camera.position = camera.position.lerp(player.camera_focus(), 8.0 * delta)
		if _trauma > 0.0:
			_trauma = maxf(_trauma - 1.2 * delta, 0.0)
			var shake := _trauma * _trauma
			_trauma_t += delta * 30.0
			camera.offset = Vector2(
				8.0 * shake * sin(_trauma_t * 1.7),
				6.0 * shake * sin(_trauma_t * 2.3)
			)
		else:
			camera.offset = Vector2.ZERO


func _process(delta):
	if is_paused:
		return
	_gray_respawn_tick(delta)
	if is_instance_valid(player) and camera:
		_autosave_tick(delta)
		# Камера уже в _physics_process — здесь только UI/реген/таймеры.
	if is_instance_valid(ui) and is_instance_valid(player):
		ui.update_ui(player, delta)
	
	# Регенерация героя: HP и мана по статам, а не жёсткая «+1 мана/с».
	# Раньше мана качалась 1/с независимо от Spirit, а HP не регенерировался.
	_regen_hero(delta)
	
	# Обработка режимов действий
	_process_action_mode()
	_update_target_ring()
	_process_pending_building()
	_process_pending_herb()
	_process_pending_archmage()
	Game.tick_shields(delta)
	StatusEffects.tick(delta)
	_check_portal()


## Регенерация героя раз в секунду: HP = 1 + Body/5, мана = 1 + Spirit/10.
func _regen_hero(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if player.state == "dead" or player.state == "decay":
		return
	mana_regen_accum += delta
	if mana_regen_accum < 1.0:
		return
	mana_regen_accum -= 1.0
	if player.current_hp < player.max_hp:
		player.heal_amount(player._calc_hp_regen())
	if player.has_mana and player.current_mana < player.max_mana:
		var gain: int = player._calc_mana_regen()
		player.current_mana = mini(player.max_mana, player.current_mana + gain)
		DamageNumber.show_at(player.global_position, gain, "mana")

func _check_portal() -> void:
	# Проверка: игрок на клетке портала?
	if not is_instance_valid(player) or not is_instance_valid(alm_map):
		return
	var cells: Array = alm_map.call("get_portal_cells")
	if cells.is_empty():
		return
	var TILE: int = 32
	var cell := Vector2i(int(player.global_position.x) / TILE, int(player.global_position.y) / TILE)
	for pc in cells:
		if cell == pc:
			_on_portal_enter()
			return

func _on_portal_enter() -> void:
	# Заглушка была: «телепорт обратно на спавн», то есть портал в никуда.
	# Теперь портал ведёт в следующую зону маршрута.
	var next_zone := str(PORTAL_CHAIN.get(Game.map_zone, ""))
	if next_zone == "":
		print("Портал из зоны '%s' ведёт в никуда — конец маршрута" % Game.map_zone)
		return
	# Автосейв ДО смены зоны: иначе после телепортации точка «до портала» потеряна.
	autosave_now()
	travel_to_zone(next_zone)


## Куда ведёт портал: start -> mid -> hard. В hard/faction портала нет,
## это конец маршрута (так и задумано игроком).
const PORTAL_CHAIN := {"start": "mid", "mid": "hard"}

var _travelling := false

## Переход в другую зону через портал.
##
## Почему ГОРЯЧАЯ ЗАМЕНА карты, а не change_scene_to_file: смена сцены
## вызывает Main._ready, который делает `Game.party.clear()`, а золото и
## инвентарь живут на узле Player. То есть переход через сцену уничтожил бы
## отряд и снаряжение — это и было признано непригодным при исследовании.
## Узел Map — обычный Node2D, его можно пересоздать, а герой, партия и HUD
## остаются живы.
func travel_to_zone(zone: String) -> void:
	if _travelling:
		return
	if not is_instance_valid(player):
		return
	_travelling = true
	var seed_value: int = Game.map_seed
	if seed_value == 0:
		seed_value = 4242
	var new_path := MapGenerator.ensure_map(seed_value, zone, MapGenerator.MAPS_DIR)
	if new_path == "" or not FileAccess.file_exists(new_path):
		push_error("Не удалось подготовить карту зоны '%s'" % zone)
		_travelling = false
		return
	await _swap_map(new_path, zone)
	_travelling = false
	print("Переход: зона '%s', карта %s" % [zone, new_path])


## Пересоздать узел Map и переселить на него героя и партию.
func _swap_map(new_path: String, zone: String) -> void:
	_clear_world_units()
	# Зона меняется ДО создания карты: AlmMap._ready и спавн используют
	# Game.map_zone, и он должен уже совпадать с новой картой.
	Game.map_zone = zone
	Game.pending_map_path = new_path
	if is_instance_valid(alm_map):
		remove_child(alm_map)
		alm_map.queue_free()
	var fresh := Node2D.new()
	fresh.name = "Map"
	fresh.set_script(load("res://scripts/alm_map.gd"))
	fresh.set("tile_size", 32)
	fresh.set("alm_path", new_path)
	add_child(fresh)
	move_child(fresh, 0)
	alm_map = fresh
	await get_tree().process_frame
	await get_tree().process_frame
	# Герой и партия — на спавн новой зоны.
	if alm_map != null and alm_map.has_method("get_spawn_pos"):
		var sp: Vector2 = alm_map.call("get_spawn_pos")
		if sp != Vector2.ZERO:
			player.global_position = sp
			player.reset_physics_interpolation()
			player.stop_movement()
	for m in Game.party:
		var unit: Node2D = m as Node2D
		if is_instance_valid(unit):
			unit.global_position = player.global_position + Vector2(32, 0)
			unit.reset_physics_interpolation()
	_spawn_map_units()
	if camera != null and is_instance_valid(player):
		camera.position = player.camera_focus()
		camera.make_current()


## Снести всё, что принадлежит прежней карте: врагов, NPC и их мешки с лутом.
## Без этого после перехода на карте остались бы юниты прошлой зоны, а
## Game.enemies/npcs копились бы впустую.
func _clear_world_units() -> void:
	for u in Game.enemies:
		var e: Node = u as Node
		if is_instance_valid(e):
			e.queue_free()
	Game.enemies.clear()
	for n in Game.npcs:
		var node: Node = n as Node
		if is_instance_valid(node):
			node.queue_free()
	Game.npcs.clear()
	# Мешки с лутом лежат отдельными узлами рядом с юнитами.
	for child in get_children():
		# Мешки лута переименованы в LootDrop (03.10), но группа осталась
		# прежней — на неё завязана очистка при переходе между зонами.
		if child.is_in_group("loot_bag") or child.name.begins_with("LootDrop"):
			child.queue_free()
	if is_instance_valid(player):
		player.stop_movement()

## --- Респавн Серых (03.10) --------------------------------------------------
##
## Замер: респавна не было НИКАКОГО. Убил всех в зоне — зона пустая навсегда,
## и «карта скучная» со временем становилась только скучнее. Теперь держим
## лимит: если живых меньше цели, через каждые N секунд появляется один зверь
## вдали от героя.
var _gray_respawn_accum := 0.0

func _alive_gray_count() -> int:
	var n := 0
	for e in Game.enemies:
		var unit: Node = e as Node
		if not is_instance_valid(unit):
			continue
		if UnitDB.has(str(unit.get("anim_set"))) and UnitDB.is_hostile(str(unit.get("anim_set"))):
			n += 1
	return n

func _gray_respawn_tick(delta: float) -> void:
	var period := GameConfig.getf("spawn", "gray_respawn_seconds")
	if period <= 0.0:
		return
	var target := GameConfig.geti("spawn", "gray_target")
	if target <= 0:
		target = maxi(GameConfig.zonei(Game.map_zone, "gray_count_min"),
			GameConfig.zonei(Game.map_zone, "gray_count_max"))
	if not is_instance_valid(player) or not is_instance_valid(alm_map):
		return
	_gray_respawn_accum += delta
	if _gray_respawn_accum < period:
		return
	_gray_respawn_accum = 0.0
	if _alive_gray_count() >= target:
		return
	var cell := _gray_respawn_cell()
	if cell.x < 0:
		return
	var pool: Array = (MapGenerator.GRAY_ZONE.get(Game.map_zone,
		MapGenerator.GRAY_ZONE["mid"]) as Dictionary).get("pool", [])
	if pool.is_empty():
		return
	var set_name: String = str(pool[randi() % pool.size()])
	var spot := _find_open_spot(cell, int(alm_map.get("tile_size")))
	if spot.x < 0.0:
		return
	var e2 := Enemy.new()
	e2.name = "Monster_" + set_name.get_file()
	e2.anim_set = set_name
	e2.max_hp = randi_range(GameConfig.zonei(Game.map_zone, "gray_hp_min"),
		GameConfig.zonei(Game.map_zone, "gray_hp_max"))
	e2.damage = randi_range(GameConfig.zonei(Game.map_zone, "gray_damage_min"),
		GameConfig.zonei(Game.map_zone, "gray_damage_max"))
	e2.position = spot
	e2.home_position = spot
	add_child(e2)
	Game.enemies.append(e2)

## Случайная проходимая клетка не ближе gray_respawn_min_dist от героя.
func _gray_respawn_cell() -> Vector2i:
	var min_d := maxi(4, GameConfig.geti("spawn", "gray_respawn_min_dist"))
	var mw: int = int(alm_map.get("map_width"))
	var mh: int = int(alm_map.get("map_height"))
	if mw <= 0 or mh <= 0:
		return Vector2i(-1, -1)
	var px := int(player.global_position.x / 32)
	var py := int(player.global_position.y / 32)
	for _i in range(80):
		var c := Vector2i(randi_range(2, mw - 3), randi_range(2, mh - 3))
		if absi(c.x - px) < min_d or absi(c.y - py) < min_d:
			continue
		if not alm_map.call("is_walkable_world", Vector2(c.x * 32 + 16, c.y * 32 + 16)):
			continue
		return c
	return Vector2i(-1, -1)


func _process_action_mode():
	if action_mode == "none" or not is_instance_valid(player):
		return
	
	match action_mode:
		"follow":
			# Идти за ближайшим союзником (пока за ближайшим NPC)
			if action_target and is_instance_valid(action_target):
				player.attack_target = action_target
				player.state = "chase"
		"attack":
			# Атаковать ближайшего врага
			if enemies.size() > 0:
				var nearest = null
				var min_dist = 9999.0
				for e in enemies:
					if is_instance_valid(e):
						var d = e.global_position.distance_to(player.global_position)
						if d < min_dist:
							min_dist = d
							nearest = e
				if nearest:
					player.attack_target = nearest
					player.state = "chase"
		"guard":
			# Стоять на месте и атаковать врагов в радиусе
			if player.state == "idle":
				for e in enemies:
					if is_instance_valid(e) and e.global_position.distance_to(player.global_position) < 150:
						player.attack_target = e
						player.state = "chase"
						break

# === Сохранения ===
#
# Меню само ничего не сохраняет: оно только сообщает о нажатии. Всё
# сохранение и загрузка - здесь, потому что только у game.gd есть живой
# игрок, WorldBus с состоянием мира и сцена, которую надо пересобрать.

## Открыть меню сохранений (Esc). Повторный вызов игнорируется.
func open_save_menu() -> void:
	if _save_menu != null and is_instance_valid(_save_menu):
		return
	_save_menu = SaveMenu.new()
	_save_menu.setup()
	_save_menu.save_requested.connect(_save_to_slot)
	_save_menu.load_requested.connect(_load_from_slot)
	_save_menu.delete_requested.connect(_delete_slot)
	_save_menu.quit_requested.connect(_quit_to_menu)
	_save_menu.quit_app_requested.connect(_quit_app)
	_save_menu.closed.connect(func() -> void: _save_menu = null)
	add_child(_save_menu)


## Собрать payload из живого состояния. world приходит снаружи, чтобы
## тест мог подставить свой WorldState без поднятия сцены.
func _build_save_payload() -> Dictionary:
	var world_dict: Dictionary = {}
	# WorldBus - это AUTOLOAD, а не GDExtension-синглтон, поэтому
	# Engine.has_singleton() его не видит: берём узел из дерева сцены.
	if is_inside_tree():
		var bus = get_node_or_null("/root/WorldBus")
		if bus != null and "state" in bus and bus.state != null:
			world_dict = bus.state.to_dict()
	return SaveSystem.build_payload(player, world_dict)


func _save_to_slot(slot: String) -> void:
	var err := SaveSystem.save(slot, _build_save_payload())
	if err != "":
		if _save_menu != null and is_instance_valid(_save_menu):
			_save_menu.set_status(tr("Не удалось сохранить: %s") % err)
		else:
			push_error("SaveSystem: " + err)
		return
	if _save_menu != null and is_instance_valid(_save_menu):
		_save_menu.set_status(tr("Сохранено в слот."))
		_save_menu._refresh()


func _load_from_slot(slot: String) -> void:
	var res := SaveSystem.load_slot(slot)
	var err_kind := str(res.get("error", ""))
	if err_kind == "version":
		_set_menu_status(tr("Сохранение сделано более новой версией игры (файл v%d, игра v%d) — загрузка отменена.")
			% [int(res.get("file_version", 0)), SaveSystem.VERSION])
		return
	if err_kind == "corrupt":
		_set_menu_status(tr("Файл сохранения повреждён и резервной копии нет."))
		return
	if res.is_empty():
		_set_menu_status(tr("Слот пуст."))
		return
	# Сначала применяем героя и сид карты, потом пересобираем сцену:
	# AlmMap читает Game.map_seed/map_zone в _ready.
	SaveSystem.apply_payload(res.get("data", {}), player)
	_restart_scene(slot)


func _delete_slot(slot: String) -> void:
	for p in [SaveSystem.slot_path(slot), SaveSystem.bak_path(slot), SaveSystem.tmp_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if _save_menu != null and is_instance_valid(_save_menu):
		_save_menu.set_status(tr("Слот удалён."))
		_save_menu._refresh()


func _quit_to_menu() -> void:
	# Паузу обязательно снять: иначе главное меню откроется в остановленном
	# дереве — без анимации фона и без реакции на ввод. Игрок жал Пробел (пауза)
	# и уходил в меню по Esc, а `get_tree().paused` оставалось в true.
	is_paused = false
	get_tree().paused = false
	_save_to_slot(SaveSystem.AUTOSAVE_SLOT)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Полный выход из процесса (кнопка «Выйти из игры» в Esc-меню).
func _quit_app() -> void:
	_save_to_slot(SaveSystem.AUTOSAVE_SLOT)
	get_tree().quit()


## Пересобрать игру из сохранённого состояния. Мир сначала кладём в
## WorldBus - иначе новая сцена поднимется со старым сидом, а состояние
## мира потеряется.
func _restart_scene(slot: String) -> void:
	var res := SaveSystem.load_slot(slot)
	var data: Dictionary = res.get("data", {})
	var world_text := JsonSafe.dump(data.get("world", {}))
	var ws_script: GDScript = load("res://scripts/world/world_state.gd")
	var restored = ws_script.from_json_text(world_text)
	var bus = get_node_or_null("/root/WorldBus")
	if bus != null and "state" in bus and restored != null:
		bus.state = restored
		# Симулятор держит ссылку на СТАРЫЙ WorldState, иначе после загрузки
		# он продолжит тикать по прежнему миру, а не по загруженному.
		if "sim" in bus and bus.sim != null and "state" in bus.sim:
			bus.sim.state = restored
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _set_menu_status(text: String) -> void:
	if _save_menu != null and is_instance_valid(_save_menu):
		_save_menu.set_status(text)


## Разовый автосейв (портал, выход из интерьера). Тот же слот, что и таймер.
func autosave_now() -> void:
	if not is_instance_valid(player):
		return
	if _save_menu != null and is_instance_valid(_save_menu):
		return
	var err := SaveSystem.save(SaveSystem.AUTOSAVE_SLOT, _build_save_payload())
	if err != "":
		push_error("SaveSystem autosave: " + err)


## Автосейв по таймеру. Пропускаем, если открыто меню сохранений (иначе
## игрок жмёт «Сохранить» и тут же получает автосейв поверх).
func _autosave_tick(delta: float) -> void:
	_autosave_accum += delta
	if _autosave_accum < autosave_interval():
		return
	_autosave_accum = 0.0
	if _save_menu != null and is_instance_valid(_save_menu):
		return
	if not is_instance_valid(player):
		return
	SaveSystem.save(SaveSystem.AUTOSAVE_SLOT, _build_save_payload())


## Сохранить при выходе из игры. Вызывается из project.godot
## (autoload-free), поэтому подписка выполняется в _ready.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if is_instance_valid(player):
			SaveSystem.save(SaveSystem.AUTOSAVE_SLOT, _build_save_payload())
