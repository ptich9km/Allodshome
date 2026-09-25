class_name InventoryCatalogPanel
extends CanvasLayer
## Каталог предметов инвентаря: иконки из assets/inventory распределяются мышкой
## по категориям «тип + материал». Материал несёт ранг качества (quality) — по нему
## впоследствии легко сравнивать предметы. Сохраняется в
## assets/maps/inventory_catalog.json: { "файл.png": {"cat": key, "quality": N} }.

signal applied
signal closed

const DEFAULT_SAVE_PATH := "res://assets/maps/inventory_catalog.json"
const PANEL_W := 1160.0
const PANEL_H := 700.0

var save_path: String = DEFAULT_SAVE_PATH

## Материалы с рангом качества (чем больше — тем лучше).
## Названия и порядок — по assets/loot_icons/README.md (материалы проекта,
## не оригинальной игры). Фэнтезийные мифрил/адамант/метеорит/кристалл ушли
## в пользу придуманных terbium/titanium/plutonium/radium.
const MATERIALS := {
	"wood":      {"name": "дерево",          "quality": 1},
	"leather":   {"name": "кожа",            "quality": 2},
	"toughskin": {"name": "плотная кожа",     "quality": 3},
	"bronze":    {"name": "бронза",          "quality": 4},
	"gold":      {"name": "золото",          "quality": 5},
	"iron":      {"name": "железо",          "quality": 6},
	"steel":     {"name": "сталь",           "quality": 7},
	"terbium":   {"name": "тербий",          "quality": 8},
	"titanium":  {"name": "титаний",         "quality": 9},
	"plutonium": {"name": "плутоний",        "quality": 10},
	"radium":    {"name": "радий",           "quality": 11},
	"dragonskin":{"name": "драконья кожа",   "quality": 12},
}

## Категории: {key, name, group} — собираются из типов и материалов.
## group: weapon / armor / shield / accessory / ranged / mage / consumable.
const TYPE_WEAPONS := ["bronze", "gold", "iron", "steel", "terbium", "titanium", "plutonium", "radium"]
const TYPE_ARMOR := ["leather", "toughskin", "bronze", "gold", "iron", "steel", "terbium", "titanium", "plutonium", "radium", "dragonskin"]
const TYPE_SHIELDS := ["wood", "bronze", "iron", "steel", "terbium", "titanium", "plutonium", "radium", "dragonskin"]
const TYPE_AMULETS := ["iron", "steel", "terbium", "titanium", "plutonium", "radium"]
const TYPE_RINGS := ["iron", "steel", "terbium", "titanium", "plutonium", "radium"]
const TYPE_BOWS := ["wood", "bronze", "iron", "steel", "terbium", "titanium", "plutonium", "radium"]
const TYPE_XBOWS := ["wood", "bronze", "iron", "steel", "terbium", "titanium", "plutonium", "radium"]

var catalog := {}          # "файл.png" -> {"cat": key, "quality": N}
var active_category := "weapon_bronze"
var item_list: Array = []  # имена файлов *.png
var item_buttons := {}     # имя файла -> Button
var item_markers := {}     # имя файла -> Label

var category_buttons := {} # key -> Button
var categories := []       # [{key, name, quality}]
var cat_meta := {}         # key -> {name, quality}
var grid_scroll: ScrollContainer
var grid: GridContainer
var status_label: Label

func setup() -> void:
	_build_categories()
	_collect_items()
	_build_ui()
	_load_catalog()
	_refresh_grid()
	_select_category(active_category)

