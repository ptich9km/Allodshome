extends SceneTree
## Smoke: «Продолжить» на экране выбора героя.
##
## Сцена character_select грузится БЕЗ main.tscn, поэтому тест не зависит от
## ui.gd и переживает параллельную работу над правой панелью. Переход на
## игровую сцену тоже не проверяем - он тянет ui.gd; вместо этого проверяется
## _load_slot_into_game(), то есть ровно то состояние, которое переживёт
## переход.
##
## Запуск: godot --headless --path . --script res://tests/continue_screen_smoke.gd

var _fails: Array[String] = []
var _checks := 0
var _sections := 0
const SECTIONS_TOTAL := 4

var _cs: Control = null


func _initialize() -> void:
	_wipe()
	_run.call_deferred()


func _run() -> void:
	_cs = await _open_screen()
	if _cs == null:
		_report()
		return
	_test_hidden_without_saves()
	await _test_visible_with_save()
	_test_restore_state()
	await _test_bad_slot_message()
	_wipe()
	_report()


func _open_screen():
	Game.hero_class = "warrior"
	Game.hero_gender = "male"
	Game.hero_name = "Новый"
	Game.hero_character_id = "mfighter"
	Game.hero_stats = {}
	Game.map_seed = 0
	var err := change_scene_to_file("res://scenes/character_select.tscn")
	if err != OK:
		return null
	await process_frame
	await create_timer(0.3).timeout
	return current_scene as Control


func _write_save(slot: String, hero: String, day: int, stamp: int) -> void:
	SaveSystem.save(slot, {
		"version": SaveSystem.VERSION,
		"map": { "seed": 777, "zone": "mid" },
		"hero": {
			"class": "mage", "gender": "female", "name": hero,
			"character_id": "fmage", "stats": {"mind": 25}, "start_book": "book",
			"max_hp": 120, "max_mana": 80, "current_hp": 90, "current_mana": 40,
			"gold": 555, "inventory": ["Potion Medium Mana"],
			"equipped": {}, "experience": {"fire": 900},
			"known_spells": {"Fire_Ball": {"charges": 3}}, "sphere_books": {"Fire": true},
			"position": Vector2(96, 192),
		},
		"world": { "day": day, "global_threat": 0.4, "relations": {}, "hero": {},
			"journal": [], "cities": { "c-1": { "pos": Vector2(8, 9) } } },
		"quests": [],
		"meta": { "hero_name": hero, "hero_class": "mage", "level": 5, "day": day,
			"zone": "mid", "seed": 777, "stamp": stamp },
	})


# --- 1. Без сохранений кнопки нет ---

func _test_hidden_without_saves() -> void:
	_check(_cs != null, "экран выбора героя открылся")
	_check(_cs.get("_continue_btn") == null, "без сохранений кнопки «Продолжить» нет")
	_check(str(_cs.get("_continue_slot")) == "", "слот не выбран")
	_check(SaveSystem.newest_slot() == "", "newest_slot() пуст, когда сохранять нечего")
	# Кнопка не должна появляться «в пустоте» - проверяем, что её нет в дереве.
	_check(_count_continue_buttons(_cs) == 0, "в дереве нет кнопки «Продолжить»")
	_sections += 1


# --- 2. С сохранением кнопка появляется в строке старта ---

func _test_visible_with_save() -> void:
	_write_save("slot_0", "Альма", 42, 1000)
	_cs = await _open_screen()
	var btn = _cs.get("_continue_btn")
	_check(btn != null, "с сохранением кнопка «Продолжить» появилась")
	_check(str(_cs.get("_continue_slot")) == "slot_0", "выбран слот_0")
	if btn != null:
		_check(str(btn.text).find("Продолжить") >= 0,
			"на кнопке надпись «Продолжить» («%s»)" % str(btn.text))
		_check(btn.custom_minimum_size.y == 48,
			"высота кнопки совпадает с «В ПУТЬ!» (%d) - блок не вырос" % int(btn.custom_minimum_size.y))
		# Кнопка обязана быть в ТОЙ ЖЕ строке, что и старт, иначе экран
		# не влезает в 1280x600 (character_select_ui_smoke это ловит).
		var start = _cs.get("_start_btn")
		_check(start != null and start.get_parent() == btn.get_parent(),
			"«Продолжить» и «В ПУТЬ!» в одной строке")
		# Ширина строки: кнопка с именем и днём в тексте раздувала строку до
		# 1240 px при доступных 1224 и вылезала за окно 1280 ровно на 16 px.
		var row = btn.get_parent()
		_check(row.get_combined_minimum_size().x <= 1224.0,
			"строка старта помещается в окно 1280 (%.0f <= 1224)"
			% row.get_combined_minimum_size().x)
		_check(btn.tooltip_text.find("Альма") >= 0 and btn.tooltip_text.find("42") >= 0,
			"имя героя и день уехали в подсказку («%s»)" % btn.tooltip_text)
	_check(_focus_owner() != null, "при открытии есть начальный фокус")
	# Свежий слот выбирается по meta.stamp, а не по порядку в каталоге.
	_write_save("slot_1", "Борис", 7, 5000)
	_cs = await _open_screen()
	_check(str(_cs.get("_continue_slot")) == "slot_1",
		"выбран самый СВЕЖИЙ слот, а не первый по имени (slot_1, stamp 5000)")
	_sections += 1


