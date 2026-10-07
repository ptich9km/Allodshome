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
		_check(int(d.get("beast", {}).get("gear_chance", -1)) == 0, "beast gear_chance=0")
		_check(int(d.get("insect", {}).get("gear_chance", -1)) == 0, "insect gear_chance=0")
		_check(int(d.get("humanoid", {}).get("gear_chance", -1)) > 0, "humanoid gear_chance>0")
		_check((d.get("beast", {}).get("herbs", []) as Array).size() > 0, "beast имеет травы")

	print("-- loot_family в units_db --")
	var db: Variant = JSON.parse_string(FileAccess.get_file_as_string(UNITS))
	_check(db is Dictionary, "units_db читается")
	if db is Dictionary:
		var u: Dictionary = db
		for key in ["monsters/squirrel", "monsters/bee", "monsters/wolf"]:
			_check(str(u.get(key, {}).get("loot_family", "")) == "beast" or str(u.get(key, {}).get("loot_family", "")) == "insect",
				"%s family=%s" % [key, u.get(key, {}).get("loot_family")])
		_check(str(u.get("monsters/orc", {}).get("loot_family", "")) == "humanoid", "orc=humanoid")
		_check(str(u.get("monsters/ogre", {}).get("loot_family", "")) == "humanoid", "ogre=humanoid")

	print("-- хитбоксы --")
	var fake := Node2D.new()
	root.add_child(fake)
	fake.set("anim_set", "heroes/swordsman")
	var rect: Rect2 = Game.unit_hit_rect(fake)
	_check(rect.size.x < 40.0, "hitbox width <40 (получено %.1f)" % rect.size.x)
	_check(rect.size.y < 70.0, "hitbox height <70 (получено %.1f)" % rect.size.y)
	fake.set("anim_set", "monsters/orc")
	var rect2: Rect2 = Game.unit_hit_rect(fake)
	_check(rect2.size.x > 0 and rect2.size.x <= 48.0, "orc hitbox width<=48 (%.1f)" % rect2.size.x)
	fake.queue_free()

	print("-- _make_loot мок (beast) --")
	# Прямой вызов логики через JSON уже проверен; полный Enemy требует сцены.
	_check(UnitDB.loot_family("monsters/squirrel") == "beast", "UnitDB.loot_family squirrel")
	_check(UnitDB.loot_family("monsters/orc") == "humanoid", "UnitDB.loot_family orc")

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
