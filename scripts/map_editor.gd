extends Node2D
## Редактор карт Allods Home. Кисть по сетке, палитра типов terrain.
## У каждого типа — набор текстур (настраивается в «Настройки…»), кисть красит
## выбранной текстурой из набора. Сохранение: JSON 1:1 (клетка -> тип + индекс
## текстуры внутри набора).

const SAVE_PATH := "res://assets/maps/my_map.json"
const SETTINGS_PATH := "user://map_editor_palette.json"
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
var _fill_mode := false
var fill_btn: Button
var _undo_stack: Array = []
var map_w_spin: SpinBox
var map_h_spin: SpinBox

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
	top.offset_left = 0; top.offset_top = 0; top.offset_right = 900; top.offset_bottom = 44
	ui.add_child(top)

	var x := 8.0
	x = _add_top_button(top, x, "Новая", _on_new)
	x = _add_top_button(top, x, "Сохранить", _on_save)
	x = _add_top_button(top, x, "Загрузить", _on_load)
	x = _add_top_button(top, x, "Настройки…", _on_settings)
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
		var img: Image = map._load_tile_region(
			int(spec.get("file", 1)), int(spec.get("variant", 0)), int(spec.get("row", 0)))
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
	for t in range(5):
		var spec: Dictionary = map.text_spec.get(t, {})
		var img := map._load_tile_region(
			int(spec.get("file", 1)), int(spec.get("variant", 0)), int(spec.get("row", 0)))
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
				if _fill_mode and brush_type >= 0:
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
			_set_cell_undo(cell, type_id)

## Записать изменение в undo-стек и применить.
func _set_cell_undo(cell: Vector2i, type_id: int) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	var i := cell.y * map.map_width + cell.x
	var old_t := map.tiles[i]
	var old_tex := map.tex_ids[i]
	if old_t == type_id and old_tex == (brush_tex_idx if type_id >= 0 else -1):
		return
	_undo_stack.append({"cell": cell, "type": old_t, "tex": old_tex})
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
	map.set_tile(cell, t, tex)
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