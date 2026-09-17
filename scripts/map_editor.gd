extends Node2D
## Редактор карт Allods Home. Кисть по сетке, палитра типов terrain.
## У каждого типа — набор текстур (настраивается в «Настройки…»), кисть красит
## выбранной текстурой из набора. Сохранение: JSON 1:1 (клетка -> тип + индекс
## текстуры внутри набора).

const SAVE_PATH := "res://assets/maps/my_map.json"
const SETTINGS_PATH := "res://assets/maps/map_editor_palette.json"
const TILE := 32

var map: CustomMap
var brush_type := 0            # 0-7 тип, -1 ластик
var brush_tex_idx := 0         # индекс текстуры в наборе типа
var brush_size := 1
var camera: Camera2D
var ui: CanvasLayer
var palette_buttons := {}      # тип -> Button
var tex_strip_grid: GridContainer
var tex_strip_buttons: Array = []
var brush_size_buttons: Array = []
var status_label: Label
var settings_panel: TextureSettingsPanel = null
var catalog_panel: InventoryCatalogPanel = null
var _fill_mode := false
var fill_btn: Button
var _undo_stack: Array = []
var map_w_spin: SpinBox
var map_h_spin: SpinBox

# Открытый .alm: сырые байты + смещение tiles-секции для обратной записи
var _alm_raw: PackedByteArray = PackedByteArray()
var _alm_tiles_off: int = -1
var _alm_path := ""
var _alm_original_tiles: PackedInt32Array = PackedInt32Array()

# Инструменты: 0 = тайлы (кисть), 1 = структуры (здания), 2 = НПЦ (юниты)
var tool_mode := 0
var tool_buttons := {}           # режим -> Button
var structure_id := -1           # выбранный тип структуры (StructureDB id)
var npc_set := ""                # выбранный набор юнита (units_db)

