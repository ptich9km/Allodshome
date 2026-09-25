class_name StatusEffects
extends Node
## Временные эффекты на юнитах (баффы, дебаффы, яды, вампиризм).
##
## Эффекты НЕ трогают базовые статы юнита — они лежат в meta("statuses")
## и читаются через функции ниже. Базовые get_* в player/enemy/npc/mercenary
## остаются чистыми, а модификаторы накладываются поверх (modifier-слой).
##
## Формат записи:
##   {"type": String, "time_left": float, ...поля эффекта}
##
## Типы: shield/resist/bless/haste/slow/invisibility/curse/vision/
##       vampirism/dot
##
## Тик вызывается из Game._process рядом с Game.tick_shields.

const META := "statuses"
const MAX_DOT_STACKS := 3

## Типы эффектов, полезных противнику (их накладывают на врага).
const HOSTILE := ["slow", "curse", "vision", "dot", "root"]
## Типы эффектов, полезных союзнику (накладывают на героя/наёмника/НПЦ).
const FRIENDLY := ["shield", "resist", "bless", "haste", "invisibility", "vampirism"]


static func _all(unit: Node2D) -> Array:
	if unit == null or not is_instance_valid(unit):
		return []
	# Именно has_meta: get_meta без существующего ключа печатает ошибку в
	# консоль, а сюда попадают все юниты каждый кадр — это тысячи ошибок/сек.
	if not unit.has_meta(META):
		return []
	var list: Variant = unit.get_meta(META)
	if list is Array:
		return list
	return []


static func _store(unit: Node2D, list: Array) -> void:
	if is_instance_valid(unit):
		unit.set_meta(META, list)


static func find_index(unit: Node2D, type: String) -> int:
	var list := _all(unit)
	for i in range(list.size()):
		if str((list[i] as Dictionary).get("type", "")) == type:
			return i
	return -1


# --- Применение -----------------------------------------------------------

## Наложить все эффекты заклинания на юнита. Повторное наложение обновляет
## длительность и берёт более сильное значение, а не копится бесконечно.
static func apply_spell(unit: Node2D, spell: Dictionary, _caster: Node2D = null) -> int:
	if not is_instance_valid(unit) or spell.is_empty():
		return 0
	var applied := 0
	for raw in spell.get("effects", []):
		if not (raw is Dictionary):
			continue
		if _apply_one(unit, raw as Dictionary, _caster):
			applied += 1
	return applied


## Наложить эффекты на всех юнитов в радиусе: враждебные — на врагов,
## дружественные — на героя и отряд. Возвращает число затронутых.
static func apply_area(center: Vector2, radius: float, spell: Dictionary, caster: Node2D) -> int:
	var touched := 0
	for unit in _units_in_radius(center, radius):
		var hostile := _enemy_of(caster, unit)
		for raw in spell.get("effects", []):
			if not (raw is Dictionary):
				continue
			var type := str((raw as Dictionary).get("type", ""))
			var is_hostile := HOSTILE.has(type)
			if is_hostile != hostile:
				continue
			if _apply_one(unit, raw as Dictionary, caster):
				touched += 1
	return touched


