extends SceneTree
## A mod beast really reaches the world: the `spawn.gray_species` rule + filtering
## of non-existent tiers.
##
## A separate test because here the mod MUST load before the first access to
## UnitDB/MapGenerator: bases are read once per process.
##
## Run: godot --headless --path . --script res://tests/mod_spawn_smoke.gd

var _fails: Array[String] = []

const ROOT := "user://mods"
const MOD_ID := "_spawn_probe"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_rmrf(ROOT.path_join(MOD_ID))
	_build_mod()
	ModLoader.set_active(true)

	_check(UnitDB.has("monsters/probe"), "мод-зверь есть в базе юнитов")
	_check(UnitDB.is_hostile("monsters/probe"), "мод-зверь враждебен (palette из базы)")

	var start_pool: Array = MapGenerator.gray_pool_for_zone("start")
	_check(start_pool.has("monsters/probe"), "зверь мода попадает в пул стартовой зоны")
	_check(not start_pool.has("monsters/probe_t2"),
		"несуществующий тир 2 не попадает в пул (фильтр по базе)")
	_check(start_pool.has("monsters/wolf"), "базовые звери остались в пуле")

	var faction_pool: Array = MapGenerator.gray_pool_for_zone("faction")
	_check(not faction_pool.has("monsters/probe"),
		"в зоне 4-5 зверь с тиром 1 не спавнится (полоса тиров уважается)")

	_check(MapGenerator.gray_species().has("probe"), "вид из данных виден генератору")

	# Book of a modded school: the shop sells it (SpellDB.make_book_item), and it
	# must resolve as an item — otherwise the inventory shows an empty cell.
	_check(SpellDB.sphere_of_book("Book Probe") == "Probe",
		"книга модовой школы узнаётся по правилу сфер")
	_check(not ItemDB.find("Book Probe").is_empty(),
		"книга модовой школы находится как предмет (сумка/лавка)")

	_rmrf(ROOT.path_join(MOD_ID))
	ModLoader.set_active(false)
	_report()


func _build_mod() -> void:
	_write_json("%s/mod.json" % MOD_ID, {"id": MOD_ID, "name": "Spawn Probe", "version": "1.0.0"})
	_write_json("%s/data/units.json" % MOD_ID, [
		{"into": "unit", "key": "monsters/probe", "extends": "monsters/wolf",
			"name_ru": "Пробный зверь", "tier": 1, "palette": 5},
	])
	_write_json("%s/data/rules.json" % MOD_ID, [
		{"into": "rule", "op": "append", "key": "spawn.gray_species", "value": ["probe"]},
		{"into": "rule", "op": "append", "key": "spells.spheres", "value": ["Probe"]},
	])
	_write_json("%s/data/spells.json" % MOD_ID, [
		{"into": "spell", "key": "Probe_Bolt", "name": "Probe_Bolt", "ru": "Пробная стрела",
			"sphere": "Probe", "damage": 10, "mana_cost": 3, "range": 300, "area": 0,
			"projectile": "firebolt", "kind": "attack", "cooldown": 0.8, "cast_time": 0.3,
			"projectile_speed": 400, "target": "enemy"},
	])


func _write_json(rel: String, data: Variant) -> void:
	var path := ROOT.path_join(rel)
	var dir := path.get_base_dir()
	if DirAccess.open(dir) == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _rmrf(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		var c := path.path_join(n)
		if da.current_is_dir():
			_rmrf(c)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(c))
		n = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK mod_spawn_smoke")
		quit(0)
	else:
		print("RESULT: FAIL mod_spawn_smoke (%d)" % _fails.size())
		quit(1)
