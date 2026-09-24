extends SceneTree
## Smoke-проверка спавна на gen_smart_01: здания, НПЦ городов (стражи/жители),
## Серые-монстры и взаимный бой «страж ↔ Серые».
## Запуск: godot --headless --path . --script res://tests/spawn_smoke.gd

func _initialize() -> void:
	# Подставляем героя, чтобы main.tscn не ушёл на character_select
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Герой"
	call_deferred("_run")

func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		print("SMOKE: не удалось сменить сцену: ", err)
		quit()
		return
	# ждём загрузку мира (2 кадра + пауза)
	await process_frame
	await create_timer(0.5).timeout

	var am = get_first_node_in_group("alm_map")
	var recs: Array = [] if am == null else am.call("get_units")
	var r_guards := 0
	var r_citizens := 0
	var r_greys := 0
	var miss: Array = []
	var blocked_spawns: Array = []
	var path_failures := 0
	for r in recs:
		var role := str(r.get("role", ""))
		match role:
			"guard": r_guards += 1
			"citizen": r_citizens += 1
			_: r_greys += 1
		if not UnitDB.has(str(r.get("set", ""))):
			miss.append(str(r.get("set", "")))
		var rec_pos := Vector2(float(r.get("x", 0)) * 32.0 + 16.0, float(r.get("y", 0)) * 32.0 + 16.0)
		if am != null and not bool(am.call("is_walkable_world", rec_pos)):
			blocked_spawns.append(rec_pos)
		if role == "guard" and am != null and bool(r.get("patrol", false)):
			var post: Array = r.get("post", [])
			if post.size() >= 2:
				var post_pos := Vector2(float(post[0]) * 32.0 + 16.0, float(post[1]) * 32.0 + 16.0)
				if rec_pos.distance_to(post_pos) > 40.0 and am.call("find_path", rec_pos, post_pos).is_empty():
					path_failures += 1
	print("SMOKE: recs=%d (стражи=%d жители=%d серые=%d) missing-sets=%s" % [
		recs.size(), r_guards, r_citizens, r_greys, str(miss)])
	print("SMOKE: blocked_spawns=%d patrol_path_failures=%d" % [
		blocked_spawns.size(), path_failures])

	var guards: Array = []
	var citizens := 0
	for n in Game.npcs:
		if n is Npc:
			if n.role == "guard":
				guards.append(n)
			else:
				citizens += 1
	var greys := Game.enemies.size()
	var patrol := 0
	for g in guards:
		if g.is_patrol:
			patrol += 1
	print("SMOKE: всего НПЦ=%d (стражи=%d патруль=%d жители=%d) Серые=%d" % [
		Game.npcs.size(), guards.size(), patrol, citizens, greys])
	var separation_ok := true
	if Game.npcs.size() >= 2:
		var first: Node2D = Game.npcs[0]
		var second: Node2D = Game.npcs[1]
		var first_pos := first.global_position
		var second_pos := second.global_position
		first.global_position = Vector2(1000.0, 1000.0)
		second.global_position = first.global_position + Vector2(2.0, 0.0)
		separation_ok = Game.movement_direction(first, Vector2.RIGHT).x < 0.0
		first.global_position = first_pos
		second.global_position = second_pos
	print("SMOKE: separation=%s" % separation_ok)

	if guards.is_empty() or Game.enemies.is_empty():
		print("SMOKE: НЕТ стражей или Серых — бой не проверить")
		quit()
		return

	# Принудительно подводим Серого (настоящего спавнутого, не сцены) к стражу и ждём бой
	var guard: Npc = guards[0]
	var gray: Enemy = null
	for e in Game.enemies:
		if e is Enemy and str(e.name).begins_with("Monster_"):
			gray = e as Enemy
			break
	if gray == null:
		print("SMOKE: RESULT: FAIL (нет спавнутого Серого)")
		quit()
		return
	var before: int = gray.current_hp
	gray.global_position = guard.global_position + Vector2(48, 0)
	guard.attack_cooldown = 0.0
	await create_timer(4.0).timeout

	var gray_damaged: bool = not is_instance_valid(gray) or gray.current_hp < before
	var gray_eng: bool = not is_instance_valid(gray)
	if is_instance_valid(gray) and is_instance_valid(guard):
		gray_eng = gray.attack_target == guard or gray.state == "attack" or gray.state == "chase"
	var guard_combat: bool = false
	if is_instance_valid(gray) and is_instance_valid(guard):
		guard_combat = guard.attack_cooldown < 1.0
	print("SMOKE: серый повреждён=%s серый отвечает=%s бой идёт=%s" % [
		gray_damaged, gray_eng, guard_combat])
	if gray_damaged and gray_eng:
		print("SMOKE: RESULT: OK (взаимный бой страж↔Серые)")
	else:
		print("SMOKE: RESULT: FAIL (бой не завязался: gray_damaged=", gray_damaged,
			" gray_eng=", gray_eng, " guard_combat=", guard_combat)
	quit()