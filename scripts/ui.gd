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
	$MinimapBorder, $HeadBarL, $HeadBarR, $HeroName,
	$PortraitBorder, $StatsBorder, $CommandL, $CommandBar,
]
const COL_W := 176  # ширина правой колонки (кромка 16 + поле 160)
const COL_HGAPS := [[5, 175], [180, 260], [265, 507], [512, 754]]  # y-диапазоны панелей
const CMD_Y := [690, 770]  # команды внизу по центру

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
	# Команды — по центру горизонтали
	var cmd_w := 16 + 160.0
	var cmd_x := (vw - cmd_w) / 2.0
	$CommandL.set_anchor(SIDE_LEFT, 0.0)
	$CommandL.set_anchor(SIDE_RIGHT, 0.0)
	$CommandL.offset_left = cmd_x
	$CommandL.offset_right = cmd_x + 16.0
	$CommandBar.set_anchor(SIDE_LEFT, 0.0)
	$CommandBar.set_anchor(SIDE_RIGHT, 0.0)
	$CommandBar.offset_left = cmd_x + 16.0
	$CommandBar.offset_right = cmd_x + cmd_w

# Панель заклинаний с иконками
var spell_buttons: Array = []
var inventory_visible: bool = true
var spells_visible: bool = true

func _setup_spells():
	if not spell_grid:
		print("WARNING: SpellGrid not found, skipping spell setup")
		return

	# Книга заклинаний: одна строка на заклинание; строится динамически
	# по известным заклинаниям героя (книги магов / свитки с зарядами).
	spell_grid.columns = 1

	# Заглушки пока нет героя: 1 ячейка
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(44, 44)
	btn.flat = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon = true
	btn.disabled = true
	spell_grid.add_child(btn)
	spell_buttons.append(btn)

	_setup_minimap()
	_setup_action_buttons()
	_update_stats()

## Перестроить книгу заклинаний по изученным заклинаниям героя.
func refresh_spell_book() -> void:
	if not is_instance_valid(player):
		return
	# Очищаем старые кнопки
	for b in spell_buttons:
		if is_instance_valid(b):
			b.queue_free()
	spell_buttons.clear()
	_spell_button_names.clear()
	spell_grid.columns = 1

	var spells := player.known_spell_list()
	if spells.is_empty():
		var stub = Button.new()
		stub.custom_minimum_size = Vector2(44, 44)
		stub.flat = true
		stub.text = "—"
		stub.disabled = true
		stub.tooltip_text = "Книга заклинаний пуста.\nМаги учат заклинания из книг стихий,\nвсе персонажи — из свитков."
		spell_grid.add_child(stub)
		spell_buttons.append(stub)
		return

	for name in spells:
		var spell: Dictionary = SpellDB.get_spell(name)
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.flat = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true

		# Иконка из базы заклинаний (inventory scroll icon)
		var icon_path := SpellDB.icon_of(name)
		var tex: Variant = null
		if icon_path != "":
			tex = load(icon_path)
		if tex == null:
			var fallback = load("res://assets/spells/spell_%02d.png" % (spells.find(name) % 24))
			if fallback:
				tex = fallback
		if tex != null:
			b.icon = tex

		var charges := player.spell_charges(name)
		var sphere := SpellDB.sphere_of(name)
		var mana := SpellDB.mana_cost(name)
		var title := str(spell.get("ru", name))
		if charges != 0:
			b.tooltip_text = "%s\n%s · зарядов: %d%s" % [title, sphere, charges,
				("\nмана: %d" % mana) if player.has_mana else ""]
		else:
			b.tooltip_text = "%s\n%s · мана: %d" % [title, sphere, mana]
		# Подпись количества под иконкой (charges, если свиток)
		if charges > 0:
			var lbl := Label.new()
			lbl.text = str(charges)
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
			lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			lbl.offset_left = -16.0
			lbl.offset_top = -16.0
			lbl.offset_right = -2.0
			lbl.offset_bottom = -2.0
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(lbl)

		b.pressed.connect(func(sn: String = name): _cast_spell_button(sn))
		spell_grid.add_child(b)
		spell_buttons.append(b)
		_spell_button_names.append(name)

## Клик по заклинанию в книге: каст по курсору.
func _cast_spell_button(name: String) -> void:
	if not is_instance_valid(player):
		return
	var target := player.get_global_mouse_position()
	player.cast_spell(name, target)
	# обновить подписи зарядов
	refresh_spell_book()
	_update_stats()

