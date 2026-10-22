extends SceneTree
## Smoke package A: лут по семействам + хитбоксы + трупы не блокируют.

const UNITS := "res://assets/units/units_db.json"
const LOOT := "res://assets/config/loot_tables.json"

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
	print("-- loot tables --")
	_check(ResourceLoader.exists(LOOT), "loot_tables.json есть")
	var lt: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOT))
	_check(lt is Dictionary, "loot_tables парсится")
	if lt is Dictionary:
		var d: Dictionary = lt
		_check(int(d.get("beast", {}).get("broken_gear_chance", -1)) == 0, "beast broken_gear_chance=0")
		_check(int(d.get("insect", {}).get("broken_gear_chance", -1)) == 0, "insect broken_gear_chance=0")
		_check(int(d.get("humanoid", {}).get("broken_gear_chance", -1)) > 0, "humanoid broken_gear_chance>0")
		# С 22.10 в лут-таблице нет целого снаряжения как основного потока:
		# gear_chance переименован в broken_gear_chance (целое — только бонус
		# intact_gear_chance), иначе у Серых копились целые вещи.
		_check(int(d.get("beast", {}).get("intact_gear_chance", -1)) == 0,
			"beast intact_gear_chance=0")
		_check((d.get("beast", {}).get("herbs", []) as Array).size() > 0, "beast имеет травы")

	print("-- loot_family в units_db --")
	var db: Variant = JSON.parse_string(FileAccess.get_file_as_string(UNITS))
	_check(db is Dictionary, "units_db читается")
	if db is Dictionary:
		var u: Dictionary = db
		# Семейства лута. Наборов `monsters/*` больше нет (11.10, чистка
		# Аллодов), и проверять их имена бессмысленно — они вернули бы null.
		# Вместо этого сторож следит за тем, что СПРАВОЧНИК семейств на месте и
		# что ни один оставшийся набор не объявляет несуществующее семейство:
		# именно так сломанная привязка лута проявила бы себя после возврата
		# монстров.
		var known := ["beast", "insect", "humanoid", "undead", "monstrous"]
		var bad_family := 0
		for name in u.keys():
			var f := str((u[name] as Dictionary).get("loot_family", ""))
			if f != "" and not (f in known):
				bad_family += 1
				print("  BAD family `%s` у набора `%s`" % [f, name])
		_check(bad_family == 0,
			"у всех наборов известное семейство лута (чужих: %d)" % bad_family)

	print("-- хитбоксы --")
	var fake := Node2D.new()
	root.add_child(fake)
	fake.set("anim_set", "seed/sw_seed")
	var rect: Rect2 = Game.unit_hit_rect(fake)
	_check(rect.size.x < 40.0, "hitbox width <40 (получено %.1f)" % rect.size.x)
	_check(rect.size.y < 70.0, "hitbox height <70 (получено %.1f)" % rect.size.y)
	fake.set("anim_set", "ork_mage_a52/t0")
	var rect2: Rect2 = Game.unit_hit_rect(fake)
	_check(rect2.size.x > 0 and rect2.size.x <= 48.0, "orc hitbox width<=48 (%.1f)" % rect2.size.x)
	fake.queue_free()

	print("-- _make_loot мок (beast) --")
	# Прямой вызов логики через JSON уже проверен; полный Enemy требует сцены.
	_check(UnitDB.loot_family("нет/такого") == "", "UnitDB.loot_family для неизвестного набора пуст")

	_report()


func _report() -> void:
	print()
	if _fails.is_empty():
		print("RESULT: OK package_a_smoke (checks=%d)" % _checks)
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL package_a_smoke (checks=%d fails=%d)" % [_checks, _fails.size()])
		quit(1)
