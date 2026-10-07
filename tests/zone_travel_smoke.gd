extends SceneTree
##
## Переход между зонами через портал (03.10).
##
## ЧТО ПРОВЕРЯЕТ
## -------------
## Раньше портал был заглушкой: `_on_portal_enter()` делал «телепорт обратно
## на спавн», то есть вёл в никуда. Переход между зонами был признан
## непригодным через change_scene_to_file, потому что Main._ready делает
## `Game.party.clear()`, а золото и инвентарь живут на узле Player.
##
## Решение — горячая замена узла Map: герой, партия, золото и инвентарь
## остаются живы, а карта и её юниты пересоздаются.
##
## Главный инвариант: ПАРТИЯ И СНАРЯЖЕНИЕ ПЕРЕЖИВАЮТ ПЕРЕХОД. Если это
## сломается, игрок теряет отряд и золото на ровном месте.
##
## ЗАПУСК
## ------
## godot --headless --path . --script res://tests/zone_travel_smoke.gd
##

var _checks := 0
var _fails: Array[String] = []


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Путешественник"
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _run() -> void:
	# Стартуем в зоне новичка — из неё портал ведёт в mid.
	Game.map_zone = "start"
	Game.request_map_by_seed(31337, "start")

	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "main.tscn загрузилась (err=%d)" % err)
		_report()
		return
	await process_frame
	await create_timer(0.6).timeout

	var game := current_scene
	_check(game != null, "сцена игры загружена")
	if game == null:
		_report()
		return

	var player = game.get("player")
	var alm_map = game.get("alm_map")
	_check(player != null, "герой на месте")
	_check(alm_map != null, "карта загрузилась")
	if player == null or alm_map == null:
		_report()
		return

	_check(Game.map_zone == "start", "стартовая зона = start (сейчас %s)" % Game.map_zone)

	# Снаряжение и партия, которые обязаны выжить.
	var merc := Mercenary.new()
	merc.anim_set = "ork_mage_a52/t1"
	game.add_child(merc)
	Game.party.append(merc)
	_check(Game.party.size() == 1, "в партии один наёмник")

	player.add_gold(777)
	var gold_before: int = player.gold
	_check(gold_before >= 777, "золото на месте до перехода (%d)" % gold_before)
	player.add_item("Common iron Long Sword")
	var inv_before: int = player.inventory.size()
	_check(inv_before > 0, "инвентарь не пуст до перехода (%d)" % inv_before)

	var old_map_id: int = alm_map.get_instance_id()
	var enemies_before: int = Game.enemies.size()
	var npcs_before: int = Game.npcs.size()
	print("  до перехода: врагов=%d NPC=%d" % [enemies_before, npcs_before])

	# --- переход через НАСТОЯЩИЙ портал, а не прямым вызовом ---
	# Прямой вызов travel_to_zone не проверяет главное: что игрок попадает в
	# портал шагом. Мутация с пустой PORTAL_CHAIN на таком тесте проходила бы.
	print("-- шаг в портал start -> mid --")
	var portal_cells: Array = alm_map.call("get_portal_cells")
	_check(not portal_cells.is_empty(), "в зоне новичка есть клетки портала (%d)"
			% portal_cells.size())
	if portal_cells.is_empty():
		_report()
		return
	var pc: Vector2i = portal_cells[0]
	player.global_position = Vector2(pc.x * 32 + 16, pc.y * 32 + 16)
	player.reset_physics_interpolation()
	await process_frame
	await create_timer(0.8).timeout

	_check(Game.map_zone == "mid", "зона сменилась на mid (сейчас %s)" % Game.map_zone)
	var new_map = game.get("alm_map")
	_check(new_map != null and is_instance_valid(new_map), "новая карта существует")
	_check(new_map != null and new_map.get_instance_id() != old_map_id,
		"узел Map пересоздан, а не переиспользован")

	# --- что обязано выжить ---
	_check(player != null and is_instance_valid(player), "герой жив после перехода")
	_check(Game.party.size() == 1, "партия сохранилась (наёмников: %d)" % Game.party.size())
	_check(is_instance_valid(merc), "узел наёмника жив")
	_check(int(player.gold) >= 777, "золото сохранилось (%d, было %d)" % [int(player.gold), gold_before])
	_check(player.inventory.size() >= inv_before,
		"инвентарь сохранился (%d, было %d)" % [player.inventory.size(), inv_before])

	# --- что обязано смениться ---
	_check(not is_instance_valid(alm_map) or alm_map.get_instance_id() != old_map_id,
		"старая карта освобождена")
	var enemies_after: int = Game.enemies.size()
	var npcs_after: int = Game.npcs.size()
	print("  после перехода: врагов=%d NPC=%d" % [enemies_after, npcs_after])
	_check(npcs_after > 0, "в новой зоне есть NPC (%d)" % npcs_after)
	# Старых юнитов не осталось: считаем, сколько Серых ПРОПИСАНО в новой карте,
	# и сравниваем с живыми. Раньше здесь была грубая граница вида
	# "enemies_after <= npcs_after + ...", и она сломалась сама собой, когда
	# плотность подняли с 15 до 71: в start зверьков 25, в mid 84 — рост законный.
	var map_base: String = str(Game.pending_map_path).get_basename()
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(map_base + ".npcs.json"))
	var rec_gray := 0
	if parsed is Dictionary:
		for rec in (parsed as Dictionary).get("npcs", []):
			var d: Dictionary = rec
			if str(d.get("role", "")) == "guard" or str(d.get("role", "")) == "citizen":
				continue
			if d.has("set"):
				rec_gray += 1
	print("  в данных новой карты серых: %d" % rec_gray)
	_check(rec_gray > 0, "в данных новой карты есть Серые (%d)" % rec_gray)
	var live_gray := 0
	for e2 in Game.enemies:
		if not is_instance_valid(e2):
			continue
		var en: Node = e2 as Node
		var sn := str(en.get("anim_set"))
		if UnitDB.has(sn) and UnitDB.is_hostile(sn):
			live_gray += 1
	_check(live_gray <= rec_gray + 2,
		"на карте не больше Серых, чем прописано (%d живых, %d в данных) — старые не накопились"
			% [live_gray, rec_gray])

	# Герой должен стоять на проходимой клетке новой карты.
	if new_map != null and new_map.has_method("is_walkable_world"):
		_check(new_map.call("is_walkable_world", player.global_position),
			"герой стоит на проходимой клетке новой карты")
		_check(player.global_position != Vector2.ZERO, "герой не в нуле (%.0f,%.0f)"
				% [player.global_position.x, player.global_position.y])

	# Наёмник переехал вместе с героем.
	if is_instance_valid(merc):
		var d: float = merc.global_position.distance_to(player.global_position)
		_check(d < 400.0, "наёмник рядом с героем после перехода (%.0f px)" % d)

	# --- цепочка зон: из mid портал ведёт в hard ---
	print("-- цепочка порталов mid -> hard --")
	var chain: Dictionary = game.get("PORTAL_CHAIN")
	_check(str(chain.get("start", "")) == "mid", "портал из start ведёт в mid")
	_check(str(chain.get("mid", "")) == "hard", "портал из mid ведёт в hard")
	_check(not chain.has("hard"), "из hard портала нет — конец маршрута")
	var mid_map = game.get("alm_map")
	var mid_portals: Array = mid_map.call("get_portal_cells")
	_check(not mid_portals.is_empty(), "в mid есть портал (%d)" % mid_portals.size())
	if not mid_portals.is_empty():
		var pc2: Vector2i = mid_portals[0]
		player.global_position = Vector2(pc2.x * 32 + 16, pc2.y * 32 + 16)
		player.reset_physics_interpolation()
		await process_frame
		await create_timer(0.8).timeout
	_check(Game.map_zone == "hard", "зона сменилась на hard (сейчас %s)" % Game.map_zone)
	_check(Game.party.size() == 1, "партия пережила второй переход")
	_check(int(player.gold) >= 777, "золото пережило второй переход")

	_report()


func _report() -> void:
	print("RESULT: %s zone_travel_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)