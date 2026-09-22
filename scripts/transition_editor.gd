extends RefCounted
## Редактор базы переходов terrain-типов.
## Визуальное окно: выбираешь пару типов (A/B), видишь 8 направлений,
## для каждого кликаешь и выбираешь variant/row из палитры тайлов.

const DB_PATH := "res://assets/maps/transition_db.json"
const TERRAIN_NAMES := {0: "Трава", 1: "Горы", 2: "Вода", 3: "Дорога", 4: "Почва", 5: "Песок", 6: "Грязь", 7: "Гора непроходимая"}
## Тип -> tile-файл для .alm/рендера (пересчёт в генераторах по типу A)
const TERRAIN_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 2}
## Тип -> файл палитры в редакторе. Показываем РЕАЛЬНЫЙ файл типа.
const PALETTE_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 1, 5: 1, 6: 1, 7: 2}
const DIR_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const DIR_LABELS := {
	"N": "Север", "NE": "СВ", "E": "Восток", "SE": "ЮВ",
	"S": "Юг", "SW": "ЮЗ", "W": "Запад", "NW": "СЗ",
}
const GRID_DIR := ["NW", "N", "NE", "W", "", "E", "SW", "S", "SE"]

## Supported transition pairs (only these have actual textures)
## Key = typeA, Value = array of typeB that have transition textures
const SUPPORTED_PAIRS := {
	0: [4],           # grass -> soil
	1: [0, 4, 6, 7],  # mountain -> grass, soil, mud, impassable mountain
	2: [4],           # water -> soil
	3: [4],           # road -> soil
	4: [0, 1, 2, 3, 5, 6],  # soil -> all
	5: [4],           # sand -> soil
	6: [4],           # mud -> soil
	7: [1],           # impassable mountain -> mountain
}

var _db: Dictionary = {}
var _rules: Dictionary = {}
var _type_a: int = 0
var _type_b: int = 4  # Default to soil since most transitions go through soil
var _panel: PanelContainer = null
var _grid_buttons: Array = []
var _dir_keys: Array = []

func _add_dir_btns(row_hb: HBoxContainer, dir_name: String) -> void:
	for sub in range(2):
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(60, 60)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.add_theme_stylebox_override("normal", _frame(Color(0.3, 0.3, 0.3)))
		btn.add_theme_stylebox_override("hover", _frame(Color(0.5, 0.5, 0.8)))
		var key: String = dir_name + str(sub + 1)
		btn.pressed.connect(_on_grid_click.bind(key))
		var lbl := Label.new()
		lbl.text = "%s%d" % [DIR_LABELS.get(dir_name, dir_name), sub + 1]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.position = Vector2(2, 2)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(lbl)
		_grid_buttons.append(btn)
		_dir_keys.append(key)
		row_hb.add_child(btn)

var _palette_popup: Panel = null
var _status_label: Label = null
var _parent_ui: CanvasLayer = null
var _opt_a: OptionButton = null
var _opt_b: OptionButton = null

# === Загрузка / сохранение DB ===

func load_db() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		_db = {"rules": {}, "interior": {}}
		_rules = {}
		return
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Dictionary:
		_db = json
		_rules = _db.get("rules", {})
	else:
		_db = {"rules": {}, "interior": {}}
		_rules = {}

func save_db() -> void:
	_db["rules"] = _rules
	var f := FileAccess.open(DB_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_db, "\t"))
	f.close()

func get_rule(type_a: int, dir: String, type_b: int) -> Dictionary:
	return _rules.get("%d:%s:%d" % [type_a, dir, type_b], {})

func set_rule(type_a: int, dir: String, type_b: int, spec: Dictionary) -> void:
	# Godot JSON пишет числа как float — нормализуем в int при установке
	var clean := {}
	for k in spec:
		var v: Variant = spec[k]
		if v is float and absf(v - roundf(v)) < 0.001:
			clean[k] = int(roundf(v))
		else:
			clean[k] = v
	_rules["%d:%s:%d" % [type_a, dir, type_b]] = clean

