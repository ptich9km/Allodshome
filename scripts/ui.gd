extends CanvasLayer
class_name GameUI

@onready var spell_grid: GridContainer = $BottomPanel/SpellPanel/SpellGrid
@onready var bottom_panel: Control = $BottomPanel
@onready var spell_panel: Control = $BottomPanel/SpellPanel
@onready var inventory_panel: Control = $BottomPanel/InventoryPanel
@onready var inventory_grid: GridContainer = $BottomPanel/InventoryPanel/InventoryScroll/InventoryGrid
@onready var pause_label: Label = $PauseLabel
@onready var stats_label: Label = $StatsBorder/StatsLabel
@onready var portrait_texture: TextureRect = $PortraitBorder/PortraitTexture
@onready var hero_name_label: Label = $HeroName
@onready var minimap_rect: ColorRect = $MinimapBorder/MinimapRect
@onready var coords_label: Label = $CoordsLabel

# Правые панели — двигаем при смене размера окна (колонка 176px у правого края)
@onready var right_panels: Array = [
	$MinimapBorder, $HeroName,
	$PortraitBorder, $StatsBorder, $CommandL, $CommandBar,
]
const COL_W := 176  # ширина правой колонки (кромка 16 + поле 160)

var show_coords := false
var hero_portrait: Texture2D = null   # дефолтный портрет героя (сброс ховера)
var _hover_name := ""
var cmd_buttons: Array = []          # кнопки команд поверх commandbarr.bmp (0-3 команды, 4 координаты)
var coords_btn: Button = null

var minimap_camera: Camera2D
var alm_map = null   # CustomMap или AlmMap (группа "alm_map")
var player: Player

# Для рисования миникарты
var minimap_image: Image
var minimap_texture: ImageTexture
var _minimap_size := Vector2.ZERO
var _minimap_timer := 0.0
const MINIMAP_INTERVAL := 0.25

func setup_ui(p: Player):
	player = p

	_setup_spells()

	# Имя и портрет выбранного героя (из экрана старта)
	hero_name_label.text = Game.hero_name
	var hero_tex = load("res://assets/equipment/%s/1.png" % Game.hero_character_id)
	if hero_tex:
		portrait_texture.texture = hero_tex
		hero_portrait = hero_tex
	else:
		var tex = load("res://assets/portraits/goodorc.png")
		if tex:
			portrait_texture.texture = tex
			hero_portrait = tex

	_setup_inventory()
	refresh_spell_book()

	# Карта для миникарты: CustomMap или AlmMap (группа "alm_map", без каста — они не родственники)
	alm_map = get_tree().get_first_node_in_group("alm_map")

	_setup_minimap()
	_setup_action_buttons()
	_layout_panels()
	# При изменении размера окна — перераскладка панелей
	get_tree().root.size_changed.connect(_layout_panels)
	_update_stats()
	_update_bottom_panel_visibility()

## Адаптивная раскладка: правая колонка 176px прижата к правому краю,
## команды 2×4 — внизу по центру. На любом разрешении (1280×800, 1920×1080).
func _layout_panels() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var x0 := maxf(0.0, vw - COL_W)
	# Правые панели: меняем только X, Y из tscn остаются
	for p in right_panels:
		if is_instance_valid(p):
			p.set_anchor(SIDE_LEFT, 1.0)
			p.set_anchor(SIDE_RIGHT, 1.0)
			p.offset_left = -COL_W
			p.offset_right = 0.0
	# Команды — фиксированы внизу слева (позиции из main.tscn), не центрируются
	_apply_stats_mm_offset()
	# Нижние панели (магия/инвентарь) — по центру игрового окна любого разрешения
	_update_bottom_panel_visibility()

## Сдвиг текста характеристик в ФИЗИЧЕСКИХ миллиметрах (как отмерено линейкой
## на мониторе): 6 мм вправо, 3 мм вниз от базовой позиции (8, 6 из .tscn).
## px = мм * DPI / 25.4 — на 96 DPI это ~23px вправо и ~11px вниз.
func _apply_stats_mm_offset() -> void:
	if not is_instance_valid(stats_label):
		return
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 96
	var px_per_mm := dpi / 25.4
	var dx := int(round(6.0 * px_per_mm))
	var dy := int(round(3.0 * px_per_mm))
	var base_left := 8.0
	var base_top := 6.0
	stats_label.offset_left = base_left + dx
	stats_label.offset_top = base_top + dy
	# Не выходить за рамку панели: ширина 176, высота 288
	stats_label.offset_right = minf(176.0, stats_label.offset_left + 164.0)
	stats_label.offset_bottom = minf(288.0, stats_label.offset_top + 290.0)

# Панель заклинаний с иконками
const SPELL_CELL := 36              # ячейка магии = spellback.bmp (36x36)
const SPELL_COLS := 12              # колонок в книге (как сетка 12 в tscn)
const SPHERE_RU := {"Fire": "Огонь", "Water": "Вода", "Air": "Воздух",
	"Earth": "Земля", "Astral": "Астрал"}
var spell_buttons: Array = []       # ВСЕ ячейки (включая пустые квадратики)
var _spell_buttons_filled: Array = []  # только ячейки с заклинаниями (аляйно с names)
var inventory_visible: bool = true
var spells_visible: bool = true

func _setup_spells():
	if not spell_grid:
		print("WARNING: SpellGrid not found, skipping spell setup")
		return
	spell_grid.columns = SPELL_COLS
	spell_grid.add_theme_constant_override("h_separation", 2)
	spell_grid.add_theme_constant_override("v_separation", 2)

