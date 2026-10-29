extends SceneTree
## Регрессия: Esc на экране выбора героя возвращает в главное меню.
##
## Раньше `_unhandled_input` в character_select отсутствовал вовсе — из
## «Новой игры» нельзя было выйти, не начав партию. Если открыта панель
## «Мир», Esc должен закрыть сначала её (и остаться на экране).
##
## Запуск: godot --headless --path . --script res://tests/character_select_escape_smoke.gd

var _fails: Array[String] = []


func _init() -> void:
	var packed: PackedScene = load("res://scenes/character_select.tscn")
	var cs = packed.instantiate()
	root.add_child(cs)
	for i in range(4):
		await process_frame

	# 1) Esc с открытой панелью «Мир» — закрывает панель, экран остаётся.
	cs._open_world_panel()
	await process_frame
	_check(cs._world_panel != null, "панель «Мир» открылась")
	_press_escape()
	for i in range(3):
		await process_frame
	_check(cs._world_panel == null, "Esc закрыл панель «Мир»")
	_check(is_instance_valid(cs) and cs.is_inside_tree(), "экран выбора героя не сменился")

	# 2) Esc без панели — уходим в главное меню.
	_press_escape()
	for i in range(6):
		await process_frame
	var cur := current_scene
	var path := ""
	if cur != null and cur.scene_file_path != "":
		path = cur.scene_file_path
	_check(path == "res://scenes/main_menu.tscn",
		"Esc вернул в главное меню (сейчас %s)" % (path if path != "" else "нет сцены"))

	_report()


func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	root.push_input(up)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK character_select_escape_smoke")
		quit(0)
	else:
		print("RESULT: FAIL character_select_escape_smoke (%d)" % _fails.size())
		quit(1)
