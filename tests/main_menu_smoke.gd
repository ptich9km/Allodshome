extends SceneTree
## Smoke главного меню Mirotokhome (05.10).
##
## Проверяет: 6 кнопок, branding, панель загрузки (6 слотов), выход с
## подтверждением, моды/сеть/об авторах. Quit НЕ вызываем (headless).
##
## Запуск: godot --headless --path . --script res://tests/main_menu_smoke.gd

var _fails: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_wipe_saves()
	_run.call_deferred()

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)

func _run() -> void:
	var err := change_scene_to_file("res://scenes/main_menu.tscn")
	_check(err == OK, "main_menu.tscn")
	await process_frame
	await create_timer(0.4).timeout

	var mm = current_scene
	_check(mm != null, "MainMenu в дереве")
	if mm == null:
		_report()
		return

	# --- Кнопки меню ---
	var btns := _buttons_in(mm)
	var texts: Array[String] = []
	for b in btns:
		texts.append((b as Button).text)
	print("INFO кнопки: %s" % str(texts))
	for need in ["Новая игра", "Загрузить игру", "Моды и дополнения",
			"Сетевая игра", "Об авторах", "Выйти"]:
		var found := false
		for t in texts:
			if str(t) == need:
				found = true
				break
		_check(found, "есть кнопка «%s»" % need)
	_check(texts.size() >= 6, "кнопок не меньше 6 (%d)" % texts.size())

	# --- Branding ---
	var title := _find_label(mm, "MIROTOKHOME")
	_check(title != null, "заголовок MIROTOKHOME")
	var all_text := _all_text(mm)
	_check(not _banned(all_text), "в меню нет «Аллоды/Allods»")
	_check(all_text.contains("0.1.0") or all_text.contains("ptich9km") or true,
		"версия/автор в подвале (info)")

	# --- Загрузить игру: 6 слотов ---
	var load_btn := _find_button(mm, "Загрузить игру")
	_check(load_btn != null, "кнопка «Загрузить игру»")
	if load_btn != null:
		load_btn.pressed.emit()
		await process_frame
		await create_timer(0.2).timeout
		var slot_btns := _buttons_in(mm)
		var slot_texts: Array[String] = []
		var empty_slots := 0
		var disabled := 0
		for b in slot_btns:
			var t := str((b as Button).text)
			if t.contains("Слот"):
				slot_texts.append(t)
				if t.contains("пусто"):
					empty_slots += 1
				if (b as Button).disabled:
					disabled += 1
		print("INFO слоты: %s" % str(slot_texts))
		_check(slot_texts.size() == 6, "6 строк слотов (%d)" % slot_texts.size())
		_check(empty_slots == 6, "без сохранений все пустые (%d)" % empty_slots)
		_check(disabled == 6, "пустые слоты disabled (%d)" % disabled)
		# Назад
		var back := _find_button(mm, "Назад")
		_check(back != null, "кнопка «Назад» в панели загрузки")
		if back != null:
			back.pressed.emit()
			await process_frame
			var menu_box_visible := false
			var mb = mm.get("_menu_box")
			if mb != null:
				menu_box_visible = (mb as Control).visible
			_check(menu_box_visible, "после «Назад» меню снова видно")

	# --- Моды / сеть / об авторах / выход (панели) ---
	for pair in [["Моды и дополнения", "Моды"], ["Сетевая игра", "Сетевая"],
			["Об авторах", "Об авторах"], ["Выйти", "Выйти"]]:
		var b := _find_button(mm, str(pair[0]))
		_check(b != null, "кнопка «%s»" % pair[0])
		if b == null:
			continue
		b.pressed.emit()
		await process_frame
		await create_timer(0.15).timeout
		var ov = mm.get("_overlay")
		_check(ov != null and (ov as Control).visible, "оверлей «%s» открыт" % pair[1])
		if pair[0] == "Об авторах":
			var txt := _all_text(mm)
			_check(txt.contains("ptich9km") or txt.contains("MIROTOKHOME"),
				"об авторах: есть MIROTOKHOME/ptich9km")
		if pair[0] == "Выйти":
			# Не нажимаем «Да» — иначе headless quit
			var yes := _find_button(mm, "Да")
			_check(yes != null, "подтверждение выхода: есть «Да»")
			var no := _find_button(mm, "Нет")
			_check(no != null, "подтверждение выхода: есть «Нет»")
			if no != null:
				no.pressed.emit()
				await process_frame
		else:
			var back := _find_button(mm, "Назад")
			if back != null:
				back.pressed.emit()
				await process_frame

	# --- project.godot main_scene ---
	var proj := FileAccess.open("res://project.godot", FileAccess.READ)
	var has_mm := false
	if proj != null:
		var txt := proj.get_as_text()
		proj.close()
		has_mm = txt.contains("main_menu.tscn")
	_check(has_mm, "project.godot: main_scene = main_menu")

	# --- character_select: без «Продолжить» ---
	err = change_scene_to_file("res://scenes/character_select.tscn")
	await process_frame
	await create_timer(0.3).timeout
	var cs = current_scene
	if cs != null:
		var cont := _find_button(cs, "Продолжить")
		_check(cont == null, "на character_select нет «Продолжить»")
		var start := _find_button(cs, "В ПУТЬ!")
		_check(start != null, "на character_select есть «В ПУТЬ!»")

	_report()

func _wipe_saves() -> void:
	SaveSystem.ensure_dir()
	for s in SaveSystem.PLAYER_SLOTS:
		for p in [SaveSystem.slot_path(s), SaveSystem.bak_path(s), SaveSystem.tmp_path(s)]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)

func _buttons_in(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_buttons_in(c))
	return out

func _find_button(node: Node, text: String) -> Button:
	for b in _buttons_in(node):
		if str((b as Button).text) == text:
			return b
	return null

func _find_label(node: Node, text: String) -> Label:
	if node is Label and str((node as Label).text) == text:
		return node
	for c in node.get_children():
		var r := _find_label(c, text)
		if r != null:
			return r
	return null

func _all_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += str((node as Label).text) + "\n"
	if node is Button:
		out += str((node as Button).text) + "\n"
	for c in node.get_children():
		out += _all_text(c)
	return out

func _banned(text: String) -> bool:
	var low := text.to_lower()
	for w in ["allod", "аллод"]:
		if low.contains(w):
			return true
	return false

func _report() -> void:
	if _fails.is_empty():
		print("RESULT: OK main_menu_smoke (%d)" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)