## Перестроить книгу магии: всегда 2 ряда по 12 ячеек = 24 книжных заклинания
## (порядок docs/rom2-ref/spells.txt). Слот 1 (1-й ряд, левая ячейка) … слот 24
## (2-й ряд, 12-я ячейка). Иконка каждой магии — реальный кадр её снаряда из
## реестра projectiles.reg (assets/projectiles/<folder>/). Выучено — иконка +
## подсказка с названием; не выучено — пустой квадрат spellback с подсказкой,
## какая магия здесь учится.
func refresh_spell_book() -> void:
	if not is_instance_valid(player):
		return
	for b in spell_buttons:
		if is_instance_valid(b):
			b.queue_free()
	spell_buttons.clear()
	_spell_buttons_filled.clear()
	_spell_button_names.clear()

	# Каноничная таблица из 24 книжных заклинаний: порядок = порядок иконок
	var slots: Array = []
	for i in range(SpellDB.BOOK_SPELLS.size()):
		slots.append({
			"name": str(SpellDB.BOOK_SPELLS[i]),
			"icon": SpellDB.projectile_icon(str(SpellDB.BOOK_SPELLS[i])),
		})
	# Прочие выученные заклинания (их дают Книги Сфер — напр. Curse/Slow/Light)
	# идут следом за каноничными 24, с иконкой свитка из базы.
	for name in player.known_spells:
		if SpellDB.book_index(str(name)) < 0:
			var ch := player.spell_charges(str(name))
			if (player.has_mana and ch == -1) or (not player.has_mana and ch > 0):
				slots.append({"name": str(name), "icon": SpellDB.icon_of(str(name))})

	for s in slots:
		var name: String = str(s["name"])
		var ch := player.spell_charges(name)
		var known: bool = (player.has_mana and ch == -1) or (not player.has_mana and ch > 0)
		_make_spell_cell(name, str(s["icon"]), known)

## Ячейка книги: фон spellback.bmp; выучено — иконка из каталога assets/spells
## (+ число зарядов свитка) и подсказка; не выучено — пустой квадрат, но тоже с
## подсказкой — какая магия сюда учится.
func _make_spell_cell(name: String, icon: String, known: bool) -> void:
	var spell := SpellDB.get_spell(name)
	var title := str(spell.get("ru", name))
	var sphere_name := SpellDB.sphere_of(name)
	var sphere := str(SPHERE_RU.get(sphere_name, sphere_name))
	var charges := player.spell_charges(name)
	var mana := SpellDB.mana_cost(name)

	if not known:
		# Пустой слот книги: подсказка показывает, какая магия здесь будет
		var cell := TextureRect.new()
		cell.custom_minimum_size = Vector2(SPELL_CELL, SPELL_CELL)
		var bgc := _spellback_tex()
		if bgc != null:
			cell.texture = bgc
			cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cell.stretch_mode = TextureRect.STRETCH_SCALE
		cell.tooltip_text = "%s\nСфера: %s\n(не выучено — выучите Книгой Магии)" % [title, sphere]
		spell_grid.add_child(cell)
		spell_buttons.append(cell)
		return

	var b := Button.new()
	b.custom_minimum_size = Vector2(SPELL_CELL, SPELL_CELL)
	b.flat = true

	var bg := TextureRect.new()
	bg.texture = _spellback_tex()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bg)

	# Иконка нужной магии из каталога assets/spells ПОВЕРХ квадрата
	if icon != "":
		var ic := TextureRect.new()
		ic.texture = load(icon)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(2, 2)
		ic.size = Vector2(SPELL_CELL - 4, SPELL_CELL - 4)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)

	b.tooltip_text = ("%s\nСфера: %s%s%s" % [title, sphere,
		(" · зарядов: %d" % charges) if charges > 0 else "",
		("\nмана: %d" % mana) if player.has_mana else ""])

	# Число зарядов свитка в ячейке (чётко читается поверх иконки)
	if charges > 0:
		var lbl := Label.new()
		lbl.text = str(charges)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lbl.offset_left = -18.0
		lbl.offset_top = -17.0
		lbl.offset_right = -1.0
		lbl.offset_bottom = -1.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lbl)

	b.pressed.connect(func(sn: String = name): _cast_spell_button(sn))
	spell_grid.add_child(b)
	spell_buttons.append(b)
	_spell_buttons_filled.append(b)
	_spell_button_names.append(name)

var _spellback: Texture2D = null
func _spellback_tex() -> Texture2D:
	if _spellback == null:
		_spellback = load("res://assets/interface/spellback.bmp")
	return _spellback

## Клик по заклинанию в книге: каст по курсору.
func _cast_spell_button(name: String) -> void:
	if not is_instance_valid(player):
		return
	var target := player.get_global_mouse_position()
	player.cast_spell(name, target)
	# обновить подписи зарядов / убрать израсходованную ячейку свитка
	refresh_spell_book()
	_update_bottom_panel_visibility()
	_update_stats()

# --- Чтение свитков МАГА: прицеливание с анимированным курсором cast/ ---

var _cast_cursor: Sprite2D = null
var _cast_frames: Array = []
var _cast_frame_t := 0.0
var _cast_frame_i := 0
var _invisible_tex: ImageTexture = null
var _scroll_hint: Label = null

## Маг дважды кликнул свиток в складе: ждём выбора цели (курсор-cast).
func _begin_scroll_targeting(item_key: String) -> void:
	var spell := SpellDB.spell_from_scroll(item_key)
	if spell == "" or not is_instance_valid(player):
		return
	Game.pending_scroll = {"spell": spell, "item_key": item_key}
	_ensure_cast_cursor()
	_hide_os_cursor()
	_update_scroll_hint(spell, true)
	SoundDB.play(7)  # ibook

