extends SceneTree
##
## Сейв v2: отряд и хотбар (28.10).
##
## ЗАЧЕМ
## -----
## До этого наёмники и назначения клавиш 1..9 не сохранялись: после «Загрузить»
## отряд исчезал, а хотбар оставался от прошлой партии (он вообще не сбрасывался
## и «протекал» между героями). Здесь проверяется слой данных: снимок отряда,
## чтение с валидацией, хотбар с отбраковкой неизвестных записей и обратная
## совместимость с сейвом v1.
##
## ЧТО НЕ ПОКРЫТО ТЕСТОМ (ручная проверка): создание живых узлов Mercenary в
## `game._restore_pending_party()` — для него нужна настоящая карта и сцена.
##
## Запуск: godot --headless --path . --script res://tests/save_party_smoke.gd

const MERC_SET := "ork_mage_a52/t1"

var _checks := 0
var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _initialize() -> void:
	_run.call_deferred()


func _valid_item_key() -> String:
	for raw in ItemDB.all():
		var item: Dictionary = raw
		var key := str(item.get("key", ""))
		if key != "" and not ItemDB.find(key).is_empty():
			return key
	return ""


func _valid_spell() -> String:
	var spells: Array = SpellDB.catalog_spells()
	return str(spells[0]) if not spells.is_empty() else ""


func _run() -> void:
	print("-- снимок отряда (данные, не узлы) --")
	var saved: Array = SaveSystem._party_saved([
		{"set": MERC_SET, "hp_max": 70, "hp": 40, "damage": 7, "spirit": 5,
			"speed": 90.0, "x": 100.0, "y": 200.0},
		{"set": "no/such_set", "hp_max": 50, "hp": 10},
		{"set": MERC_SET, "hp_max": 60, "hp": 999, "damage": -3, "spirit": -1,
			"speed": 0.0, "x": 0.0, "y": 0.0},
		"не словарь",
	])
	_check(saved.size() == 2, "неизвестный набор и мусор отброшены (осталось %d)"
		% saved.size())
	var first: Dictionary = saved[0]
	_check(str(first.get("set", "")) == MERC_SET, "набор сохранён")
	_check(int(first.get("hp", 0)) == 40, "текущий HP сохранён")
	_check(is_equal_approx(float(first.get("x", 0.0)), 100.0), "позиция X сохранена")
	var second: Dictionary = saved[1]
	_check(int(second.get("hp", 0)) == 60,
		"HP выше максимума обрезан (%d)" % int(second.get("hp", 0)))
	_check(int(second.get("damage", -1)) == 0, "отрицательный урон выправлен")
	_check(float(second.get("speed", 0.0)) >= 10.0, "нулевая скорость поднята")

	print("-- хотбар: только существующие записи --")
	var spell := _valid_spell()
	var item_key := _valid_item_key()
	_check(spell != "", "в базе есть заклинание для хотбара")
	_check(item_key != "", "в базе есть предмет для хотбара")
	var hotbar: Dictionary = SaveSystem._hotbar_saved({
		"0": {"kind": "spell", "name": spell},
		1: {"kind": "item", "key": item_key},
		"2": {"kind": "spell", "name": "NoSuchSpell"},
		"3": {"kind": "item", "key": "No Such Item"},
		"4": {"kind": "other"},
		"9": {"kind": "spell", "name": spell},
		"x": {"kind": "spell", "name": spell},
	})
	_check(hotbar.size() == 2, "осталось 2 живые записи (сейчас %d)" % hotbar.size())
	_check(hotbar.has(0) and str(hotbar[0].get("name", "")) == spell,
		"строковый ключ слота прочитан, заклинание сохранено")
	_check(hotbar.has(1) and str(hotbar[1].get("key", "")) == item_key,
		"предмет сохранён в слоте 1")
	_check(not hotbar.has(9), "слот вне 0..8 отброшен")

	print("-- v1 без новых полей читается --")
	Game.hotbar = {7: {"kind": "spell", "name": spell}}
	Game.pending_party = [{"set": MERC_SET}]
	SaveSystem.apply_payload({
		"map": {"seed": 1, "zone": "start"},
		"hero": {"class": "warrior", "gender": "m", "name": "Old", "race": "humans"},
	}, null, "")
	_check(Game.pending_party.is_empty(), "v1: отряда нет — очередь пуста")
	_check(Game.hotbar.is_empty(), "v1: хотбар очищен, а не унаследован")

	print("-- v2: отряд и хотбар доезжают до Game --")
	SaveSystem.apply_payload({
		"map": {"seed": 1, "zone": "start"},
		"hero": {
			"class": "warrior", "gender": "m", "name": "New", "race": "humans",
			"party": [{"set": MERC_SET, "hp_max": 70, "hp": 50, "damage": 6,
				"spirit": 4, "speed": 90.0, "x": 320.0, "y": 160.0}],
			"hotbar": {"2": {"kind": "spell", "name": spell}},
		},
	}, null, "")
	_check(Game.pending_party.size() == 1, "отряд ждёт сборки карты (1 боец)")
	_check(Game.hotbar.size() == 1 and Game.hotbar.has(2),
		"хотбар восстановлен в Game")

	print("-- версии --")
	_check(SaveSystem.VERSION == 2, "схема сейва = v2")
	_check(SaveSystem.VERSION > 1, "сейв v1 остаётся читаемым (младше текущего)")

	Game.pending_party = []
	Game.hotbar = {}
	print("")
	if _fails.is_empty():
		print("RESULT: OK save_party_smoke (%d checks)" % _checks)
	else:
		print("RESULT: FAIL save_party_smoke (%d checks, %d fails)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)
