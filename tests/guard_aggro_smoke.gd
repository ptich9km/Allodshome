extends SceneTree
## Guard aggro radius (player request 22.10: the town guard grabbed Greys too
## far around the town and got under the hero's feet).
##
## Checks:
##  1. GameConfig carries npc.guard_aggro_radius / npc.guard_leash (the values
##     are data now, not a stuck @export default);
##  2. the radius is 30 % smaller than the old 190 px hard-coded value;
##  3. the leash is not shorter than the radius (a guard must reach a target
##     that already entered its aggro circle);
##  4. a live guard takes the numbers from the config, and a citizen keeps
##     damage = 0 (citizens never fight, so they have no aggro at all).
##
## Run: godot --headless --path . --script res://tests/guard_aggro_smoke.gd

const OLD_RADIUS := 190.0

var _fails: Array = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print("AGGRO: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var radius := GameConfig.getf("npc", "guard_aggro_radius")
	var leash := GameConfig.getf("npc", "guard_leash")
	_check(radius > 0.0, "радиус агро стражи из конфига: %.1f" % radius)
	_check(is_equal_approx(radius, OLD_RADIUS * 0.7),
		"радиус агро уменьшен на 30 %%: %.1f -> %.1f" % [OLD_RADIUS, radius])
	_check(leash >= radius, "поводок %.1f не короче радиуса %.1f" % [leash, radius])

	var guard := Npc.new()
	guard.role = "guard"
	guard.damage = 5
	_check(is_equal_approx(guard.aggro_radius, radius),
		"страж по умолчанию берёт радиус из конфига (%.1f)" % guard.aggro_radius)
	_check(guard.patrol_radius >= 1, "у стража есть радиус патруля")

	var citizen := Npc.new()
	citizen.role = "citizen"
	_check(citizen.damage == 0, "житель не дерётся (агро ему не нужно)")
	guard.free()
	citizen.free()

	if _fails.is_empty():
		print("RESULT: OK guard_aggro_smoke (проверок: %d)" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL guard_aggro_smoke (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)