# Инвентарь
var inventory_slots: Array = []
var inventory_items: Array = []
var inventory_items_meta: Array = []  # исходные Dictionary предметов (для key/quality)

func _setup_inventory():
	# Сетка с вертикальным скроллом: по 12 слотов в ряд.
	# Склад владений героя + магическая витрина (книги/свитки) в конце.
	inventory_grid.columns = 12
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
	# Склад: предметы, которыми владеет герой
	for key in player.inventory:
		var item := ItemDB.find(str(key))
		if not item.is_empty():
			_add_inventory_slot(item, slot_bg)
	# Витрина магии: книги стихий (маг) и свитки (для всех) — учить/читать
	for item in ItemDB.all():
		var q := str(item.get("quality", ""))
		if q in ["Book", "Scroll", "SuperScroll"]:
			_add_inventory_slot(item, slot_bg)
	if inventory_slots.is_empty():
		var lab := Label.new()
		lab.text = "Склад пуст"
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		inventory_grid.add_child(lab)

## Создать слот инвентаря для предмета item (экипировка или магия).
func _add_inventory_slot(item: Dictionary, slot_bg: Texture2D) -> void:
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

## Обработчик клика по предмету — экипировать героя / изучить магию.
func _on_item_clicked(item: Dictionary):
	if not is_instance_valid(player):
		return
	var quality := str(item.get("quality", ""))
	var item_key := str(item.get("key", ""))

	# Магические предметы: книга стихии (маг) или свиток (любой).
	# Имена в item_db: key="Book Fire", name_ru="Book Огонь" — используем key.
	if quality == "Book":
		if player.learn_sphere_book(item_key):
			SoundDB.play(7)  # ibook
			refresh_spell_book()
			_update_stats()
		return
	if quality in ["Scroll", "SuperScroll"]:
		if player.read_scroll(item_key):
			SoundDB.play(7)  # ibook
			refresh_spell_book()
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

	# 1) Юнит под курсором (монстр или житель): хит-бокс спрайта (видимая область)
	for e in Game.enemies + Game.npcs:
		if is_instance_valid(e) and Game.unit_hit_rect(e).grow(6.0).has_point(world):
			var set_name := ""
			if e is Enemy or e is Npc:
				set_name = str(e.anim_set)
			if set_name != "":
				pic = str(UnitDB.get_set(set_name).get("picture", ""))
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
			# Портрета нет (не у всех юнитов/структур есть картинка) — герой
			_hover_name = ""
			portrait_texture.texture = hero_portrait
			return
		tex = load(path)
		if tex != null:
			_portrait_cache[lower] = tex
	if tex != null:
		portrait_texture.texture = tex
	else:
		portrait_texture.texture = hero_portrait

func _setup_minimap():
	# Создаём изображение миникарты (190x190)
	minimap_image = Image.create(190, 190, false, Image.FORMAT_RGBA8)
	minimap_texture = ImageTexture.create_from_image(minimap_image)
	minimap_rect.color = Color(0, 0, 0, 0)
	# Добавляем TextureRect для отображения
	var tex_rect = TextureRect.new()
	tex_rect.name = "MinimapTex"
	tex_rect.offset_left = 0
	tex_rect.offset_top = 0
	tex_rect.offset_right = 190
	tex_rect.offset_bottom = 190
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	minimap_rect.add_child(tex_rect)

