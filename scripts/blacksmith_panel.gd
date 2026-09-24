class_name BlacksmithPanel
extends CanvasLayer
## Кузница: переплавка оружия/брони в слитки.
## Фон: blacksmith.jpeg (1024×1024), уменьшен до 768×768 (×0.75),
## отцентрирован в 1280×800. Зоны пересчитаны: экранные = (orig × 0.75) + offset.
##   BLACKSMITH_OUTPUT — 7×1 (слева) — результат переплавки
##   PLAYER_INVENTORY  — 2×6 (снизу) — вещи игрока для переплавки

signal closed

## Маппинг material.item_db → material.ingot (loot_icons)
const _MATERIAL_MAP := {
	"Iron": "iron", "Bronze": "bronze", "Steel": "steel",
	"Silver": "argentum", "Gold": "lutetium",
	"Adamantium": "titanium", "Mithrill": "terbium",
	"Meteoric": "plutonium", "Crystal": "radium",
	"Dragon Leather": "chromium", "Hard Leather": "cobalt",
	"Leather": "wolfram", "Wood": "yttrium",
	"Magic Wood": "gallium",
}
const _DEFAULT_INGOT := "iron"

const _BG_PATH := "res://assets/blacksmith/blacksmith.jpeg"
const _BG_SCALE := 0.75          # 1024 → 768
const _SCREEN := Vector2(1280, 800)
const _BG_SIZE := 768.0          # 1024 × 0.75
const _OFFSET := Vector2(256, 16)  # центрирование в 1280×800

## Зоны (из README, координаты в 1024×1024, пересчитаны в экранные)
const _OUTPUT_RECT := Rect2(290.5, 173.5, 129.0, 482.25)  # 7×1
const _INV_RECT := Rect2(454.75, 607.75, 555.75, 171.75)  # 2×6

var player: Player
var _bg: TextureRect
var _output_items: Array = []  # [{key, material}]

func setup(p: Player) -> void:
	player = p
	layer = 10

	# Затемнение
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Фон кузницы (768×768, отцентрирован) — ручное уменьшение через Image
	var bg_tex: Texture2D = load(_BG_PATH)
	var img: Image = bg_tex.get_image()
	img.resize(int(_BG_SIZE), int(_BG_SIZE), Image.INTERPOLATE_BILINEAR)
	_bg = TextureRect.new()
	_bg.texture = ImageTexture.create_from_image(img)
	_bg.position = _OFFSET
	_bg.size = Vector2(_BG_SIZE, _BG_SIZE)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Кнопка закрытия (в правом нижнем углу фона)
	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.position = _OFFSET + Vector2(637, 712)
	close_btn.size = Vector2(105, 30)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(close)
	add_child(close_btn)

	# Заголовок
	var title := Label.new()
	title.text = "КУЗНИЦА"
	title.position = _OFFSET + Vector2(22, 15)
	title.size = Vector2(300, 27)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	add_child(title)

	_refresh()

func _refresh() -> void:
	_clear_slots()
	_build_output_slots()
	_build_inventory_slots()

## Слоты результата (BLACKSMITH_OUTPUT — 7×1 слева)
func _build_output_slots() -> void:
	var cell_w: float = _OUTPUT_RECT.size.x / 1.0
	var cell_h: float = _OUTPUT_RECT.size.y / 7.0
	for row in range(7):
		var slot_bg := ColorRect.new()
		slot_bg.color = Color(0.15, 0.12, 0.1, 0.7)
		slot_bg.position = Vector2(_OUTPUT_RECT.position.x,
								   _OUTPUT_RECT.position.y + row * cell_h)
		slot_bg.size = Vector2(cell_w, cell_h)
		slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot_bg)

		# Иконка слитка (если есть)
		if row < _output_items.size():
			var item: Dictionary = _output_items[row]
			var ingot_path := _ingot_path(item.get("material", ""))
			var icon_tex: Texture2D = load(ingot_path)
			if icon_tex:
				var icon := TextureRect.new()
				icon.texture = icon_tex
				icon.position = Vector2(_OUTPUT_RECT.position.x + 24,
										_OUTPUT_RECT.position.y + row * cell_h + 8)
				icon.size = Vector2(60, 60)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(icon)

