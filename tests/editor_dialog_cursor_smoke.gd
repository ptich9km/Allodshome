extends SceneTree
## Курсор в диалогах редактора (жалоба игрока 29.10).
##
## FileDialog и PopupPanel — отдельные Window со своим вьюпортом: спрайт
## игрового курсора из главного окна туда не рисуется. Пока диалог открыт,
## cursor_layer обязан вернуть системную стрелку, иначе курсора не видно.
##
## Запуск: godot --headless --path . --script res://tests/editor_dialog_cursor_smoke.gd

var _fails: Array[String] = []


func _init() -> void:
	var ed = load("res://scenes/map_editor.tscn").instantiate()
	root.add_child(ed)
	for i in range(6):
		await process_frame
	var cur = ed.get_node_or_null("CursorLayer")
	_check(cur != null, "слой курсора найден")
	if cur == null:
		_report()
		return
	_check(cur._system_cursor == false, "в редакторе системный курсор скрыт")
	_check(cur._cursor_applied, "курсор применён при старте (системный спрятан)")
	_check(cur._sprite != null and cur._sprite.visible, "спрайт курсора виден")

	# 1) FileDialog «Открыть…»
	ed._on_open_map()
	for i in range(4):
		await process_frame
	var fd = _find_window(ed, "FileDialog")
	_check(fd != null and fd.visible, "FileDialog открыт")
	_check(cur._system_cursor == true, "в FileDialog системный курсор включён")
	_check(not cur._sprite.visible, "спрайт курсора в FileDialog скрыт")
	if fd != null:
		fd.hide()
		for i in range(3):
			await process_frame
	_check(cur._system_cursor == false, "после закрытия FileDialog курсор снова свой")
	_check(cur._sprite.visible, "спрайт курсора вернулся")

	# 2) PopupPanel пикера структур
	ed._select_tool(1)
	for i in range(4):
		await process_frame
	var pop = _find_window(ed, "", true)
	_check(pop != null and pop.visible, "PopupPanel открыт")
	_check(cur._system_cursor == true, "в PopupPanel системный курсор включён")
	if pop != null:
		pop.hide()
		for i in range(3):
			await process_frame
	_check(cur._system_cursor == false, "после закрытия PopupPanel курсор снова свой")

	ed.queue_free()
	await process_frame
	_report()


## Первый видимый Window-потомок с именем/классом; popup=true — любой Popup.
func _find_window(node: Node, cls: String, popup: bool = false):
	for c in node.get_children():
		if c is Window and (c as Window).visible:
			if cls != "" and c.get_class() == cls:
				return c
			if popup and (c is Popup or c.get_class() == "PopupPanel"):
				return c
		var r = _find_window(c, cls, popup)
		if r != null:
			return r
	return null


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK editor_dialog_cursor_smoke")
		quit(0)
	else:
		print("RESULT: FAIL editor_dialog_cursor_smoke (%d)" % _fails.size())
		quit(1)
