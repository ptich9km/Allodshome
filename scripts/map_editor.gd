extends Node2D
## Редактор карт Allods Home.
##
## Карта живёт в двух форматах:
##   .alm  — то, что грузит игра (полная запись: info/tiles/heights/obstacles);
##   .json — внутренний формат редактора (для отладки и старых файлов).
##
## Рядом с .alm пишутся sidecar-ы: .spawn.json, .portal.json,
## .structures.json, .npcs.json, .nowalk.json, .allowwalk.json и .meta.json.
## Игра читает их через AlmMap; «Своя игра» показывает список из
## user://maps/custom/ и стартует выбранную карту.

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

# Инструменты: 0 = тайлы (кисть), 1 = структуры (здания), 2 = НПЦ (юниты),
# 3 = выбор/инспектор (по умолчанию — чтобы случайным кликом не испортить карту)
var tool_mode := 3
var tool_buttons := {}           # режим -> Button
var structure_id := -1           # выбранный тип структуры (StructureDB id)
var npc_set := ""                # выбранный набор юнита (units_db)
var prop_name := ""              # выбранный объект-проп (map-objects)
var portal_target := ""          # "" — по цепочке зон, иначе id сектора
var _inspect_msg := ""           # сообщение инспектора (держится до смены инструмента)

# Паспорт карты (пишется в <имя>.meta.json рядом с .alm)
var _meta_title := ""
var _zone_opt: OptionButton
var _zone := "start"

# Подсветка футпринта структуры под курсором (красная — нельзя ставить)
var _footprint: Line2D


