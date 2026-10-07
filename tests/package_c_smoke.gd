extends SceneTree
## Smoke package C: авто-каст мага (auto_spell, heal targets, buff tiers).

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
	_check(Game.auto_heal_targets == "party", "heal targets=party")
	_check(Game.auto_buff_tier == "none", "buff tier=none")

	print("-- SpellDB kinds --")
	_check(SpellDB.kind_of("Heal") == "heal", "Heal kind=heal")
	_check(SpellDB.kind_of("Haste") == "buff", "Haste kind=buff")
	_check(SpellDB.kind_of("Bless") == "buff", "Bless kind=buff")
	_check(SpellDB.kind_of("Invisibility") == "buff", "Invis kind=buff")
	_check(SpellDB.target_of("Heal") == "ally", "Heal target=ally")

	print("-- конфиг --")
	_check(absf(GameConfig.getf("magic", "auto_heal_ratio") - 0.45) < 0.001,
		"auto_heal_ratio=0.45")
	_check(GameConfig.getf("magic", "auto_buff_interval") >= 0.2,
		"auto_buff_interval задан")

	print("-- set auto + candidates --")
	Game.auto_spell = "Heal"
	Game.auto_heal_targets = "party"
	# Кандидаты party: пустая партия → лечить некого (не падает)
	Game.party.clear()
	Game.hero = null
	_check(Game.auto_spell == "Heal", "auto_spell=Heal")
	Game.auto_buff_tier = "light"
	_check(Game.auto_buff_tier == "light", "tier=light")
	Game.auto_buff_tier = "medium"
	_check(Game.auto_buff_tier == "medium", "tier=medium")
	Game.auto_buff_tier = "advanced"
	_check(Game.auto_buff_tier == "advanced", "tier=advanced")
	Game.auto_spell = ""
	Game.auto_buff_tier = "none"
	Game.auto_heal_targets = "party"

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
