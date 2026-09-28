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
const SECTIONS_TOTAL := 5

var _cs: Control = null


func _initialize() -> void:
	_wipe()
	_run.call_deferred()


func _run() -> void:
	_cs = await _open_screen()
	if _cs == null:
		_report()
		return
	# await обязателен для функций с await внутри: без него вызов возвращает
	# корутину немедленно, секция молча не выполняется, и тест выглядит
	# зелёным. Именно так уже терялась секция 5 - счётчик секций это поймал.
	# _test_hidden_without_saves и _test_restore_state await не содержат.
	_test_hidden_without_saves()
	await _test_visible_with_save()
	_test_restore_state()
	await _test_delete_and_hide()
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


# --- 1. Без сохранений блока нет ---

func _test_hidden_without_saves() -> void:
	_check(_cs != null, "экран выбора героя открылся")
	var box = _cs.get("_continue_box")
	_check(box != null, "узел блока «Продолжить» создан")
	if box != null:
		_check(box.visible == false, "без сохранений блок СКРЫТ (не занимает место на экране)")
	_check(SaveSystem.newest_slot() == "", "newest_slot() пуст, когда сохранять нечего")
	_sections += 1


# --- 2. С сохранением блок появляется и заполнен ---

func _write_save(slot: String, hero: String, day: int, gold: int) -> void:
	SaveSystem.save(slot, {
		"version": SaveSystem.VERSION,
		"map": { "seed": 777, "zone": "mid" },
		"hero": {
			"class": "mage", "gender": "female", "name": hero,
			"character_id": "fmage", "stats": {"mind": 25}, "start_book": "book",
			"max_hp": 120, "max_mana": 80, "current_hp": 90, "current_mana": 40,
			"gold": gold, "inventory": ["Potion Medium Mana"],
			"equipped": {}, "experience": {"fire": 900},
			"known_spells": {"Fire_Ball": {"charges": 3}}, "sphere_books": {"Fire": true},
			"position": Vector2(96, 192),
		},
		"world": { "day": day, "global_threat": 0.4, "relations": {}, "hero": {},
			"journal": [], "cities": { "c-1": { "pos": Vector2(8, 9) } } },
		"quests": [],
		"meta": { "hero_name": hero, "hero_class": "mage", "level": 5, "day": day,
			"zone": "mid", "seed": 777, "stamp": 1000 + day },
	})


func _test_visible_with_save() -> void:
	_write_save("slot_0", "Альма", 42, 555)
	# Пересоздаём экран, чтобы блок построился заново.
	_cs = await _open_screen()
	var box = _cs.get("_continue_box")
	_check(box != null and box.visible, "с сохранением блок ПОКАЗАН")
	var texts := _collect_text(box)
	var joined := " ".join(texts)
	_check(joined.find("Альма") >= 0, "в блоке видно имя героя из слота («%s»)" % joined.substr(0, 90))
	_check(joined.find("42") >= 0, "в блоке виден день мира (42)")
	_check(joined.find("Маг") >= 0, "класс героя показан по-русски")
	var cont = _cs.get("_continue_btn")
	_check(cont != null and not cont.disabled, "кнопка «Продолжить» есть и активна")
	# Все спинки слотов: пустые не должны предлагать «Загрузить».
	var load_buttons := _find_buttons_by_text(box, "Загрузить")
	_check(load_buttons.size() == 1, "кнопка «Загрузить» только у занятого слота (%d)" % load_buttons.size())
	var del_buttons := _find_buttons_by_text(box, "Удалить")
	_check(del_buttons.size() == 1, "кнопка «Удалить» только у занятого слота (%d)" % del_buttons.size())
	# Чек-лист AGENTS §10.2: контейнеры, а не координаты.
	_check(_has_container(box), "блок построен контейнерами")
	_check(_focus_owner() != null, "при открытии есть начальный фокус")
	_sections += 1


# --- 3. Восстановление состояния (без смены сцены) ---

