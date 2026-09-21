extends RefCounted
## Редактор базы переходов terrain-типов.
## Визуальное окно: выбираешь пару типов (A/B), видишь 8 направлений,
## для каждого кликаешь и выбираешь variant/row из палитры тайлов.

const DB_PATH := "res://assets/maps/transition_db.json"
const TERRAIN_NAMES := {0: "Трава", 1: "Горы", 2: "Вода", 3: "Дорога", 4: "Почва", 5: "Песок", 6: "Грязь"}
const TERRAIN_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7}  # тип -> tile-файл
const DIR_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const DIR_LABELS := {
	"N": "Север", "NE": "СВ", "E": "Восток", "SE": "ЮВ",
	"S": "Юг", "SW": "ЮЗ", "W": "Запад", "NW": "СЗ",
}
const GRID_DIR := ["NW", "N", "NE", "W", "", "E", "SW", "S", "SE"]

var _db: Dictionary = {}
var _rules: Dictionary = {}
var _type_a: int = 0
var _type_b: int = 2
var _panel: PanelContainer = null
var _grid_buttons: Array = []
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
	_rules["%d:%s:%d" % [type_a, dir, type_b]] = spec

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
	for id in range(7):
		opt_a.add_item(TERRAIN_NAMES[id], id)
	opt_a.selected = 0
	opt_a.item_selected.connect(_on_type_a_changed)
	type_row.add_child(opt_a)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	type_row.add_child(spacer)

	var lbl_b := Label.new()
	lbl_b.text = "Тип B (сосед):"
	type_row.add_child(lbl_b)
	var opt_b := OptionButton.new()
	_opt_b = opt_b
	for id in range(7):
		opt_b.add_item(TERRAIN_NAMES[id], id)
	opt_b.selected = 2
	opt_b.item_selected.connect(_on_type_b_changed)
	type_row.add_child(opt_b)

	# Сетка 3x3
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)

	_grid_buttons.clear()
	for i in range(9):
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(80, 80)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.add_theme_stylebox_override("normal", _frame(Color(0.3, 0.3, 0.3)))
		btn.add_theme_stylebox_override("hover", _frame(Color(0.5, 0.5, 0.8)))
		btn.add_theme_stylebox_override("pressed", _frame(Color(0.3, 0.8, 0.3)))

		if GRID_DIR[i] != "":
			var dir: String = GRID_DIR[i]
			btn.pressed.connect(_on_grid_click.bind(dir))
			var lbl := Label.new()
			lbl.text = DIR_LABELS.get(dir, dir)
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.position = Vector2(2, 2)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(lbl)
		else:
			btn.disabled = true
			var lbl := Label.new()
			lbl.text = "A"
			lbl.add_theme_font_size_override("font_size", 16)
			lbl.position = Vector2(28, 28)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(lbl)

		_grid_buttons.append(btn)
		grid.add_child(btn)

	# Кнопки управления
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Сохранить"
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

	var import_btn := Button.new()
	import_btn.text = "Импорт из .alm (авто)"
	import_btn.pressed.connect(_on_import_alm)
	btn_row.add_child(import_btn)

	var reload_btn := Button.new()
	reload_btn.text = "Перечитать"
	reload_btn.pressed.connect(_on_reload)
	btn_row.add_child(reload_btn)

	var close_btn := Button.new()
	close_btn.text = "Закрыть"
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
	for i in range(9):
		var dir: String = GRID_DIR[i]
		var btn: TextureButton = _grid_buttons[i]
		if dir == "":
			btn.texture_normal = _interior_tex(_type_a)
			continue
		var spec: Dictionary = get_rule(_type_a, dir, _type_b)
		if spec.is_empty():
			btn.texture_normal = null
			btn.tooltip_text = "%s -> %s: не задано" % [TERRAIN_NAMES[_type_a], TERRAIN_NAMES[_type_b]]
		else:
			btn.texture_normal = tile_from_spec(spec)
			btn.tooltip_text = "%s -> %s %s: f%d v%d r%d" % [
				TERRAIN_NAMES[_type_a], TERRAIN_NAMES[_type_b], dir,
				spec.get("file", 0), spec.get("variant", 0), spec.get("row", 0)]

func _interior_tex(type: int) -> Texture2D:
	var interior: Dictionary = _db.get("interior", {})
	if interior.has(str(type)):
		return tile_from_spec(interior[str(type)])
	return null

# === Обработчики ===

func _on_type_a_changed(idx: int) -> void:
	_type_a = _opt_a.get_item_id(idx)
	_refresh_grid()

func _on_type_b_changed(idx: int) -> void:
	_type_b = _opt_b.get_item_id(idx)
	_refresh_grid()

func _on_grid_click(dir: String) -> void:
	_open_palette(dir)

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

