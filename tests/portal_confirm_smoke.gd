extends SceneTree
## Окно подтверждения портала (23.10).
##
## Запуск: godot --headless --path . --script res://tests/portal_confirm_smoke.gd

var _checks := 0
var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var script: GDScript = load("res://scripts/portal_confirm.gd")
	var dlg = script.new()
	var got := [-1]
	dlg.answered.connect(func(v: bool) -> void: got[0] = 1 if v else 0)
	dlg.setup("Тихая Заводь", "Серый Брод")
	root.add_child(dlg)
	await process_frame

	var title := _find(dlg, "Title") as Label
	var body := _find(dlg, "Body") as Label
	var stay := _find(dlg, "Stay") as Button
	var go := _find(dlg, "Go") as Button
	_check(title != null and title.text.contains("Тихая Заводь"), "заголовок с именем карты")
	_check(body != null and body.text.contains("Серый Брод"), "текст с именем назначения")
	_check(stay != null and stay.text == Loc.t("ui.portal.stay"), "кнопка «Остаться»")
	_check(go != null and go.text == Loc.t("ui.portal.go"), "кнопка «Уйти»")
	_check(stay != null and stay.has_focus(), "фокус на безопасной кнопке")

	# Esc = «Остаться»
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	dlg._input(esc)
	await process_frame
	_check(got[0] == 0, "Esc отвечает «Остаться»")
	_check(not is_instance_valid(dlg), "окно закрывается после ответа")

	print("")
	if _fails.is_empty():
		print("RESULT: OK portal_confirm_smoke (%d checks)" % _checks)
	else:
		print("RESULT: FAIL portal_confirm_smoke (%d checks, %d fails)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)


func _find(node: Node, part: String) -> Node:
	if node.name.to_lower().contains(part.to_lower()):
		return node
	for ch in node.get_children():
		var hit := _find(ch, part)
		if hit != null:
			return hit
	return null
