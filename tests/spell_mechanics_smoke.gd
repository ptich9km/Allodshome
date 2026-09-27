extends SceneTree
## Headless-проверка МЕХАНИКИ заклинаний, которые раньше не работали.
##
## Проверяет то, что нельзя увидеть в базе данных:
##  1. Teleport — прицел точкой (target=point) и реальное перемещение;
##  2. стена ровно 6 клеток × 2 ряда: урон, спрайт и блок берут ОДИН размер;
##  3. Prismatic_Spray бьёт 4..6 целей, а не одну.
##
## Запуск:
##   godot --headless --path . --script res://tests/spell_mechanics_smoke.gd

const ORIGIN := Vector2(600, 600)

var _fails: Array = []
var _hero: Player = null


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 13, "spirit": 12,
		"blade": 10, "bludgeon": 10, "pike": 10, "shooting": 10,
		"fire": 20, "water": 20, "air": 20, "earth": 20, "astral": 20,
		"weapon": "staff", "shield": false, "armor": "light"}
	Game.hero_class = "mage"
	Game.hero_name = "Маг"
	Game.debug_magic = true
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("MECH: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	# Сцена из main.tscn, а не голый root: SpellVFX._scene() берёт current_scene,
	# и без загруженной сцены стены/ауры просто не создаются (тест прошёл бы
	# вхолостую, проверяя null вместо поведения).
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "загрузка main.tscn: %d" % err)
		_finish()
		return
	await process_frame
	await create_timer(0.6).timeout
	_hero = get_first_node_in_group("player") as Player
	_check(_hero != null, "герой загружен со сцены")
	if _hero == null:
		_finish()
		return
	_hero.set("current_mana", 999)
	_clear_map_enemies()
	_test_teleport()
	await _test_wall()
	await _test_chain()
	_finish()


## Убрать с карты живых Серых. Тест проверяет заклинания, а не бой: враг с
## реальной карты бьёт подставного противника, и проверка «стена земли не
## ранит» падала на 2 HP по чужой причине.
func _clear_map_enemies() -> void:
	# Стражи живут в Game.npcs и тоже бьют: 2 HP, потерянные подставным врагом,
	# ломали проверку «стена земли не ранит» — урон шёл не от стены.
	for n in Game.npcs.duplicate():
		Game.npcs.erase(n)
		if is_instance_valid(n) and n is Node:
			(n as Node).queue_free()
	_check(true, "с карты убраны стражи: %d" % Game.npcs.size())
	var cleared := 0
	for e in Game.enemies.duplicate():
		Game.enemies.erase(e)
		if is_instance_valid(e) and e is Node:
			(e as Node).queue_free()
			cleared += 1
	_check(true, "с карты убрано живых врагов: %d" % cleared)


# --- 1. Телепорт -----------------------------------------------------------

func _test_teleport() -> void:
	var spell := SpellDB.get_spell("Teleport")
	_check(SpellDB.target_of("Teleport") == "point",
		"Teleport целится точкой (было target=self — прицела не было)")
	_check(int(spell.get("range", 0)) > 0, "у Teleport есть дальность (%s)" % str(spell.get("range")))

	# Точка назначения — на проходимой клетке рядом с героем, иначе
	# is_walkable_world() отклонит каст и проверять будет нечего.
	var dest := _walkable_near(_hero.global_position, Vector2(96, 0))
	_check(dest != Vector2.ZERO, "найдена проходимая точка для телепорта")
	if dest == Vector2.ZERO:
		return
	_hero.global_position = ORIGIN
	_hero._teleport_to(dest)
	_check(_hero.global_position.distance_to(dest) < 1.0,
		"Teleport перемещает героя к точке (%.0f -> %.0f)"
			% [ORIGIN.x, _hero.global_position.x])

	# Второй каст отклоняем: та же точка = нулевой вектор, normalize() на этом
	# раньше сыпал C++-предупреждениями.
	var same := _hero.global_position
	_hero._teleport_to(same)
	_check(_hero.global_position.is_equal_approx(same),
		"Teleport в ту же точку не ломает позицию")