func _ready() -> void:
	# Тематический анимированный курсор вместо системной стрелки.
	add_child(load("res://scripts/cursor_layer.gd").new())
	camera = Camera2D.new()
	camera.zoom = Vector2(1, 1)
	# Камера редактора двигается в _process (idle): при включённой physics-
	# интерполяции проекта движок печатает WARNING о переопределении режима.
	# Камере редактора интерполяция не нужна — отключаем флаг на узле.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	camera.reset_physics_interpolation()
	add_child(camera)
	camera.make_current()

	map = CustomMap.new()
	add_child(map)
	map.new_map(64, 64)
	# Рамка футпринта здания под курсором: видно, куда встанет 3×3 и
	# пересекается ли с соседним (красная — нельзя).
	_footprint = Line2D.new()
	_footprint.width = 2.0
	_footprint.z_index = 20
	_footprint.visible = false
	map.add_child(_footprint)
	_build_ui()
	_load_global_sets()
	_update_palette_icons()
	_build_texture_strip()
	_center_camera()
	_select_tool(3)   # стартуем с инструментом «Выбор» (нельзя случайно испортить)

	# Автооткрытие карты из аргумента запуска:
	# godot --path . res://scenes/map_editor.tscn -- --open-alm=res://assets/maps/gen/gen_smart_01.alm
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--open-alm="):
			var p := a.trim_prefix("--open-alm=")
			if FileAccess.file_exists(p):
				_open_alm_file(p)
			break

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	# Единая тема игры: до этого панели редактора рисовались дефолтной темой
	# Godot — отсюда «странные» плоские кнопки без наведения.
	var theme := UiKit.base_theme()

	# Верхняя панель: контейнеры вместо пиксельных координат.
	var top := Panel.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 42
	top.theme = theme
	ui.add_child(top)
	var tm := MarginContainer.new()
	tm.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.set_margins(tm, 6, 4, 6, 4)
	top.add_child(tm)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	tm.add_child(top_row)

	_add_top_button(top_row, "Новая", _on_new)
	_add_top_button(top_row, "Открыть…", _on_open_map)
	_add_top_button(top_row, "Сохранить .alm", _on_save_alm)
	_add_top_button(top_row, "Играть", _on_play)
	_add_top_button(top_row, "Проверить", _on_validate)
	_add_top_button(top_row, "Настройки…", _on_settings)
	_add_top_button(top_row, "Назад (F9)", _on_back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	# Размер новой карты и зона
	var wl := Label.new()
	wl.text = "Ш:"
	wl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(wl)
	map_w_spin = SpinBox.new()
	map_w_spin.min_value = 16; map_w_spin.max_value = 256; map_w_spin.value = 64; map_w_spin.step = 8
	map_w_spin.custom_minimum_size = Vector2(88, 30)
	top_row.add_child(map_w_spin)

	var hl := Label.new()
	hl.text = "В:"
	hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(hl)
	map_h_spin = SpinBox.new()
	map_h_spin.min_value = 16; map_h_spin.max_value = 256; map_h_spin.value = 64; map_h_spin.step = 8
	map_h_spin.custom_minimum_size = Vector2(88, 30)
	top_row.add_child(map_h_spin)

	var zl := Label.new()
	zl.text = "Зона:"
	zl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(zl)
	_zone_opt = OptionButton.new()
	_zone_opt.custom_minimum_size = Vector2(170, 30)
	for i in range(StartSetup.ZONES.size()):
		_zone_opt.add_item(StartSetup.zone_label(str(StartSetup.ZONES[i])), i)
	_zone_opt.item_selected.connect(func(i): _zone = str(StartSetup.ZONES[i]))
	top_row.add_child(_zone_opt)

	# Нижняя строка статуса (не перекрывает клики по карте).
	var bottom := Panel.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -26
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.theme = theme
	ui.add_child(bottom)
	status_label = Label.new()
	status_label.position = Vector2(10, 3)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(status_label)

	# Палитра слева (до нижней строки статуса). Внутри ScrollContainer:
	# на 1280×600 кнопок и полосы текстур больше, чем высоты панели.
	var pal := Panel.new()
	pal.offset_left = 8; pal.offset_top = 48; pal.offset_right = 208
	pal.anchor_bottom = 1.0
	pal.offset_bottom = -30
	pal.theme = theme
	ui.add_child(pal)

	var pal_scroll := ScrollContainer.new()
	pal_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	pal_scroll.offset_left = 2; pal_scroll.offset_top = 2
	pal_scroll.offset_right = -2; pal_scroll.offset_bottom = -2
	pal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pal.add_child(pal_scroll)

	var pal_box := Control.new()
	pal_box.custom_minimum_size = Vector2(192, 700)
	pal_scroll.add_child(pal_box)

	var py := 8.0
	var step := 26.0
	for t in range(9):
		var b := Button.new()
		b.text = CustomMap.TYPE_NAMES[t]
		b.toggle_mode = true
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.position = Vector2(8, py)
		b.size = Vector2(176, 24)
		b.pressed.connect(func(id=t): _select_brush(id))
		pal_box.add_child(b)
		palette_buttons[t] = b
		py += step

	var erase := _palette_button(pal_box, "Ластик", py, func(): _select_brush(-1), true)
	palette_buttons[-1] = erase
	py += step

	fill_btn = _palette_button(pal_box, "Залить", py,
		func(): _fill_mode = not _fill_mode, true)
	fill_btn.tooltip_text = "Залить область"
	py += step

	py = _tool_button(pal_box, py, 1, "Структуры")
	py = _tool_button(pal_box, py, 6, "Пропы")
	py = _tool_button(pal_box, py, 2, "НПЦ")
	py = _tool_button(pal_box, py, 7, "Спавн")
	py = _tool_button(pal_box, py, 8, "Портал")
	py = _tool_button(pal_box, py, 3, "Выбор")
	py = _tool_button(pal_box, py, 4, "Запрет")
	py = _tool_button(pal_box, py, 5, "Проход")
	tool_buttons[6].tooltip_text = "Пропы: деревья, камни, бочки"
	tool_buttons[4].tooltip_text = "Нельзя пройти"
	tool_buttons[5].tooltip_text = "Разрешить проход"

	var tlabel := Label.new()
	tlabel.text = "Текстура:"
	tlabel.position = Vector2(8, py)
	pal_box.add_child(tlabel)
	py += 20

	# Полоса выбора текстуры из набора категории
	var strip_scroll := ScrollContainer.new()
	strip_scroll.position = Vector2(8, py)
	strip_scroll.size = Vector2(176, 120)
	pal_box.add_child(strip_scroll)

	tex_strip_grid = GridContainer.new()
	tex_strip_grid.columns = 3
	tex_strip_grid.add_theme_constant_override("h_separation", 4)
	tex_strip_grid.add_theme_constant_override("v_separation", 4)
	strip_scroll.add_child(tex_strip_grid)
	py += 126

	# Размер кисти
	var blabel := Label.new()
	blabel.text = "Кисть:"
	blabel.position = Vector2(8, py)
	pal_box.add_child(blabel)
	brush_size_buttons.clear()
	for i in range(3):
		var sb := Button.new()
		sb.text = str(i + 1)
		sb.toggle_mode = true
		sb.button_pressed = (i == 0)
		sb.position = Vector2(8 + i * 28, py + 20)
		sb.size = Vector2(24, 24)
		sb.pressed.connect(func(s=i+1):
			brush_size = s
			_update_brush_size_buttons())
		pal_box.add_child(sb)
		brush_size_buttons.append(sb)

func _palette_button(parent: Control, text: String, y: float, cb: Callable,
		toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.position = Vector2(8, y)
	b.size = Vector2(176, 24)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _tool_button(parent: Control, y: float, mode: int, text: String) -> float:
	var b := _palette_button(parent, text, y, func(): _select_tool(mode), true)
	tool_buttons[mode] = b
	return y + 26.0

func _update_brush_size_buttons() -> void:
	for i in range(brush_size_buttons.size()):
		var b: Button = brush_size_buttons[i]
		b.button_pressed = (i + 1 == brush_size)

func _add_top_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(104, 30)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _select_brush(t: int) -> void:
	brush_type = t
	brush_tex_idx = 0
	_inspect_msg = ""
	for k in palette_buttons:
		palette_buttons[k].button_pressed = (k == t)
	_build_texture_strip()

## Переключение инструмента: 0 тайлы, 1 структуры, 2 НПЦ, 3 выбор,
## 4 «Нельзя пройти», 5 «Разрешить проход», 6 пропы, 7 спавн, 8 порталы.
func _select_tool(mode: int) -> void:
	tool_mode = mode
	_inspect_msg = ""
	for m in tool_buttons:
		tool_buttons[m].button_pressed = (m == mode)
	for k in palette_buttons:
		palette_buttons[k].button_pressed = false
	fill_btn.button_pressed = false
	_fill_mode = false
	structure_id = -1
	npc_set = ""
	prop_name = ""
	match mode:
		1:
			_open_structure_picker()
		2:
			_open_npc_picker()
		6:
			_open_prop_picker()
		8:
			_open_portal_picker()

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
	_add_npc_section(vbox, pop, "Городские жители", "city_")
	_add_npc_section(vbox, pop, "Серые (монстры)", "monsters/")
	_add_npc_section(vbox, pop, "Герои", "hero/")
	var rest: Array = []
	for name in UnitDB.all_names(""):
		var sn := str(name)
		if sn.begins_with("city_") or sn.begins_with("monsters/") or sn.begins_with("hero/"):
			continue
		rest.append(sn)
	_add_npc_grid(vbox, pop, "Прочие наборы", rest)
	pop.popup_centered()

## Секция пикера НПЦ: заголовок + сетка кнопок с превью.
func _add_npc_section(parent: VBoxContainer, pop: PopupPanel, title: String, prefix: String) -> void:
	_add_npc_grid(parent, pop, title, UnitDB.all_names(prefix))

func _add_npc_grid(parent: VBoxContainer, pop: PopupPanel, title: String, names: Array) -> void:
	if names.is_empty():
		return
	parent.add_child(_npc_section_label(title))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for name in names:
		_add_npc_button(grid, str(name), pop)

## Пикер пропов: деревья/камни/бочки из map-objects. Проп ставится типом 7,
## но, в отличие от прежнего поведения, НЕ двигает точку спавна героя.
func _open_prop_picker() -> void:
	var pop := PopupPanel.new()
	pop.title = "Пропы (map-objects)"
	pop.size = Vector2i(470, 520)
	pop.position = Vector2i(220, 80)
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
	for raw in ObjectDB.all_names():
		var name := str(raw)
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.expand_icon = true
		var path := ObjectDB.frame_path(name, 1)
		if ResourceLoader.exists(path):
			b.icon = load(path)
		b.tooltip_text = name
		b.pressed.connect(func(obj=name, pp=pop):
			prop_name = obj
			structure_id = -1
			npc_set = ""
			status_label.text = "Проп: %s" % obj
			pp.queue_free())
		grid.add_child(b)
	pop.popup_centered()

## Пикер цели портала: «по цепочке зон» или конкретный сектор мира.
func _open_portal_picker() -> void:
	var pop := PopupPanel.new()
	pop.title = "Портал: куда ведёт"
	pop.size = Vector2i(420, 460)
	pop.position = Vector2i(230, 100)
	add_child(pop)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_top = 28
	pop.add_child(sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	sc.add_child(col)

	var chain := Button.new()
	chain.text = "По цепочке зон (start → mid → hard)"
	chain.tooltip_text = "Портал без адреса: игра сама выберет следующую зону"
	chain.pressed.connect(func():
		portal_target = ""
		status_label.text = "Портал: по цепочке зон"
		pop.queue_free())
	col.add_child(chain)

	var wm: GDScript = load("res://scripts/world/world_map.gd")
	for raw in wm.ids():
		var sector_id := str(raw)
		var info: Dictionary = wm.sector(sector_id)
		var name_key := str(info.get("name_key", ""))
		var title := Loc.t(name_key) if name_key != "" else sector_id
		var b := Button.new()
		b.text = "%s — %s (%s)" % [sector_id, title, StartSetup.zone_label(str(info.get("tier", "")))]
		b.pressed.connect(func(to=sector_id, pp=pop):
			portal_target = to
			status_label.text = "Портал: %s" % to
			pp.queue_free())
		col.add_child(b)
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
	for t in range(9):
		var spec: Dictionary = map.text_spec.get(t, {})
		var img := map._load_spec_image(spec)
		if img:
			var b: Button = palette_buttons[t]
			b.icon = ImageTexture.create_from_image(img)
			b.expand_icon = true

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(settings_panel):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_on_back()
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
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if _point_over_ui(event.position):
				return
			var rc := _mouse_to_cell()
			if rc.x >= 0 and rc.y >= 0:
				_erase_entity(rc)
				status_label.text = "Снято на %d,%d" % [rc.x, rc.y]
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _point_over_ui(event.position):
				return
			var cell := _mouse_to_cell()
			if cell.x >= 0 and cell.y >= 0:
				if tool_mode == 3:
					_inspect(cell)
				elif tool_mode == 4:
					_toggle_nowalk(cell)
				elif tool_mode == 5:
					_toggle_allowwalk(cell)
				elif tool_mode == 1 and structure_id > 0:
					_place_structure(cell)
				elif tool_mode == 2 and npc_set != "":
					_place_npc(cell)
				elif tool_mode == 6 and prop_name != "":
					_place_prop(cell)
				elif tool_mode == 7:
					_place_spawn(cell)
				elif tool_mode == 8:
					_place_portal(cell)
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

## Инструмент «Выбор»: показать в статусе, что стоит на клетке — НПЦ, структура
## или объект-препятствие (по слоям данных, без изменения карты).
func _inspect(cell: Vector2i) -> void:
	if map.has_allowwalk(cell):
		_inspect_msg = "Клетка %d,%d — РАЗРЕШЁН ПРОХОД (поверх препятствия)" % [cell.x, cell.y]
		return
	if map.has_nowalk(cell):
		_inspect_msg = "Клетка %d,%d — ЗАПРЕТ ПРОХОДА (разметка)" % [cell.x, cell.y]
		return
	if cell == map.spawn_cell:
		_inspect_msg = "Клетка %d,%d — СПАВН ГЕРОЯ" % [cell.x, cell.y]
		return
	var pi := map.portal_index_at(cell)
	if pi >= 0:
		var rec_p: Dictionary = map.portals[pi]
		var to := str(rec_p.get("to", ""))
		_inspect_msg = "Портал %d,%d → %s" % [cell.x, cell.y,
			to if to != "" else "следующая зона по цепочке"]
		return
	for rec in map.npcs:
		if int(rec.get("x", -1)) == cell.x and int(rec.get("y", -1)) == cell.y:
			var set_name := str(rec.get("set", ""))
			var o := UnitDB.get_set(set_name)
			var hostile := " (монстр)" if UnitDB.is_hostile(set_name) else ""
			_inspect_msg = "НПЦ: %s — %s%s" % [set_name, o.get("desc", ""), hostile]
			return
	var si := map.structure_index_at(cell)
	if si >= 0:
		var rec_s: Dictionary = map.structures[si]
		var def := StructureDB.get_by_id(int(rec_s.get("type_id", 0)))
		_inspect_msg = "Структура: %s (id %s, %s)" % [def.get("desc", "?"), rec_s.get("type_id"), def.get("folder", "")]
		return
	# Объект-препятствие (дерево/камень) — проп типом 7
	var spec := map.texture_spec_at(cell)
	var obj_name := ObjectDB.object_name_from_spec(spec)
	if obj_name != "" and map.tile_id_at(cell) >= 7:
		_inspect_msg = "Проп: %s" % obj_name
		return
	var t := map.tile_id_at(cell)
	if t >= 0:
		_inspect_msg = "Клетка %d,%d — %s" % [cell.x, cell.y, CustomMap.TYPE_NAMES[t]]
	else:
		_inspect_msg = "Клетка %d,%d — пусто" % [cell.x, cell.y]

## Поставить структуру (здание) с якорем-клеткой (левый-нижний угол корпуса).
## Проверяются границы карты и пересечение футпринтов.
func _place_structure(cell: Vector2i) -> void:
	if structure_id <= 0:
		return
	if map.add_structure(cell, structure_id):
		status_label.text = "Структура %s на %d,%d" % [
			StructureDB.display_name_by_id(structure_id), cell.x, cell.y]
	else:
		status_label.text = "Не влезает: %s (границы или пересечение)" % \
			StructureDB.display_name_by_id(structure_id)

## Поставить НПЦ (жителя/монстра) на клетку.
func _place_npc(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	map.npcs.append({"x": cell.x, "y": cell.y, "set": npc_set})
	map._rebuild_entities()
	status_label.text = "НПЦ %s на %d,%d" % [npc_set, cell.x, cell.y]

## Поставить проп (дерево/камень/бочку) — тип 7, спавн не двигается.
func _place_prop(cell: Vector2i) -> void:
	if prop_name == "":
		return
	map.add_object(cell, prop_name)
	status_label.text = "Проп %s на %d,%d" % [prop_name, cell.x, cell.y]

## Поставить точку спавна героя (одна на карту).
func _place_spawn(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	map.spawn_cell = cell
	map._refresh_spawn()
	status_label.text = "Спавн героя: %d,%d" % [cell.x, cell.y]

## Поставить портал. Цель выбирается в пикере (по цепочке зон или сектор).
func _place_portal(cell: Vector2i) -> void:
	map.add_portal(cell, portal_target, "")
	status_label.text = "Портал на %d,%d → %s" % [cell.x, cell.y,
		portal_target if portal_target != "" else "по цепочке зон"]

## Инструмент «Нельзя пройти»: отметить/снять запрет прохода на клетке.
func _toggle_nowalk(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	var on: bool = map.toggle_nowalk(cell)
	_inspect_msg = "Запрет прохода %d,%d: %s" % [cell.x, cell.y, "ВКЛ" if on else "снят"]
	status_label.text = _inspect_msg

## Инструмент «Разрешить проход»: пустить юнита сквозь препятствие (дерево/камень),
## поверх таблицы цен текстур (WalkTable). Вода/барьер остаются непроходимыми.
func _toggle_allowwalk(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= map.map_width or cell.y >= map.map_height:
		return
	var on: bool = map.toggle_allowwalk(cell)
	_inspect_msg = "Разрешить проход %d,%d: %s" % [cell.x, cell.y, "ВКЛ" if on else "снят"]
	status_label.text = _inspect_msg

## Ластик снимает всё, что стоит на клетке: структуру (по любой клетке
## футпринта), НПЦ, портал, спавн и проп. Тип 7 больше не «двигает» спавн,
## поэтому проп снимается отдельно от точки старта.
func _erase_entity(cell: Vector2i) -> void:
	var changed := false
	if map.spawn_cell == cell:
		map.spawn_cell = Vector2i(-1, -1)
		map._refresh_spawn()
		changed = true
	if map.remove_portal_at(cell):
		changed = true
	if map.remove_structure_at(cell):
		changed = true
	for i in range(map.npcs.size() - 1, -1, -1):
		var rec: Dictionary = map.npcs[i]
		if int(rec.get("x", -1)) == cell.x and int(rec.get("y", -1)) == cell.y:
			map.npcs.remove_at(i)
			changed = true
	var spec := map.texture_spec_at(cell)
	if map.tile_id_at(cell) >= 7 and ObjectDB.object_name_from_spec(spec) != "":
		map.set_tile(cell, -1)
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
	# Новая карта начинается «с нуля»: старого .alm нет, полная запись.
	_alm_path = ""
	_alm_raw = PackedByteArray()
	_alm_tiles_off = -1
	_alm_original_tiles = PackedInt32Array()
	_meta_title = ""
	_load_global_sets()  # вернуть наборы текстур из палитры (не дефолт)
	brush_tex_idx = 0
	_update_palette_icons()
	_build_texture_strip()
	_center_camera()
	_select_tool(3)
	status_label.text = "Новая карта %dx%d — не забудьте спавн, портал и «Сохранить .alm»" % [w, h]

## Открыть .alm (или старый JSON редактора) через диалог.
func _on_open_map() -> void:
	MapMeta.ensure_dir()
	var fd := FileDialog.new()
	fd.use_native_dialog = false   # иначе курсор игры не виден в системном окне
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.current_dir = ProjectSettings.globalize_path(MapMeta.CUSTOM_DIR)
	fd.filters = PackedStringArray([
		"*.alm ; Карта (.alm)", "*.json ; Карта редактора (.json)"])
	fd.file_selected.connect(_open_alm_file)
	add_child(fd)
	fd.popup_centered(Vector2i(760, 520))

func _open_alm_file(path: String) -> void:
	MapMeta.ensure_dir()
	if path.to_lower().ends_with(".json"):
		_open_json_file(path)
		return
	var data := AlmLoader.load_map(path)
	if data.is_empty():
		status_label.text = "Не удалось открыть .alm: " + path
		return
	map.import_alm(data)
	_alm_raw = data["raw"]
	_alm_tiles_off = int(data["tiles_off"])
	_alm_path = path
	_alm_original_tiles = data["tiles"].duplicate()
	var meta := MapMeta.read(path)
	_meta_title = str(meta.get("title", path.get_file().get_basename()))
	_set_zone(str(meta.get("zone", _zone)))
	_remember_last_alm(path)
	_restore_spawn_anchor()
	_populate_entities_from_alm(data)
	_after_load_refresh()
	status_label.text = "Открыт .alm: %s (%dx%d)" % [path.get_file(), map.map_width, map.map_height]

## Старый JSON редактора: только импорт, .alm из него не пишется (пока не
## сохранишь как .alm — путь к .alm остаётся пустым).
func _open_json_file(path: String) -> void:
	if not map.load_map(path):
		status_label.text = "Не удалось открыть JSON: " + path
		return
	_alm_path = ""
	_alm_raw = PackedByteArray()
	_alm_tiles_off = -1
	_alm_original_tiles = PackedInt32Array()
	_meta_title = path.get_file().get_basename()
	_after_load_refresh()
	status_label.text = "Открыт JSON редактора: %s (сохраните как .alm)" % path.get_file()

func _after_load_refresh() -> void:
	map_w_spin.value = map.map_width
	map_h_spin.value = map.map_height
	brush_tex_idx = 0
	_update_palette_icons()
	_build_texture_strip()
	_center_camera()
	_select_tool(3)   # после открытия — «Выбор», чтобы не задеть карту

func _set_zone(zone: String) -> void:
	_zone = zone if StartSetup.ZONES.has(zone) else "start"
	if _zone_opt != null:
		_zone_opt.selected = maxi(0, StartSetup.ZONES.find(_zone))

## Восстановить спавн из файла-якоря "<имя>.spawn.json". Точка спавна —
## отдельное поле карты, а не клетка типа 7: иначе любой проп её «перетаскивал».
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
		map.spawn_cell = cell
		map._refresh_spawn()

## Сохранить: новый файл — диалог, открытый — поверх (быстрый путь для tiles).
func _on_save_alm() -> void:
	if _alm_path == "":
		_save_alm_as(false)
		return
	_write_current_alm()

var _play_after_save := false

func _save_alm_as(play_after: bool) -> void:
	_play_after_save = play_after
	MapMeta.ensure_dir()
	var fd := FileDialog.new()
	fd.use_native_dialog = false   # иначе курсор игры не виден в системном окне
	# Сохраняем только в user://maps/custom: список в блоке «Мир» читает
	# именно эту папку, и сейв копирует карту вместе с sidecar-ами.
	fd.access = FileDialog.ACCESS_USERDATA
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.current_dir = "maps/custom"
	fd.current_file = MapMeta.unused_path(_meta_title if _meta_title != "" else "map").get_file()
	fd.filters = PackedStringArray(["*.alm ; Карта (.alm)"])
	fd.file_selected.connect(func(path):
		_alm_path = _user_path(str(path))
		_meta_title = _alm_path.get_file().get_basename()
		_write_current_alm()
		if _play_after_save:
			_play_after_save = false
			_go_play())
	add_child(fd)
	fd.popup_centered(Vector2i(760, 520))

## FileDialog с ACCESS_USERDATA в разных сборках отдаёт то `user://maps/...`,
## то относительный `maps/...`. Приводим к виду, который понимает FileAccess
## и который потом видит список карт.
func _user_path(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.begins_with("user://") or p.begins_with("res://"):
		return p
	if p.length() >= 2 and p[1] == ":":
		return p            # абсолютный путь Windows
	if p.begins_with("/"):
		return p
	return "user://" + p.trim_prefix("./")

## Полная запись (новая карта) или патч tiles (открытый .alm) + sidecar-ы.
func _write_current_alm() -> void:
	if _alm_path == "":
		return
	var tiles := map.export_alm_tiles(_alm_original_tiles)
	var ok := false
	if _alm_tiles_off >= 0 and not _alm_raw.is_empty():
		ok = AlmLoader.write_tiles(_alm_path, _alm_raw, _alm_tiles_off, tiles)
	else:
		ok = AlmLoader.write_map(_alm_path, map.map_width, map.map_height, tiles,
			map.export_heights(), map.export_alm_obstacles(),
			_meta_title if _meta_title != "" else _alm_path.get_file().get_basename())
	if not ok:
		status_label.text = "ОШИБКА записи .alm!"
		return
	_alm_original_tiles = tiles.duplicate()
	# После полной записи перечитываем файл: дальше патчим только tiles.
	if _alm_tiles_off < 0:
		var data := AlmLoader.load_map(_alm_path)
		if not data.is_empty():
			_alm_raw = data["raw"]
			_alm_tiles_off = int(data["tiles_off"])
			_alm_original_tiles = data["tiles"].duplicate()
	_save_spawn_anchor()
	_write_entity_sidecars()
	MapMeta.write(_alm_path, {
		"title": _meta_title if _meta_title != "" else _alm_path.get_file().get_basename(),
		"zone": _zone,
		"w": map.map_width, "h": map.map_height,
	})
	status_label.text = "Сохранено: " + _alm_path

## «Играть»: сохранить и открыть выбор героя с этой картой.
func _on_play() -> void:
	if _alm_path == "" or not FileAccess.file_exists(_alm_path):
		_save_alm_as(true)
		return
	_write_current_alm()
	_go_play()

func _go_play() -> void:
	Game.start_preset = {
		"mode": "map", "path": _alm_path,
		"seed": StartSetup.random_seed(), "zone": _zone,
	}
	Game.editor_return_scene = "res://scenes/character_select.tscn"
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

## Проверка карты перед запуском: спавн, порталы, структуры, НПЦ.
func _on_validate() -> void:
	var problems := MapValidator.validate(map, _alm_path, _zone)
	_show_validation(problems)

func _show_validation(problems: Array) -> void:
	var pop := PopupPanel.new()
	pop.title = "Проверка карты"
	pop.size = Vector2i(620, 420)
	pop.position = Vector2i(180, 120)
	add_child(pop)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_top = 28
	pop.add_child(sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	sc.add_child(col)
	if problems.is_empty():
		var ok := Label.new()
		ok.text = "Проблем не найдено. Карту можно запускать."
		col.add_child(ok)
	for raw in problems:
		var p: Dictionary = raw
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
		var level := str(p.get("level", "warn"))
		l.text = ("ОШИБКА: " if level == "error" else "внимание: ") + str(p.get("text", ""))
		if level == "error":
			l.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		col.add_child(l)
	pop.popup_centered()

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
	# Порталы (sidecar редактора; в .alm порталов нет — они не влезали в формат)
	map.portals.clear()
	var pr: Variant = _read_sidecar_file(base + ".portal.json")
	if pr is Array:
		map.portals = _copy_recs(pr)
	# Ручная разметка «Нельзя пройти» (sidecar рядом с .alm)
	map.nowalk.clear()
	var nw: Variant = _read_sidecar_file(base + ".nowalk.json")
	if nw is Array:
		for pair in nw:
			if pair is Array and pair.size() >= 2:
				map.nowalk[Vector2i(int(pair[0]), int(pair[1]))] = true
	# Ручная разметка «Разрешить проход» (sidecar рядом с .alm)
	map.allowwalk.clear()
	var aw: Variant = _read_sidecar_file(base + ".allowwalk.json")
	if aw is Array:
		for pair in aw:
			if pair is Array and pair.size() >= 2:
				map.allowwalk[Vector2i(int(pair[0]), int(pair[1]))] = true
	map._rebuild_entities()
	map._refresh_nowalk()
	map._refresh_allowwalk()

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
		if parsed.has("portals") and parsed["portals"] is Array:
			return parsed["portals"]
		if parsed.has("nowalk") and parsed["nowalk"] is Array:
			return parsed["nowalk"]
		if parsed.has("allowwalk") and parsed["allowwalk"] is Array:
			return parsed["allowwalk"]
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
	# Порталы: {"portals": [{x, y, to, dir}]} — формат читает AlmMap.
	var fp := FileAccess.open(base + ".portal.json", FileAccess.WRITE)
	if fp != null:
		fp.store_string(JSON.stringify({"portals": map.portals}))
		fp.close()
	# Разметка «Нельзя пройти»
	var nw_list: Array = []
	for cell in map.nowalk:
		nw_list.append([cell.x, cell.y])
	var fnw := FileAccess.open(base + ".nowalk.json", FileAccess.WRITE)
	if fnw != null:
		fnw.store_string(JSON.stringify({"nowalk": nw_list}))
		fnw.close()
	# Разметка «Разрешить проход»
	var aw_list: Array = []
	for cell in map.allowwalk:
		aw_list.append([cell.x, cell.y])
	var faw := FileAccess.open(base + ".allowwalk.json", FileAccess.WRITE)
	if faw != null:
		faw.store_string(JSON.stringify({"allowwalk": aw_list}))
		faw.close()

## Запомнить, какую карту открыл пользователь (память редактора между сессиями).
## Игра этот файл больше не читает: путь передаётся явно в _on_back через
## Game.request_map_by_path().
func _remember_last_alm(path: String) -> void:
	var f := FileAccess.open("user://last_alm_path.txt", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(path)
	f.close()

## Спавн -> файл-якорь "<имя>.spawn.json" рядом с .alm (его читает AlmMap).
## Нет точки — старый якорь удаляется, иначе игра телепортировала бы героя
## в место, которое редактор уже «убрал».
func _save_spawn_anchor() -> void:
	if _alm_path.is_empty():
		return
	var anchor_path := _alm_path.get_basename() + ".spawn.json"
	var cell := map.spawn_cell
	if cell.x < 0:
		if FileAccess.file_exists(anchor_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(anchor_path))
		return
	var f := FileAccess.open(anchor_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"x": cell.x, "y": cell.y}))
	f.close()

## Куда вернуться: в главное меню, в выбор героя (если редактор открыт оттуда)
## или в игру (F9 из отладки). Раньше всегда уходил в main.tscn, поэтому
## редактор из меню «выкидывал» игрока в мир с чужой картой.
func _on_back() -> void:
	var back := Game.editor_return_scene
	Game.editor_return_scene = ""
	if back == "":
		back = "res://scenes/main_menu.tscn"
	if back.ends_with("character_select.tscn"):
		# Возвращаемся к выбору героя с этой картой в блоке «Мир».
		if _alm_path != "" and FileAccess.file_exists(_alm_path):
			Game.start_preset = {
				"mode": "map", "path": _alm_path,
				"seed": StartSetup.random_seed(), "zone": _zone,
			}
	elif back.ends_with("main.tscn"):
		if _alm_path != "" and FileAccess.file_exists(_alm_path):
			_write_current_alm()
			Game.request_map_by_path(_alm_path)
		else:
			Game.request_map_by_path("")
	get_tree().change_scene_to_file(back)

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
	var path := SETTINGS_PATH
	if not FileAccess.file_exists(path) and FileAccess.file_exists(TextureSettingsPanel.FALLBACK_PATH):
		path = TextureSettingsPanel.FALLBACK_PATH
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
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
	if _inspect_msg != "":
		# Сообщение инспектора держится, пока не выбран другой инструмент
		status_label.text = _inspect_msg
		return
	_update_footprint()
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

## Рамка футпринта под курсором для инструмента «Структуры».
func _update_footprint() -> void:
	if _footprint == null or map == null:
		return
	if tool_mode != 1 or structure_id <= 0:
		_footprint.visible = false
		return
	var def := StructureDB.get_by_id(structure_id)
	if def.is_empty():
		_footprint.visible = false
		return
	var cell := _mouse_to_cell()
	var fw := int(def.get("tile_width", 1))
	var th := int(def.get("tile_height", 1))
	var fh := int(def.get("full_height", th))
	var rect := Rect2i(cell.x, cell.y - (fh - th), fw, fh)
	var ok := rect.position.x >= 0 and rect.position.y >= 0 \
		and rect.end.x <= map.map_width and rect.end.y <= map.map_height
	if ok:
		for other in map.structures:
			if map.structure_rect(other as Dictionary).intersects(rect):
				ok = false
				break
	var x0 := float(rect.position.x * TILE)
	var y0 := float(rect.position.y * TILE)
	var x1 := float(rect.end.x * TILE)
	var y1 := float(rect.end.y * TILE)
	_footprint.points = PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1),
		Vector2(x0, y1), Vector2(x0, y0)])
	_footprint.default_color = Color(0.35, 1.0, 0.45, 0.9) if ok \
		else Color(1.0, 0.35, 0.3, 0.95)
	_footprint.visible = true