# === Текстура из spec ===

func tile_from_spec(spec: Dictionary) -> Texture2D:
	var file_n: int = int(spec.get("file", 1))
	var variant: int = int(spec.get("variant", 0))
	var row: int = int(spec.get("row", 0))
	var path := "res://assets/terrain/tiles/tile%d-%02d_%02d.png" % [file_n, variant, row]
	var tex: Variant = load(path)
	if tex != null:
		return tex as Texture2D
	return null

# === Построение UI ===

func open_editor(parent_ui: CanvasLayer) -> void:
	_parent_ui = parent_ui
	load_db()
	_build_panel(parent_ui)

func _build_panel(parent_ui: CanvasLayer) -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = PanelContainer.new()
	_panel.name = "TransitionEditor"
	_panel.offset_left = 200
	_panel.offset_top = 50
	_panel.offset_right = 920
	_panel.offset_bottom = 600
	_panel.z_index = 200
	parent_ui.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	# Заголовок
	var title := Label.new()
	title.text = "РЕДАКТОР ПЕРЕХОДОВ TERRAIN-ТИПОВ"
	title.add_theme_font_size_override("font_size", 14)
	vb.add_child(title)

	# Строка выбора типов
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 20)
	vb.add_child(type_row)

	var lbl_a := Label.new()
	lbl_a.text = "Тип A (клетка):"
	type_row.add_child(lbl_a)
	var opt_a := OptionButton.new()
	_opt_a = opt_a
	for id in range(8):
		opt_a.add_item(TERRAIN_NAMES[id], id)
	opt_a.selected = 0
	opt_a.item_selected.connect(_on_type_a_changed)
	type_row.add_child(opt_a)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	type_row.add_child(spacer)

	var lbl_b := Label.new()
	lbl_b.text = "Type B (neighbor):"
	type_row.add_child(lbl_b)
	var opt_b := OptionButton.new()
	_opt_b = opt_b
	# Populate with supported neighbors for default type A
	var supported: Array = SUPPORTED_PAIRS.get(_type_a, [])
	for id in supported:
		opt_b.add_item(TERRAIN_NAMES[id], id)
	if supported.size() > 0:
		opt_b.selected = 0
		_type_b = supported[0]
	opt_b.item_selected.connect(_on_type_b_changed)
	type_row.add_child(opt_b)

	# Direction rose layout:
	#   NW1 NW2 | N1 N2 | NE1 NE2
	#   -------|-------|--------
	#   W1  W2  | A1-A6 | E1  E2
	#   -------|-------|--------
	#   SW1 SW2 | S1 S2 | SE1 SE2

	_grid_buttons.clear()
	_dir_keys.clear()

	# Row 1: NW N NE
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vb.add_child(row1)
	_add_dir_btns(row1, "NW")
	_add_dir_btns(row1, "N")
	_add_dir_btns(row1, "NE")

	# Row 2: W | center(6) | E
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	vb.add_child(row2)
	_add_dir_btns(row2, "W")

	# Center: 6 interior variant buttons
	var center_grid := GridContainer.new()
	center_grid.columns = 3
	center_grid.add_theme_constant_override("h_separation", 2)
	center_grid.add_theme_constant_override("v_separation", 2)
	for iv in range(6):
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(60, 60)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.add_theme_stylebox_override("normal", _frame(Color(0.8, 0.6, 0.2)))
		btn.add_theme_stylebox_override("hover", _frame(Color(1.0, 0.8, 0.3)))
		var akey: String = "A%d" % (iv + 1)
		btn.pressed.connect(_on_grid_click.bind(akey))
		var lbl := Label.new()
		lbl.text = akey
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.position = Vector2(18, 2)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(lbl)
		_grid_buttons.append(btn)
		_dir_keys.append(akey)
		center_grid.add_child(btn)
	row2.add_child(center_grid)

	_add_dir_btns(row2, "E")

	# Row 3: SW S SE
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	vb.add_child(row3)
	_add_dir_btns(row3, "SW")
	_add_dir_btns(row3, "S")
	_add_dir_btns(row3, "SE")

	# Кнопки управления
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

	var reload_btn := Button.new()
	reload_btn.text = "Reload"
	reload_btn.pressed.connect(_on_reload)
	btn_row.add_child(reload_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 10)
	vb.add_child(_status_label)

	_refresh_grid()