static func _apply_one(unit: Node2D, effect: Dictionary, caster: Node2D) -> bool:
	var type := str(effect.get("type", ""))
	if type == "":
		return false
	var list := _all(unit)

	# Яд копится до предела, остальное — обновляет один слот.
	if type == "dot":
		var dots := 0
		for e in list:
			if str((e as Dictionary).get("type", "")) == "dot":
				dots += 1
		if dots >= MAX_DOT_STACKS:
			return false

	# Щит идёт в существующий meta-щит Game (он уже тикается в Game.tick_shields).
	if type == "shield":
		Game.apply_shield(unit, int(effect.get("amount", 0)), float(effect.get("duration", 30.0)))
		return true

	var entry := effect.duplicate(true)
	entry.erase("type")
	entry["type"] = type
	var duration := float(effect.get("duration", 10.0))
	# В оригинале сопротивление режет не только урон, но и ДЛИТЕЛЬНОСТЬ
	# огненных/магических эффектов (spells.txt у Protection_from_*).
	if type == "dot" and effect.has("sphere"):
		duration *= _resist_factor(unit, str(effect.get("sphere", "")))
	entry["time_left"] = duration
	entry["caster"] = caster
	entry["target"] = unit

	var i := find_index(unit, type)
	if i < 0:
		list.append(entry)
	else:
		var old: Dictionary = list[i]
		entry["time_left"] = maxf(float(old.get("time_left", 0.0)), float(entry["time_left"]))
		# Яд копится, остальное берёт максимум (медленнее = сильнее).
		if type == "dot":
			list.append(entry)
		else:
			for key in entry.keys():
				var key_s := str(key)
				if key_s in ["time_left", "type", "caster"]:
					continue
				if key_s in old and _is_numeric(key_s):
					entry[key] = _stronger(key_s, old[key], entry[key])
			list[i] = entry
	_store(unit, list)
	return true


static func _is_numeric(key: String) -> bool:
	return key in ["amount", "mult", "defense", "attack", "ratio", "dps", "duration"]


## Доля от сопротивления стихии: 100 % резиста обнуляет длительность яда.
static func _resist_factor(unit: Node2D, sphere: String) -> float:
	if sphere == "":
		return 1.0
	var prot := Game.unit_protection(unit, sphere)
	return clampf(1.0 - float(prot) / 100.0, 0.0, 1.0)


static func _stronger(key: String, a: Variant, b: Variant) -> Variant:
	# Для mult/duration больше = сильнее, для defense (может быть отрицательным)
	# больше по модулю = сильнее.
	if key in ["mult", "duration", "amount", "dps", "attack"]:
		return maxf(float(a), float(b))
	if key == "defense":
		return a if absf(float(a)) >= absf(float(b)) else b
	return a


static func remove(unit: Node2D, type: String) -> void:
	var list := _all(unit)
	for i in range(list.size() - 1, -1, -1):
		if str((list[i] as Dictionary).get("type", "")) == type:
			list.remove_at(i)
	_store(unit, list)


static func clear(unit: Node2D) -> void:
	_store(unit, [])


# --- Тик ------------------------------------------------------------------

## Уменьшить таймеры, нанести тики яда, снять истёкшие эффекты.
static func tick(delta: float) -> void:
	for unit in _all_units():
		if not is_instance_valid(unit):
			continue
		var list := _all(unit)
		if list.is_empty():
			continue
		for i in range(list.size() - 1, -1, -1):
			var e: Dictionary = list[i]
			e["time_left"] = float(e.get("time_left", 0.0)) - delta
			if str(e.get("type", "")) == "dot":
				_tick_dot(e, delta)
			if float(e["time_left"]) <= 0.0:
				list.remove_at(i)
		_store(unit, list)


## Яд тикает раз в секунду целым уроном, чтобы не сыпать дробные числа на экран.
static func _tick_dot(e: Dictionary, delta: float) -> void:
	var dps := float(e.get("dps", 0.0))
	if dps <= 0.0:
		return
	e["acc"] = float(e.get("acc", 0.0)) + delta
	if float(e["acc"]) < 1.0:
		return
	e["acc"] = float(e["acc"]) - 1.0
	var target: Variant = e.get("target", null)
	if is_instance_valid(target):
		Game.deal_damage(target as Node2D, maxi(1, int(dps)), "magic",
			str(e.get("sphere", "")), e.get("caster", null) as Node2D)


static func _all_units() -> Array:
	var out: Array = [Game.hero]
	out.append_array(Game.enemies)
	out.append_array(Game.npcs)
	out.append_array(Game.party)
	return out


# --- Запросы --------------------------------------------------------------

static func speed_mult(unit: Node2D) -> float:
	if is_rooted(unit):
		return 0.0
	var m := 1.0
	for e in _all(unit):
		var t := str(e.get("type", ""))
		if t == "haste":
			m *= maxf(0.1, float(e.get("mult", 1.0)))
		elif t == "slow":
			m *= clampf(float(e.get("mult", 1.0)), 0.1, 2.0)
	return clampf(m, 0.1, 3.0)


