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

	# Загружаем портрет героя из оригинала
	var tex = load("res://assets/portraits/goodorc.png")
	if tex:
		portrait_texture.texture = tex
		hero_portrait = tex

	_setup_inventory()

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
	
	# 2 ряда по 12 = 24 иконки заклинаний
	spell_grid.columns = 12
	
	for i in range(24):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(40, 40)
		btn.flat = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		
		# Загружаем иконку
		var icon_path = "res://assets/spells/spell_%02d.png" % i
		var tex = load(icon_path)
		if tex:
			btn.icon = tex
		else:
			# Заглушка если файл не найден
			var icon = Image.create(48, 48, false, Image.FORMAT_RGBA8)
			icon.fill(Color(0.2, 0.2, 0.3, 1.0))
			btn.icon = ImageTexture.create_from_image(icon)
		
		btn.pressed.connect(func(idx=i): cast_ability(idx))
		spell_grid.add_child(btn)
		spell_buttons.append(btn)
	
	_setup_minimap()
	_setup_action_buttons()
	_update_stats()

# Инвентарь
var inventory_slots: Array = []
var inventory_items: Array = []

func _setup_inventory():
	# Сетка с вертикальным скроллом: по 12 слотов в ряд, показываем все
	# экипируемые предметы настоящей базы (assets/items/item_db.json).
	inventory_grid.columns = 12

	var slot_bg = load("res://assets/interface/myitem.png")

	for item in ItemDB.equippable_items():
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

		var gear := {
			"slot": ItemDB.slot_of(item),
			"weapon": ItemDB.weapon_kind(item),
			"two_handed": ItemDB.is_two_handed(item),
			"armor": ItemDB.armor_kind(item),
		}
		_add_item(inventory_slots.size() - 1, str(item.get("icon", "")), str(item.get("name_ru", "")), gear)

## Обработчик клика по предмету — экипировать героя.
func _on_item_clicked(item: Dictionary):
	if not is_instance_valid(player):
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
	print("Экипировано: " + str(item.get("name", "?")))

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

	var ptx: int = int(player.global_position.x) / alm_map.tile_size()
	var pty: int = int(player.global_position.y) / alm_map.tile_size()
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
			var etx: int = int(enemy.global_position.x) / alm_map.tile_size()
			var ety: int = int(enemy.global_position.y) / alm_map.tile_size()
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

	var stats = "ИМЯ: ГЕРОЙ\n"
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
			var ts: int = alm_map.tile_size()
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

	for i in range(spell_buttons.size()):
		var button = spell_buttons[i] as Button
		if i < p.abilities.size():
			var ability = p.abilities[i]
			var ability_ready = p.ability_cooldowns[i] <= 0 and p.current_mana >= ability.mana_cost
			button.disabled = not ability_ready
			button.modulate = Color(1, 1, 1, 0.4) if not ability_ready else Color.WHITE
		else:
			# Заглушки — всегда disabled
			button.disabled = true
			button.modulate = Color(1, 1, 1, 0.3)

	_draw_minimap()

func cast_ability(index: int):
	if not player:
		return
	# Первые 3 — реальные заклинания
	if index < 3:
		var target_pos = get_viewport().get_mouse_position()
		player.cast_ability(index, target_pos)
	else:
		# Остальные 21 — заглушки
		print("Заклинание #%d — в разработке" % (index + 1))

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