func _ready() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(1, 1)
	add_child(camera)
	camera.make_current()

	map = CustomMap.new()
	add_child(map)
	map.new_map(64, 64)
	_build_ui()
	_load_global_sets()
	_update_palette_icons()
	_build_texture_strip()
	_center_camera()

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	# Верхняя панель
	var top := Panel.new()
	top.offset_left = 0; top.offset_top = 0; top.offset_right = 1180; top.offset_bottom = 44
	ui.add_child(top)

	var x := 8.0
	x = _add_top_button(top, x, "Новая", _on_new)
	x = _add_top_button(top, x, "Сохранить", _on_save)
	x = _add_top_button(top, x, "Загрузить", _on_load)
	x = _add_top_button(top, x, "Открыть .alm…", _on_open_alm)
	x = _add_top_button(top, x, "Сохранить .alm", _on_save_alm)
	x = _add_top_button(top, x, "Настройки…", _on_settings)
	x = _add_top_button(top, x, "Предметы…", _on_catalog)
	x = _add_top_button(top, x, "Назад в игру (F9)", _on_back)

	# Размер новой карты
	var wl := Label.new()
	wl.text = "Ш:"; wl.position = Vector2(x, 12)
	top.add_child(wl)
	map_w_spin = SpinBox.new()
	map_w_spin.min_value = 16; map_w_spin.max_value = 256; map_w_spin.value = 64; map_w_spin.step = 8
	map_w_spin.position = Vector2(x + 22, 8); map_w_spin.size = Vector2(72, 28)
	top.add_child(map_w_spin)
	var hl := Label.new()
	hl.text = "В:"; hl.position = Vector2(x + 100, 12)
	top.add_child(hl)
	map_h_spin = SpinBox.new()
	map_h_spin.min_value = 16; map_h_spin.max_value = 256; map_h_spin.value = 64; map_h_spin.step = 8
	map_h_spin.position = Vector2(x + 122, 8); map_h_spin.size = Vector2(72, 28)
	top.add_child(map_h_spin)

	status_label = Label.new()
	status_label.position = Vector2(x + 210, 12)
	top.add_child(status_label)

	# Палитра слева
	var pal := Panel.new()
	pal.offset_left = 8; pal.offset_top = 52; pal.offset_right = 186; pal.offset_bottom = 720
	ui.add_child(pal)

	var py := 8.0
	for t in range(8):
		var b := Button.new()
		b.text = CustomMap.TYPE_NAMES[t]
		b.toggle_mode = true
		b.position = Vector2(8, py)
		b.size = Vector2(150, 26)
		b.pressed.connect(func(id=t): _select_brush(id))
		pal.add_child(b)
		palette_buttons[t] = b
		py += 32

	var erase := Button.new()
	erase.text = "Ластик"
	erase.toggle_mode = true
	erase.position = Vector2(8, py)
	erase.size = Vector2(150, 26)
	erase.pressed.connect(func(): _select_brush(-1))
	pal.add_child(erase)
	palette_buttons[-1] = erase
	py += 32

	var fill := Button.new()
	fill.text = "Залить область"
	fill.toggle_mode = true
	fill.position = Vector2(8, py)
	fill.size = Vector2(150, 26)
	fill.pressed.connect(func(): _fill_mode = not _fill_mode)
	pal.add_child(fill)
	fill_btn = fill
	py += 32

	var st_btn := Button.new()
	st_btn.text = "Структуры"
	st_btn.toggle_mode = true
	st_btn.position = Vector2(8, py)
	st_btn.size = Vector2(150, 26)
	st_btn.pressed.connect(func(): _select_tool(1))
	pal.add_child(st_btn)
	tool_buttons[1] = st_btn
	py += 32

	var npc_btn := Button.new()
	npc_btn.text = "НПЦ"
	npc_btn.toggle_mode = true
	npc_btn.position = Vector2(8, py)
	npc_btn.size = Vector2(150, 26)
	npc_btn.pressed.connect(func(): _select_tool(2))
	pal.add_child(npc_btn)
	tool_buttons[2] = npc_btn
	py += 32

	var tlabel := Label.new()
	tlabel.text = "Текстура:"
	tlabel.position = Vector2(8, py)
	pal.add_child(tlabel)
	py += 22

	# Полоса выбора текстуры из набора категории
	var strip_scroll := ScrollContainer.new()
	strip_scroll.position = Vector2(8, py)
	strip_scroll.size = Vector2(170, 218)
	pal.add_child(strip_scroll)

	tex_strip_grid = GridContainer.new()
	tex_strip_grid.columns = 3
	tex_strip_grid.add_theme_constant_override("h_separation", 4)
	tex_strip_grid.add_theme_constant_override("v_separation", 4)
	strip_scroll.add_child(tex_strip_grid)

	# Размер кисти
	var blabel := Label.new()
	blabel.text = "Кисть:"
	blabel.position = Vector2(8, 486)
	pal.add_child(blabel)
	brush_size_buttons.clear()
	for i in range(3):
		var sb := Button.new()
		sb.text = str(i + 1)
		sb.toggle_mode = true
		sb.button_pressed = (i == 0)
		sb.position = Vector2(8 + i * 28, 508)
		sb.size = Vector2(24, 24)
		sb.pressed.connect(func(s=i+1):
			brush_size = s
			_update_brush_size_buttons())
		pal.add_child(sb)
		brush_size_buttons.append(sb)

func _update_brush_size_buttons() -> void:
	for i in range(brush_size_buttons.size()):
		var b: Button = brush_size_buttons[i]
		b.button_pressed = (i + 1 == brush_size)

func _add_top_button(parent: Control, x: float, text: String, cb: Callable) -> float:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, 6)
	b.size = Vector2(110, 30)
	b.pressed.connect(cb)
	parent.add_child(b)
	return x + 118

func _select_brush(t: int) -> void:
	brush_type = t
	brush_tex_idx = 0
	for k in palette_buttons:
		palette_buttons[k].button_pressed = (k == t)
	_build_texture_strip()

## Переключение инструмента: 0 тайлы, 1 структуры, 2 НПЦ.
func _select_tool(mode: int) -> void:
	tool_mode = mode
	for m in tool_buttons:
		tool_buttons[m].button_pressed = (m == mode)
	if mode == 1:
		_open_structure_picker()
	elif mode == 2:
		_open_npc_picker()

