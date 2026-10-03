extends SceneTree
## Headless-проверка физики и подсветки целей.
##
## Три вещи, которые выглядели как «ненастоящая игра», и были не стилизом:
##  1. motion_mode намеренно оставлен GROUNDED: вариант FLOATING проверялся
##     и отвергнут (fuzz_edge: 1 застревание из 62), причина — не он;
##  2. у врага целиком гасилась скорость при непроходимом впереди, и он не
##     умел скользить вдоль стены (у игрого это уже починили, у NPC — нет);
##  3. кольцо выделения считалось по несуществующим полям w/h в units_db.json
##     и всегда было 144 px независимо от юнита.
##
## Запуск:
##   godot --headless --path . --script res://tests/unit_physics_smoke.gd

const AIR_TILE := Vector2i(64, 64)   # заведомо вода/непроходимо (центр карты)

var _fails: Array = []
var _hero: Player = null
var _map: Node = null


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 13, "spirit": 12,
		"blade": 10, "bludgeon": 10, "pike": 10, "shooting": 10,
		"fire": 20, "water": 20, "air": 20, "earth": 20, "astral": 20,
		"weapon": "staff", "shield": false, "armor": "light"}
	Game.hero_class = "mage"
	Game.hero_name = "Маг"
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("PHYS: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "загрузка main.tscn: %d" % err)
		_finish()
		return
	await process_frame
	await create_timer(0.6).timeout
	_hero = get_first_node_in_group("player") as Player
	_map = get_first_node_in_group("alm_map")
	_check(_hero != null, "герой загружен")
	if _hero == null:
		_finish()
		return

	_test_motion_mode()
	_test_choose_slide()
	_test_enemy_slide()
	_test_select_ring()
	_finish()


# --- 1b. Выбор оси при скольжении (Game.choose_slide) -----------------------

## Замер 03.10: свободное движение диагональное (179 кадров из 179, угол
## 0.998), то есть ломало не сама походка, а СКОЛЬЖЕНИЕ. Раньше ось
## выбиралась по порядку `if can_x ... elif can_y ...`, а не по близости к
## направлению, и звери дёргались у деревьев.
func _test_choose_slide() -> void:
	print("-- скольжение: выбор оси --")
	var diag := Vector2(0.7071, 0.7071)
	# Обе оси свободны и направление строго диагональное — выбор неоднозначен,
	# но ось обязана быть одной из двух, а не «ничейной».
	var s := Game.choose_slide(diag, true, true)
	_check(s == Vector2(1, 0) or s == Vector2(0, 1),
		"обе оси свободны — выбрана одна из них (%s)" % str(s))

	# Направление сильно по X: выбирать надо X, даже если порядок проверок
	# другой. Именно этот случай ломался раньше.
	var mostly_x := Vector2(0.9, 0.1)
	_check(Game.choose_slide(mostly_x, true, true) == Vector2(1, 0),
		"движение преимущественно по X -> скользим по X")
	_check(Game.choose_slide(Vector2(0.1, 0.9), true, true) == Vector2(0, 1),
		"движение преимущественно по Y -> скользим по Y")

	# Закрытая ось исключается.
	_check(Game.choose_slide(mostly_x, false, true) == Vector2(0, 1),
		"X закрыт -> скользим по Y")
	_check(Game.choose_slide(mostly_x, true, false) == Vector2(1, 0),
		"Y закрыт -> скользим по X")
	_check(Game.choose_slide(diag, false, false) == Vector2.ZERO,
		"обе оси закрыты -> никуда не скользим (нужно тормозить)")

	# Знак берётся из направления: влево-вверх не должно уводить вправо.
	_check(Game.choose_slide(Vector2(-0.9, 0.1), true, true) == Vector2(-1, 0),
		"движение влево -> скользим влево, а не вправо")
	_check(Game.choose_slide(Vector2(0.0, 0.0), true, true) == Vector2.ZERO,
		"нулевое направление -> ZERO, а не случайная ось")


# --- 1. motion_mode (осознанно НЕ меняем) --------------------------------

## Тест написан под гипотезу «коробка на машине = motion_mode». Гипотеза была
## ПРОВЕРЕНА и ОТВЕРГНУТА: с MOTION_MODE_FLOATING fuzz_edge детерминированно
## давал 1 застревание из 62 в кармане между двумя препятствиями. В GROUNDED
## скользящая поверхность классифицируется как «пол» и выталкивает героя из
## узкого места, в FLOATING любая коллизия — глухая стена.
##
## Настоящая причина «езды по рельсам» — не motion_mode, а ГАШЕНИЕ СКОРОСТИ
## ЦЕЛИКОМ при непроходимом впереди; оно починено раздельным скольжением по
## осям (проверяется в секции 2). Этот тест фиксирует решение, чтобы его
## снова не «починили».
func _test_motion_mode() -> void:
	var bodies: Array = []
	for c in get_root().get_children():
		_collect_bodies(c, bodies)
	_check(bodies.size() > 0, "найдено тел на карте: %d" % bodies.size())

	var floating: Array = []
	for b in bodies:
		if (b as CharacterBody2D).motion_mode == CharacterBody2D.MOTION_MODE_FLOATING:
			floating.append((b as Node).name)
	_check(floating.is_empty(),
		"ни одно тело не переведено в MOTION_MODE_FLOATING — это ломало проходимость (нарушители: %s)"
			% str(floating.duplicate().slice(0, 5)))
	_check(_hero.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED,
		"герой в MOTION_MODE_GROUNDED (осознанно: FLOATING давал застревание в карманах)")


func _collect_bodies(node: Node, out: Array) -> void:
	if node is CharacterBody2D:
		out.append(node)
	for c in node.get_children():
		_collect_bodies(c, out)


# --- 2. Скольжение вдоль стены --------------------------------------------

## Враг, которому велено идти в непроходимую клетку ПОД УГОЛОМ, должен
## скользить вдоль препятствия, а не висеть на месте со сбитой скоростью.
func _test_enemy_slide() -> void:
	var e: Enemy = await _spawn_enemy_on_land()
	if e == null:
		_check(false, "не удалось поставить врага на проходимую клетку")
		return
	e.move_speed = 120.0
	e.set("state", "idle")
	var start := e.global_position
	# Цель — диагонально в непроходимую клетку: полный вектор запрещён,
	# но одна из осей остаётся разрешённой.
	var blocked := _blocked_cell_near(e.global_position)
	_check(blocked.x >= 0, "найдена непроходимая клетка (%s)" % str(blocked))
	if blocked.x < 0:
		return
	var goal := Vector2(blocked.x * 32 + 16, blocked.y * 32 + 16)
	var dir := Game.safe_dir(start, goal)
	# Шаг строго по одной оси, как в реальном move_and_slide при упоре.
	var step := Vector2(dir.x, 0.0) * 120.0 * 0.016
	if absf(dir.x) < 0.01:
		step = Vector2(0.0, dir.y) * 120.0 * 0.016
	_check(not e._can_step(step * 4.0),
		"шаг в непроходимую сторону отклоняется (есть что скользить)")

	# Скольжение: ось, оставшаяся свободной, обязана быть разрешена.
	var along := Vector2(step.x, 0.0) if absf(dir.x) > 0.01 else Vector2(0.0, step.y)
	_check(e._can_step(along),
		"скольжение вдоль препятствия разрешено (старая гасила скорость целиком)")

	# И живой прогон: скорость по разрешённой оси должна ненулевая.
	e._move_checked(dir, 120.0, 0.016)
	_check(e.velocity.length() > 1.0,
		"враг сохраняет скорость при скольжении (%.1f px/s)" % e.velocity.length())
	e.queue_free()
	await process_frame


func _blocked_cell_near(from: Vector2) -> Vector2i:
	if _map == null or not _map.has_method("is_walkable_world"):
		return Vector2i(-1, -1)
	for r in range(2, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(int(from.x) / 32 + dx, int(from.y) / 32 + dy)
				if not bool(_map.call("is_walkable_world", Vector2(c.x * 32 + 16, c.y * 32 + 16))):
					return c
	return Vector2i(-1, -1)


func _spawn_enemy_on_land() -> Enemy:
	if _map == null or not _map.has_method("is_walkable_world"):
		return null
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := Vector2((int(_hero.global_position.x) / 32 + dx) * 32 + 16,
					(int(_hero.global_position.y) / 32 + dy) * 32 + 16)
				if bool(_map.call("is_walkable_world", p)):
					var e := Enemy.new()
					e.anim_set = "monsters/orc"
					e.max_hp = 100
					e.damage = 1
					e.position = p
					# SceneTree.get_root() — это Window, у него нет
					# get_first_node_in_group(); группу ищем у самого SceneTree.
					(current_scene as Node).add_child(e)
					Game.enemies.append(e)
					await process_frame
					return e
	return null


func _first_enemy() -> Enemy:
	for e in Game.enemies:
		if is_instance_valid(e) and e is Enemy:
			return e as Enemy
	return null


# --- 3. Кольцо выделения ---------------------------------------------------

func _test_select_ring() -> void:
	# w/h в units_db.json НЕТ — там есть tile_size. Проверяем на наборе,
	# где размер реально отличается, чтобы заглушка 128 не прошла случайно.
	var sizes: Array = []
	for set_name in ["humans/militia", "monsters/orc", "monsters/troll"]:
		var ts := UnitDB.tile_size(set_name)
		sizes.append(ts)
	_check(sizes.size() == 3, "tile_size читается для трёх наборов: %s" % str(sizes))

	# Кольцо у героя строится из _unit_metrics, а не из константы 128.
	var m: Array = Game._unit_metrics(_hero)
	var ts := maxi(1, UnitDB.tile_size(_hero.anim_set_name()))
	_check(int(m[0]) == ts * 32 and int(m[1]) == ts * 32,
		"размер кольца героя = tile_size × 32 = %d px (было 128 для всех)"
			% (ts * 32))

	# Диаметр кольца не должен быть 144 px у юнита, который меньше.
	if ts * 32 < 128:
		_check(int(m[0]) != 128 or ts * 32 == 128,
			"кольцо не застряло на заглушке 128 px для набора %s" % _hero.anim_set_name())

	# И у живого врага с другим набором размер должен отличаться.
	var foe: Enemy = await _spawn_enemy_on_land()
	if foe != null:
		var fm: Array = Game._unit_metrics(foe)
		_check(int(fm[0]) == maxi(1, UnitDB.tile_size(foe.anim_set)) * 32,
			"размер кольца врага %s = %d px" % [foe.anim_set, int(fm[0])])
		foe.queue_free()
		await process_frame


func _finish() -> void:
	if _fails.is_empty():
		print("PHYS: RESULT: OK")
	else:
		print("PHYS: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