## Каменное проклятие: «Temporarily turns a single target to stone»
## (spells.txt) — цель не двигается.
static func is_rooted(unit: Node2D) -> bool:
	return find_index(unit, "root") >= 0


static func vision_mult(unit: Node2D) -> float:
	var m := 1.0
	for e in _all(unit):
		if str(e.get("type", "")) == "vision":
			m *= clampf(float(e.get("mult", 1.0)), 0.1, 2.0)
	return clampf(m, 0.1, 2.0)


## Плоская прибавка к attack/defense (bless).
static func stat_flat(unit: Node2D, stat: String) -> int:
	var v := 0.0
	for e in _all(unit):
		if str(e.get("type", "")) == "bless":
			v += float(e.get(stat, 0))
	return int(round(v))


## Множитель защиты (curse сокращает, сжат снизу на 0.25).
static func defense_mult(unit: Node2D) -> float:
	var m := 1.0
	for e in _all(unit):
		if str(e.get("type", "")) == "curse":
			m += float(e.get("defense", 0.0))
	return clampf(m, 0.25, 3.0)


## Временное сопротивление стихии (Protection_from_*).
static func resist_bonus(unit: Node2D, sphere: String) -> int:
	var v := 0.0
	for e in _all(unit):
		if str(e.get("type", "")) == "resist" and str(e.get("sphere", "")) == sphere:
			v += float(e.get("amount", 0))
	return int(round(v))


static func is_invisible(unit: Node2D) -> bool:
	return find_index(unit, "invisibility") >= 0


## Невидимость срывается при атаке.
static func break_invisibility(unit: Node2D) -> void:
	remove(unit, "invisibility")


## Доля возвращаемого урона при касте (vampirism на КАСТЕРЕ).
static func vampirism_ratio(unit: Node2D) -> float:
	var v := 0.0
	for e in _all(unit):
		if str(e.get("type", "")) == "vampirism":
			v += float(e.get("ratio", 0.0))
	return clampf(v, 0.0, 1.0)


## Типы активных эффектов — для UI-индикаторов.
static func active_types(unit: Node2D) -> Array:
	var out: Array = []
	for e in _all(unit):
		var t := str(e.get("type", ""))
		if t != "" and not out.has(t):
			out.append(t)
	return out


static func time_left(unit: Node2D, type: String) -> float:
	var i := find_index(unit, type)
	return 0.0 if i < 0 else float((_all(unit)[i] as Dictionary).get("time_left", 0.0))


# --- Вспомогательное ------------------------------------------------------

## Наложить ТОЛЬКО враждебные эффекты на всех юнитов в радиусе.
## Так вызывается взрыв снаряда: яд/замедление ложатся на врагов, а
## вампиризм и прочие «на себя» эффекты сюда не подставляются.
static func apply_hostile_area(center: Vector2, radius: float, spell: Dictionary, caster: Node2D) -> int:
	var touched := 0
	for unit in _units_in_radius(center, radius):
		if _enemy_of(caster, unit) == false and unit != caster:
			continue
		for raw in spell.get("effects", []):
			if not (raw is Dictionary):
				continue
			if not HOSTILE.has(str((raw as Dictionary).get("type", ""))):
				continue
			if _apply_one(unit, raw as Dictionary, caster):
				touched += 1
	return touched


static func _enemy_of(caster: Node2D, unit: Node2D) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false
	return Game.enemies.has(caster) or (unit != caster and not _ally_of(caster, unit))


static func _ally_of(a: Node2D, b: Node2D) -> bool:
	if a == b:
		return true
	if Game.party.has(a) and Game.party.has(b):
		return true
	if Game.npcs.has(a) and Game.npcs.has(b):
		return true
	return false


static func _units_in_radius(center: Vector2, radius: float) -> Array:
	var out: Array = []
	for unit in _all_units():
		if not is_instance_valid(unit):
			continue
		if unit.global_position.distance_to(center) <= radius:
			out.append(unit)
	return out