func _open_structure_picker() -> void:
	var pop := PopupPanel.new()
	pop.title = "Структуры"
	pop.size = Vector2i(430, 500)
	pop.position = Vector2i(220, 90)
	add_child(pop)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_top = 28
	pop.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)
	for sid in StructureDB.ids():
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 56)
		b.expand_icon = true
		var tex: Texture2D = StructureDB.preview_texture(sid)
		if tex != null:
			b.icon = tex
		b.tooltip_text = "%d: %s" % [sid, StructureDB.display_name_by_id(sid)]
		b.pressed.connect(func(id=sid, pp=pop):
			structure_id = id
			npc_set = ""
			status_label.text = "Структура: %s" % StructureDB.display_name_by_id(id)
			pp.queue_free())
		grid.add_child(b)
	pop.popup_centered()

func _open_npc_picker() -> void:
	var pop := PopupPanel.new()
	pop.title = "НПЦ (юниты)"
	pop.size = Vector2i(430, 500)
	pop.position = Vector2i(220, 90)
	add_child(pop)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_top = 28
	pop.add_child(sc)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	sc.add_child(vbox)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_npc_section_label("Жители (humans)"))
	vbox.add_child(grid)
	for name in UnitDB.all_names("humans/"):
		_add_npc_button(grid, name, pop)
	var grid2 := GridContainer.new()
	grid2.columns = 6
	grid2.add_theme_constant_override("h_separation", 4)
	grid2.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_npc_section_label("Монстры (monsters)"))
	vbox.add_child(grid2)
	for name in UnitDB.all_names("monsters/"):
		_add_npc_button(grid2, name, pop)
	pop.popup_centered()

func _npc_section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l

func _add_npc_button(grid: GridContainer, name: String, pop: PopupPanel) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(62, 56)
	b.expand_icon = true
	var tex: Texture2D = UnitDB.preview_frame(name)
	if tex != null:
		b.icon = tex
	b.tooltip_text = name
	b.pressed.connect(func(set_name=name, pp=pop):
		npc_set = set_name
		structure_id = -1
		status_label.text = "НПЦ: %s" % set_name
		pp.queue_free())
	grid.add_child(b)

func _select_tex(idx: int) -> void:
	brush_tex_idx = idx
	for i in range(tex_strip_buttons.size()):
		var b: Button = tex_strip_buttons[i]
		b.button_pressed = (i == idx)

func _build_texture_strip() -> void:
	if tex_strip_grid == null:
		return
	for child in tex_strip_grid.get_children():
		child.queue_free()
	tex_strip_buttons.clear()
	var set: Array = map.texture_sets.get(brush_type, [])
	for i in range(set.size()):
		var spec: Dictionary = set[i]
		var img: Image = map._load_spec_image(spec)
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.expand_icon = true
		b.icon = ImageTexture.create_from_image(img)
		b.toggle_mode = true
		b.button_pressed = (i == brush_tex_idx)
		b.pressed.connect(func(idx=i): _select_tex(idx))
		tex_strip_grid.add_child(b)
		tex_strip_buttons.append(b)

func _update_palette_icons() -> void:
	# Иконки палитры из текущих текстур заливки
	for t in range(8):
		var spec: Dictionary = map.text_spec.get(t, {})
		var img := map._load_spec_image(spec)
		if img:
			var b: Button = palette_buttons[t]
			b.icon = ImageTexture.create_from_image(img)
			b.expand_icon = true

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(settings_panel):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_Z and event.ctrl_pressed:
		_undo()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if camera:
				camera.zoom = camera.zoom * 1.15
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if camera:
				camera.zoom = camera.zoom / 1.15
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _point_over_ui(event.position):
				return
			var cell := _mouse_to_cell()
			if cell.x >= 0 and cell.y >= 0:
				if tool_mode == 1 and structure_id > 0:
					_place_structure(cell)
				elif tool_mode == 2 and npc_set != "":
					_place_npc(cell)
				elif _fill_mode and brush_type >= 0:
					_flood_fill(cell, brush_type, brush_tex_idx)
					fill_btn.button_pressed = false
					_fill_mode = false
				elif brush_type >= 0:
					_paint(cell, brush_type, brush_size)
				else:
					_paint(cell, -1, brush_size)

func _point_over_ui(screen_pos: Vector2) -> bool:
	if ui == null:
		return false
	for child in ui.get_children():
		if child is Control:
			var r := Rect2(child.global_position, child.size)
			if r.has_point(screen_pos):
				return true
	return false

