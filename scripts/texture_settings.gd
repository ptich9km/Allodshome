class_name TextureSettingsPanel
extends CanvasLayer
## Окно настроек map editor: для каждой категории (типа terrain) собрать набор
## текстур {file, variant, row} из исходных тайлов. Клик по варианту в сетке —
## добавить/убрать текстуру из набора категории (вариант + выбранный ряд).
## «Сохранить» применяет наборы к карте и пишет палитру в
## res://assets/maps/map_editor_palette.json (файл в git — наборы
## синхронизируются между устройствами и используются игрой).
signal applied
signal closed

const SAVE_PATH := "res://assets/maps/map_editor_palette.json"
const PANEL_W := 840.0
const PANEL_H := 560.0

var map: CustomMap
var working_sets := {}      # тип -> Array[{file, variant, row}]
var active_type := 0
var active_file := 1
var active_row := 0

var type_buttons := {}      # тип -> Button
var file_buttons := {}      # файл -> Button (1..4 = tile, 0 = объекты)
var variant_buttons := {}   # вариант -> Button
var variant_markers := {}   # вариант -> ColorRect (индикатор «в наборе»)
var variant_grid: GridContainer
var object_buttons := {}    # путь -> Button (объекты map-objects)
var object_markers := {}    # путь -> ColorRect
var objects_scroll: ScrollContainer
var objects_grid: GridContainer
var object_list: Array = [] # [{name, path}] из map-objects
var row_box: HBoxContainer
var row_slider: HSlider
var row_label: Label
var set_grid: GridContainer
var set_count_label: Label

func setup(m: CustomMap) -> void:
	map = m
	working_sets = _copy_sets(map.texture_sets)
	_build_ui()
	_collect_objects()
	_select_type(active_type)
	_select_file(active_file)

func _collect_objects() -> void:
	object_list.clear()
	var dir := DirAccess.open("res://assets/map-objects")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var p := "res://assets/map-objects/%s/sprites-001.png" % entry
			if ResourceLoader.exists(p):
				object_list.append({"name": entry, "path": p})
		entry = dir.get_next()
	dir.list_dir_end()
	object_list.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))

func _copy_sets(sets: Dictionary) -> Dictionary:
	var out := {}
	for t in range(9):
		var arr: Array = []
		if sets.has(t):
			arr = sets[t]
		elif sets.has(str(t)):
			arr = sets[str(t)]
		var copy: Array = []
		for item in arr:
			if item is Dictionary:
				var di: Dictionary = item
				copy.append(di.duplicate(true))
		out[t] = copy
	return out

func _build_ui() -> void:
	layer = 10

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2((1280 - PANEL_W) / 2, (800 - PANEL_H) / 2)
	panel.size = Vector2(PANEL_W, PANEL_H)
	add_child(panel)

	var title := Label.new()
	title.text = "Настройки текстур — наборы для категорий"
	title.position = Vector2(14, 10)
	panel.add_child(title)

	_build_type_column(panel)
	_build_variant_area(panel)
	_build_set_column(panel)
	_build_buttons(panel)

func _build_type_column(panel: Panel) -> void:
	var left := Panel.new()
	left.position = Vector2(12, 40)
	left.size = Vector2(140, 470)
	panel.add_child(left)

	var ty := 8.0
	for t in range(9):
		var b := Button.new()
		b.text = CustomMap.TYPE_NAMES[t]
		b.toggle_mode = true
		b.position = Vector2(8, ty)
		b.size = Vector2(124, 32)
		b.pressed.connect(func(id=t): _select_type(id))
		left.add_child(b)
		type_buttons[t] = b
		ty += 40.0

	var hint := Label.new()
	hint.text = "Выберите категорию,\nзатем соберите её\nнабор текстур справа."
	hint.position = Vector2(8, ty + 12)
	left.add_child(hint)