## Ближайшая проходимая точка в заданном направлении от точки отсчёта.
func _walkable_near(from: Vector2, dir: Vector2) -> Vector2:
	var map_node = get_first_node_in_group("alm_map")
	if map_node == null or not map_node.has_method("is_walkable_world"):
		return from + dir
	for step in range(1, 12):
		var p: Vector2 = from + dir * float(step)
		if bool(map_node.call("is_walkable_world", p)):
			return p
	return Vector2.ZERO


# --- 2. Стена 6 × 2 --------------------------------------------------------

func _test_wall() -> void:
	for name in ["Wall_of_Fire", "Wall_of_Earth"]:
		var cells: Variant = SpellDB.get_spell(name).get("zone_cells", null)
		# Godot парсит JSON-числа как float, поэтому 6 == 6.0 и сравниваем через int().
		var ok: bool = cells is Array and (cells as Array).size() == 2 \
			and int((cells as Array)[0]) == 6 and int((cells as Array)[1]) == 2
		_check(ok, "%s задан размером 6x2 клетки (%s)" % [name, str(cells)])

	# Спавн стены огня и проверка, что урон/спрайт/блок — один и тот же размер.
	var pos := _hero.global_position + Vector2(0, 120)
	var wall := SpellVFX.spawn_wall(pos, "Fire", _hero, 6.0, "damage", Vector2i(6, 2), 25)
	_check(wall != null, "стена огня создаётся")
	if wall == null:
		return
	await process_frame
	_check(wall.pixel_size() == Vector2(192, 64),
		"зона стены = 192x64 px (6x2 клетки), получено %s" % str(wall.pixel_size()))
	var covered := wall.covered_cells()
	_check(covered.size() == 12, "стена накрывает 12 клеток (6x2), получено %d" % covered.size())
	# Привязка к сетке: границы зоны должны лежать НА границах клеток,
	# иначе визуал врал бы про то, какие клетки накроет.
	_check(wall.in_telegraph(), "зона начинается с фазы подсказки (урон ещё не идёт)")
	# Отсчёт от фактического центра: после snap_to_grid() зона стоит на границе
	# клеток и может отличаться от точки клика на доли клетки.
	var ctr := wall.global_position
	var half := wall.pixel_size() * 0.5
	var left_edge := ctr.x - half.x
	var top_edge := ctr.y - half.y
	_check(is_equal_approx(fmod(absf(left_edge), 32.0), 0.0)
			or is_equal_approx(fmod(absf(left_edge), 32.0), 32.0),
		"левая граница стены лежит на границе клетки (x=%.1f)" % left_edge)
	_check(is_equal_approx(fmod(absf(top_edge), 32.0), 0.0)
			or is_equal_approx(fmod(absf(top_edge), 32.0), 32.0),
		"верхняя граница стены лежит на границе клетки (y=%.1f)" % top_edge)
	# Маска соседей: контур рисуется только там, где сосед СНАРУЖИ.
	# Верхне-левая угловая клетка 6x2: внутри только E, S и диагональ SE;
	# N, W, NE, NW, SW — снаружи (сверху и слева зоны нет).
	var corner := wall.first_cell()
	var cm := wall.neighbour_mask(corner)
	_check(cm == 2 | 4 | 32,
		"у верхне-левой угловой клетки открыты N и W (маска %d, ждём %d)"
			% [cm, 2 | 4 | 32])
	# В зоне высотой 2 клетки НЕТ позиции, у которой все 8 соседей внутри:
	# верхний ряд упирается в верх зоны, нижний — в низ. Это и правильно
	# (прямоугольник получает сплошной контур), но означает, что проверять надо
	# оба ряда по отдельности.
	var top_mid := wall.neighbour_mask(wall.first_cell() + Vector2i(2, 0))
	_check(top_mid == 2 | 4 | 8 | 32 | 64,
		"верхний ряд: N/NE/NW снаружи, S/E/W/SE/SW внутри (маска %d, ждём %d)"
			% [top_mid, 2 | 4 | 8 | 32 | 64])
	var bot_mid := wall.neighbour_mask(wall.first_cell() + Vector2i(2, 1))
	_check(bot_mid == 1 | 2 | 8 | 16 | 128,
		"нижний ряд: S/SE/SW снаружи, N/E/W/NE/NW внутри (маска %d, ждём %d)"
			% [bot_mid, 1 | 2 | 8 | 16 | 128])

	# Геометрия — чистая проверка, без зависимости от ИИ врагов.
	_check(wall.covers_point(ctr), "точка в центре стены внутри зоны")
	_check(wall.covers_point(ctr + Vector2(88, 20)), "край 6x2 (88, 20) внутри зоны")
	_check(not wall.covers_point(ctr + Vector2(104, 0)),
		"точка в 3 клетках вбок — снаружи зоны (иначе стена шире 6 клеток)")

	# Внутри зоны — урон, снаружи — нет. Врагов глушим: живой Enemy за 0.8 с
	# успевает подойти и самовольно войти в зону, и проверка врала бы.
	var inside := _spawn_foe(ctr)
	var outside := _spawn_foe(ctr + Vector2(160, 0))
	inside.max_hp = 400
	outside.max_hp = 400
	inside.current_hp = 400
	outside.current_hp = 400
	inside.move_speed = 0.0
	outside.move_speed = 0.0
	inside.set("state", "idle")
	outside.set("state", "idle")
	await create_timer(1.4).timeout   # телеграф 0.55 + щелчок + тики
	_check(int(inside.current_hp) < 400, "стена огня ранит внутри (%d HP)" % int(inside.current_hp))
	_check(int(outside.current_hp) == 400,
		"стена огня не бьёт снаружи зоны (%d HP)" % int(outside.current_hp))
	_inside.erase(inside)
	_inside.erase(outside)
	inside.queue_free()
	outside.queue_free()
	wall.queue_free()
	await process_frame

	# Стена земли: блокируются ровно те же 12 клеток, что и рисуется.
	var earth := SpellVFX.spawn_wall(pos, "Earth", _hero, 8.0, "block", Vector2i(6, 2), 0)
	if earth != null:
		await process_frame
		var earth_cells := earth.covered_cells()
		_check(earth_cells.size() == 12,
			"стена земли блокирует 12 клеток, получено %d" % earth_cells.size())
		_check(not earth.deals_damage(), "стена земли не наносит урон")
		var foe := _spawn_foe(earth.global_position)
		foe.max_hp = 400
		foe.current_hp = 400
		foe.move_speed = 0.0
		foe.set("state", "idle")
		await create_timer(1.4).timeout
		_check(int(foe.current_hp) == 400,
			"стена земли не ранит (%d HP)" % int(foe.current_hp))
		_inside.erase(foe)
		foe.queue_free()
		earth.queue_free()
		await process_frame