func _mouse_to_cell() -> Vector2i:
	var world := get_global_mouse_position()
	world.x -= map.position.x
	world.y -= map.position.y
	return Vector2i(int(world.x) / TILE, int(world.y) / TILE)

func _paint(center: Vector2i, type_id: int, size: int) -> void:
	var r := size - 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := center + Vector2i(dx, dy)
			if type_id == -1:
				_erase_entity(cell)
			_set_cell_undo(cell, type_id)

## Поставить структуру (здание) с якорем-клеткой (левый-нижний угол корпуса).
func _place_structure(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	map.structures.append({"x": cell.x, "y": cell.y, "type_id": structure_id})
	map._rebuild_entities()
	status_label.text = "Структура %s на %d,%d" % [StructureDB.display_name_by_id(structure_id), cell.x, cell.y]

## Поставить НПЦ (жителя/монстра) на клетку.
func _place_npc(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	map.npcs.append({"x": cell.x, "y": cell.y, "set": npc_set})
	map._rebuild_entities()
	status_label.text = "НПЦ %s на %d,%d" % [npc_set, cell.x, cell.y]

## Ластик также снимает структуру/НПЦ, якорь которых — на этой клетке.
func _erase_entity(cell: Vector2i) -> void:
	var changed := false
	for i in range(map.structures.size() - 1, -1, -1):
		var rec: Dictionary = map.structures[i]
		if int(rec.get("x", -1)) == cell.x and int(rec.get("y", -1)) == cell.y:
			map.structures.remove_at(i)
			changed = true
	for i in range(map.npcs.size() - 1, -1, -1):
		var rec: Dictionary = map.npcs[i]
		if int(rec.get("x", -1)) == cell.x and int(rec.get("y", -1)) == cell.y:
			map.npcs.remove_at(i)
			changed = true
	if changed:
		map._rebuild_entities()

## Записать изменение в undo-стек и применить.
func _set_cell_undo(cell: Vector2i, type_id: int) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	var i := cell.y * map.map_width + cell.x
	var old_t := map.tiles[i]
	var old_tex := map.tex_ids[i]
	var old_under := map.under_tiles[i]
	if old_t == type_id and old_tex == (brush_tex_idx if type_id >= 0 else -1):
		return
	_undo_stack.append({"cell": cell, "type": old_t, "tex": old_tex, "under": old_under})
	if _undo_stack.size() > 2000:
		_undo_stack.pop_front()
	if type_id >= 0:
		map.set_tile(cell, type_id, brush_tex_idx)
	else:
		map.set_tile(cell, -1)

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	var cell: Vector2i = entry["cell"]
	var t: int = entry["type"]
	var tex: int = entry["tex"]
	var under: int = entry.get("under", -1)
	var i := cell.y * map.map_width + cell.x
	map.tiles[i] = t
	map.tex_ids[i] = tex
	map.under_tiles[i] = under
	map._refresh_cell(cell)
	status_label.text = "Отменено (%d)" % _undo_stack.size()

## Заливка области: все соседние клетки того же типа -> выбранный тип.
func _flood_fill(start: Vector2i, new_type: int, new_tex: int) -> void:
	if start.x < 0 or start.y < 0 or start.x >= map.map_width or start.y >= map.map_height:
		return
	var old_type := map.tile_id_at(start)
	if old_type == new_type:
		return
	var stack: Array = [start]
	var visited := {}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		# Пустота (-1) считается "той же" за границами карты — без этой проверки
		# заливка пустой области уходит в бесконечность за края карты.
		if c.x < 0 or c.y < 0 or c.x >= map.map_width or c.y >= map.map_height:
			continue
		if visited.has(c):
			continue
		visited[c] = true
		if map.tile_id_at(c) != old_type:
			continue
		_set_cell_undo(c, new_type)
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))
	status_label.text = "Залито!"

func _center_camera() -> void:
	camera.position = Vector2(map.map_width * TILE / 2, map.map_height * TILE / 2)

func _on_new() -> void:
	var w := int(map_w_spin.value)
	var h := int(map_h_spin.value)
	map.new_map(w, h)
	_load_global_sets()  # вернуть наборы текстур из палитры (не дефолт)
	brush_tex_idx = 0
	_update_palette_icons()
	_build_texture_strip()
	_center_camera()
	status_label.text = "Новая карта %dx%d" % [w, h]