func _build_variant_area(panel: Panel) -> void:
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(168, 40)
	tabs.size = Vector2(560, 30)
	tabs.add_theme_constant_override("separation", 4)
	panel.add_child(tabs)

	for f in range(7):
		var b := Button.new()
		b.text = "tile%d" % (f + 1)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(52, 28)
		b.pressed.connect(func(id=f+1): _select_file(id))
		tabs.add_child(b)
		file_buttons[f + 1] = b

	var ob := Button.new()
	ob.text = "Объекты"
	ob.toggle_mode = true
	ob.custom_minimum_size = Vector2(62, 28)
	ob.pressed.connect(func(): _select_file(0))
	tabs.add_child(ob)
	file_buttons[0] = ob

	variant_grid = GridContainer.new()
	variant_grid.columns = 4
	variant_grid.position = Vector2(168, 78)
	variant_grid.size = Vector2(360, 360)
	variant_grid.add_theme_constant_override("h_separation", 6)
	variant_grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(variant_grid)

	objects_scroll = ScrollContainer.new()
	objects_scroll.position = Vector2(168, 78)
	objects_scroll.size = Vector2(360, 360)
	objects_scroll.visible = false
	panel.add_child(objects_scroll)

	objects_grid = GridContainer.new()
	objects_grid.columns = 4
	objects_grid.add_theme_constant_override("h_separation", 6)
	objects_grid.add_theme_constant_override("v_separation", 6)
	objects_scroll.add_child(objects_grid)

	row_box = HBoxContainer.new()
	row_box.position = Vector2(168, 452)
	row_box.size = Vector2(360, 44)
	panel.add_child(row_box)

	row_label = Label.new()
	row_label.text = "Ряд: 0"
	row_label.custom_minimum_size = Vector2(96, 28)
	row_box.add_child(row_label)

	row_slider = HSlider.new()
	row_slider.min_value = 0
	row_slider.max_value = 15
	row_slider.step = 1
	row_slider.value = 0
	row_slider.custom_minimum_size = Vector2(250, 28)
	row_slider.value_changed.connect(_on_row_changed)
	row_box.add_child(row_slider)

	var hint := Label.new()
	hint.text = "Вариант + ряд = одна текстура.\nКлик по варианту — добавить в набор / убрать из набора."
	hint.position = Vector2(168, 496)
	hint.size = Vector2(360, 50)
	panel.add_child(hint)

func _build_set_column(panel: Panel) -> void:
	var title := Label.new()
	title.text = "Набор категории:"
	title.position = Vector2(548, 40)
	panel.add_child(title)

	set_count_label = Label.new()
	set_count_label.position = Vector2(548, 62)
	panel.add_child(set_count_label)

	var set_scroll := ScrollContainer.new()
	set_scroll.position = Vector2(548, 88)
	set_scroll.size = Vector2(272, 320)
	panel.add_child(set_scroll)

	set_grid = GridContainer.new()
	set_grid.columns = 5
	set_grid.add_theme_constant_override("h_separation", 6)
	set_grid.add_theme_constant_override("v_separation", 6)
	set_scroll.add_child(set_grid)

	var add_btn := Button.new()
	add_btn.text = "+ Добавить текстуру по умолчанию"
	add_btn.position = Vector2(548, 420)
	add_btn.size = Vector2(272, 30)
	add_btn.pressed.connect(_on_add_default)
	panel.add_child(add_btn)

	var hint := Label.new()
	hint.text = "Клик по текстуре набора — убрать.\nНельзя удалить последнюю."
	hint.position = Vector2(548, 460)
	hint.size = Vector2(272, 50)
	panel.add_child(hint)

func _build_buttons(panel: Panel) -> void:
	var save_btn := Button.new()
	save_btn.text = "Сохранить"
	save_btn.position = Vector2(PANEL_W - 260, PANEL_H - 42)
	save_btn.size = Vector2(120, 30)
	save_btn.pressed.connect(_on_save)
	panel.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Отмена"
	cancel_btn.position = Vector2(PANEL_W - 130, PANEL_H - 42)
	cancel_btn.size = Vector2(110, 30)
	cancel_btn.pressed.connect(_on_cancel)
	panel.add_child(cancel_btn)

# --- Логика ---

func _select_type(t: int) -> void:
	active_type = t
	for k in type_buttons:
		var b: Button = type_buttons[k]
		b.button_pressed = (int(k) == t)
	_refresh_set_grid()

func _select_file(f: int) -> void:
	active_file = f
	for k in file_buttons:
		var b: Button = file_buttons[k]
		b.button_pressed = (int(k) == f)
	if f == 0:
		# Режим объектов map-objects: ряд не нужен, показываем сетку объектов
		row_box.visible = false
		objects_scroll.visible = true
		variant_grid.visible = false
		_refresh_variants()
		return
	row_box.visible = true
	objects_scroll.visible = false
	variant_grid.visible = true
	var nrows := _file_rows(f)
	row_slider.max_value = maxf(1.0, float(nrows - 1))
	if active_row >= nrows:
		active_row = nrows - 1
	row_slider.value = active_row
	_refresh_variants()

func _on_row_changed(value: float) -> void:
	active_row = int(value)
	row_label.text = "Ряд: %d" % active_row
	_refresh_variants()

func _file_rows(file_idx: int) -> int:
	var path := "res://assets/terrain/tile%d-%02d.bmp" % [file_idx, 0]
	var tex: Variant = load(path)
	if tex == null:
		return 1
	return int(tex.get_height()) / 32

func _refresh_variants() -> void:
	if active_file == 0:
		_build_object_grid()
		return
	for child in variant_grid.get_children():
		child.queue_free()
	variant_buttons.clear()
	variant_markers.clear()
	var vmax := 4 if active_file == 4 else 16
	for v in range(vmax):
		var img: Image = map._load_tile_region(active_file, v, active_row)
		var b := Button.new()
		b.custom_minimum_size = Vector2(83, 83)
		b.expand_icon = true
		b.icon = ImageTexture.create_from_image(img)
		b.pressed.connect(func(va := v, ff := active_file, rr := active_row): _toggle_texture(ff, va, rr))
		variant_grid.add_child(b)
		variant_buttons[v] = b

		var marker := ColorRect.new()
		marker.color = Color(0.2, 1.0, 0.2, 1.0)
		marker.size = Vector2(12, 12)
		marker.position = Vector2(68, 68)
		marker.visible = _is_in_set(active_file, v, active_row)
		b.add_child(marker)
		variant_markers[v] = marker