func _build_categories() -> void:
	categories.clear()
	cat_meta.clear()
	for m in TYPE_WEAPONS:
		var q: int = MATERIALS[m]["quality"]
		var key := "weapon_%s" % m
		categories.append({"key": key, "name": "Оружие: %s" % str(MATERIALS[m]["name"]), "quality": q})
		cat_meta[key] = {"name": "Оружие: %s" % str(MATERIALS[m]["name"]), "quality": q, "short": "М"}
	for m in TYPE_ARMOR:
		var q: int = MATERIALS[m]["quality"]
		var key := "armor_%s" % m
		categories.append({"key": key, "name": "Броня: %s" % str(MATERIALS[m]["name"]), "quality": q})
		cat_meta[key] = {"name": "Броня: %s" % str(MATERIALS[m]["name"]), "quality": q, "short": "Б"}
	for m in TYPE_SHIELDS:
		var q: int = MATERIALS[m]["quality"]
		var key := "shield_%s" % m
		categories.append({"key": key, "name": "Щит: %s" % str(MATERIALS[m]["name"]), "quality": q})
		cat_meta[key] = {"name": "Щит: %s" % str(MATERIALS[m]["name"]), "quality": q, "short": "Щ"}
	for m in TYPE_AMULETS:
		var q: int = MATERIALS[m]["quality"]
		var key := "amulet_%s" % m
		categories.append({"key": key, "name": "Амулет: %s" % str(MATERIALS[m]["name"]), "quality": q})
		cat_meta[key] = {"name": "Амулет: %s" % str(MATERIALS[m]["name"]), "quality": q, "short": "А"}
	for m in TYPE_RINGS:
		var q: int = MATERIALS[m]["quality"]
		var key := "ring_%s" % m
		categories.append({"key": key, "name": "Кольцо: %s" % str(MATERIALS[m]["name"]), "quality": q})
		cat_meta[key] = {"name": "Кольцо: %s" % str(MATERIALS[m]["name"]), "quality": q, "short": "К"}
	for m in TYPE_BOWS:
		var q: int = MATERIALS[m]["quality"]
		var key := "bow_%s" % m
		categories.append({"key": key, "name": "Лук: %s" % str(MATERIALS[m]["name"]), "quality": q})
		cat_meta[key] = {"name": "Лук: %s" % str(MATERIALS[m]["name"]), "quality": q, "short": "Л"}
	for m in TYPE_XBOWS:
		var q: int = MATERIALS[m]["quality"]
		var key := "xbow_%s" % m
		categories.append({"key": key, "name": "Арбалет: %s" % str(MATERIALS[m]["name"]), "quality": q})
		cat_meta[key] = {"name": "Арбалет: %s" % str(MATERIALS[m]["name"]), "quality": q, "short": "Аб"}
	for entry in [
		{"key": "mage_cloth", "name": "Одежда мага (тряпичная)", "quality": 0, "short": "ОМ"},
		{"key": "mage_weapon", "name": "Оружие мага (посохи)", "quality": 0, "short": "П"},
		{"key": "scrolls", "name": "Свитки (одноразовые)", "quality": 0, "short": "С"},
		{"key": "mage_books", "name": "Книги умений мага", "quality": 0, "short": "Кн"},
		{"key": "potions", "name": "Бутылки и зелья", "quality": 0, "short": "З"},
		{"key": "quest", "name": "Квестовые (особые)", "quality": 0, "short": "Кв"},
	]:
		var key := str(entry["key"])
		var name := str(entry["name"])
		categories.append({"key": key, "name": name, "quality": int(entry["quality"])})
		cat_meta[key] = {"name": name, "quality": int(entry["quality"]), "short": str(entry["short"])}
		if entry["key"] == "potions":
			active_category = key

func _collect_items() -> void:
	item_list.clear()
	var dir := DirAccess.open("res://assets/inventory")
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".png") and not f.begins_with("."):
			item_list.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	item_list.sort()