func _frame(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.15, 0.15, 0.15)
	s.border_color = color
	s.set_border_width_all(2)
	s.set_content_margin_all(2)
	return s

# === Обновление сетки ===

func _refresh_grid() -> void:
	for i in range(_grid_buttons.size()):
		var btn: TextureButton = _grid_buttons[i]
		var key: String = _dir_keys[i] if i < _dir_keys.size() else ""
		if key.begins_with("A"):
			# Interior variant button
			var rule_key: String = "%d:%s:%d" % [_type_a, key, _type_a]
			var spec: Dictionary = _rules.get(rule_key, {})
			btn.texture_normal = tile_from_spec(spec) if not spec.is_empty() else null
			btn.tooltip_text = "Interior %s %s: %s" % [
				TERRAIN_NAMES[_type_a], key,
				("v%d r%d" % [spec.get("variant", 0), spec.get("row", 0)])
				if not spec.is_empty() else "not set"]
		else:
			# Direction button: key = "NW1", "N2" etc
			var rule_key: String = "%d:%s:%d" % [_type_a, key, _type_b]
			var spec: Dictionary = _rules.get(rule_key, {})
			if spec.is_empty():
				btn.texture_normal = null
				btn.tooltip_text = "%s -> %s %s: not set" % [
					TERRAIN_NAMES[_type_a], TERRAIN_NAMES[_type_b], key]
			else:
				btn.texture_normal = tile_from_spec(spec)
				btn.tooltip_text = "%s -> %s %s: v%d r%d" % [
					TERRAIN_NAMES[_type_a], TERRAIN_NAMES[_type_b], key,
					spec.get("variant", 0), spec.get("row", 0)]

func _interior_spec(type: int) -> Dictionary:
	var interior: Dictionary = _db.get("interior", {})
	var v: Variant = interior.get(str(type), {})
	return v if v is Dictionary else {}

func _set_interior_spec(type: int, spec: Dictionary) -> void:
	if not _db.has("interior") or not (_db["interior"] is Dictionary):
		_db["interior"] = {}
	if spec.is_empty():
		_db["interior"].erase(str(type))
	else:
		_db["interior"][str(type)] = spec

# === Обработчики ===

func _on_type_a_changed(idx: int) -> void:
	_type_a = _opt_a.get_item_id(idx)
	# Update type B dropdown to only show supported neighbors
	_opt_b.clear()
	var supported: Array = SUPPORTED_PAIRS.get(_type_a, [])
	for id in supported:
		_opt_b.add_item(TERRAIN_NAMES[id], id)
	if supported.size() > 0:
		_opt_b.selected = 0
		_type_b = supported[0]
	_refresh_grid()

func _on_type_b_changed(idx: int) -> void:
	_type_b = _opt_b.get_item_id(idx)
	_refresh_grid()

func _on_grid_click(key: String) -> void:
	# key: "" or "A1"-"A6" for interior, "NW1"/"N2" etc for directions
	_open_palette(key)

func _on_save() -> void:
	save_db()
	_status_label.text = "Сохранено в %s" % DB_PATH

func _on_reload() -> void:
	load_db()
	_refresh_grid()
	_status_label.text = "Перечитано из %s" % DB_PATH

func _on_close() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null

# === Палитра выбора тайла ===