func _draw_minimap():
	if not alm_map or not is_instance_valid(player):
		return

	var mw: int = alm_map.map_width
	var mh: int = alm_map.map_height
	if mw == 0:
		return

	var ptx: int = int(player.global_position.x) / alm_map.tile_size
	var pty: int = int(player.global_position.y) / alm_map.tile_size
	var scale_x := 190.0 / float(mw)
	var scale_y := 190.0 / float(mh)

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
			for py in range(sy, min(ey + 1, 190)):
				for px in range(sx, min(ex + 1, 190)):
					minimap_image.set_pixel(px, py, color)

	# Игрок (белая точка)
	var px := int(ptx * scale_x)
	var py := int(pty * scale_y)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := px + dx; var yy := py + dy
			if xx >= 0 and xx < 190 and yy >= 0 and yy < 190:
				minimap_image.set_pixel(xx, yy, Color(1, 1, 1, 1))

	# Враги (красные точки)
	for enemy in Game.enemies:
		if is_instance_valid(enemy):
			var etx: int = int(enemy.global_position.x) / alm_map.tile_size
			var ety: int = int(enemy.global_position.y) / alm_map.tile_size
			var exx := int(etx * scale_x); var eyy := int(ety * scale_y)
			if exx >= 0 and exx < 190 and eyy >= 0 and eyy < 190:
				minimap_image.set_pixel(exx, eyy, Color(1.0, 0.2, 0.2, 1.0))

	minimap_texture.update(minimap_image)
	var tex_rect = minimap_rect.get_node_or_null("MinimapTex")
	if tex_rect:
		tex_rect.texture = minimap_texture

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
	var hp_regen = p._calc_hp_regen()
	var mana_regen = p._calc_mana_regen()

	var stats = "ИМЯ: %s\n" % Game.hero_name
	stats += "─────────────\n"
	stats += "ТЕЛО:%d  ЛОВКОСТЬ:%d\n" % [p.body, p.agility]
	stats += "РАЗУМ:%d  ДУХ:%d\n" % [p.mind, p.spirit]
	stats += "─────────────\n"
	stats += "HP:%d/%d  РЕГЕН:%d\n" % [p.current_hp, p.max_hp, hp_regen]
	stats += "МАНА:%d/%d  РЕГЕН:%d\n" % [p.current_mana, p.max_mana, mana_regen]
	stats += "─────────────\n"
	stats += "АТАКА:%d  УРОН:%d-%d\n" % [attack, damage_min, damage_max]
	stats += "ЗАЩИТА:%d  ПОГЛОЩ:%d\n" % [defense, absorption]
	stats += "СКОРОСТЬ:%d  ОБЗОР:%d\n" % [int(p.move_speed), sight]
	stats += "─────────────\n"
	stats += "ОГОНЬ:%d  ВОДА:%d  ВОЗДУХ:%d\n" % [p.get_protection_fire(), p.get_protection_water(), p.get_protection_air()]
	stats += "ЗЕМЛЯ:%d  АСТРАЛ:%d\n" % [p.get_protection_earth(), p.get_protection_astral()]
	stats += "─────────────\n"
	stats += "МЕЧ:%d  ТОПОР:%d  ДУБИНА:%d\n" % [p.blade_skill, p.axe_skill, p.bludgeon_skill]
	stats += "КОПЬЁ:%d  СТРЕЛЬБА:%d\n" % [p.pike_skill, p.shooting_skill]
	stats += "МАГИЯ: О:%d В:%d ВО:%d ЗЕ:%d А:%d\n" % [p.fire_skill, p.water_skill, p.air_skill, p.earth_skill, p.astral_skill]
	stats_label.text = stats

func update_ui(p: Player):
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
				var names := ["Трава (tile1)", "Земля (tile2)", "Вода (tile3)", "Дорога (tile4)"]
				lines += "Тайл мыши: %s\n" % (names[t] if t >= 0 and t < names.size() else str(t))
				if alm_map.has_method("flag_at_world"):
					var fl: int = alm_map.flag_at_world(world)
					lines += "Флаг: %d (0 зем/1 холм/2 вода/3 выс/4 барьер)\n" % fl
		coords_label.text = lines

	# Подсветка кнопок книги заклинаний: доступно/недостаточно маны или зарядов
	for i in range(spell_buttons.size()):
		var button = spell_buttons[i] as Button
		if button == null:
			continue
		# Ищем заклинание по tooltip? — проще хранить список имён кнопок
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

	_draw_minimap()

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

	# Высота секций
	var spell_h = 90.0
	var inv_h = 95.0
	var gap = 5.0

	if spells_visible and inventory_visible:
		# Магия сверху, инвентарь снизу
		spell_panel.offset_top = 0.0
		spell_panel.offset_bottom = spell_h
		inventory_panel.offset_top = spell_h + gap
		inventory_panel.offset_bottom = spell_h + gap + inv_h
		bottom_panel.offset_top = 800.0 - (spell_h + gap + inv_h)
	elif spells_visible:
		spell_panel.offset_top = 0.0
		spell_panel.offset_bottom = spell_h
		bottom_panel.offset_top = 800.0 - spell_h
	else:
		inventory_panel.offset_top = 0.0
		inventory_panel.offset_bottom = inv_h
		bottom_panel.offset_top = 800.0 - inv_h

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