func _build_ui() -> void:
	layer = 10

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2((1280 - PANEL_W) / 2, (800 - PANEL_H) / 2)
	panel.size = Vector2(PANEL_W, PANEL_H)
	add_child(panel)

	var title := Label.new()
	title.text = "Каталог предметов инвентаря (тип + материал = качество)"
	title.position = Vector2(14, 8)
	panel.add_child(title)

	# Слева: категории (скролл — их много)
	var left := Panel.new()
	left.position = Vector2(12, 36)
	left.size = Vector2(230, 590)
	panel.add_child(left)

	var cat_scroll := ScrollContainer.new()
	cat_scroll.position = Vector2(8, 8)
	cat_scroll.size = Vector2(214, 574)
	left.add_child(cat_scroll)

	var cat_box := VBoxContainer.new()
	cat_box.add_theme_constant_override("separation", 4)
	cat_scroll.add_child(cat_box)

	for c in categories:
		var key := str(c["key"])
		var b := Button.new()
		b.text = str(c["name"])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(k := key): _select_category(k))
		cat_box.add_child(b)
		category_buttons[key] = b

	status_label = Label.new()
	status_label.text = ""
	status_label.position = Vector2(8, 600)
	status_label.size = Vector2(214, 60)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(status_label)

	# Центр: сетка всех иконок
	grid_scroll = ScrollContainer.new()
	grid_scroll.position = Vector2(254, 36)
	grid_scroll.size = Vector2(700, 600)
	panel.add_child(grid_scroll)

	grid = GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(grid)

	var hint := Label.new()
	hint.text = "Клик по предмету — назначить выбранную категорию (слева). Повторный клик — убрать.\nМаркер: буква типа + ранг качества. Зелёный = текущая категория, жёлтый = другая."
	hint.position = Vector2(254, 640)
	hint.size = Vector2(700, 40)
	panel.add_child(hint)

	var save_btn := Button.new()
	save_btn.text = "Сохранить"
	save_btn.position = Vector2(PANEL_W - 260, PANEL_H - 40)
	save_btn.size = Vector2(120, 30)
	save_btn.pressed.connect(_on_save)
	panel.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Отмена"
	cancel_btn.position = Vector2(PANEL_W - 130, PANEL_H - 40)
	cancel_btn.size = Vector2(110, 30)
	cancel_btn.pressed.connect(_on_cancel)
	panel.add_child(cancel_btn)

func _select_category(key: String) -> void:
	active_category = key
	for k in category_buttons:
		var b: Button = category_buttons[k]
		b.button_pressed = (str(k) == key)
	_refresh_markers()
	var meta: Dictionary = cat_meta.get(key, {})
	status_label.text = "Категория:\n%s (качеств. %d)" % [str(meta.get("name", key)), int(meta.get("quality", 0))]

func _refresh_grid() -> void:
	for child in grid.get_children():
		child.queue_free()
	item_buttons.clear()
	item_markers.clear()
	for name in item_list:
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 62)
		b.expand_icon = true
		var tex: Variant = load("res://assets/inventory/" + name)
		if tex != null:
			b.icon = tex
		b.pressed.connect(func(n: String = name, k: String = active_category): _on_item_clicked(n, k))
		grid.add_child(b)
		item_buttons[name] = b

		var marker := Label.new()
		marker.position = Vector2(2, 2)
		marker.add_theme_font_size_override("font_size", 10)
		b.add_child(marker)
		item_markers[name] = marker
	_refresh_markers()

func _refresh_markers() -> void:
	for name in item_list:
		var marker: Label = item_markers.get(name)
		if marker == null:
			continue
		if not catalog.has(name):
			marker.text = ""
			continue
		var entry: Dictionary = catalog[name]
		var cat_key := str(entry.get("cat", ""))
		var q := int(entry.get("quality", 0))
		var meta: Dictionary = cat_meta.get(cat_key, {})
		marker.text = "%s%d" % [str(meta.get("short", "")), q]
		if cat_key == active_category:
			marker.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2, 1))
		else:
			marker.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1))

func _on_item_clicked(name: String, cat_key: String) -> void:
	var cur := str(catalog.get(name, {}).get("cat", "")) if catalog.has(name) else ""
	if cur == cat_key:
		catalog.erase(name)
	else:
		var meta: Dictionary = cat_meta.get(cat_key, {})
		catalog[name] = {"cat": cat_key, "quality": int(meta.get("quality", 0))}
	_refresh_markers()
	status_label.text = "%s -> %s (качеств. %d)" % [
		name,
		str(cat_meta.get(cat_key, {}).get("name", cat_key)),
		int(cat_meta.get(cat_key, {}).get("quality", 0))]

func _load_catalog() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		catalog = parsed

func _on_save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("Каталог: не удалось записать " + save_path)
		return
	f.store_string(JSON.stringify(catalog))
	f.close()
	print("Каталог сохранён: %d предметов" % catalog.size())
	applied.emit()
	_close()

func _on_cancel() -> void:
	closed.emit()
	_close()

func _close() -> void:
	queue_free()