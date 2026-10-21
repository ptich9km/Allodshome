extends Node
class_name EventSystem
## Динамические события на карте героя (19.10).
##
## Что это: на карте периодически появляется «стычка» — две враждебные
## группы Серых сходятся и дерутся по обычному боевому конвейеру
## (Game.deal_damage). Событие живёт ttl_seconds реального времени, потом
## деспавнится; маркер на миникарте виден всегда (решение игрока).
##
## Почему реальное время: день мира в живой игре не тикает (world_bus.gd,
## «сим-мир НЕ тикает»), поэтому TTL — секунды.
##
## Вне поля зрения героя бой тикает «дёшево»: раз в ABSTRACT_TICK сек
## стороны обмениваются половинным уроном через Game.deal_damage. В поле
## зрения — обычный FSM enemy.gd с foe_group.

const ABSTRACT_TICK := 2.0        # сек между «дешёвыми» обменами ударами
const BATTLE_RADIUS_PX := 600.0   # радиус поиска противника в стычке
const GROUP_GAP_CELLS := 4        # клетки между центрами групп

static var instance: EventSystem = null

var _events: Array[Dictionary] = []   # активные события текущей карты
var _spawn_accum := 0.0
var _abstract_accum := 0.0
var _map_key := ""                    # "seed:zone:w:h" текущей карты
var _next_event_id := 1

func _ready() -> void:
	add_to_group("events")
	instance = self
	if MinimapMarkers.instance == null:
		MinimapMarkers.new()
	tree_exiting.connect(_on_exiting)

func _on_exiting() -> void:
	if instance == self:
		instance = null

func _process(delta: float) -> void:
	if GameConfig.geti("events", "enabled") == 0:
		return
	_check_map_changed()
	if MinimapMarkers.instance != null:
		MinimapMarkers.instance.tick_life(delta)
	# Жизнь событий (TTL в реальных секундах).
	for ev in _events.duplicate():
		ev["ttl_left"] = float(ev["ttl_left"]) - delta
		if float(ev["ttl_left"]) <= 0.0:
			_expire_event(ev)
	# Абстрактное разрешение боёв вне видимости героя.
	_abstract_accum += delta
	if _abstract_accum >= ABSTRACT_TICK:
		_abstract_accum = 0.0
		_abstract_tick()
	# Спавн новых событий.
	_spawn_accum += delta
	var period := GameConfig.getf("events", "spawn_period")
	if period <= 0.0 or _spawn_accum < period:
		return
	_spawn_accum = 0.0
	if randi() % 100 >= GameConfig.geti("events", "spawn_chance"):
		return
	_try_spawn_event()

## Смена карты (портал): локальные события и маркеры обнуляются; сейв
## хранит события отдельно и материализует их на нужной карте.
func _check_map_changed() -> void:
	var map: Node = get_tree().get_first_node_in_group("alm_map")
	if map == null:
		return
	var key := "%d:%s:%d:%d" % [Game.map_seed, Game.map_zone,
		int(map.get("map_width")), int(map.get("map_height"))]
	if key == _map_key:
		return
	_map_key = key
	for ev in _events:
		_free_event_units(ev)
	_events.clear()
	if MinimapMarkers.instance != null:
		MinimapMarkers.instance.clear_all()
	# События из сейва (19.10): материализуются один раз для этой карты.
	if Game.pending_events.size() > 0:
		if GameConfig.geti("events", "enabled") != 0:
			apply_payload(Game.pending_events)
		Game.pending_events = []

## Попытка заспавнить стычку. Возвращает id события или 0.
func _try_spawn_event() -> int:
	if _events.size() >= GameConfig.geti("events", "max_active"):
		return 0
	var map: Node = get_tree().get_first_node_in_group("alm_map")
	if map == null or Game.hero == null or not is_instance_valid(Game.hero):
		return 0
	var cell := _event_cell(map)
	if cell.x < 0:
		return 0
	# Пара наборов для стычки: разные семейства, затем разные виды, иначе
	# любые два разных набора пула (см. _pick_event_sets).
	var pool: Array = MapGenerator.gray_pool_for_zone(Game.map_zone)
	if pool.is_empty():
		return 0
	var pair: Array = _pick_event_sets(pool)
	if pair.size() < 2:
		return 0
	var set_a := str(pair[0])
	var set_b := str(pair[1])
	var ttl := randf_range(GameConfig.getf("events", "ttl_seconds_min"),
		GameConfig.getf("events", "ttl_seconds_max"))
	var ev := _new_event(cell, set_a, set_b, ttl)
	_spawn_group(map, ev, "a", set_a, cell, -1)
	_spawn_group(map, ev, "b", set_b, cell, 1)
	if (ev["members_a"] as Array).is_empty() or (ev["members_b"] as Array).is_empty():
		_free_event_units(ev)
		return 0
	_events.append(ev)
	_attach_marker(ev, ttl)
	print("EVENT: стычка %s против %s в (%d,%d), %.0f сек" % [
		set_a, set_b, cell.x, cell.y, ttl])
	return int(ev["id"])