func _open_palette(dir: String) -> void:
	if _palette_popup != null and is_instance_valid(_palette_popup):
		_palette_popup.queue_free()

	_palette_popup = Panel.new()
	_palette_popup.name = "TilePalette"
	_palette_popup.set_anchors_preset(Control.PRESET_CENTER)
	_palette_popup.offset_left = -320
	_palette_popup.offset_top = -250
	_palette_popup.offset_right = 320
	_palette_popup.offset_bottom = 250
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
	title.text = "Тайл: %s -> %s [%s]" % [
		TERRAIN_NAMES[_type_a], TERRAIN_NAMES[_type_b], DIR_LABELS.get(dir, dir)]
	title.add_theme_font_size_override("font_size", 12)
	vb.add_child(title)

	var file_n: int = TERRAIN_FILE.get(_type_a, 1)
	var max_rows := 14 if file_n != 3 else 8

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 16
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(grid)

	for v in range(16):
		for r in range(max_rows):
			var spec := {"file": file_n, "variant": v, "row": r}
			var btn := TextureButton.new()
			btn.custom_minimum_size = Vector2(32, 32)
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			btn.texture_normal = tile_from_spec(spec)
			btn.tooltip_text = "v%d r%d" % [v, r]
			btn.pressed.connect(_on_palette_pick.bind(dir, spec))
			grid.add_child(btn)

	var clear_btn := Button.new()
	clear_btn.text = "Очистить (убрать правило)"
	clear_btn.pressed.connect(_on_palette_clear.bind(dir))
	vb.add_child(clear_btn)

func _on_palette_pick(dir: String, spec: Dictionary) -> void:
	set_rule(_type_a, dir, _type_b, spec)
	_refresh_grid()
	_status_label.text = "Правило установлено: %s %s->%s = f%d v%d r%d" % [
		TERRAIN_NAMES[_type_a], dir, TERRAIN_NAMES[_type_b],
		spec["file"], spec["variant"], spec["row"]]
	if _palette_popup != null and is_instance_valid(_palette_popup):
		_palette_popup.queue_free()

func _on_palette_clear(dir: String) -> void:
	_rules.erase("%d:%s:%d" % [ _type_a, dir, _type_b])
	_refresh_grid()
	_status_label.text = "Правило удалено: %s %s->%s" % [
		TERRAIN_NAMES[_type_a], dir, TERRAIN_NAMES[_type_b]]
	if _palette_popup != null and is_instance_valid(_palette_popup):
		_palette_popup.queue_free()

# === Импорт из .alm карт разработчиков ===

func _on_import_alm() -> void:
	var pv := "res://assets/maps/pvm/"
	var maps := [
		"sb_anp_greenlnd_1_1.alm",
		"sb_anp_tropic_1_0.alm",
		"sb_anp_canyon_1_0.alm",
		"sb_anp_orcish_1_0.alm",
		"sb_anp_gothic_1_2.alm",
		"sb_anp_som_1_0.alm",
		"sc_an_nord_3_2.alm",
		"hc_an_4islands_4_6.alm",
		"sc_an_madp_2_1.alm",
	]
	# Ключ: "typeA:dir:typeB" -> {"file:variant:row": count}
	var stats := {}
	var total_cells := 0
	for f in maps:
		var p: String = pv + f
		if not FileAccess.file_exists(p):
			continue
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
				var dirs := {"N": Vector2i(0, -1), "S": Vector2i(0, 1),
							 "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
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
					var key: String = "%d:%s:%d" % [t, dir_name, nt]
					if not stats.has(key):
						stats[key] = {}
					stats[key][tile_key] = int(stats[key].get(tile_key, 0)) + 1
					total_cells += 1
	# Заполняем правила самыми частотными тайлами
	var imported := 0
	for key in stats:
		var parts: Array = key.split(":")
		if parts.size() != 3:
			continue
		var type_a: int = int(parts[0])
		var dir: String = parts[1]
		var type_b: int = int(parts[2])
		var items: Dictionary = stats[key]
		var best_key := ""
		var best_count := 0
		for tk in items:
			if int(items[tk]) > best_count:
				best_count = int(items[tk])
				best_key = tk
		if best_key == "":
			continue
		var bp: Array = best_key.split(":")
		if bp.size() != 3:
			continue
		var spec := {"file": int(bp[0]), "variant": int(bp[1]), "row": int(bp[2])}
		set_rule(type_a, dir, type_b, spec)
		imported += 1
	# Также заполняем диагонали из 4-связных данных (комбинация cardinal)
	# Для диагоналей: берем.variant из "комбинации" двух cardinal direction
	_refresh_grid()
	_status_label.text = "Импорт: %d правил из %d клеток на границах. Сохраните!" % [imported, total_cells]
