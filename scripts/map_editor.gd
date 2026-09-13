extends Node2D
## Редактор карт Allods Home. Кисть по сетке, палитра типов terrain.
## Сохранение: JSON 1:1 (клетка -> тип). Игра читает как есть.

const SAVE_PATH := "res://assets/maps/my_map.json"
const TILE := 32

var map: CustomMap
var brush_type := 0            # 0-4 тип, -1 ластик
var brush_size := 1
var camera: Camera2D
var ui: CanvasLayer
var palette_buttons := {}      # тип -> Button
var status_label: Label

func _ready() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(1, 1)
	add_child(camera)
	camera.make_current()

	map = CustomMap.new()
	add_child(map)
	map.new_map(64, 64)
	_build_ui()
	_update_palette_icons()
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
	x = _add_top_button(top, x, "Назад в игру (F9)", _on_back)

	status_label = Label.new()
	status_label.position = Vector2(x + 20, 12)
	top.add_child(status_label)

	# Палитра слева
	var pal := Panel.new()
	pal.offset_left = 8; pal.offset_top = 52; pal.offset_right = 120; pal.offset_bottom = 320
	ui.add_child(pal)

	var py := 8.0
	for t in range(5):
		var b := Button.new()
		b.text = CustomMap.TYPE_NAMES[t]
		b.toggle_mode = true
		b.position = Vector2(8, py)
		b.size = Vector2(92, 42)
		b.pressed.connect(func(id=t): _select_brush(id))
		pal.add_child(b)
		palette_buttons[t] = b
		py += 50

	var erase := Button.new()
	erase.text = "Ластик"
	erase.toggle_mode = true
	erase.position = Vector2(8, py)
	erase.size = Vector2(92, 30)
	erase.pressed.connect(func(): _select_brush(-1))
	pal.add_child(erase)
	palette_buttons[-1] = erase

	# Размер кисти
	var lbl := Label.new()
	lbl.text = "Кисть:"
	lbl.position = Vector2(8, py + 40)
	pal.add_child(lbl)
	for i in range(3):
		var sb := Button.new()
		sb.text = str(i + 1)
		sb.toggle_mode = true
		sb.position = Vector2(8 + i * 26, py + 62)
		sb.size = Vector2(24, 24)
		sb.pressed.connect(func(s=i+1): brush_size = s)
		pal.add_child(sb)

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
	for k in palette_buttons:
		palette_buttons[k].button_pressed = (k == t)

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
				if brush_type >= 0:
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
			map.set_tile(center + Vector2i(dx, dy), type_id)

func _center_camera() -> void:
	camera.position = Vector2(map.map_width * TILE / 2, map.map_height * TILE / 2)

func _on_new() -> void:
	map.new_map(64, 64)
	status_label.text = "Новая карта 64x64"

func _on_save() -> void:
	if map.save_map(SAVE_PATH):
		status_label.text = "Сохранено: " + SAVE_PATH
	else:
		status_label.text = "ОШИБКА сохранения!"

func _on_load() -> void:
	if map.load_map(SAVE_PATH):
		status_label.text = "Загружено: " + SAVE_PATH
	else:
		status_label.text = "Файл не найден: " + SAVE_PATH

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _process(_delta) -> void:
	if camera:
		var speed := 300.0 * _delta * (1.0 / camera.zoom.x)
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
		status_label.text = "Клетка: %s Тип: %s   (WASD/стрелки - камера, колесо - зум)" % [_mouse_to_cell(), _type_name(brush_type)]

func _type_name(t: int) -> String:
	if t < 0:
		return "ластик"
	return CustomMap.TYPE_NAMES[t]