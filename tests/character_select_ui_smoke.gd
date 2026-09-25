extends SceneTree
## Smoke-проверка экрана выбора персонажа (scripts/character_select.gd).
##
## Экран был собран на хардкоженных координатах 1280×800 (position/size у каждого
## узла). Проверяем, что теперь это контейнеры + единая тема, и — главное —
## что интерфейс не вылезает за окно ни на 1280×800, ни на 1280×600.
##
## Запуск: godot --headless --path . --script res://tests/character_select_ui_smoke.gd

const SIZES := [Vector2i(1280, 800), Vector2i(1280, 600)]

var _fails: Array[String] = []

func _init() -> void:
	var scene: PackedScene = load("res://scenes/character_select.tscn")
	var cs = scene.instantiate()
	root.add_child(cs)
	for i in range(6):
		await process_frame
	await _inspect(cs, Vector2i(1280, 800), "1280x800")
	await _inspect(cs, Vector2i(1280, 600), "1280x600")
	_structure(cs)
	_report()

## Ничего не должно вылезать за пределы окна.
func _inspect(cs, size_px: Vector2i, tag: String) -> void:
	root.size = size_px
	for i in range(3):
		await process_frame
	var win := Rect2(Vector2.ZERO, Vector2(size_px))
	var worst := ""
	for node in _walk(cs):
		var c := node as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r := Rect2(c.global_position, c.size)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not win.encloses(r):
			worst = "%s %s=%s" % [c.get_path(), "size" if win.size.x < r.size.x else "pos", r]
			break
	_check(worst == "", "[%s] весь интерфейс внутри окна%s" % [tag, "" if worst == "" else " — " + worst])

## Контейнерная структура, тема, фокус.
func _structure(cs) -> void:
	_check(cs.theme != null, "на корне висит единая тема UiKit")
	_check(cs.get("_root") is VBoxContainer, "корневая раскладка — VBoxContainer")

	var cards: Array = cs.get("_cards")
	_check(cards.size() == 4, "карточек 4 (было %d)" % cards.size())
	var panels := 0
	var themed := 0
	for card in cards:
		if card is PanelContainer:
			panels += 1
		if card.theme_type_variation == &"CsCard":
			themed += 1
	_check(panels == cards.size(), "карточки — PanelContainer (%d из %d)" % [panels, cards.size()])
	_check(themed == cards.size(), "карточки используют стиль темы (%d из %d)" % [themed, cards.size()])

	# Никаких ручных координат: у узлов НЕ должно быть заданных position/size
	# вне контейнеров (position != Vector2.ZERO означает ручную раскладку).
	var manual := 0
	for node in _walk(cs):
		var c := node as Control
		if c == null or c is Container:
			continue
		if c.get_parent() is Container:
			continue
		if c is ColorRect:
			continue  # фон — он и должен быть на весь экран
		if c is Label and c.position != Vector2.ZERO:
			manual += 1
	_check(manual == 0, "нет ручной раскладки узлов (найдено: %d)" % manual)

	# Ввод и фокус
	var name_input: LineEdit = cs.get("name_input")
	_check(name_input != null, "поле ввода имени на месте")
	_check(name_input != null and name_input.custom_minimum_size.x >= 200.0, "поле имени не мелкое")
	var start_btn: Button = cs.get("_start_btn")
	_check(start_btn != null, "кнопка «В ПУТЬ!» на месте")
	_check(start_btn != null and start_btn.custom_minimum_size.x >= 200.0, "кнопка старта не мелкая")
	var aff: Array[Button] = cs.get("_affinity_buttons")
	_check(aff.size() == 10, "кнопок склонности 10 (%d)" % aff.size())
	var wired := 0
	for b in aff:
		if b.focus_neighbor_left.is_empty() == false and b.focus_neighbor_right.is_empty() == false:
			wired += 1
	_check(wired == aff.size(), "у кнопок склонности прописаны соседи фокуса (%d из %d)" % [wired, aff.size()])

## Обойти всё дерево.
func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK character_select_ui_smoke")
		quit(0)
	else:
		print("RESULT: FAIL character_select_ui_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