func _on_save() -> void:
	if map.save_map(SAVE_PATH):
		status_label.text = "Сохранено: " + SAVE_PATH
	else:
		status_label.text = "ОШИБКА сохранения!"

func _on_load() -> void:
	if map.load_map(SAVE_PATH):
		brush_tex_idx = 0
		_update_palette_icons()
		_build_texture_strip()
		status_label.text = "Загружено: " + SAVE_PATH
	else:
		status_label.text = "Файл не найден: " + SAVE_PATH

## Открыть .alm с диска (FileDialog).
func _on_open_alm() -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["*.alm ; Карта Allods 2 (.alm)", "*.json ; Карта редактора (.json)"])
	fd.file_selected.connect(_open_alm_file)
	add_child(fd)
	fd.popup_centered(Vector2i(700, 500))

func _open_alm_file(path: String) -> void:
	var data := AlmLoader.load_map(path)
	if data.is_empty():
		status_label.text = "Не удалось открыть .alm: " + path
		return
	map.import_alm(data)
	_alm_raw = data["raw"]
	_alm_tiles_off = int(data["tiles_off"])
	_alm_path = path
	_alm_original_tiles = data["tiles"].duplicate()
	_remember_last_alm(path)
	_restore_spawn_anchor()
	_populate_entities_from_alm(data)
	map_w_spin.value = map.map_width
	map_h_spin.value = map.map_height
	brush_tex_idx = 0
	_update_palette_icons()
	_build_texture_strip()
	_center_camera()
	status_label.text = "Открыт .alm: %s (%dx%d)" % [path.get_file(), map.map_width, map.map_height]

## Восстановить спавн из файла-якоря "<имя>.spawn.json" (если есть): ставим
## клетке тип 7 (запоминает землю под собой), чтобы точка была видна и сохранялась.
func _restore_spawn_anchor() -> void:
	if _alm_path.is_empty():
		return
	var anchor_path := _alm_path.get_basename() + ".spawn.json"
	if not FileAccess.file_exists(anchor_path):
		return
	var f := FileAccess.open(anchor_path, FileAccess.READ)
	if f == null:
		return
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is not Dictionary:
		return
	var cell := Vector2i(int(json.get("x", -1)), int(json.get("y", -1)))
	if cell.x < 0 or cell.y < 0:
		return
	if cell.x < map.map_width and cell.y < map.map_height:
		map.set_tile(cell, 7)

## Сохранить текущую карту обратно в .alm (перезаписать только секцию tiles) +
## якорь спавна в файле "<имя>.spawn.json" рядом с картой.
func _on_save_alm() -> void:
	if _alm_tiles_off < 0 or _alm_path.is_empty():
		status_label.text = "Сначала откройте .alm"
		return
	var new_tiles := map.export_alm_tiles(_alm_original_tiles)
	if AlmLoader.write_tiles(_alm_path, _alm_raw, _alm_tiles_off, new_tiles):
		_alm_original_tiles = new_tiles.duplicate()
		_save_spawn_anchor()
		_write_entity_sidecars()
		status_label.text = "Сохранено в .alm: " + _alm_path
	else:
		status_label.text = "ОШИБКА записи .alm!"

## Структуры/НПЦ после открытия .alm: если есть sidecar-файлы (полное состояние,
## писал редактор) — берём их; иначе секции 4/6 самого .alm.
func _populate_entities_from_alm(data: Dictionary) -> void:
	var base := _alm_path.get_basename()
	var s: Variant = _read_sidecar_file(base + ".structures.json")
	if s is Array:
		map.structures = _copy_recs(s)
	else:
		map.structures = _structures_from_alm(data)
	var u: Variant = _read_sidecar_file(base + ".npcs.json")
	if u is Array:
		map.npcs = _copy_recs(u)
	else:
		map.npcs = _npcs_from_alm(data)
	map._rebuild_entities()

func _structures_from_alm(data: Dictionary) -> Array:
	var out: Array = []
	for rec in data.get("structures", []):
		out.append({"x": rec.get("x", 0), "y": rec.get("y", 0), "type_id": rec.get("type_id", 0)})
	return out