# --- 3. Призматическое сияние ----------------------------------------------

func _test_chain() -> void:
	_check(SpellDB.get_spell("Prismatic_Spray").get("projectile", "") == "chain",
		"Prismatic_Spray помечен как chain")
	var center := _hero.global_position + Vector2(0, 240)
	var foes: Array = []
	for i in range(6):
		var e := _spawn_foe(center + Vector2((i - 3) * 24, 0))
		e.max_hp = 400
		e.current_hp = 400
		e.move_speed = 0.0
		e.set("state", "idle")
		foes.append(e)
	# Один вне радиуса — его сияние не должно доставать.
	var far := _spawn_foe(center + Vector2(400, 0))
	far.max_hp = 400
	far.current_hp = 400
	far.move_speed = 0.0
	far.set("state", "idle")
	foes.append(far)
	await process_frame

	_hero._cast_chain_spell("Prismatic_Spray", SpellDB.get_spell("Prismatic_Spray"),
		"Air", 12, 96.0, center)
	await create_timer(0.15).timeout

	var hit := 0
	var missed := 0
	for e in foes:
		if e == far:
			continue
		if int(e.current_hp) < 400:
			hit += 1
		else:
			missed += 1
	_check(hit >= 4, "сияние задело %d из 6 целей (нужно >= 4)" % hit)
	_check(int(far.current_hp) == 400, "цель вне радиуса не задета")
	_check(hit + missed == 6, "все 6 целей в радиусе проверены")
	for e in foes:
		_inside.erase(e)
		e.queue_free()
	await process_frame


var _inside: Array = []

func _spawn_foe(pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.name = "MechTestFoe"
	e.anim_set = "monsters/orc"
	e.max_hp = 400
	e.damage = 1
	e.position = pos
	root.add_child(e)
	Game.enemies.append(e)
	_inside.append(e)
	return e


func _finish() -> void:
	if _fails.is_empty():
		print("MECH: RESULT: OK")
	else:
		print("MECH: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