func _is_in_set(file_idx: int, variant: int, row: int) -> bool:
	var set: Array = working_sets.get(active_type, [])
	for item in set:
		if item is Dictionary:
			if int(item.get("file", 0)) == file_idx \
					and int(item.get("variant", -1)) == variant \
					and int(item.get("row", -1)) == row:
				return true
	return false

func _toggle_texture(file_idx: int, variant: int, row: int) -> void:
	var set: Array = working_sets.get(active_type, [])
	for i in range(set.size()):
		var item: Dictionary = set[i]
		if int(item.get("file", 0)) == file_idx \
				and int(item.get("variant", -1)) == variant \
				and int(item.get("row", -1)) == row:
			if set.size() > 1:
				set.remove_at(i)
				_refresh_variants()
				_refresh_set_grid()
			return
	set.append({"file": file_idx, "variant": variant, "row": row})
	_refresh_variants()
	_refresh_set_grid()

## --- Объекты map-objects ---

func _build_object_grid() -> void:
	for child in objects_grid.get_children():
		child.queue_free()
	object_buttons.clear()
	object_markers.clear()
	for obj in object_list:
		var name := str(obj["name"])
		var path := str(obj["path"])
		var tex: Variant = load(path)
		var b := Button.new()
		b.custom_minimum_size = Vector2(83, 83)
		b.expand_icon = true
		if tex != null:
			var img: Image = tex.get_image()
			b.icon = ImageTexture.create_from_image(img)
		b.pressed.connect(func(n := name): _toggle_object(n))
		objects_grid.add_child(b)
		object_buttons[name] = b

		# Маркер «в наборе»
		var marker := ColorRect.new()
		marker.color = Color(0.2, 1.0, 0.2, 1.0)
		marker.size = Vector2(12, 12)
		marker.position = Vector2(68, 68)
		marker.visible = _is_object_in_set(name)
		b.add_child(marker)
		object_markers[name] = marker

		# Бейджи: A — анимированный, R — разрушаемый
		var badges := ""
		if ObjectDB.frame_count(name) > 1:
			badges += "A"
		if ObjectDB.is_destructible(name):
			badges += "R"
		if badges != "":
			var bd := Label.new()
			bd.text = badges
			bd.position = Vector2(2, 2)
			bd.add_theme_color_override("font_color", Color(1, 0.9, 0.2, 1))
			b.add_child(bd)

func _toggle_object(name: String) -> void:
	var set: Array = working_sets.get(active_type, [])
	for i in range(set.size()):
		var item: Dictionary = set[i]
		if str(item.get("kind", "")) == "object" and ObjectDB.object_name_from_spec(item) == name:
			if set.size() > 1:
				set.remove_at(i)
				_refresh_variants()
				_refresh_set_grid()
			return
	set.append({"kind": "object", "obj": name})
	_refresh_variants()
	_refresh_set_grid()

func _is_object_in_set(name: String) -> bool:
	var set: Array = working_sets.get(active_type, [])
	for item in set:
		if item is Dictionary:
			if str(item.get("kind", "")) == "object" and ObjectDB.object_name_from_spec(item) == name:
				return true
	return false

func _refresh_set_grid() -> void:
	for child in set_grid.get_children():
		child.queue_free()
	var set: Array = working_sets.get(active_type, [])
	set_count_label.text = "Текстур в наборе: %d (клик — убрать)" % set.size()
	for i in range(set.size()):
		var item: Dictionary = set[i]
		var img: Image = map._load_spec_image(item)
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.expand_icon = true
		b.icon = ImageTexture.create_from_image(img)
		b.pressed.connect(func(idx := i): _remove_from_set(idx))
		set_grid.add_child(b)

func _remove_from_set(idx: int) -> void:
	var set: Array = working_sets.get(active_type, [])
	if set.size() <= 1:
		return
	set.remove_at(idx)
	_refresh_set_grid()
	_refresh_variants()

func _on_add_default() -> void:
	var def: Dictionary = CustomMap.DEFAULT_TEX[active_type]
	# У цветовых плейсхолдеров (строения/НПЦ/спавн) нет variant/row
	if not _is_in_set(int(def.get("file", 1)), int(def.get("variant", -1)), int(def.get("row", -1))):
		var set: Array = working_sets.get(active_type, [])
		set.append(def.duplicate(true))
		_refresh_set_grid()
		_refresh_variants()

func _on_save() -> void:
	map.set_texture_sets(working_sets)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"texture_sets": working_sets}))
		f.close()
	applied.emit()
	_close()

func _on_cancel() -> void:
	closed.emit()
	_close()

func _close() -> void:
	queue_free()