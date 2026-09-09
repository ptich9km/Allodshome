extends CanvasLayer
class_name GameUI

@onready var hp_bar: ProgressBar = $BottomPanel/HpBar
@onready var mana_bar: ProgressBar = $BottomPanel/ManaBar
@onready var spell_panel: HBoxContainer = $SpellPanel
@onready var pause_label: Label = $PauseLabel
@onready var stats_label: Label = $StatsBorder/StatsLabel
@onready var portrait_texture: TextureRect = $PortraitBorder/PortraitTexture
@onready var minimap_rect: ColorRect = $MinimapBorder/MinimapRect
@onready var follow_btn: Button = $ActionPanel/FollowBtn
@onready var attack_btn: Button = $ActionPanel/AttackBtn
@onready var guard_btn: Button = $ActionPanel/GuardBtn
@onready var inventory_grid: GridContainer = $BottomPanel/InventoryGrid

var minimap_camera: Camera2D
var minimap_tilemap: TileMapLayer
var player: Player

# Для рисования миникарты
var minimap_image: Image
var minimap_texture: ImageTexture

func setup_ui(p: Player):
	player = p

	hp_bar.max_value = player.max_hp
	hp_bar.value = player.current_hp
	mana_bar.max_value = player.max_mana
	mana_bar.value = player.current_mana

	for i in range(player.abilities.size()):
		var ability = player.abilities[i]
		var button = Button.new()
		button.text = "%d. %s" % [i + 1, ability.name.capitalize()]
		button.custom_minimum_size = Vector2(80, 28)
		button.pressed.connect(func(): cast_ability(i))
		spell_panel.add_child(button)

	var tex = load("res://assets/sprites/hero.png")
	if tex:
		portrait_texture.texture = tex

	_setup_inventory()
	minimap_tilemap = get_tree().get_first_node_in_group("tilemap")
	_setup_minimap()
	_setup_action_buttons()
	_update_stats()

# Инвентарь
var inventory_slots: Array = []
var inventory_items: Array = []

func _setup_inventory():
	# Создаём 40 слотов (10 колонок × 4 ряда)
	inventory_grid.columns = 10
	inventory_grid.custom_minimum_size = Vector2(700, 64)
	
	for i in range(40):
		var slot = TextureRect.new()
		slot.custom_minimum_size = Vector2(48, 48)
		slot.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		slot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		slot.modulate = Color(0.15, 0.15, 0.15, 1.0)  # тёмный фон
		
		# Рамка слота
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.12, 1.0)
		style.border_color = Color(0.3, 0.3, 0.3, 1.0)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		slot.add_theme_stylebox_override("panel", style)
		
		inventory_grid.add_child(slot)
		inventory_slots.append(slot)
		inventory_items.append(null)
	
	# Добавляем стартовые предметы
	_add_item(0, "res://assets/sprites/hero.png", "Меч")
	_add_item(1, "res://assets/sprites/orc.png", "Щит")
	_add_item(5, "res://assets/sprites/slime.png", "Зелье")

func _add_item(slot_idx: int, icon_path: String, name: String):
	if slot_idx >= 0 and slot_idx < inventory_slots.size():
		var tex = load(icon_path)
		if tex:
			inventory_slots[slot_idx].texture = tex
			inventory_slots[slot_idx].modulate = Color.WHITE
		inventory_items[slot_idx] = {"name": name, "icon": icon_path}

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
	if not minimap_tilemap or not is_instance_valid(player):
		return
	
	var player_tile = Vector2i(int(player.global_position.x / 64), int(player.global_position.y / 32))
	var map_center = player_tile
	
	# Рисуем тайлы вокруг игрока
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var tile_x = map_center.x + dx
			var tile_y = map_center.y + dy
			var screen_x = 95 + dx * 9
			var screen_y = 95 + dy * 9
			
			if screen_x < 0 or screen_x >= 190 or screen_y < 0 or screen_y >= 190:
				continue
			
			# Определяем цвет тайла
			var color = Color(0, 0, 0, 0)
			# Трава — зелёный, стена — серый
			var dist = abs(tile_x) + abs(tile_y)
			if dist <= 7:
				color = Color(0.2, 0.6, 0.15, 0.8)
			elif dist == 8:
				color = Color(0.4, 0.35, 0.3, 0.8)
			
			if color.a > 0:
				for py in range(screen_y - 3, screen_y + 4):
					for px in range(screen_x - 3, screen_x + 4):
						if py >= 0 and py < 190 and px >= 0 and px < 190:
							minimap_image.set_pixel(px, py, color)
	
	# Рисуем игрока (синяя точка)
	var px = 95
	var py = 95
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if py+dy >= 0 and py+dy < 190 and px+dx >= 0 and px+dx < 190:
				minimap_image.set_pixel(px+dx, py+dy, Color(0.2, 0.4, 1.0, 1.0))
	
	# Рисуем врагов (красные точки)
	for enemy in Game.enemies:
		if is_instance_valid(enemy):
			var etx = int((enemy.global_position.x - player.global_position.x) / 64) + 95
			var ety = int((enemy.global_position.y - player.global_position.y) / 32) + 95
			if etx >= 0 and etx < 190 and ety >= 0 and ety < 190:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						minimap_image.set_pixel(etx+dx, ety+dy, Color(1.0, 0.2, 0.2, 1.0))
	
	minimap_texture.update(minimap_image)
	var tex_rect = minimap_rect.get_node_or_null("MinimapTex")
	if tex_rect:
		tex_rect.texture = minimap_texture

func _update_stats():
	if not is_instance_valid(player):
		return
	var p = player
	var stats = "ИМЯ: ГЕРОЙ\n"
	stats += "═══════════════\n"
	stats += "СИЛА:        %d\n" % p.strength
	stats += "ЛОВКОСТЬ:    %d\n" % p.agility
	stats += "ИНТЕЛЛЕКТ:   %d\n" % p.intellect
	stats += "ВЫНОСЛИВОСТЬ:%d\n" % p.endurance
	stats += "ДУХ:         %d\n" % p.spirit
	stats += "═══════════════\n"
	stats += "УРОН:        %d-%d\n" % [p.strength, p.strength + 5]
	stats += "БРОНЯ:       %d\n" % (p.endurance / 2)
	stats += "ЗАЩИТА:      %d\n" % (p.endurance / 3)
	stats += "ОПЫТ:        0\n"
	stats += "СКОРОСТЬ:    %d\n" % int(p.move_speed)
	stats_label.text = stats

func update_ui(p: Player):
	if not is_instance_valid(p):
		return
	hp_bar.value = p.current_hp
	mana_bar.value = p.current_mana

	for i in range(spell_panel.get_child_count()):
		if i < p.abilities.size():
			var button = spell_panel.get_child(i) as Button
			var ability = p.abilities[i]
			var ability_ready = p.ability_cooldowns[i] <= 0 and p.current_mana >= ability.mana_cost
			button.disabled = not ability_ready
			if p.ability_cooldowns[i] > 0:
				button.text = "%s (%.1fs)" % [ability.name.capitalize(), p.ability_cooldowns[i]]
			else:
				button.text = "%d. %s" % [i + 1, ability.name.capitalize()]

	_draw_minimap()

func cast_ability(index: int):
	if player:
		var target_pos = get_viewport().get_mouse_position()
		player.cast_ability(index, target_pos)

func _process(_delta):
	if Game.is_paused:
		pause_label.visible = true
		pause_label.text = "ТАКТИЧЕСКАЯ ПАУЗА"
	else:
		pause_label.visible = false