func _new_event(cell: Vector2i, set_a: String, set_b: String, ttl: float) -> Dictionary:
	var ev := {
		"id": _next_event_id, "kind": "battle",
		"cell_x": cell.x, "cell_y": cell.y,
		"ttl_left": ttl,
		"tag_a": "ev%d_a" % _next_event_id,
		"tag_b": "ev%d_b" % _next_event_id,
		"set_a": set_a, "set_b": set_b,
		"members_a": [], "members_b": [],
	}
	_next_event_id += 1
	return ev

func _attach_marker(ev: Dictionary, ttl: float) -> void:
	if MinimapMarkers.instance == null:
		return
	var cell := Vector2i(int(ev["cell_x"]), int(ev["cell_y"]))
	ev["marker_id"] = MinimapMarkers.instance.add(MinimapMarkers.Kind.BATTLE,
		cell, ttl, Game.map_seed, Game.map_zone)

## Клетка события: проходимая, 400-900 px от героя, вне городов (структур).
func _event_cell(map: Node) -> Vector2i:
	var tile := int(map.get("tile_size"))
	var mw := int(map.get("map_width"))
	var mh := int(map.get("map_height"))
	if mw <= 0 or mh <= 0:
		return Vector2i(-1, -1)
	var hero_cell := Vector2i(
		int(Game.hero.global_position.x) / tile,
		int(Game.hero.global_position.y) / tile)
	var dmin := GameConfig.geti("events", "spawn_min_dist") / tile
	var dmax := GameConfig.geti("events", "spawn_max_dist") / tile
	for _attempt in range(120):
		var ang := randf() * TAU
		var dist := float(randi_range(dmin, dmax))
		var cell := hero_cell + Vector2i(int(cos(ang) * dist), int(sin(ang) * dist))
		if cell.x < 2 or cell.y < 2 or cell.x >= mw - 2 or cell.y >= mh - 2:
			continue
		if not _cell_free(map, cell):
			continue
		return cell
	return Vector2i(-1, -1)

## Клетка свободна: проходима и в радиусе 2 клеток нет зданий (не город).
func _cell_free(map: Node, cell: Vector2i) -> bool:
	var tile := int(map.get("tile_size"))
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := cell + Vector2i(dx, dy)
			var pos := Vector2(float((c.x + 0.5) * tile), float((c.y + 0.5) * tile))
			if not bool(map.call("is_walkable_world", pos)):
				return false
			if map.has_method("structure_at") \
					and not (map.call("structure_at", c) as Dictionary).is_empty():
				return false
	return true
## Пара наборов для стычки: сначала разные семейства (loot_family), затем
## разные виды (имя без "_tN"), иначе любые два разных набора пула.
func _pick_event_sets(pool: Array) -> Array:
	var by_family := {}
	var by_species := {}
	for s in pool:
		var nm := str(s)
		if not UnitDB.has(nm):
			continue
		var fam := UnitDB.loot_family(nm)
		if fam == "":
			fam = "default"
		if not by_family.has(fam):
			by_family[fam] = nm
		var species := nm
		var idx := nm.rfind("_t")
		if idx > 0:
			var tail := nm.substr(idx + 2)
			var digits := true
			for ch in tail:
				if not (ch >= "0" and ch <= "9"):
					digits = false
					break
			if digits:
				species = nm.substr(0, idx)
		if not by_species.has(species):
			by_species[species] = nm
	if by_family.size() >= 2:
		var keys: Array = by_family.keys()
		return [str(by_family[keys[0]]), str(by_family[keys[1]])]
	if by_species.size() >= 2:
		var keys2: Array = by_species.keys()
		return [str(by_species[keys2[0]]), str(by_species[keys2[1]])]
	if pool.size() >= 2:
		return [str(pool[0]), str(pool[1])]
	return []

