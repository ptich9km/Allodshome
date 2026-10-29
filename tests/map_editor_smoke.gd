extends SceneTree
## Редактор карт: пропы, спавн, структуры по футпринту, порталы, валидатор.
##
## Главная регрессия: раньше ЛЮБОЙ проп ставился клеткой типа 7, а `set_tile`
## на типе 7 переставлял `spawn_cell`. Одно дерево уводило точку старта героя.
##
## Запуск: godot --headless --path . --script res://tests/map_editor_smoke.gd

const TMP := "user://map_editor_smoke.alm"
const TMP_JSON := "user://map_editor_smoke.json"

var _fails: Array[String] = []


func _init() -> void:
	var ids: Array = StructureDB.ids()
	_check(ids.size() > 0, "в базе есть здания")
	var sid := int(ids[0]) if ids.size() > 0 else 200

	var m := CustomMap.new()
	root.add_child(m)
	m.new_map(24, 24)
	_check(m.map_width == 24 and m.map_height == 24, "карта 24x24 создана")

	# --- Спавн отдельно от пропов (регрессия) ---
	m.spawn_cell = Vector2i(5, 5)
	var obj_names := ObjectDB.all_names()
	_check(obj_names.size() > 0, "в ObjectDB есть объекты")
	if obj_names.size() > 0:
		var obj := str(obj_names[0])
		m.add_object(Vector2i(7, 7), obj)
		_check(m.spawn_cell == Vector2i(5, 5),
			"проп НЕ перетаскивает спавн (%s)" % str(m.spawn_cell))
		_check(m.tile_id_at(Vector2i(7, 7)) == 7, "проп стоит типом 7")
		_check(ObjectDB.alm_id_of(obj) > 0, "у пропа есть id в alm_objects (%d)"
			% ObjectDB.alm_id_of(obj))
		m.set_tile(Vector2i(8, 8), 7, 0)
		_check(m.spawn_cell == Vector2i(5, 5),
			"краска типа 7 тоже НЕ двигает спавн")

	# --- Здания ---
	var placed := m.add_structure(Vector2i(12, 12), sid)
	_check(placed, "здание поставлено")
	var def := StructureDB.get_by_id(sid)
	var fw := int(def.get("tile_width", 1))
	var th := int(def.get("tile_height", 1))
	var fh := int(def.get("full_height", th))
	_check(not m.add_structure(Vector2i(13, 12), sid),
		"пересечение запрещено")
	_check(not m.add_structure(Vector2i(23, 23), sid),
		"за границей карты запрещено")
	# Снятие по любой клетке футпринта (не только по якорю)
	var inner := Vector2i(12 + fw - 1, 12 - (fh - th))
	_check(m.structure_index_at(inner) >= 0, "клетка футпринта найдена")
	_check(m.remove_structure_at(inner), "здание снято кликом по краю футпринта")
	_check(m.structures.is_empty(), "структур не осталось")

	# --- Порталы ---
	m.add_portal(Vector2i(4, 4), "s21", "")
	_check(m.portals.size() == 1 and m.portal_index_at(Vector2i(4, 4)) == 0,
		"портал поставлен")
	m.add_portal(Vector2i(4, 4), "", "")
	_check(m.portals.size() == 1 and str((m.portals[0] as Dictionary).get("to", "x")) == "",
		"повторная установка обновляет портал, а не плодит")
	_check(m.remove_portal_at(Vector2i(4, 4)), "портал снят")
	_check(m.portals.is_empty(), "порталов не осталось")

	# --- Спавн / высоты / препятствия ---
	m.spawn_cell = Vector2i(3, 3)
	var heights := m.export_heights()
	_check(heights.size() == m.map_width * m.map_height, "высоты на всю карту (%d)" % heights.size())
	var obs := m.export_alm_obstacles()
	_check(obs.size() == m.map_width * m.map_height, "препятствия на всю карту")
	if obj_names.size() > 0:
		_check(obs[7 * m.map_width + 7] > 0, "проп попал в секцию obstacles")

	# --- Сохранение JSON (внутренний формат) ---
	m.add_portal(Vector2i(4, 4), "s21", "")
	_check(m.save_map(TMP_JSON), "JSON сохранён")
	var m2 := CustomMap.new()
	root.add_child(m2)
	_check(m2.load_map(TMP_JSON), "JSON загружен")
	_check(m2.spawn_cell == Vector2i(3, 3), "спавн пережил JSON (%s)" % str(m2.spawn_cell))
	_check(m2.portals.size() == 1, "порталы пережили JSON")
	_check(m2.tile_id_at(Vector2i(7, 7)) == 7, "проп пережил JSON")

	# --- Валидатор ---
	var no_spawn := CustomMap.new()
	root.add_child(no_spawn)
	no_spawn.new_map(16, 16)
	var problems := MapValidator.validate(no_spawn, "", "start")
	_check(_has_error(problems, "спавн"), "валидатор: нет спавна -> ошибка")
	no_spawn.spawn_cell = Vector2i(2, 2)
	problems = MapValidator.validate(no_spawn, "", "start")
	_check(_has_error(problems, "не сохранена"), "валидатор: нет .alm -> ошибка")
	# Неизвестное здание (снесённые Аллодовские id)
	no_spawn.structures.append({"x": 2, "y": 2, "type_id": 8})
	problems = MapValidator.validate(no_spawn, TMP, "start")
	_check(_has_error(problems, "Неизвестное здание"), "валидатор: неизвестный type_id")
	no_spawn.structures.clear()
	# Порталы
	no_spawn.add_portal(Vector2i(4, 4), "s99", "")
	problems = MapValidator.validate(no_spawn, TMP, "start")
	_check(_has_error(problems, "несуществующий сектор"), "валидатор: портал в никуда")
	no_spawn.portals.clear()
	no_spawn.add_portal(Vector2i(4, 4), "", "")
	problems = MapValidator.validate(no_spawn, TMP, "faction")
	_check(_has_error(problems, "тупик"), "валидатор: «по цепочке» из faction = тупик")
	no_spawn.portals.clear()
	problems = MapValidator.validate(no_spawn, TMP, "start")
	_check(problems.is_empty(), "валидатор: чистая карта без ошибок (%d)" % problems.size())

	# --- Полная запись из редактора (новый .alm) ---
	var tiles := m2.export_alm_tiles(PackedInt32Array())
	_check(AlmLoader.write_map(TMP, m2.map_width, m2.map_height, tiles,
		m2.export_heights(), m2.export_alm_obstacles(), "smoke"), ".alm записан из редактора")
	var loaded := AlmLoader.load_map(TMP)
	_check(int(loaded.get("width", 0)) == 24, ".alm читается AlmLoader (%dx%d)"
		% [int(loaded.get("width", 0)), int(loaded.get("height", 0))])

	# --- Сама сцена редактора: инструменты и «Новая» ---
	var packed: PackedScene = load("res://scenes/map_editor.tscn")
	var ed = packed.instantiate()
	root.add_child(ed)
	for i in range(4):
		await process_frame
	_check(ed.tool_buttons.size() >= 8, "в редакторе есть инструменты (%d)" % ed.tool_buttons.size())
	_check(ed.palette_buttons.size() == 10, "палитра типов + ластик (%d)" % ed.palette_buttons.size())
	ed._zone = "mid"
	ed.map_w_spin.value = 32
	ed.map_h_spin.value = 32
	ed._on_new()
	await process_frame
	_check(ed.map.map_width == 32 and ed.map.map_height == 32, "«Новая» создаёт 32x32")
	_check(ed._alm_path == "", "после «Новой» путь .alm пуст")
	ed._on_validate()
	await process_frame
	_check(ed._footprint != null, "рамка футпринта создана")

	# Полная запись из редактора: .alm + sidecar-ы + meta.json
	ed._alm_path = "user://map_editor_smoke_write.alm"
	ed._meta_title = "smoke"
	ed._zone = "start"
	ed.map.spawn_cell = Vector2i(4, 4)
	if obj_names.size() > 0:
		ed.map.add_object(Vector2i(6, 6), str(obj_names[0]))
	ed._write_current_alm()
	var base: String = str(ed._alm_path).get_basename()
	_check(FileAccess.file_exists(ed._alm_path), "редактор записал .alm")
	_check(FileAccess.file_exists(base + ".spawn.json"), "редактор записал .spawn.json")
	_check(FileAccess.file_exists(base + ".structures.json"), "редактор записал sidecar структур")
	_check(FileAccess.file_exists(base + ".meta.json"), "редактор записал .meta.json")
	var meta := MapMeta.read(ed._alm_path)
	_check(str(meta.get("zone", "")) == "start", "мета: зона start")
	var reopened := AlmLoader.load_map(ed._alm_path)
	_check(not reopened.is_empty(), "записанный редактором .alm читается")
	_check((reopened.get("obstacles", PackedByteArray()) as PackedByteArray).size()
		== 32 * 32, "obstacles записаны на всю карту")
	for suffix in ["", ".spawn.json", ".structures.json", ".npcs.json",
			".portal.json", ".nowalk.json", ".allowwalk.json", ".meta.json"]:
		var p: String = base + str(suffix) if suffix != "" else ed._alm_path
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	ed.queue_free()
	await process_frame

	_cleanup()
	_report()


func _has_error(problems: Array, needle: String) -> bool:
	for raw in problems:
		var p: Dictionary = raw
		if str(p.get("level", "")) == "error" and str(p.get("text", "")).contains(needle):
			return true
	return false


func _cleanup() -> void:
	for p in [TMP, TMP_JSON, TMP.get_basename() + ".meta.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK map_editor_smoke")
		quit(0)
	else:
		print("RESULT: FAIL map_editor_smoke (%d)" % _fails.size())
		quit(1)