## Свиток применён по цели (вызывает Game). Сброс режима + обновление склад/книги.
func _finish_scroll_targeting() -> void:
	_cancel_scroll_targeting()
	refresh_inventory()
	refresh_spell_book()
	_update_bottom_panel_visibility()
	_update_stats()

## Отмена прицеливания: свиток НЕ тратится, курсор-прицел снимается.
func _cancel_scroll_targeting() -> void:
	Game.pending_scroll = {}
	_restore_os_cursor()
	if _cast_cursor != null and is_instance_valid(_cast_cursor):
		_cast_cursor.visible = false
	if _scroll_hint != null and is_instance_valid(_scroll_hint):
		_scroll_hint.visible = false

func _ensure_cast_cursor() -> void:
	if _cast_cursor != null and is_instance_valid(_cast_cursor):
		return
	_cast_cursor = Sprite2D.new()
	_cast_cursor.name = "CastCursor"
	_cast_cursor.visible = false
	add_child(_cast_cursor)
	var dir := DirAccess.open("res://assets/cursors/cast")
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array = []
	var fn := dir.get_next()
	while fn != "":
		if fn.begins_with("sprites-") and fn.ends_with(".png"):
			names.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	names.sort()
	_cast_frames.clear()
	for nm in names:
		var tex: Variant = load("res://assets/cursors/cast/" + nm)
		if tex != null:
			_cast_frames.append(tex)
	_cast_frame_t = 0.0
	_cast_frame_i = 0

## Скрыть системный курсор: рисуем свой (анимированный) поверх.
func _hide_os_cursor() -> void:
	if _invisible_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color(0, 0, 0, 0))
		_invisible_tex = ImageTexture.create_from_image(img)
	Input.set_custom_mouse_cursor(_invisible_tex, Input.CURSOR_ARROW, Vector2.ZERO)

func _restore_os_cursor() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)

## Подсказка над нижними панелями: куда применять выбранный свиток.
func _update_scroll_hint(spell: String, on: bool) -> void:
	if _scroll_hint == null:
		_scroll_hint = Label.new()
		_scroll_hint.name = "ScrollHint"
		_scroll_hint.add_theme_font_size_override("font_size", 16)
		_scroll_hint.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
		_scroll_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_scroll_hint.add_theme_constant_override("outline_size", 4)
		_scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_scroll_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_scroll_hint)
		_scroll_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_scroll_hint.offset_top = -66.0
		_scroll_hint.offset_bottom = -42.0
	_scroll_hint.visible = on
	if not on:
		return
	var kind := SpellDB.kind_of(spell)
	var dir_text := "урона/области: укажите ВРАГА" \
		if kind in ["attack", "area", "wall"] else "себя ИЛИ союзника"
	_scroll_hint.text = ("Примените «%s» на %s (ПКМ/ESC — отмена)"
		% [str(SpellDB.get_spell(spell).get("ru", spell)), dir_text])

# Инвентарь
var inventory_slots: Array = []
var inventory_items: Array = []
var inventory_items_meta: Array = []  # исходные Dictionary предметов (для key/quality)

# Двойной клик по магическому предмету (книга/свиток) — учим/читаем.
var _magic_click_key := ""
var _magic_click_time := 0.0

## true, если это повторный клик по тому же предмету в течение 0.45 с.
func _magic_double_click(item_key: String) -> bool:
	var now := Time.get_ticks_msec()
	var hit := _magic_click_key == item_key and now - _magic_click_time < 450
	_magic_click_key = item_key
	_magic_click_time = now
	return hit

func _setup_inventory():
	# Сетка в ОДИН ряд (горизонтальный скролл), как в оригинале.
	inventory_grid.columns = 100
	var slot_bg = load("res://assets/interface/myitem.png")
	build_inventory_grid(slot_bg)

## Пересобрать сетку инвентаря после покупки/продажи/лута/зелья.
func refresh_inventory() -> void:
	for s in inventory_slots:
		if is_instance_valid(s):
			s.queue_free()
	inventory_slots.clear()
	inventory_items.clear()
	inventory_items_meta.clear()
	var slot_bg = load("res://assets/interface/myitem.png")
	build_inventory_grid(slot_bg)

func build_inventory_grid(slot_bg: Texture2D) -> void:
	if not is_instance_valid(player):
		return
	inventory_grid.columns = 100   # один ряд (скролл вправо)
	# Склад: подсчёт одинаковых предметов (стак) для счётчика в углу
	var counts := {}
	for key in player.inventory:
		var k := str(key)
		counts[k] = int(counts.get(k, 0)) + 1
	# Книги и свитки лежат в складе как обычные предметы (купить в лавке) и
	# учатся/читаются двойным кликом по ячейке; книга одного заклинания
	# синтезируется (в item_db её нет — там только 5 книг стихий).
	for key in player.inventory:
		var item := ItemDB.find(str(key))
		if item.is_empty():
			item = SpellDB.book_item(str(key))
			if item.is_empty():
				continue
		_add_inventory_slot(item, slot_bg, int(counts[str(key)]))
	if inventory_slots.is_empty():
		var lab := Label.new()
		lab.text = "Склад пуст"
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		inventory_grid.add_child(lab)