func _test_restore_state() -> void:
	Game.map_seed = 0
	Game.hero_name = "Сломан"
	Game.hero_class = "warrior"
	var err: String = _cs.call("_load_slot_into_game", "slot_0")
	_check(err == "", "загрузка слота без ошибки («%s»)" % err)
	_check(int(Game.map_seed) == 777, "сид карты восстановлен (%d)" % int(Game.map_seed))
	_check(str(Game.map_zone) == "mid", "зона карты восстановлена")
	_check(str(Game.hero_name) == "Альма", "имя героя восстановлено")
	_check(str(Game.hero_class) == "mage", "класс героя восстановлен")
	_check(str(Game.hero_gender) == "female", "пол героя восстановлен")
	_check(str(Game.hero_character_id) == "fmage", "id персонажа восстановлен")
	_check(int((Game.hero_stats as Dictionary).get("mind", 0)) == 25, "атрибуты восстановлены")
	# Мир должен оказаться в WorldBus - иначе новая сцена поднимется со старым.
	var bus = root.get_node_or_null("WorldBus")
	_check(bus != null, "автозагрузка WorldBus на месте")
	if bus != null:
		_check(bus.state != null and int(bus.state.day) == 42,
			"мир заменён на загруженный: день %s" % str(bus.state.day if bus.state else null))
		_check(bus.state != null and is_equal_approx(float(bus.state.global_threat), 0.4),
			"угроза мира восстановлена")
		_check(bus.sim != null and bus.sim.state == bus.state,
			"симулятор смотрит на ЗАГРУЖЕННЫЙ мир, а не на старый")
	_sections += 1


# --- 4. Удаление слота ---

func _test_delete_and_hide() -> void:
	_cs.call("_on_delete_slot", "slot_0")
	await process_frame
	await create_timer(0.2).timeout
	_check(not FileAccess.file_exists(SaveSystem.slot_path("slot_0")), "файл слота удалён")
	_check(not FileAccess.file_exists(SaveSystem.bak_path("slot_0")), "и .bak удалён вместе с ним")
	_check(SaveSystem.newest_slot() == "", "после удаления сохранять нечего")
	var box = _cs.get("_continue_box")
	_check(box != null and box.visible == false,
		"после удаления последнего слота блок снова СКРЫТ")
	_check(_cs.get("_continue_btn") == null, "кнопка «Продолжить» снята вместе с блоком")
	_sections += 1


# --- 5. Битый/чужой слот не пускает в игру ---

func _test_bad_slot_message() -> void:
	_write_save("slot_1", "Из будущего", 5, 1)
	var raw := FileAccess.get_file_as_string(SaveSystem.slot_path("slot_1"))
	var doc: Dictionary = JSON.parse_string(raw) as Dictionary
	doc["version"] = SaveSystem.VERSION + 7
	var f := FileAccess.open(SaveSystem.slot_path("slot_1"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	_cs = await _open_screen()
	# Блок с единственным негодным сохранением обязан быть скрыт: пусть
	# игрок не увидит «Продолжить», который гарантированно провалится.
	var box = _cs.get("_continue_box")
	_check(box != null and box.visible == false,
		"блок скрыт, если единственное сохранение из будущей версии")
	Game.map_seed = 0
	var err: String = _cs.call("_load_slot_into_game", "slot_1")
	_check(err.find("новой версией") >= 0 and err.find("нельзя") >= 0,
		"на попытку загрузки вернулось внятное сообщение («%s»)" % err)
	_check(int(Game.map_seed) == 0, "состояние игры не изменилось при отказе")
	_sections += 1


# --- вспомогательное ---

func _collect_text(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		out.append_array(_collect_text(c))
	return out


func _find_buttons_by_text(node: Node, needle: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is Button and (node as Button).text.find(needle) >= 0:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_buttons_by_text(c, needle))
	return out


func _has_container(node: Node) -> bool:
	if node is VBoxContainer or node is HBoxContainer or node is PanelContainer:
		return true
	for c in node.get_children():
		if _has_container(c):
			return true
	return false


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
