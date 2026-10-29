extends SceneTree
## Правила контента: базовые значения из данных + расширение модом.
##
## Проверяем главный смысл M3: мод может добавить НЕ тип записи, а новый ТИП
## контента — школу магии, категорию брони, расу — и игра это подхватывает.
##
## Запуск: godot --headless --path . --script res://tests/content_rules_smoke.gd

var _fails: Array[String] = []

const ROOT := "user://mods"
const MOD_ID := "_rules_probe"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_rmrf(ROOT.path_join(MOD_ID))

	# --- база: значения совпадают с прежними константами (моды выключены) ---
	_check(ContentRules.list("spells.spheres").size() == 5, "5 сфер магии из данных")
	_check(ContentRules.list("items.weapon_types").size() == 21, "21 тип оружия из данных")
	_check(ContentRules.list("items.head_types").size() == 7, "7 типов шлемов из данных")
	_check(ContentRules.list("races").size() == 4, "4 расы из данных")
	_check(ContentRules.dict("map.house_folders").has("ork"), "жильё по расам в данных")
	_check(ContentRules.list("inn.candidates").size() == 4, "кандидаты таверны в данных")
	_check(ContentRules.int_value("units.hostile_palette", 0) == 5, "враждебная палитра в данных")

	var copy := ContentRules.list("items.head_types")
	copy.append("ЧУЖОЙ")
	_check(ContentRules.list("items.head_types").size() == 7, "list() отдаёт копию, данные не портятся")

	# --- поведение на базе не изменилось ---
	_check(ItemDB.slot_of({"type": "Long Sword"}) == "weapon", "меч -> слот weapon")
	_check(ItemDB.slot_of({"type": "Tower Shield"}) == "shield", "щит -> слот shield")
	_check(ItemDB.is_two_handed({"type": "Staff"}), "посох двуручный")
	_check(SpellDB.sphere_of_book("Book Fire") == "Fire", "книга огня -> Fire")
	_check(SpellDB.book_item_names().size() == 5, "пять книг стихий")
	_check(UnitDB.is_hostile("monsters/wolf"), "волк враждебен")
	_check(not UnitDB.is_hostile("city_smith"), "горожанин не враждебен")
	_check(UnitDB.loot_family_of("monsters/bee_t3") == "insect", "пчела -> insect")
	_check(CharacterSelect.races().size() == 4, "экран героя: 4 расы")

	# --- мод расширяет правила ---
	_build_mod()
	ModLoader.set_active(true)
	ContentRules.reload()
	_check(SpellDB.sphere_of_book("Book Shadow") == "Shadow", "мод добавил школу Shadow")
	_check(SpellDB.book_item_names().has("Book Shadow"), "книга новой школы появляется сама")
	_check(ItemDB.slot_of({"type": "Crown"}) == "head", "мод добавил тип Crown в шлемы")
	_check(CharacterSelect.races().size() == 5, "мод добавил расу")
	_check(not CharacterSelect.races().is_empty(), "список рас читается")
	var shadow_race: Dictionary = ContentRules.race("shadow")
	_check(str(shadow_race.get("label", "")) == "Тень", "раса мода находится по id")
	_check(ModLoader.errors().is_empty(), "ошибок загрузки нет: %s" % str(ModLoader.errors()))

	_rmrf(ROOT.path_join(MOD_ID))
	ModLoader.set_active(false)
	_report()


func _build_mod() -> void:
	_write_json("%s/mod.json" % MOD_ID, {
		"id": MOD_ID, "name": "Rules Probe", "version": "1.0.0",
	})
	_write_json("%s/data/rules.json" % MOD_ID, [
		{"kind": "rule", "op": "append", "key": "spells.spheres", "value": ["Shadow"]},
		{"kind": "rule", "op": "append", "key": "items.head_types", "value": ["Crown"]},
		{"kind": "rule", "op": "append", "key": "races", "value": [{"id": "shadow", "label": "Тень"}]},
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
		print("RESULT: OK content_rules_smoke")
		quit(0)
	else:
		print("RESULT: FAIL content_rules_smoke (%d)" % _fails.size())
		quit(1)
