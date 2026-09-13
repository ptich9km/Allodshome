extends CanvasLayer
class_name GameUI

@onready var spell_grid: GridContainer = $BottomPanel/SpellPanel/SpellGrid
@onready var bottom_panel: Control = $BottomPanel
@onready var spell_panel: Panel = $BottomPanel/SpellPanel
@onready var inventory_panel: Panel = $BottomPanel/InventoryPanel
@onready var inventory_grid: GridContainer = $BottomPanel/InventoryPanel/InventoryScroll/InventoryGrid
@onready var pause_label: Label = $PauseLabel
@onready var stats_label: Label = $StatsBorder/StatsLabel
@onready var portrait_texture: TextureRect = $PortraitBorder/PortraitTexture
@onready var minimap_rect: ColorRect = $MinimapBorder/MinimapRect
@onready var follow_btn: Button = $ActionPanel/FollowBtn
@onready var attack_btn: Button = $ActionPanel/AttackBtn
@onready var guard_btn: Button = $ActionPanel/GuardBtn

var minimap_camera: Camera2D
var alm_map: AlmMap
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

	_setup_inventory()

	# AlmMap для миникарты (реальные данные карты)
	alm_map = get_tree().get_first_node_in_group("alm_map") as AlmMap

	_setup_minimap()
	_setup_action_buttons()
	_update_stats()
	_update_bottom_panel_visibility()

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
	# Один ряд слотов со скроллом влево/вправо
	inventory_grid.columns = 40

	var slot_bg = load("res://assets/interface/myitem.png")

	for i in range(40):
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
		inventory_items.append(null)

	# Тестовые предметы (иконки из оригинала)
	_add_item(0, "res://assets/inventory/0001002-000.png", "Меч")
	_add_item(1, "res://assets/inventory/0014001-000.png", "Зелье")
	_add_item(2, "res://assets/inventory/0002001-000.png", "Щит")

func _add_item(slot_idx: int, icon_path: String, item_name: String):
	if slot_idx >= 0 and slot_idx < inventory_slots.size():
		var tex = load(icon_path)
		if tex:
			var slot = inventory_slots[slot_idx]
			# Иконка предмета поверх фона слота
			var icon_rect = TextureRect.new()
			icon_rect.texture = tex
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			slot.add_child(icon_rect)
		inventory_items[slot_idx] = {"name": item_name, "icon": icon_path}

func _setup_action_buttons():
	follow_btn.pressed.connect(func(): _set_action_mode("follow"))
	attack_btn.pressed.connect(func(): _set_action_mode("attack"))
	guard_btn.pressed.connect(func(): _set_action_mode("guard"))

func _set_action_mode(mode: String):
	# Сбрасываем подсветку всех кнопок
	follow_btn.modulate = Color.WHITE
	attack_btn.modulate = Color.WHITE
	guard_btn.modulate = Color.WHITE
	
	match mode:
		"follow":
			follow_btn.modulate = Color.YELLOW
			Game.action_mode = "follow"
		"attack":
			attack_btn.modulate = Color.RED
			Game.action_mode = "attack"
		"guard":
			guard_btn.modulate = Color.GREEN
			Game.action_mode = "guard"

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

	var ptx := int(player.global_position.x) / alm_map.tile_width
	var pty := int(player.global_position.y) / alm_map.tile_height
	var scale_x := 190.0 / float(mw)
	var scale_y := 190.0 / float(mh)

	minimap_image.fill(Color(0.03, 0.03, 0.04, 1.0))

	# Вся карта: трава/земля/вода/скалы по типам terrain
	for ty in range(mh):
		for tx in range(mw):
			var t := AlmLoader.terrain_type(alm_map._hflags[ty * mw + tx])
			var color: Color
			match t:
				2, -1:
					color = Color(0.15, 0.35, 0.75, 1.0)  # вода
				3, -2:
					color = Color(0.5, 0.45, 0.38, 1.0)   # скала/барьер
				1:
					color = Color(0.55, 0.45, 0.3, 1.0)   # земля
				_:
					color = Color(0.25, 0.55, 0.25, 1.0)   # трава
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
			var etx := int(enemy.global_position.x) / alm_map.tile_width
			var ety := int(enemy.global_position.y) / alm_map.tile_height
			var exx := int(etx * scale_x); var eyy := int(ety * scale_y)
			if exx >= 0 and exx < 190 and eyy >= 0 and eyy < 190:
				minimap_image.set_pixel(exx, eyy, Color(1.0, 0.2, 0.2, 1.0))

	minimap_texture.update(minimap_image)
	var tex_rect = minimap_rect.get_node_or_null("MinimapTex")
	if tex_rect:
		tex_rect.texture = minimap_texture

func _update_stats():
	if not is_instance_valid(player):
		return
	var p = player

	# Производные значения (формулы как в оригинале)
	var damage_min = p.strength
	var damage_max = p.strength + 5
	var defense = p.endurance / 2
	var absorption = p.endurance / 3
	var hp_regen = 1 + p.endurance / 10
	var mana_regen = 1 + p.spirit / 10

	var stats = "ИМЯ: ГЕРОЙ\n"
	stats += "─────────────────\n"
	stats += "СИЛА:        %d\n" % p.strength
	stats += "РАЗУМ:       %d\n" % p.intellect
	stats += "ЛОВКОСТЬ:    %d\n" % p.agility
	stats += "ДУХ:         %d\n" % p.spirit
	stats += "─────────────────\n"
	stats += "ЗДОРОВЬЕ:    %d/%d\n" % [p.current_hp, p.max_hp]
	stats += "РЕГЕН HP:    %d\n" % hp_regen
	stats += "МАНА:        %d/%d\n" % [p.current_mana, p.max_mana]
	stats += "РЕГЕН МАНЫ:  %d\n" % mana_regen
	stats += "─────────────────\n"
	stats += "АТАКА:       %d\n" % p.strength
	stats += "УРОН:        %d-%d\n" % [damage_min, damage_max]
	stats += "ЗАЩИТА:      %d\n" % defense
	stats += "ПОГЛОЩЕНИЕ:  %d\n" % absorption
	stats += "СКОРОСТЬ:    %d\n" % int(p.move_speed)
	stats += "─────────────────\n"
	stats += "ЗАЩИТА ОГОНЬ:  %d\n" % (p.spirit / 2)
	stats += "ЗАЩИТА ВОДА:   %d\n" % (p.spirit / 2)
	stats += "ЗАЩИТА ВОЗДУХ: %d\n" % (p.spirit / 2)
	stats += "ЗАЩИТА ЗЕМЛЯ:  %d\n" % (p.spirit / 2)
	stats += "ЗАЩИТА АСТРАЛ: %d\n" % (p.spirit / 2)
	stats_label.text = stats

func update_ui(p: Player):
	if not is_instance_valid(p):
		return

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
	var inv_h = 80.0
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
