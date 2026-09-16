extends SceneTree
## Тест выбора персонажа: проверяем mouse_filter узлов карточек (баг: дети
## перехватывали клик MOUSE_FILTER_STOP) и эмулируем клик через gui_input.

var select_node: Node

func _init() -> void:
	var scene: PackedScene = load("res://scenes/character_select.tscn")
	select_node = scene.instantiate()
	root.add_child(select_node)
	await _frames(5)

	var failures := 0

	# 1) Каждая карточка: Panel STOP, все дети IGNORE (клик доходит до панели)
	print("start selected =", select_node.selected)
	for i in range(select_node._cards.size()):
		var panel: Control = select_node._cards[i]
		if panel.mouse_filter != Control.MOUSE_FILTER_STOP:
			print("  FAIL card %d: panel filter %d (нужен STOP)" % [i, panel.mouse_filter])
			failures += 1
		for ch in panel.get_children():
			if ch.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				print("  FAIL card %d: узел %s filter %d (нужен IGNORE)" % [i, ch.name, ch.mouse_filter])
				failures += 1

	# 2) Эмуляция клика по карточкам: gui_input на панели
	for idx in [1, 3, 0, 2]:
		var panel: Control = select_node._cards[idx]
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		panel.gui_input.emit(ev)
		await _frames(1)
		var ok: bool = select_node.selected == idx
		print("клик по карточке %d -> selected=%d %s" % [idx, select_node.selected, "OK" if ok else "FAIL"])
		if not ok:
			failures += 1

	print("RESULT:", "OK" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame