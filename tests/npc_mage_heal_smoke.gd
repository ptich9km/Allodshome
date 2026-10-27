extends SceneTree
## Headless-проверка: маги-НПЦ лечат себя и раненых союзников.
##
## Повод (игрок, 27.10): «когда героя сильно подбили, он не лечится и не лечит
## других» — у героя авто-лечение включалось только вручную, а у НПЦ его не
## было вовсе. Здесь стережётся поведение НПЦ:
##  1. маг-НПЦ лечит СЕБЯ ниже порога;
##  2. лечит раненого союзника рядом (при полном своём HP);
##  3. обычный воин-НПЦ не лечит;
##  4. врага не лечит никогда;
##  5. после лечения уходит в кулдаун и второй раз сразу не лечит;
##  6. далёкого союзника не лечит (радиус).
##
## Запуск:
##   godot --headless --path . --script res://tests/npc_mage_heal_smoke.gd

var _fails: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("NPCMAGE: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	Game.hero = null
	Game.npcs = []
	Game.party = []
	Game.enemies = []

	# 1. Себя.
	var mage := _npc("city_human_mage/t1", Vector2.ZERO, 20, 100)
	Game.npcs.append(mage)
	mage._mage_heal_tick(0.1)
	_check(int(mage.current_hp) > 20, "маг-НПЦ лечит себя (%d -> %d)"
		% [20, int(mage.current_hp)])
	_check(mage._heal_cd > 0.0, "после лечения уходит в кулдаун")

	# 5. Второй раз сразу — не лечит.
	var hp_after := int(mage.current_hp)
	mage._mage_heal_tick(0.1)
	_check(int(mage.current_hp) == hp_after, "в кулдауне повторно не лечит")

	# 2. Союзника рядом, при полном своём HP.
	Game.npcs = []
	var medic := _npc("city_ork_mage/t1", Vector2.ZERO, 100, 100)
	var wounded := _npc("city_human_warrior/t2", Vector2(60, 0), 20, 100)
	Game.npcs.append(medic)
	Game.npcs.append(wounded)
	medic._mage_heal_tick(0.1)
	_check(int(wounded.current_hp) > 20, "маг-НПЦ лечит раненого союзника (%d -> %d)"
		% [20, int(wounded.current_hp)])
	_check(int(medic.current_hp) == 100, "себя не трогает, когда полон")

	# 6. Далеко — не лечит.
	Game.npcs = []
	var far_medic := _npc("city_human_mage/t1", Vector2.ZERO, 100, 100)
	var far_wounded := _npc("city_human_warrior/t2", Vector2(600, 0), 20, 100)
	Game.npcs.append(far_medic)
	Game.npcs.append(far_wounded)
	far_medic._mage_heal_tick(0.1)
	_check(int(far_wounded.current_hp) == 20, "далёкого союзника не лечит")

	# 3. Воин-НПЦ не лечит.
	Game.npcs = []
	var warrior := _npc("city_human_warrior/t2", Vector2.ZERO, 20, 100)
	Game.npcs.append(warrior)
	warrior._mage_heal_tick(0.1)
	_check(int(warrior.current_hp) == 20, "воин-НПЦ не лечит (нет магии)")

	# 4. Врага не лечит.
	Game.npcs = []
	Game.enemies = []
	var healer := _npc("city_human_mage/t1", Vector2.ZERO, 100, 100)
	var foe := _npc("monsters/wolf", Vector2(40, 0), 10, 100)
	Game.npcs.append(healer)
	Game.enemies.append(foe)
	healer._mage_heal_tick(0.1)
	_check(int(foe.current_hp) == 10, "врага не лечит")

	# Прибираем статики, чтобы не мешать другим тестам.
	Game.npcs = []
	Game.enemies = []
	_finish()


func _npc(set_name: String, pos: Vector2, hp: int, max_hp: int) -> Npc:
	var n := Npc.new()
	n.anim_set = set_name
	n.max_hp = max_hp
	n.current_hp = hp
	n.global_position = pos
	n.state = "idle"
	return n


func _finish() -> void:
	if _fails.is_empty():
		print("NPCMAGE: RESULT: OK")
	else:
		print("NPCMAGE: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
