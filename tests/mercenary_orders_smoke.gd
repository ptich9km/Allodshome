extends SceneTree
##
## Приказы отряда (28.10): кнопки HUD управляют не только героем.
##
## ЗАЧЕМ
## -----
## `Game.action_mode` читал только `game.gd`, а наёмники всегда бежали за
## ближайшим врагом в 240 px. Кнопки «След./Атак./Охр./Стоп» для отряда были
## декорацией. Теперь режим выбирает НАМЕРЕНИЕ (какую цель и куда идти), а
## движение остаётся прежним.
##
## ЧТО ПРОВЕРЯЕМ (решения, без физики кадра):
##   1. пустой режим = «следовать» (прежнее поведение, строй отряда не ломается);
##   2. «Стоп» бить только в пределах удара, «Охрана» — в радиусе поста,
##      «Атака» — в радиусе от ГЕРОЯ;
##   3. «След.» не гонится за врагом дальше лиза от героя;
##   4. «Охрана» возвращается на пост, а если герой ушёл дальше лиза — идёт за ним;
##   5. смена приказа переносит пост на текущее место;
##   6. кнопка «Стоп» пишет отдельный режим "stop", а не "none" (иначе стоп и
##      «приказа нет» — одно значение).
##
## Запуск: godot --headless --path . --script res://tests/mercenary_orders_smoke.gd

const FOLLOW_RADIUS := 240.0
const FOLLOW_LEASH := 320.0
const ATTACK_RADIUS := 480.0
const GUARD_RADIUS := 150.0
const GUARD_LEASH := 400.0
const FOLLOW_GAP := 64.0

var _checks := 0
var _fails: Array[String] = []
var _hero: Node2D = null
var _merc: Node2D = null
var _foes: Array[Node2D] = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _initialize() -> void:
	_run.call_deferred()


func _spawn_foe(at: Vector2) -> Node2D:
	var n := Node2D.new()
	n.global_position = at
	root.add_child(n)
	_foes.append(n)
	Game.enemies.append(n)
	return n


func _clear_foes() -> void:
	for n in _foes:
		if is_instance_valid(n):
			n.queue_free()
	_foes.clear()
	Game.enemies.clear()


func _set_order(mode: String) -> void:
	Game.action_mode = mode
	_merc.call("_sync_order")


func _run() -> void:
	Game.hero_stats = {"body": 10, "agility": 10, "mind": 10, "spirit": 10}
	Game.hero_class = "warrior"

	_hero = Node2D.new()
	_hero.global_position = Vector2(1000, 1000)
	root.add_child(_hero)
	Game.hero = _hero

	_merc = Mercenary.new()
	_merc.set("anim_set", "ork_mage_a52/t1")
	root.add_child(_merc)
	_merc.global_position = Vector2(1000, 1000)
	await process_frame
	_check(_merc.get("_anim") != null, "наёмник собран (анимация на месте)")

	print("-- пустой режим = следовать --")
	Game.action_mode = "none"
	_merc.set("_order", "")
	_merc.call("_sync_order")
	_check(str(_merc.get("_order")) == "follow",
		"режим 'none' читается как 'follow' (%s)" % str(_merc.get("_order")))

	print("-- смена приказа переносит пост --")
	_merc.global_position = Vector2(1200, 1000)
	_set_order("guard")
	var anchor: Vector2 = _merc.get("_anchor")
	_check(anchor.is_equal_approx(Vector2(1200, 1000)),
		"пост охраны = место на момент приказа (%s)" % str(anchor))

	print("-- радиусы целей --")
	_clear_foes()
	# Враг в 200 px от наёмника и в 300 px от героя: это «следуй» (240) и
	# «атака» (480), но дальше радиуса охраны (150).
	_hero.global_position = Vector2(1000, 1000)
	_merc.global_position = Vector2(1100, 1000)
	var far := _spawn_foe(Vector2(1300, 1000))
	_merc.set("_order", "")        # переставить пост на новое место
	_set_order("guard")
	_check(_merc.call("_order_target") == null, "охрана не берёт врага за 200 px")
	_set_order("follow")
	_check(_merc.call("_order_target") == far, "следование берёт врага в 240 px")
	_set_order("attack")
	_check(_merc.call("_order_target") == far, "атака берёт врага в 480 px от героя")

	print("-- стоп: только ответка --")
	_clear_foes()
	_merc.global_position = Vector2(1200, 1000)
	var close := _spawn_foe(Vector2(1210, 1000))   # 10 px — в пределах удара
	var mid := _spawn_foe(Vector2(1300, 1000))     # 100 px — уже не ответка
	_set_order("stop")
	_check(_merc.call("_nearest_enemy_from", _merc.global_position,
		Game.attack_reach(_merc) + 4.0) == close,
		"стоп видит врага в пределах удара")
	_check(_merc.call("_order_target") != mid, "стоп не бежит за врагом в 100 px")
	_merc.call("_hold_position", 0.016)
	_check((_merc.get("velocity") as Vector2).length() < 0.01,
		"стоп: скорость нулевая")

	print("-- след.: не гнаться далеко от героя --")
	_clear_foes()
	var lure := _spawn_foe(Vector2(1500, 1000))   # 500 px от героя, 240+ от наёмника?
	_merc.global_position = Vector2(1400, 1000)   # 100 px до врага
	_hero.global_position = Vector2(1000, 1000)
	_set_order("follow")
	var pulled = _merc.call("_order_target")
	_check(pulled == null or pulled != lure,
		"следование не гонится за врагом дальше лиза (%s)" % str(pulled))

	print("-- охрана: возврат на пост и уход за героем --")
	_clear_foes()
	_merc.global_position = Vector2(1200, 1000)
	_set_order("guard")
	_merc.global_position = Vector2(1260, 1000)   # отошёл на 60 px
	_merc.call("_hold_position", 0.016)
	var back: Vector2 = _merc.get("velocity")
	_check(back.x < -1.0, "охрана идёт назад к посту (vx %.0f)" % back.x)

	_hero.global_position = Vector2(1700, 1000)   # ушёл на 500 от поста
	# Разворот не мгновенный: скорость меняется через accel, поэтому даём кадры.
	for _i in range(40):
		_merc.call("_hold_position", 0.016)
	var chase: Vector2 = _merc.get("velocity")
	_check(chase.x > 1.0, "герой ушёл — охрана идёт за ним (vx %.0f)" % chase.x)

	print("-- кнопка «Стоп» пишет отдельный режим --")
	var ui_src := FileAccess.get_file_as_string("res://scripts/ui.gd")
	_check(ui_src.contains('Game.action_mode = "stop"'),
		"ui.gd: кнопка «Стоп» ставит action_mode = \"stop\"")
	_check(not ui_src.contains('"stop":\n\t\t\tactive = 3\n\t\t\tGame.action_mode = "none"'),
		"ui.gd: стоп больше не сливается с 'none'")

	# Дефолт игры: режим не задан — строй не ломается.
	Game.action_mode = "none"
	_check(FOLLOW_RADIUS < FOLLOW_LEASH, "лиз следования больше радиуса поиска")
	_check(GUARD_RADIUS < ATTACK_RADIUS, "охрана короче атаки")
	_check(GUARD_LEASH > FOLLOW_GAP, "лиз охраны больше дистанции строя")

	_clear_foes()
	_merc.queue_free()
	_hero.queue_free()
	Game.hero = null
	Game.action_mode = "none"
	print("")
	if _fails.is_empty():
		print("RESULT: OK mercenary_orders_smoke (%d checks)" % _checks)
	else:
		print("RESULT: FAIL mercenary_orders_smoke (%d checks, %d fails)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)