func _npcs_from_alm(data: Dictionary) -> Array:
	var out: Array = []
	for rec in data.get("units", []):
		var set_name := UnitDB.set_name_for_id(int(rec.get("type_id", 0)))
		if set_name != "":
			out.append({"x": rec.get("x", 0), "y": rec.get("y", 0), "set": set_name})
	return out

func _copy_recs(src: Array) -> Array:
	var out: Array = []
	for r in src:
		if r is Dictionary:
			out.append(r.duplicate(true))
	return out

## Прочитать sidecar: null — файла нет, иначе массив записей ({"structures"/"npcs"}).
func _read_sidecar_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		if parsed.has("structures") and parsed["structures"] is Array:
			return parsed["structures"]
		if parsed.has("npcs") and parsed["npcs"] is Array:
			return parsed["npcs"]
		return []
	if parsed is Array:
		return parsed
	return null

## Сохранить полное состояние структур/НПЦ рядом с .alm (сам .alm не трогаем).
func _write_entity_sidecars() -> void:
	if _alm_path.is_empty():
		return
	var base := _alm_path.get_basename()
	var fs := FileAccess.open(base + ".structures.json", FileAccess.WRITE)
	if fs != null:
		fs.store_string(JSON.stringify({"structures": map.structures}))
		fs.close()
	var fn := FileAccess.open(base + ".npcs.json", FileAccess.WRITE)
	if fn != null:
		fn.store_string(JSON.stringify({"npcs": map.npcs}))
		fn.close()

## Запомнить, какую карту открыл пользователь: игра (main.tscn) грузит её при F9.
func _remember_last_alm(path: String) -> void:
	var f := FileAccess.open("user://last_alm_path.txt", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(path)
	f.close()

## Спавн (тип 7) -> файл-якорь "<имя>.spawn.json" рядом с .alm (его читает AlmMap).
func _save_spawn_anchor() -> void:
	if _alm_path.is_empty():
		return
	var cell := map.spawn_cell
	if cell.x < 0:
		return
	var anchor_path := _alm_path.get_basename() + ".spawn.json"
	var f := FileAccess.open(anchor_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"x": cell.x, "y": cell.y}))
	f.close()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

## --- Настройки текстур ---

func _on_settings() -> void:
	if is_instance_valid(settings_panel):
		return
	settings_panel = TextureSettingsPanel.new()
	settings_panel.setup(map)
	add_child(settings_panel)
	settings_panel.applied.connect(_on_settings_applied)
	settings_panel.closed.connect(_on_settings_closed)

func _on_settings_applied() -> void:
	# Панель уже применила наборы к карте и сохранила в user://
	brush_tex_idx = 0
	_update_palette_icons()
	_build_texture_strip()
	status_label.text = "Настройки текстур сохранены"

func _on_settings_closed() -> void:
	settings_panel = null

## --- Каталог предметов инвентаря ---

func _on_catalog() -> void:
	if is_instance_valid(catalog_panel):
		return
	catalog_panel = InventoryCatalogPanel.new()
	catalog_panel.setup()
	add_child(catalog_panel)
	catalog_panel.applied.connect(_on_catalog_applied)
	catalog_panel.closed.connect(_on_catalog_closed)

func _on_catalog_applied() -> void:
	status_label.text = "Каталог предметов сохранён"

func _on_catalog_closed() -> void:
	catalog_panel = null

## Глобальные наборы текстур (палитра редактора) — переживают перезапуск.
func _load_global_sets() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Dictionary and json.has("texture_sets"):
		map.set_texture_sets(json["texture_sets"])

func _process(_delta) -> void:
	if camera:
		var speed: float = 300.0 * _delta * (1.0 / camera.zoom.x)
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1
		if dir != Vector2.ZERO:
			camera.position += dir.normalized() * speed
	if map:
		var tex_info := "-"
		var set: Array = map.texture_sets.get(brush_type, [])
		if brush_type >= 0 and set.size() > 0:
			tex_info = "%d/%d" % [brush_tex_idx + 1, set.size()]
		status_label.text = "Клетка: %s Тип: %s Текстура: %s   (WASD - камера, колесо - зум)" % [
			_mouse_to_cell(), _type_name(brush_type), tex_info]

func _type_name(t: int) -> String:
	if t < 0:
		return "ластик"
	return CustomMap.TYPE_NAMES[t]