## Спавн группы стычки: центр группы = cell со сдвигом side_dir клеток.
func _spawn_group(map: Node, ev: Dictionary, side: String, set_name: String,
		center: Vector2i, side_dir: int) -> void:
	var tile := int(map.get("tile_size"))
	var my_tag := str(ev["tag_" + side])
	var other := "b" if side == "a" else "a"
	var foe_tag := str(ev["tag_" + other])
	var placed: Array = ev["members_" + side]
	var count := randi_range(GameConfig.geti("events", "members_min"),
		GameConfig.geti("events", "members_max"))
	var mults: Array = MapGenerator.gray_tier_mults(set_name)
	for _k in range(count):
		var off := Vector2i(side_dir * (GROUP_GAP_CELLS + randi() % 2), randi_range(-2, 2))
		var c := center + off
		var pos := Vector2(float((c.x + 0.5) * tile), float((c.y + 0.5) * tile))
		if not bool(map.call("is_walkable_world", pos)):
			continue
		var e := Enemy.new()
		e.name = "EventMonster_%s" % set_name.get_file()
		e.anim_set = set_name
		e.max_hp = int(round(float(randi_range(
			GameConfig.zonei(Game.map_zone, "gray_hp_min"),
			GameConfig.zonei(Game.map_zone, "gray_hp_max"))) * float(mults[0])))
		e.damage = int(round(float(randi_range(
			GameConfig.zonei(Game.map_zone, "gray_damage_min"),
			GameConfig.zonei(Game.map_zone, "gray_damage_max"))) * float(mults[1])))
		e.position = pos
		e.home_position = pos
		e.event_tag = my_tag
		e.foe_group = foe_tag
		var host := get_parent()
		if host == null:
			host = get_tree().current_scene
		if host == null:
			e.queue_free()
			continue
		host.add_child(e)
		Game.enemies.append(e)
		placed.append(e)

## Цель для участника стычки (вызывается из Enemy._combat_target).
static func foe_for(e: Enemy) -> Node2D:
	if instance == null:
		return null
	return instance._foe_for(e)

func _foe_for(e: Enemy) -> Node2D:
	for ev in _events:
		var tag_a := str(ev["tag_a"])
		var tag_b := str(ev["tag_b"])
		if e.event_tag != tag_a and e.event_tag != tag_b:
			continue
		var best: Node2D = null
		var bd := BATTLE_RADIUS_PX
		for other in Game.enemies:
			if other == null or not is_instance_valid(other):
				continue
			var o: Enemy = other as Enemy
			if o == null or o.event_tag != e.foe_group:
				continue
			if o.state == "dying" or o.state == "decay" or o.state == "corpse":
				continue
			var d := Game.units_range(e, o)
			if d < bd:
				bd = d
				best = o
		return best
	return null

## «Дешёвое» разрешение боёв вне поля зрения героя.
func _abstract_tick() -> void:
	var fog: Node = get_tree().get_first_node_in_group("fog")
	for ev in _events.duplicate():
		var pos := Vector2(float(int(ev["cell_x"]) + 1) * 16.0,
			float(int(ev["cell_y"]) + 1) * 16.0)
		var visible_now := false
		if fog != null and bool(fog.get("enabled")) \
				and int(fog.call("state_at_world", pos)) == FogOfWar.STATE_VISIBLE:
			visible_now = true
		if visible_now:
			continue   # бой на глазах у игрока — рулит настоящий FSM
		var a: Enemy = _first_alive(ev, "members_a")
		var b: Enemy = _first_alive(ev, "members_b")
		if a == null or b == null:
			_finish_event(ev)
			continue
		var dmg_a := maxi(1, int(round(float(a.damage) * 0.5)))
		var dmg_b := maxi(1, int(round(float(b.damage) * 0.5)))
		Game.deal_damage(b, dmg_a, "physical", "", a)
		Game.deal_damage(a, dmg_b, "physical", "", b)
		if _first_alive(ev, "members_a") == null or _first_alive(ev, "members_b") == null:
			_finish_event(ev)

func _first_alive(ev: Dictionary, key: String) -> Enemy:
	for u in ev[key]:
		# Каст на ОСВОБОЖДЁННОМ объекте бросает «Trying to cast a freed
		# object» — сначала проверка по Variant, потом каст.
		if u is Object and is_instance_valid(u) == false:
			continue
		var e: Enemy = u as Enemy
		if e != null and is_instance_valid(e) \
				and e.state != "dying" and e.state != "decay" and e.state != "corpse":
			return e
	return null