## Слоты инвентаря (PLAYER_INVENTORY — 2×6 снизу)
func _build_inventory_slots() -> void:
	var cell_w: float = _INV_RECT.size.x / 6.0
	var cell_h: float = _INV_RECT.size.y / 2.0

	# Собираем экипируемые предметы из инвентаря
	var equip_items: Array = []
	if is_instance_valid(player):
		var seen := {}
		for key in player.inventory:
			var item := ItemDB.find(str(key))
			if item.is_empty():
				continue
			if not ItemDB.is_equippable(item):
				continue
			var k := str(key)
			seen[k] = seen.get(k, 0) + 1
		for key in seen:
			var item := ItemDB.find(str(key))
			equip_items.append({"key": key, "count": seen[key], "item": item})

	var idx := 0
	for row in range(2):
		for col in range(6):
			var slot_bg := ColorRect.new()
			slot_bg.color = Color(0.1, 0.1, 0.15, 0.7)
			slot_bg.position = Vector2(_INV_RECT.position.x + col * cell_w,
									   _INV_RECT.position.y + row * cell_h)
			slot_bg.size = Vector2(cell_w, cell_h)
			slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(slot_bg)

			if idx < equip_items.size():
				var entry: Dictionary = equip_items[idx]
				var item: Dictionary = entry["item"]
				var tex_path: String = str(item.get("icon", ""))
				var icon_tex: Texture2D = null
				if not tex_path.is_empty():
					icon_tex = load(tex_path)
				if icon_tex:
					var icon := TextureRect.new()
					icon.texture = icon_tex
					icon.position = slot_bg.position + Vector2(8, 8)
					icon.size = Vector2(cell_w - 16, cell_h - 24)
					icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
					add_child(icon)

				# Кнопка переплавки
				var btn := Button.new()
				btn.text = "Плавить"
				btn.position = slot_bg.position + Vector2(4, cell_h - 18)
				btn.size = Vector2(cell_w - 8, 16)
				btn.add_theme_font_size_override("font_size", 9)
				btn.pressed.connect(_smelt_item.bind(str(entry["key"])))
				add_child(btn)

				# Счётчик
				if entry["count"] > 1:
					var cnt_label := Label.new()
					cnt_label.text = "×%d" % entry["count"]
					cnt_label.position = slot_bg.position + Vector2(cell_w - 28, 2)
					cnt_label.add_theme_font_size_override("font_size", 9)
					cnt_label.add_theme_color_override("font_color", Color.WHITE)
					add_child(cnt_label)

			idx += 1

## Переплавка предмета
func _smelt_item(key: String) -> void:
	if not is_instance_valid(player):
		return
	if not player.remove_item(key):
		return
	var item := ItemDB.find(key)
	var material: String = str(item.get("material", ""))
	_output_items.append({"key": key, "material": material})
	SoundDB.play(9)
	print("Переплавлено: %s → слиток %s" % [key, _ingot_material(material)])
	_refresh()

## Путь к иконке слитка (fallback: weapon-иконка если ingot не найден)
func _ingot_path(material: String) -> String:
	var mat: String = _ingot_material(material)
	var ingot_path := "res://assets/professions/blacksmith/%s_ingot.png" % mat
	if ResourceLoader.exists(ingot_path):
		return ingot_path
	# Fallback: используем weapon-иконку
	var weapon_path := "res://assets/loot_icons/%s_weapon.png" % mat
	if ResourceLoader.exists(weapon_path):
		return weapon_path
	return ""

func _ingot_material(material: String) -> String:
	return _MATERIAL_MAP.get(material, _DEFAULT_INGOT)

func _clear_slots() -> void:
	for c in get_children():
		if c == _bg:
			continue
		if c is ColorRect and c != get_child(0):
			c.queue_free()
		elif c is TextureRect and c != _bg:
			c.queue_free()
		elif c is Button:
			c.queue_free()
		elif c is Label and c.position.y < 50:
			pass  # не удалять заголовок

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	closed.emit()
	queue_free()