func _open_palette(key: String) -> void:
	if _palette_popup != null and is_instance_valid(_palette_popup):
		_palette_popup.queue_free()

	_palette_popup = Panel.new()
	_palette_popup.name = "TilePalette"
	_palette_popup.set_anchors_preset(Control.PRESET_CENTER)
	_palette_popup.offset_left = -400
	_palette_popup.offset_top = -300
	_palette_popup.offset_right = 400
	_palette_popup.offset_bottom = 300
	_palette_popup.z_index = 300
	_parent_ui.add_child(_palette_popup)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_palette_popup.add_child(margin)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vb)

	var title := Label.new()
	if key.begins_with("A"):
		title.text = "Interior %s %s — pick a tile" % [TERRAIN_NAMES[_type_a], key]
	else:
		title.text = "Transition: %s -> %s [%s] — pick a tile" % [
			TERRAIN_NAMES[_type_a], TERRAIN_NAMES[_type_b], key]
	title.add_theme_font_size_override("font_size", 12)
	vb.add_child(title)

	var file_n: int
	if key.begins_with("A"):
		file_n = PALETTE_FILE.get(_type_a, 1)
	else:
		file_n = PALETTE_FILE.get(_type_a, 1)
	var max_rows := 8 if file_n == 3 else 14
	var max_vars := 4 if file_n == 4 else 16

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = max_vars
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(grid)

	for r in range(max_rows):
		for v in range(max_vars):
			var spec := {"file": file_n, "variant": v, "row": r}
			var btn := TextureButton.new()
			btn.custom_minimum_size = Vector2(32, 32)
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			btn.texture_normal = tile_from_spec(spec)
			btn.tooltip_text = "v%d r%d" % [v, r]
			btn.pressed.connect(_on_palette_pick.bind(key, spec))
			grid.add_child(btn)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var clear_btn := Button.new()
	clear_btn.text = "Clear" if key != "" else "Reset interior"
	clear_btn.pressed.connect(_on_palette_clear.bind(key))
	btn_row.add_child(clear_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_palette_cancel)
	btn_row.add_child(cancel_btn)

func _on_palette_pick(key: String, spec: Dictionary) -> void:
	if key.begins_with("A"):
		# Interior variant: store as rule with A key
		var rule_key: String = "%d:%s:%d" % [_type_a, key, _type_a]
		_rules[rule_key] = spec
		_refresh_grid()
		_status_label.text = "Interior %s %s = v%d r%d" % [
			TERRAIN_NAMES[_type_a], key, spec["variant"], spec["row"]]
	else:
		# Direction: store with full key
		var rule_key: String = "%d:%s:%d" % [_type_a, key, _type_b]
		_rules[rule_key] = spec
		_refresh_grid()
		_status_label.text = "Rule: %s %s->%s = v%d r%d" % [
			TERRAIN_NAMES[_type_a], key, TERRAIN_NAMES[_type_b],
			spec["variant"], spec["row"]]
	if _palette_popup != null and is_instance_valid(_palette_popup):
		_palette_popup.queue_free()

func _on_palette_cancel() -> void:
	if _palette_popup != null and is_instance_valid(_palette_popup):
		_palette_popup.queue_free()

func _on_palette_clear(key: String) -> void:
	if key.begins_with("A"):
		var rule_key: String = "%d:%s:%d" % [_type_a, key, _type_a]
		_rules.erase(rule_key)
		_refresh_grid()
		_status_label.text = "Interior %s %s cleared" % [TERRAIN_NAMES[_type_a], key]
	else:
		var rule_key: String = "%d:%s:%d" % [_type_a, key, _type_b]
		_rules.erase(rule_key)
		_refresh_grid()
		_status_label.text = "Rule deleted: %s %s" % [TERRAIN_NAMES[_type_a], key]
	if _palette_popup != null and is_instance_valid(_palette_popup):
		_palette_popup.queue_free()

# === Импорт из .alm карт разработчиков ===