## Стычка кончилась: выжившие становятся обычными Серыми.
func _finish_event(ev: Dictionary) -> void:
	_clear_tags(ev)
	_remove_marker(ev)
	_events.erase(ev)
	print("EVENT: стычка %d завершилась" % int(ev["id"]))

## Стычка истекла по времени: выжившие деспавнятся без лута.
func _expire_event(ev: Dictionary) -> void:
	_free_event_units(ev)
	_remove_marker(ev)
	_events.erase(ev)
	print("EVENT: стычка %d истекла по времени" % int(ev["id"]))

func _clear_tags(ev: Dictionary) -> void:
	for key in ["members_a", "members_b"]:
		for u in ev[key]:
			var e: Enemy = u as Enemy
			if e != null and is_instance_valid(e):
				e.event_tag = ""
				e.foe_group = ""

func _free_event_units(ev: Dictionary) -> void:
	for key in ["members_a", "members_b"]:
		for u in ev[key]:
			var e: Enemy = u as Enemy
			if e != null and is_instance_valid(e):
				Game.enemies.erase(e)
				e.queue_free()

func _remove_marker(ev: Dictionary) -> void:
	if MinimapMarkers.instance != null and ev.has("marker_id"):
		MinimapMarkers.instance.remove(int(ev["marker_id"]))

## --- Сериализация (save_system.gd, payload.events) ------------------------

## Активные события в JSON-виде. Узлы не сериализуемы — только данные.
func to_payload() -> Array:
	var out: Array = []
	for ev in _events:
		out.append({
			"kind": str(ev["kind"]),
			"cell_x": int(ev["cell_x"]), "cell_y": int(ev["cell_y"]),
			"ttl_left": float(ev["ttl_left"]),
			"set_a": str(ev["set_a"]), "set_b": str(ev["set_b"]),
			"seed": int(Game.map_seed), "zone": str(Game.map_zone),
		})
	return out

## Материализовать события из сейва (только те, что для текущей карты).
func apply_payload(list: Array) -> void:
	for d in list:
		var rec: Dictionary = d as Dictionary
		if int(rec.get("seed", -1)) != Game.map_seed \
				or str(rec.get("zone", "")) != Game.map_zone:
			continue
		_respawn_event(rec)

func _respawn_event(rec: Dictionary) -> void:
	var map: Node = get_tree().get_first_node_in_group("alm_map")
	if map == null:
		return
	var cell := Vector2i(int(rec.get("cell_x", -1)), int(rec.get("cell_y", -1)))
	var set_a := str(rec.get("set_a", ""))
	var set_b := str(rec.get("set_b", ""))
	if cell.x < 0 or set_a == "" or set_b == "" \
			or not UnitDB.has(set_a) or not UnitDB.has(set_b):
		return
	var ttl := maxf(10.0, float(rec.get("ttl_left", 90.0)))
	var ev := _new_event(cell, set_a, set_b, ttl)
	_spawn_group(map, ev, "a", set_a, cell, -1)
	_spawn_group(map, ev, "b", set_b, cell, 1)
	if (ev["members_a"] as Array).is_empty() or (ev["members_b"] as Array).is_empty():
		_free_event_units(ev)
		return
	_events.append(ev)
	_attach_marker(ev, ttl)

## --- Тесты -----------------------------------------------------------------

## Форс-спавн события в заданной клетке (детерминизм в смоке). Возвращает id.
func debug_spawn_event_at(cell: Vector2i, set_a: String, set_b: String) -> int:
	var map: Node = get_tree().get_first_node_in_group("alm_map")
	if map == null or set_a == "" or set_b == "" \
			or not UnitDB.has(set_a) or not UnitDB.has(set_b):
		return 0
	var ttl := GameConfig.getf("events", "ttl_seconds_max")
	var ev := _new_event(cell, set_a, set_b, ttl)
	_spawn_group(map, ev, "a", set_a, cell, -1)
	_spawn_group(map, ev, "b", set_b, cell, 1)
	if (ev["members_a"] as Array).is_empty() or (ev["members_b"] as Array).is_empty():
		_free_event_units(ev)
		return 0
	_events.append(ev)
	_attach_marker(ev, ttl)
	return int(ev["id"])

## Тестовый хук: немедленно истечить все события.
func debug_expire_all() -> void:
	for ev in _events.duplicate():
		_expire_event(ev)

func event_count() -> int:
	return _events.size()
