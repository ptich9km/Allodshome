extends SceneTree
## Smoke package C: авто-волшебство мага (уровни, цели, авто-лечение).
##
## С 27.10 авто-волшебство — настройка в Esc → Настройки (раздел «Магия»),
## а не скрытый Alt+ПКМ. Уровень по умолчанию «Базовое», цель «Я и моя группа».
## Главный регресс, который здесь стережётся: раньше для цели "party"
## перебирался только `Game.party` (наёмники), и маг НЕ лечил и не баффал себя.

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _run() -> void:
	print("-- Game.auto_* --")
	_check(Game.auto_spell == "", "auto_spell по умолчанию пуст")
	_check(Game.auto_buff_tier == "base", "уровень по умолчанию = base (Базовое)")
	_check(Game.auto_targets == "party", "цель по умолчанию = party (я и группа)")

	print("-- SpellDB kinds --")
	_check(SpellDB.kind_of("Heal") == "heal", "Heal kind=heal")
	_check(SpellDB.kind_of("Haste") == "buff", "Haste kind=buff")
	_check(SpellDB.kind_of("Bless") == "buff", "Bless kind=buff")
	_check(SpellDB.kind_of("Invisibility") == "buff", "Invis kind=buff")
	_check(SpellDB.kind_of("Shield") == "self", "Shield kind=self (только на мага)")
	_check(SpellDB.target_of("Heal") == "ally", "Heal target=ally")

	print("-- конфиг --")
	_check(absf(GameConfig.getf("magic", "auto_heal_ratio") - 0.45) < 0.001,
		"auto_heal_ratio=0.45")
	_check(GameConfig.getf("magic", "auto_buff_interval") >= 0.2,
		"auto_buff_interval задан")
	_check(GameConfig.getf("magic", "npc_heal_cooldown") >= 1.0,
		"npc_heal_cooldown задан")
	_check(GameConfig.getf("magic", "npc_heal_percent") > 0.0,
		"npc_heal_percent задан")

	print("-- уровни и наборы заклинаний --")
	var hero := Player.new()
	var add = hero.get("known_spells")
	add["Haste"] = {"charges": -1}
	add["Shield"] = {"charges": -1}
	add["Bless"] = {"charges": -1}
	var base_list: Array = hero._auto_buff_spells_for_tier()
	Game.auto_buff_tier = "base"
	base_list = hero._auto_buff_spells_for_tier()
	_check(base_list.has("Haste") and base_list.has("Shield"),
		"Базовое: ускорение + щит")
	_check(not base_list.has("Bless"), "Базовое без благословения")
	Game.auto_buff_tier = "medium"
	var mid_list: Array = hero._auto_buff_spells_for_tier()
	_check(mid_list.has("Bless") and mid_list.has("Protection_from_Fire"),
		"Среднее: благословение + защиты")
	_check(not mid_list.has("Invisibility"), "Среднее без невидимости")
	Game.auto_buff_tier = "max"
	var max_list: Array = hero._auto_buff_spells_for_tier()
	_check(max_list.has("Invisibility"), "Максимальное: + невидимость")

	print("-- цели: маг всегда в списке --")
	Game.auto_buff_tier = "base"
	Game.party.clear()
	Game.npcs.clear()
	Game.auto_targets = "self"
	var self_only: Array = hero._auto_targets()
	_check(self_only.size() == 1 and self_only[0] == hero,
		"«Только я» — в списке ровно маг")
	Game.auto_targets = "party"
	var party_only: Array = hero._auto_targets()
	_check(party_only.has(hero), "«Я и моя группа» включает самого мага")
	Game.auto_targets = "party_neutral"
	_check(hero._auto_targets().has(hero), "«Я, группа и нейтраллы» тоже включает мага")

	print("-- лечение: выбор заклинания --")
	_check(hero._auto_heal_spell() == "", "без изученного Heal лечить нечем")
	Game.auto_spell = "Heal"
	add["Heal"] = {"charges": -1}
	_check(hero._auto_heal_spell() == "Heal", "изученный Heal выбирается автоматически")
	Game.auto_spell = ""
	_check(hero._auto_heal_spell() == "Heal",
		"без ручного выбора берётся первое изученное лечение")

	hero.free()
	Game.auto_spell = ""
	Game.auto_buff_tier = "base"
	Game.auto_targets = "party"
	_report()


func _report() -> void:
	print()
	if _fails.is_empty():
		print("RESULT: OK package_c_smoke (checks=%d)" % _checks)
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL package_c_smoke (checks=%d fails=%d)" % [_checks, _fails.size()])
		quit(1)