func _on_import_alm() -> void:
	var pv := "res://assets/maps/pvm/"
	# Собираем все .alm в папке (регистр не важен: .alm/.ALM)
	var maps: Array[String] = []
	var dir := DirAccess.open(pv)
	if dir != null:
		for f in dir.get_files():
			var fl := f.to_lower()
			if fl.ends_with(".alm"):
				maps.append(f)
	maps.sort()
	if maps.is_empty():
		_status_label.text = "Импорт: нет .alm в %s" % pv
		return

	# Ключ: "typeA:dir:typeB" -> {"file:variant:row": count}
	var stats := {}
	var interior_stats := {}  # "type" -> {"file:variant:row": count}
	var total_cells := 0
	var dirs := {
		"N": Vector2i(0, -1), "S": Vector2i(0, 1),
		"E": Vector2i(1, 0), "W": Vector2i(-1, 0),
		"NE": Vector2i(1, -1), "NW": Vector2i(-1, -1),
		"SE": Vector2i(1, 1), "SW": Vector2i(-1, 1),
	}
	for f in maps:
		var p: String = pv + f
		var m: Dictionary = AlmLoader.load_map(p)
		if m.is_empty():
			continue
		var w: int = int(m["width"])
		var h: int = int(m["height"])
		var tiles: PackedInt32Array = m["tiles"]
		for y in range(h):
			for x in range(w):
				var i: int = y * w + x
				var t: int = AlmLoader.tile_type(tiles[i])
				var raw_f: int = AlmLoader.tile_file(tiles[i])
				var r: int = AlmLoader.tile_frame(tiles[i])
				var file_n: int = (raw_f >> 4) + 1
				var variant: int = raw_f & 0xF
				var tile_key: String = "%d:%d:%d" % [file_n, variant, r]
				var is_edge := false
				for dir_name in dirs:
					var d: Vector2i = dirs[dir_name]
					var nx: int = x + int(d.x)
					var ny: int = y + int(d.y)
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni: int = ny * w + nx
					var nt: int = AlmLoader.tile_type(tiles[ni])
					if nt == t:
						continue
					is_edge = true
					var key: String = "%d:%s:%d" % [t, dir_name, nt]
					if not stats.has(key):
						stats[key] = {}
					stats[key][tile_key] = int(stats[key].get(tile_key, 0)) + 1
					total_cells += 1
				if not is_edge:
					# Интерьер: самый частый тайл «внутри» типа
					if not interior_stats.has(str(t)):
						interior_stats[str(t)] = {}
					interior_stats[str(t)][tile_key] = int(interior_stats[str(t)].get(tile_key, 0)) + 1

	# Заполняем правила самыми частотными тайлами
	var imported := 0
	for key in stats:
		var parts: Array = key.split(":")
		if parts.size() != 3:
			continue
		var spec := _best_spec(stats[key])
		if spec.is_empty():
			continue
		set_rule(int(parts[0]), parts[1], int(parts[2]), spec)
		imported += 1

	# Интерьер для типов, которые встретились на картах
	var imported_int := 0
	for tkey in interior_stats:
		var spec := _best_spec(interior_stats[tkey])
		if spec.is_empty():
			continue
		if not _db.has("interior"):
			_db["interior"] = {}
		_db["interior"][tkey] = spec
		imported_int += 1

	_refresh_grid()
	_status_label.text = "Импорт: %d правил + %d interior из %d карт (%d клеток на границах). Сохраните!" % [
		imported, imported_int, maps.size(), total_cells]

## Самый частотный tile-key -> spec {file, variant, row}
func _best_spec(items: Dictionary) -> Dictionary:
	var best_key := ""
	var best_count := 0
	for tk in items:
		if int(items[tk]) > best_count:
			best_count = int(items[tk])
			best_key = str(tk)
	if best_key == "":
		return {}
	var bp: Array = best_key.split(":")
	if bp.size() != 3:
		return {}
	return {"file": int(bp[0]), "variant": int(bp[1]), "row": int(bp[2])}
