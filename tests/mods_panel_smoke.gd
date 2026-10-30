extends SceneTree
## Mods panel: rows, enabling, order, Esc, settings persistence.
##
## The test creates temporary mods `_ui_*` and MUST restore `user://mods.cfg` to
## its original state: the player keeps own mod settings there.
##
## Run: godot --headless --path . --script res://tests/mods_panel_smoke.gd

var _fails: Array[String] = []

const ROOT := "user://mods"
const CFG := "user://mods.cfg"
const IDS := ["_ui_alpha", "_ui_beta"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var cfg_backup := _read_cfg()
	_cleanup()
	_build_mods()
	ModLoader.set_active(true)

	var panel := ModsPanel.new()
	panel.name = "ModsPanel"
	root.add_child(panel)
	for i in range(4):
		await process_frame

	var list: Node = panel.get("_list")
	var count: Label = panel.get("_count")
	_check(list != null, "список строк создан")
	# Count by OUR ids, not by the total number of rows: the player has own mods
	# in user://mods, and the test must pass together with them (hit this on
	# 2026-10-29).
	_check(_has_row(list, "_ui_alpha") and _has_row(list, "_ui_beta"),
		"строка на каждый тестовый мод")
	_check(count != null and not count.text.is_empty(), "счётчик заполнен")

	# Regression of 2026-10-29: "copied a mod, but the menu is empty". The scan is
	# cached, so "Refresh" must rescan the folder, not only repaint the rows.
	_write_json("_ui_gamma/mod.json", {"id": "_ui_gamma", "name": "_ui_gamma", "version": "1.0.0"})
	_write_json("_ui_gamma/data/units.json", [
		{"into": "unit", "key": "monsters/_ui_gamma_hound", "extends": "monsters/wolf"},
	])
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ROOT.path_join("_ui_orphan")))
	_check(not _has_row(list, "_ui_gamma"), "до «Обновить» список остаётся прежним (кэш скана)")
	panel._on_refresh()
	for i in range(3):
		await process_frame
	_check(_has_row(list, "_ui_gamma"),
		"«Обновить» находит мод, скопированный после открытия панели")
	_check(ModLoader.orphan_folders().has(ROOT.path_join("_ui_orphan")),
		"папка без mod.json попадает в подсказку, а не теряется молча")

	# disabling
	var alpha_row: Node = list.get_node_or_null("Row__ui_alpha")
	_check(alpha_row != null, "строка _ui_alpha найдена")
	if alpha_row != null:
		var check: CheckButton = alpha_row.find_child("Enabled", true, false)
		_check(check != null and check.button_pressed, "_ui_alpha включён до переключения")
		if check != null:
			check.button_pressed = false
			check.toggled.emit(false)
		for i in range(3):
			await process_frame
		_check(not ModLoader.is_enabled("_ui_alpha"), "_ui_alpha выключен")
		_check(FileAccess.file_exists(CFG), "настройки модов записаны в user://mods.cfg")
		var enabled_ids: Array[String] = []
		for m in ModLoader.mods():
			enabled_ids.append(str(m["id"]))
		_check(not enabled_ids.has("_ui_alpha"), "выключенный мод не попадает в набор")

	# order: beta above alpha
	var before := _order_index("_ui_alpha")
	ModLoader.move("_ui_alpha", -1)
	_check(_order_index("_ui_alpha") < before or before == 0, "перемещение меняет ручной порядок")

	# Esc closes
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	panel._unhandled_input(esc)
	_check(bool(panel.get("_closed")), "Esc закрывает панель")

	# restore the player's settings
	_cleanup()
	_restore_cfg(cfg_backup)
	ModLoader.reset()
	_report()


func _has_row(list: Node, id: String) -> bool:
	return list.get_node_or_null("Row_" + id) != null


func _order_index(id: String) -> int:
	var i := 0
	for m in ModLoader.all_mods():
		if str(m["id"]) == id:
			return i
		i += 1
	return -1


func _build_mods() -> void:
	for id in IDS:
		_write_json("%s/mod.json" % id, {"id": id, "name": id, "version": "1.0.0"})
		_write_json("%s/data/units.json" % id, [
			{"into": "unit", "key": "monsters/%s_hound" % id, "extends": "monsters/wolf"},
		])


func _write_json(rel: String, data: Variant) -> void:
	var path := ROOT.path_join(rel)
	var dir := path.get_base_dir()
	if DirAccess.open(dir) == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _read_cfg() -> String:
	if not FileAccess.file_exists(CFG):
		return ""
	return FileAccess.get_file_as_string(CFG)


func _restore_cfg(text: String) -> void:
	if text == "":
		if FileAccess.file_exists(CFG):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
		return
	var f := FileAccess.open(CFG, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cleanup() -> void:
	for id in IDS:
		_rmrf(ROOT.path_join(id))
	_rmrf(ROOT.path_join("_ui_gamma"))
	_rmrf(ROOT.path_join("_ui_orphan"))


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
		print("RESULT: OK mods_panel_smoke")
		quit(0)
	else:
		print("RESULT: FAIL mods_panel_smoke (%d)" % _fails.size())
		quit(1)