# --- 3. Восстановление состояния (без смены сцены) ---

func _test_restore_state() -> void:
	Game.map_seed = 0
	Game.hero_name = "Сломан"
	Game.hero_class = "warrior"
	var err: String = _cs.call("_load_slot_into_game", "slot_1")
	_check(err == "", "загрузка слота без ошибки («%s»)" % err)
	_check(int(Game.map_seed) == 777, "сид карты восстановлен (%d)" % int(Game.map_seed))
	_check(str(Game.map_zone) == "mid", "зона карты восстановлена")
	_check(str(Game.hero_name) == "Борис", "имя героя восстановлено")
	_check(str(Game.hero_class) == "mage", "класс героя восстановлен")
	_check(str(Game.hero_gender) == "female", "пол героя восстановлен")
	_check(str(Game.hero_character_id) == "fmage", "id персонажа восстановлен")
	_check(int((Game.hero_stats as Dictionary).get("mind", 0)) == 25, "атрибуты восстановлены")
	# Мир должен оказаться в WorldBus - иначе новая сцена поднимется со старым.
	var bus = root.get_node_or_null("WorldBus")
	_check(bus != null, "автозагрузка WorldBus на месте")
	if bus != null:
		_check(bus.state != null and int(bus.state.day) == 7,
			"мир заменён на загруженный: день %s" % str(bus.state.day if bus.state else null))
		_check(bus.state != null and is_equal_approx(float(bus.state.global_threat), 0.4),
			"угроза мира восстановлена")
		_check(bus.sim != null and bus.sim.state == bus.state,
			"симулятор смотрит на ЗАГРУЖЕННЫЙ мир, а не на старый")
	_sections += 1


# --- 4. Сохранение из будущей версии не пускает в игру ---

func _test_bad_slot_message() -> void:
	_write_save("slot_2", "Из будущего", 5, 9000)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.slot_path("slot_2")))
	doc["version"] = SaveSystem.VERSION + 7
	var f := FileAccess.open(SaveSystem.slot_path("slot_2"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	_cs = await _open_screen()
	# Свежий слот - как раз испорченный. Кнопка обязана исчезнуть: игрок не
	# должен видеть «Продолжить», который гарантированно провалится.
	_check(_cs.get("_continue_btn") == null,
		"кнопка скрыта, если самый свежий слот из будущей версии")
	# Но испорченный слот не должен ломать выбор: берём заведомо годный.
	Game.map_seed = 0
	var err: String = _cs.call("_load_slot_into_game", "slot_2")
	_check(err.find("новой версией") >= 0 and err.find("нельзя") >= 0,
		"на попытку загрузки вернулось внятное сообщение («%s»)" % err)
	_check(int(Game.map_seed) == 0, "состояние игры не изменилось при отказе")
	_sections += 1


# --- вспомогательное ---

func _count_continue_buttons(node: Node) -> int:
	var n := 0
	if node == null:
		return 0
	if node is Button and (node as Button).text.begins_with("Продолжить"):
		n += 1
	for c in node.get_children():
		n += _count_continue_buttons(c)
	return n


func _focus_owner() -> Control:
	var vp := root.get_viewport()
	return vp.gui_get_focus_owner() if vp != null else null


func _wipe() -> void:
	SaveSystem.ensure_dir()
	for slot in SaveSystem.PLAYER_SLOTS + [SaveSystem.AUTOSAVE_SLOT]:
		for p in [SaveSystem.slot_path(slot), SaveSystem.bak_path(slot), SaveSystem.tmp_path(slot)]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	print("проверок: %d" % _checks)
	if _sections != SECTIONS_TOTAL:
		print("FAIL отработало %d секций из %d - какая-то не вызвана с await"
			% [_sections, SECTIONS_TOTAL])
		_fails.append("не все секции отработали")
	if _fails.is_empty():
		print("RESULT: OK continue_screen_smoke")
		quit(0)
	else:
		print("RESULT: FAIL continue_screen_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