## Создать слот инвентаря для предмета item (экипировка или магия).
## count>1 — показать количество стека в правом верхнем углу (как у разработчиков).
func _add_inventory_slot(item: Dictionary, slot_bg: Texture2D, count: int = 0) -> void:
	var slot = TextureRect.new()
	slot.custom_minimum_size = Vector2(68, 68)
	slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.stretch_mode = TextureRect.STRETCH_SCALE
	if slot_bg:
		slot.texture = slot_bg
	else:
		slot.modulate = Color(0.15, 0.15, 0.15, 1.0)
	inventory_grid.add_child(slot)
	inventory_slots.append(slot)
	inventory_items.append(item)
	inventory_items_meta.append(item)

	var gear := {
		"slot": ItemDB.slot_of(item),
		"weapon": ItemDB.weapon_kind(item),
		"two_handed": ItemDB.is_two_handed(item),
		"armor": ItemDB.armor_kind(item),
	}
	_add_item(inventory_slots.size() - 1, str(item.get("icon", "")), str(item.get("name_ru", "")), gear)

	# Счётчик количества (стак/деньги) в правом верхнем углу слота
	if count > 1:
		var cnt := Label.new()
		cnt.text = str(count)
		cnt.add_theme_font_size_override("font_size", 12)
		cnt.add_theme_color_override("font_color", Color(1, 0.9, 0.45))
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		cnt.add_theme_constant_override("outline_size", 4)
		cnt.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		cnt.offset_left = -24.0
		cnt.offset_top = 0.0
		cnt.offset_right = -2.0
		cnt.offset_bottom = 18.0
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cnt)

## Обработчик клика по предмету — экипировать героя / изучить магию.
func _on_item_clicked(item: Dictionary):
	if not is_instance_valid(player):
		return
	var quality := str(item.get("quality", ""))
	var item_key := str(item.get("key", ""))

	# Магические предметы: книга (маг) или свиток (любой). Учатся/читаются
	# ДВОЙНЫМ кликом по ячейке склада; предмет при этом расходуется.
	# Имена: ключ "Book Fire Arrow"/"Scroll Fire Ball" — SpellDB их распознаёт.
	if quality == "Book":
		if not _magic_double_click(item_key):
			return
		if player.learn_book(item_key):
			SoundDB.play(7)  # ibook
			refresh_inventory()
			refresh_spell_book()
			_update_bottom_panel_visibility()
			_update_stats()
		else:
			print("Книги магии читает только маг (и заклинание должно быть новым).")
		return
	if quality in ["Scroll", "SuperScroll"]:
		if not _magic_double_click(item_key):
			return
		# Маг читает свиток ПРИЦЕЛЬНО (курсор-прицел, применяет 1 раз по цели);
		# не-маг копит заряд в панели магии.
		if player.has_mana:
			_begin_scroll_targeting(item_key)
			return
		if player.read_scroll(item_key):
			SoundDB.play(7)  # ibook
			refresh_inventory()
			refresh_spell_book()
			_update_bottom_panel_visibility()
			_update_stats()
		return

	# Зелья: лечение/мана из склада
	if quality == "Potion":
		_use_potion(item_key, item)
		return

	var slot := str(item.get("slot", ""))
	if slot == "armor":
		player.armor_kind = str(item.get("armor", "light"))
	elif slot == "weapon":
		player.weapon = str(item.get("weapon", "sword"))
		player.two_handed = bool(item.get("two_handed", false))
		player.has_shield = false
	elif slot == "shield":
		if player.two_handed:
			print("Щит нельзя с двуручным оружием!")
			return
		player.has_shield = true
	player.refresh_animation()
	_update_stats()
	print("Экипировано: " + str(item.get("name_ru", item_key)))

## Зелья из склада: лечение/мана (объём по названию), предмет расходуется.
func _use_potion(item_key: String, item: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	var key := item_key.to_lower()
	var heal := 0
	var mana := 0
	if "healing" in key:
		heal = 60 if "big" in key else (30 if "medium" in key else 20)
	elif "mana" in key:
		mana = 50 if "big" in key else (25 if "medium" in key else 15)
	elif "regen" in key:
		heal = 15
		mana = 10
	if heal <= 0 and mana <= 0:
		return
	if not player.remove_item(item_key):
		return
	player.current_hp = mini(player.max_hp, player.current_hp + heal)
	if player.max_mana > 0:
		player.current_mana = mini(player.max_mana, player.current_mana + mana)
	SoundDB.play(11)
	refresh_inventory()
	_update_stats()
	print("Использовано: " + str(item.get("name_ru", item_key)))

func _add_item(slot_idx: int, icon_path: String, item_name: String, gear: Dictionary = {}):
	if slot_idx >= 0 and slot_idx < inventory_slots.size():
		var tex = load(icon_path)
		var slot: TextureRect = inventory_slots[slot_idx]
		if tex:
			# Иконка предмета поверх фона слота (не перехватывает клики!)
			var icon_rect = TextureRect.new()
			icon_rect.texture = tex
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(icon_rect)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var item_data: Dictionary = gear.duplicate(true)
		item_data["name"] = item_name
		item_data["icon"] = icon_path
		# Магический предмет (книга/свиток): ключ и качество для обработки
		var src: Dictionary = inventory_items_meta[slot_idx] if slot_idx < inventory_items_meta.size() else {}
		if not src.is_empty():
			item_data["key"] = str(src.get("key", ""))
			item_data["quality"] = str(src.get("quality", ""))
		inventory_items[slot_idx] = item_data

		# Кликабельный слот: наводим и нажимаем для экипировки
		slot.gui_input.connect(func(event: InputEvent, data := item_data):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_item_clicked(data))

func _setup_action_buttons():
	# Кнопки команд поверх commandbarr.bmp: 2 ряда x 4 (40x40), прозрачные,
	# с tooltip-подписями (надписи не влезают в ячейки, как в оригинале).
	var labels := [
		"Следовать", "Атаковать", "Охранять", "Стоп",
		"Координаты", "Патруль", "Разговор", "Отдых",
	]
	for i in range(labels.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(39, 39)
		b.position = Vector2(6 + (i % 4) * 40, 5 + (i / 4) * 40)
		b.size = Vector2(39, 39)
		b.flat = true
		b.tooltip_text = labels[i]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		$CommandBar.add_child(b)
		cmd_buttons.append(b)
		match i:
			0: b.pressed.connect(func(): _set_action_mode("follow"))
			1: b.pressed.connect(func(): _set_action_mode("attack"))
			2: b.pressed.connect(func(): _set_action_mode("guard"))
			3: b.pressed.connect(func(): _set_action_mode("stop"))
			4:
				b.toggle_mode = true
				coords_btn = b
				b.pressed.connect(func(): _toggle_coords())
			_:
				b.disabled = true  # остальные — заглушки (в разработке)
	coords_label.visible = false

func _set_action_mode(mode: String):
	# Сбрасываем подсветку всех командных кнопок
	for i in range(4):
		cmd_buttons[i].modulate = Color.WHITE

	match mode:
		"follow":
			cmd_buttons[0].modulate = Color.YELLOW
			Game.action_mode = "follow"
		"attack":
			cmd_buttons[1].modulate = Color.RED
			Game.action_mode = "attack"
		"guard":
			cmd_buttons[2].modulate = Color.GREEN
			Game.action_mode = "guard"
		"stop":
			Game.action_mode = "none"

func _toggle_coords():
	show_coords = not show_coords
	coords_btn.button_pressed = show_coords
	coords_label.visible = show_coords

## Портрет под курсором: враг-юнит (UnitDB picture) или здание (structures Picture).
## Если нет — портрет героя. Файлы assets/portraits/<имя>.png (lowercase).
var _portrait_cache := {}
func _hover_portrait() -> void:
	if not is_instance_valid(player):
		return
	var world := player.get_global_mouse_position()
	var pic := ""
	var hover_set := ""   # набор анимаций юнита под курсором (фолбэк-портрет)

	# 1) Юнит под курсором (монстр или житель): хит-бокс спрайта (видимая область)
	for e in Game.enemies + Game.npcs:
		if is_instance_valid(e) and Game.unit_hit_rect(e).grow(6.0).has_point(world):
			if e is Enemy or e is Npc:
				hover_set = str(e.anim_set)
			if hover_set != "":
				pic = str(UnitDB.get_set(hover_set).get("picture", ""))
			break

	# 2) Иначе здание под курсором (хитбокс структуры)
	if pic == "" and alm_map and alm_map.map_width > 0:
		var ts: int = alm_map.tile_size
		var cell := Vector2i(int(world.x) / ts, int(world.y) / ts)
		if alm_map.has_method("structure_at"):
			var h: Dictionary = alm_map.structure_at(cell)
			if not h.is_empty():
				pic = str(h.get("picture", ""))

	if pic == "":
		# Сброс на портрет героя
		if _hover_name != "":
			_hover_name = ""
			portrait_texture.texture = hero_portrait
		return

	var lower := pic.to_lower()
	if lower == _hover_name:
		return
	_hover_name = lower
	var tex: Texture2D = _portrait_cache.get(lower)
	if tex == null:
		var path := "res://assets/portraits/%s.png" % lower
		if not ResourceLoader.exists(path):
			# Портрета-файла нет: для юнитов показываем кадр его спрайта
			# (у людей файлов portraits/*.png нет — рисуем самого НПЦ).
			if hover_set != "":
				tex = UnitDB.preview_frame(hover_set)
				if tex != null:
					_portrait_cache[lower] = tex
			if tex == null:
				_hover_name = ""
				portrait_texture.texture = hero_portrait
				return
			# Кадр спрайта — в центр в оригинальном размере (без растягивания)
			portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		else:
			tex = load(path)
			if tex != null:
				_portrait_cache[lower] = tex
			# Настоящий портрет (герой/здания) — вписываем с сохранением пропорций
			portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if tex != null:
		portrait_texture.texture = tex
	else:
		portrait_texture.texture = hero_portrait

func _setup_minimap():
	# Защита от повторного вызова: раньше setup_ui вызывал это дважды
	# (напрямую и через _setup_spells) — создавался дубликат узла MinimapTex.
	if minimap_rect.get_node_or_null("MinimapTex") != null:
		return
	minimap_rect.color = Color(0, 0, 0, 0)
	# TextureRect для миникарты: размер задаётся под рамку при отрисовке
	# (см. _draw_minimap), чтобы картинка не вылезала за MinimapRect.
	var tex_rect = TextureRect.new()
	tex_rect.name = "MinimapTex"
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	minimap_rect.add_child(tex_rect)
	minimap_image = null
	minimap_texture = null

## Точки юнитов двигаются, поэтому миникарта не полностью статична, но полный
## перебор всей карты каждый кадр (65k клеток на Beach) — лишний. Обновляем
## с фиксированным шагом.
func _update_minimap(delta: float) -> void:
	_minimap_timer -= delta
	if _minimap_timer <= 0.0:
		_minimap_timer = MINIMAP_INTERVAL
		_draw_minimap()

func _draw_minimap():
	if not alm_map or not is_instance_valid(player):
		return

	var mw: int = alm_map.map_width
	var mh: int = alm_map.map_height
	if mw == 0:
		return

	# Размер рисунка = рамка MinimapRect (160x160 в tscn), а не жёсткие 190,
	# из-за которых карта вылезала на панель команд и за экран.
	var msize: Vector2 = minimap_rect.size
	var w := int(msize.x)
	var h := int(msize.y)
	if w <= 0 or h <= 0:
		return

	# Первый кадр или смена размера рамки — пересоздаём изображение/текстуру.
	if minimap_image == null or minimap_texture == null or _minimap_size != msize:
		_minimap_size = msize
		minimap_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		minimap_texture = ImageTexture.create_from_image(minimap_image)
		var tex_rect := minimap_rect.get_node_or_null("MinimapTex")
		if tex_rect:
			tex_rect.offset_right = float(w)
			tex_rect.offset_bottom = float(h)

	var ptx: int = int(player.global_position.x) / alm_map.tile_size
	var pty: int = int(player.global_position.y) / alm_map.tile_size
	var scale_x := float(w) / float(mw)
	var scale_y := float(h) / float(mh)

	minimap_image.fill(Color(0.03, 0.03, 0.04, 1.0))

	# Вся карта: цвета по типу клетки (CustomMap) или terrain (.alm)
	for ty in range(mh):
		for tx in range(mw):
			var color := _minimap_color_at(tx, ty)
			if color.a == 0.0:
				continue
			var sx := int(tx * scale_x)
			var sy := int(ty * scale_y)
			var ex := int((tx + 1) * scale_x)
			var ey := int((ty + 1) * scale_y)
			for py in range(sy, mini(ey + 1, h)):
				for px in range(sx, mini(ex + 1, w)):
					minimap_image.set_pixel(px, py, color)

	# Игрок (белая точка)
	var px := int(ptx * scale_x)
	var py := int(pty * scale_y)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := px + dx; var yy := py + dy
			if xx >= 0 and xx < w and yy >= 0 and yy < h:
				minimap_image.set_pixel(xx, yy, Color(1, 1, 1, 1))

	# Враги (красные точки)
	for enemy in Game.enemies:
		if is_instance_valid(enemy):
			var etx: int = int(enemy.global_position.x) / alm_map.tile_size
			var ety: int = int(enemy.global_position.y) / alm_map.tile_size
			var exx := int(etx * scale_x); var eyy := int(ety * scale_y)
			if exx >= 0 and exx < w and eyy >= 0 and eyy < h:
				minimap_image.set_pixel(exx, eyy, Color(1.0, 0.2, 0.2, 1.0))

	minimap_texture.update(minimap_image)
	var tex_rect2 := minimap_rect.get_node_or_null("MinimapTex")
	if tex_rect2:
		tex_rect2.texture = minimap_texture

# Цвет клетки для миникарты: CustomMap -> тип (0-7), .alm -> terrain_type
func _minimap_color_at(tx: int, ty: int) -> Color:
	if alm_map is CustomMap:
		var t: int = alm_map.tile_id_at(Vector2i(tx, ty))
		match t:
			1: return Color(0.55, 0.45, 0.3, 1.0)    # земля
			2: return Color(0.75, 0.7, 0.4, 1.0)      # песок
			3: return Color(0.15, 0.35, 0.75, 1.0)    # вода
			4: return Color(0.5, 0.45, 0.38, 1.0)     # скала
			5: return Color(0.45, 0.3, 0.2, 1.0)      # строение
			6: return Color(0.4, 0.8, 0.9, 1.0)       # НПЦ
			7: return Color(1.0, 0.85, 0.2, 1.0)      # спавн
			0: return Color(0.25, 0.55, 0.25, 1.0)    # трава
			_: return Color(0, 0, 0, 0)                # пусто
	var t2: int = alm_map.cell_type_at(tx, ty)
	match t2:
		2:
			return Color(0.15, 0.35, 0.75, 1.0)  # вода (tile3)
		1:
			return Color(0.5, 0.45, 0.38, 1.0)   # горы/холмы (tile2)
		3:
			return Color(0.7, 0.65, 0.55, 1.0)   # дорога (tile4)
		_:
			return Color(0.25, 0.55, 0.25, 1.0)   # трава (tile1)

func _update_stats():
	if not is_instance_valid(player):
		return
	var p = player

	# Производные значения (формулы как в оригинале)
	var damage_min = p.get_damage_min()
	var damage_max = p.get_damage_max()
	var defense = p.get_defense()
	var absorption = p.get_absorption()
	var attack = p.get_attack()
	var sight = p.get_sight()

	var stats = "      %s\n" % Game.hero_name
	stats += "СИЛА     %d  ЖИЗНЬ\n" % [p.body]
	stats += "ЛОВКОСТЬ %d  %d/%d\n" % [p.agility, p.current_hp, p.max_hp]
	stats += "РАЗУМ    %d  МАНА\n" % [p.mind]
	stats += "ДУХ      %d  %d/%d\n" % [p.spirit, p.current_mana, p.max_mana]
	stats += "УРОН %d-%d  ЗАЩИТА %d\n" % [damage_min, damage_max, defense]
	stats += "АТАКА   %d  ПОГЛОЩ %d\n" % [attack, absorption]
	stats += "НАВЫКИ     СОПРОТИВЛ.\n"
	stats += "МЕЧ      %d  ОГОНЬ   %d\n" % [p.blade_skill, p.get_protection_fire()]
	stats += "ТОПОР    %d  ВОДА    %d\n" % [p.axe_skill, p.get_protection_water()]
	stats += "ДУБИНА   %d  ВОЗДУХ  %d\n" % [p.bludgeon_skill, p.get_protection_air()]
	stats += "КОПЬЁ    %d  ЗЕМЛЯ   %d\n" % [p.pike_skill, p.get_protection_earth()]
	stats += "СТРЕЛЬБА %d  АСТРАЛ  %d\n" % [p.shooting_skill, p.get_protection_astral()]
	stats += "      ОБЗОР    %d\n" % [sight]
	stats += "      СКОРОСТЬ %d\n" % [int(p.move_speed)]
	stats += "НАГРУЗКА %.1f/%.0f\n" % [p.get_load(), p.load_capacity()]
	stats += "ОПЫТ     %d\n" % [p.total_experience()]
	stats_label.text = stats

func update_ui(p: Player, delta: float = 0.0):
	if not is_instance_valid(p):
		return
	_hover_portrait()

	# Отладочные координаты: позиция героя, курсора, клетки, тайл и проходимость.
	if show_coords:
		var lines := "КООРДИНАТЫ\n"
		lines += "Герой: %d, %d px\n" % [int(p.global_position.x), int(p.global_position.y)]
		var mouse := get_viewport().get_mouse_position()
		var world := p.get_global_mouse_position() if p.has_method("get_global_mouse_position") else Vector2.ZERO
		lines += "Мышь: %d, %d px\n" % [int(mouse.x), int(mouse.y)]
		if alm_map:
			var ts: int = alm_map.tile_size
			var tc := Vector2i(int(p.global_position.x) / ts, int(p.global_position.y) / ts)
			var mc := Vector2i(int(world.x) / ts, int(world.y) / ts)
			lines += "Клетка героя: %d, %d\n" % [tc.x, tc.y]
			lines += "Клетка мыши: %d, %d\n" % [mc.x, mc.y]
			var walk_h: bool = alm_map.is_walkable_world(p.global_position)
			lines += "Проход героя: %s\n" % ("да" if walk_h else "НЕТ")
			var walk_m: bool = alm_map.is_walkable_world(world)
			lines += "Проход мыши: %s\n" % ("да" if walk_m else "НЕТ")
			if mc.x >= 0 and mc.y >= 0 and mc.x < alm_map.map_width and mc.y < alm_map.map_height:
				var t: int = alm_map.cell_type_at(mc.x, mc.y)
				var names := ["Трава (tile1)", "Горы (tile2 — проходимо, медленно)", "Вода (tile3)", "Дорога (tile4)"]
				lines += "Тайл мыши: %s\n" % (names[t] if t >= 0 and t < names.size() else str(t))
				if not walk_m and alm_map.has_method("blocked_reason"):
					var reason: String = alm_map.call("blocked_reason", mc)
					if reason != "":
						lines += "Занято: %s\n" % reason
				if alm_map.has_method("flag_at_world"):
					var fl: int = alm_map.flag_at_world(world)
					lines += "Флаг: %d (0 зем/1 холм/2 вода/3 выс/4 барьер)\n" % fl
		coords_label.text = lines

	# Подсветка кнопок книги заклинаний: доступно/недостаточно маны или зарядов
	for i in range(_spell_buttons_filled.size()):
		var button = _spell_buttons_filled[i] as Button
		if button == null:
			continue
		if i < _spell_button_names.size():
			var sn: String = str(_spell_button_names[i])
			if player.can_cast(sn):
				button.modulate = Color.WHITE
				button.disabled = false
			else:
				button.modulate = Color(1, 1, 1, 0.45)
				button.disabled = true
		else:
			button.modulate = Color(1, 1, 1, 0.3)

	_update_minimap(delta)

var _spell_button_names: Array = []

func cast_ability(index: int):
	# Больше не используется (кнопки кастуют через _cast_spell_button)
	pass

func _process(_delta):
	if Game.is_paused:
		pause_label.visible = true
		pause_label.text = "ТАКТИЧЕСКАЯ ПАУЗА"
	else:
		pause_label.visible = false

	# Анимированный курсор-прицел свитка следует за мышью
	if not Game.pending_scroll.is_empty() and _cast_cursor != null:
		_cast_cursor.global_position = get_viewport().get_mouse_position()
		if _cast_frames.size() > 0:
			_cast_frame_t += _delta
			if _cast_frame_t >= 0.06:
				_cast_frame_t = 0.0
				_cast_frame_i = (_cast_frame_i + 1) % _cast_frames.size()
				_cast_cursor.texture = _cast_frames[_cast_frame_i]
			if _cast_cursor.texture == null:
				_cast_cursor.texture = _cast_frames[0]
		_cast_cursor.visible = true
	else:
		if _cast_cursor != null and is_instance_valid(_cast_cursor):
			_cast_cursor.visible = false

func toggle_inventory():
	inventory_visible = !inventory_visible
	_update_bottom_panel_visibility()

func toggle_spells():
	spells_visible = !spells_visible
	_update_bottom_panel_visibility()

# Магия (B) и инвентарь (I) — независимые панели.
# Обе видны: магия сверху, инвентарь снизу. Контейнер подгоняется под контент.
func _update_bottom_panel_visibility():
	spell_panel.visible = spells_visible
	inventory_panel.visible = inventory_visible

	var any_visible = spells_visible or inventory_visible
	bottom_panel.visible = any_visible
	if not any_visible:
		return

	# Магия и инвентарь — полоса 720px ПО ЦЕНТРУ игрового окна (на любом
	# разрешении), чтобы панель магии была над игроком, а не в углу.
	var vw := get_viewport().get_visible_rect().size.x
	var vh := get_viewport().get_visible_rect().size.y
	var bw := 720.0
	bottom_panel.offset_left = (vw - bw) / 2.0
	bottom_panel.offset_right = bottom_panel.offset_left + bw

	# Высота книги заклинаний: по числу строк сетки ячеек 36px (минимум 12),
	# но не ниже фона 90px. Маг после выучивания многих книг — книга растёт вверх.
	var n := spell_buttons.size()
	if n <= 0:
		n = 12
	var rows := maxi(1, ceili(float(n) / float(SPELL_COLS)))
	var spell_h := clampf(10.0 + rows * (SPELL_CELL + 2.0), 90.0, 230.0)
	var inv_h = 95.0
	var gap = 5.0

	var book_w := 480.0
	spell_panel.offset_left = (bw - book_w) / 2.0
	spell_panel.offset_right = spell_panel.offset_left + book_w

	if spells_visible and inventory_visible:
		# Магия сверху, инвентарь снизу
		spell_panel.offset_top = 0.0
		spell_panel.offset_bottom = spell_h
		inventory_panel.offset_top = spell_h + gap
		inventory_panel.offset_bottom = spell_h + gap + inv_h
		bottom_panel.offset_top = vh - (spell_h + gap + inv_h)
	elif spells_visible:
		spell_panel.offset_top = 0.0
		spell_panel.offset_bottom = spell_h
		bottom_panel.offset_top = vh - spell_h
	else:
		inventory_panel.offset_top = 0.0
		inventory_panel.offset_bottom = inv_h
		bottom_panel.offset_top = vh - inv_h
	bottom_panel.offset_bottom = vh

# --- Экономика (P0): панели магазина / школы / таверны ---

var _shop: ShopPanel = null
var _school: SchoolPanel = null
var _inn: InnPanel = null
var _interior_pos := Vector2.ZERO   # позиция героя перед входом в здание
var _in_interior := false

## Вход в здание: герой «уходит внутрь» (скрыт на карте), выходит при закрытии.
func _enter_interior() -> void:
	if not is_instance_valid(player):
		return
	if not Game.pending_scroll.is_empty():
		_cancel_scroll_targeting()   # прицеливание свитка внутри здания не нужно
	_interior_pos = player.global_position
	player.stop_movement()          # не «ускакивает» по старой цели, пока в меню
	player.visible = false
	_in_interior = true

func _exit_interior() -> void:
	if not _in_interior:
		return
	_in_interior = false
	if is_instance_valid(player):
		player.visible = true
		# Точка выхода: исходная позиция, но на ПРОХОДИМОЙ клетке (не «в здании»)
		player.global_position = _clamp_to_walkable(_interior_pos)

## Ближайшая проходимая точка рядом с запрошенной (спираль по клеткам).
func _clamp_to_walkable(from: Vector2) -> Vector2:
	var map_node = get_tree().get_first_node_in_group("alm_map")
	if map_node == null or not map_node.has_method("is_walkable_world"):
		return from
	if map_node.is_walkable_world(from):
		return from
	var cell := Vector2i(int(from.x) / 32, int(from.y) / 32)
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var p := Vector2((cell.x + dx) * 32 + 16, (cell.y + dy) * 32 + 16)
				if map_node.is_walkable_world(p):
					return p
	return from

## Общий обработчик закрытия любой панели: показать героя у здания.
func _on_panel_closed() -> void:
	_shop = null
	_school = null
	_inn = null
	_exit_interior()

## Открыта ли какая-то панель-интерьер (клики не должны двигать героя по карте).
func is_editor_open() -> bool:
	return is_instance_valid(_shop) or is_instance_valid(_school) or is_instance_valid(_inn)

## Курсор над каким-либо элементом интерфейса (панель/кнопка/книга/инвентарь)?
## Клик по UI не должен читаться как движение/атака по карте.
func is_pointer_over_ui(screen_pos: Vector2) -> bool:
	for child in get_children():
		if child is Control and _control_contains(child, screen_pos):
			return true
	return false

func _control_contains(c: Control, p: Vector2) -> bool:
	# Вся цепочка родителей должна быть видимой (скрытые панели не блокируют)
	var cur: Control = c
	while cur is Control:
		if not cur.visible:
			return false
		cur = cur.get_parent() as Control
	if Rect2(c.global_position, c.size).has_point(p):
		return true
	for ch in c.get_children():
		if ch is Control and _control_contains(ch, p):
			return true
	return false

## Магазин: купля/продажа (клик по зданию Shop).
func open_shop() -> void:
	if _shop != null and is_instance_valid(_shop):
		return
	_enter_interior()
	_shop = ShopPanel.new()
	_shop.setup(player)
	_shop.closed.connect(_on_panel_closed)
	_shop.inventory_changed.connect(refresh_inventory)
	add_child(_shop)
	refresh_inventory()

## Школа тренировок: навыки за золото (клик по Training School).
func open_school() -> void:
	if _school != null and is_instance_valid(_school):
		return
	_enter_interior()
	_school = SchoolPanel.new()
	_school.setup(player)
	_school.closed.connect(_on_panel_closed)
	add_child(_school)

## Таверна: наём наёмников и разговоры (клик по Inn).
func open_inn() -> void:
	if _inn != null and is_instance_valid(_inn):
		return
	_enter_interior()
	_inn = InnPanel.new()
	_inn.setup(player)
	_inn.closed.connect(_on_panel_closed)
	add_child(_inn)
