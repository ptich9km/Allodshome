class_name InventoryPanel
extends CanvasLayer
## Модальное окно «Инвентарь и Экипировка»: кукла + 10 слотов + инвентарь + тултипы.
##
## Паттерн identical ShopPanel/InnPanel: CanvasLayer → dim → DesignRoot → content.
## Открывается через GameUI.open_inventory_panel(), закрывается по Esc / кнопке.

signal closed
signal inventory_changed

const _DESIGN_SIZE := Vector2(1024, 768)
const _CLOSE_SIZE := Vector2(170, 44)
const _CLOSE_POSITION := Vector2(840, 720)
const EQUIP_SLOT_SIZE := Vector2(54, 54)

var player: Player
var _panel_root: Control
var _previous_focus: Control
var _equip_slots := {}          # slot -> {panel: Control, icon: TextureRect}
var _doll: TextureRect = null
var _highlight_slot := ""       # пустой слот для подсветки подходящих предметов
var _inventory_slots: Array = []  # PanelContainer'ы ячеек инвентаря
var _inventory_items: Array = []  # Dictionary предметов по индексу
var _hover_card: PanelContainer = null
var _gold_label: Label


func setup(p: Player) -> void:
	player = p
	layer = 10
	_build_ui()


func _ready() -> void:
	_previous_focus = UiKit.save_focus(self)
	UiKit.bind_resize(get_viewport(), _update_layout)
	_refresh()
	if _equip_slots.has("weapon"):
		var cell: Dictionary = _equip_slots["weapon"]
		if cell.has("panel") and is_instance_valid(cell.panel):
			cell.panel.call_deferred("grab_focus")


func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)


func _input(event: InputEvent) -> void:
	if UiKit.esc_pressed(event):
		close()
		set_input_as_handled()


func close() -> void:
	UiKit.restore_focus(_previous_focus)
	closed.emit()
	queue_free()


func _update_layout() -> void:
	if is_instance_valid(_panel_root):
		UiKit.fit_design_root(_panel_root, _DESIGN_SIZE)


# ─────────────────────── UI build ───────────────────────

func _make_theme() -> Theme:
	var theme := UiKit.base_theme()
	UiKit.add_title(theme, &"InvTitle")
	UiKit.add_gold_label(theme, &"InvGoldLabel")
	UiKit.add_slot(theme, &"EquipSlot")
	theme.set_stylebox("panel", &"EquipSlotActive", UiKit.panel_style(
		Color(0.18, 0.14, 0.10, 0.95), UiKit.DIALOG_BORDER, 4, 3))
	UiKit.add_slot(theme, &"InvSlot")
	UiKit.add_button(theme, &"InvClose",
		Color(0.24, 0.13, 0.07, 0.96), Color(0.70, 0.40, 0.14),
		Color(0.36, 0.19, 0.08, 0.98), Color(1.0, 0.74, 0.26))
	UiKit.apply_scrollbar(theme)
	return theme


func _build_ui() -> void:
	var dim := UiKit.make_dim(0.58)
	add_child(dim)

	_panel_root = Control.new()
	_panel_root.name = "DesignRoot"
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.size = _DESIGN_SIZE
	_panel_root.theme = _make_theme()
	add_child(_panel_root)

	# Заголовок
	var title := Label.new()
	title.theme_type_variation = &"InvTitle"
	title.text = "ИНВЕНТАРЬ И ЭКИПИРОВКА"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 12.0
	title.offset_bottom = 48.0
	title.offset_left = 300.0
	title.offset_right = -200.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(title)

	# Золото
	_gold_label = Label.new()
	_gold_label.theme_type_variation = &"InvGoldLabel"
	_gold_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gold_label.offset_left = -220.0
	_gold_label.offset_top = 16.0
	_gold_label.offset_right = -30.0
	_gold_label.offset_bottom = 44.0
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_gold_label)

	# Кнопка «Закрыть»
	var close_btn := Button.new()
	close_btn.name = "Close"
	close_btn.text = "Закрыть"
	close_btn.custom_minimum_size = _CLOSE_SIZE
	close_btn.position = _CLOSE_POSITION
	close_btn.size = _CLOSE_SIZE
	close_btn.theme_type_variation = &"InvClose"
	close_btn.pressed.connect(close)
	_panel_root.add_child(close_btn)

	# Левая половина: кукла + слоты экипировки
	_build_equipment_area()

	# Правая половина: инвентарь
	_build_inventory_area()

	_refresh()


# ─────────────────────── Экипировка ───────────────────────

func _build_equipment_area() -> void:
	var container := CenterContainer.new()
	container.set_anchors_preset(Control.PRESET_CUSTOM)
	container.offset_left = 20.0
	container.offset_top = 60.0
	container.offset_right = 500.0
	container.offset_bottom = 710.0
	_panel_root.add_child(container)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	container.add_child(row)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	row.add_child(left_col)
	var mid_col := VBoxContainer.new()
	mid_col.add_theme_constant_override("separation", 8)
	row.add_child(mid_col)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	row.add_child(right_col)

	# Кукла
	_doll = TextureRect.new()
	_doll.texture = load("res://assets/equipment/%s/1.png" % Game.hero_character_id) \
		if ResourceLoader.exists("res://assets/equipment/%s/1.png" % Game.hero_character_id) \
		else null
	_doll.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_doll.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_doll.custom_minimum_size = Vector2(130, 200)
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for slot in ["weapon", "shield", "hands", "cloak"]:
		left_col.add_child(_make_equip_slot(slot))
	mid_col.add_child(_make_equip_slot("head"))
	mid_col.add_child(_doll)
	mid_col.add_child(_make_equip_slot("body"))
	for slot in ["amulet", "ring1", "ring2", "feet"]:
		right_col.add_child(_make_equip_slot(slot))


func _make_equip_slot(slot: String) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	wrapper.add_theme_constant_override("separation", 2)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"EquipSlot"
	panel.custom_minimum_size = EQUIP_SLOT_SIZE
	panel.focus_mode = Control.FOCUS_ALL
	panel.tooltip_text = ItemDB.slot_title(slot)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	panel.gui_input.connect(_on_slot_input.bind(slot))
	panel.focus_entered.connect(func(): _on_slot_focus(slot, true))
	panel.focus_exited.connect(func(): _on_slot_focus(slot, false))
	_attach_slot_card(panel, slot)
	_equip_slots[slot] = {"panel": panel, "icon": icon}
	wrapper.add_child(panel)

	# Подпись слота
	var label := Label.new()
	label.text = ItemDB.slot_title(slot)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(label)

	return wrapper


func _on_slot_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_slot_clicked(slot)


func _on_slot_focus(slot: String, entered: bool) -> void:
	if not entered and _highlight_slot == slot:
		_set_slot_highlight("")
	elif entered and str(player.equipped.get(slot, "")) == "":
		_set_slot_highlight(slot)


func _on_slot_clicked(slot: String) -> void:
	if not is_instance_valid(player):
		return
	var key := str(player.equipped.get(slot, ""))
	if key != "":
		if player.unequip_slot(slot):
			if not player.has_item(key):
				player.add_item(key)
			SoundDB.play(6)
			_set_slot_highlight("")
			_refresh_inventory_grid()
			inventory_changed.emit()
		return
	if _highlight_slot == slot:
		_set_slot_highlight("")
	else:
		_set_slot_highlight(slot)


func _set_slot_highlight(slot: String) -> void:
	_highlight_slot = slot
	for s in ItemDB.EQUIP_SLOTS:
		var cell: Dictionary = _equip_slots.get(s, {})
		if cell.is_empty():
			continue
		var panel: PanelContainer = cell.panel
		if s == slot:
			panel.theme_type_variation = &"EquipSlotActive"
		else:
			panel.theme_type_variation = &"EquipSlot"
	_refresh_inventory_grid()


func _item_matches_slot(item: Dictionary) -> bool:
	if _highlight_slot == "":
		return true
	return ItemDB.fits_slot(item, _highlight_slot)


func _refresh_equipment() -> void:
	if not is_instance_valid(player) or _equip_slots.is_empty():
		return
	for slot in ItemDB.EQUIP_SLOTS:
		var cell: Dictionary = _equip_slots[slot]
		var icon_rect: TextureRect = cell.icon
		var key := str(player.equipped.get(slot, ""))
		if key == "":
			icon_rect.texture = null
		else:
			var it := ItemDB.find(key)
			icon_rect.texture = load(str(it.get("icon", ""))) if not it.is_empty() else null


# ─────────────────────── Инвентарь ───────────────────────

const INV_SLOT := 62
const INV_GAP := 4
const INV_MARGIN := 10

var _inventory_grid: GridContainer
var _inventory_scroll: ScrollContainer

func _build_inventory_area() -> void:
	var container := VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_CUSTOM)
	container.offset_left = 520.0
	container.offset_top = 60.0
	container.offset_right = 1010.0
	container.offset_bottom = 710.0
	container.add_theme_constant_override("separation", 6)
	_panel_root.add_child(container)

	# Заголовок «Инвентарь»
	var inv_title := Label.new()
	inv_title.text = "СКЛАД"
	inv_title.add_theme_font_size_override("font_size", 16)
	inv_title.add_theme_color_override("font_color", UiKit.TITLE_COLOR)
	inv_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(inv_title)

	# Сетка инвентаря с прокруткой
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	container.add_child(scroll)
	_inventory_scroll = scroll

	var grid := GridContainer.new()
	grid.columns = _inventory_columns()
	grid.add_theme_constant_override("h_separation", INV_GAP)
	grid.add_theme_constant_override("v_separation", INV_GAP)
	scroll.add_child(grid)
	_inventory_grid = grid


func _inventory_columns() -> int:
	var w := 490.0  # ширина доступной области
	var usable := w - INV_MARGIN * 2.0
	return maxi(1, int((usable + INV_GAP) / float(INV_SLOT + INV_GAP)))


func _refresh_inventory_grid() -> void:
	for s in _inventory_slots:
		if is_instance_valid(s):
			s.queue_free()
	_inventory_slots.clear()
	_inventory_items.clear()

	if not is_instance_valid(player):
		return

	# Подсчёт стаков
	var counts := {}
	for key in player.inventory:
		var k := str(key)
		counts[k] = int(counts.get(k, 0)) + 1

	for key in player.inventory:
		var item := ItemDB.find(str(key))
		if item.is_empty():
			continue
		_add_inventory_slot(item, int(counts[str(key)]))

	if _inventory_slots.is_empty():
		var lab := Label.new()
		lab.text = "Склад пуст"
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		_inventory_grid.add_child(lab)

	# Обновить золото
	if _gold_label != null and is_instance_valid(player):
		_gold_label.text = "Золото: %d" % player.gold


func _add_inventory_slot(item: Dictionary, count: int = 0) -> void:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"InvSlot"
	slot.custom_minimum_size = Vector2(INV_SLOT, INV_SLOT)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	_attach_item_card(slot, item)

	if _highlight_slot != "" and not _item_matches_slot(item):
		slot.modulate = Color(1, 1, 1, 0.30)

	_inventory_grid.add_child(slot)
	_inventory_slots.append(slot)
	_inventory_items.append(item)

	# Иконка
	var icon_path := str(item.get("icon", ""))
	if icon_path != "":
		var tex = load(icon_path)
		if tex:
			var icon_rect := TextureRect.new()
			icon_rect.texture = tex
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_rect.offset_left = 4.0
			icon_rect.offset_top = 4.0
			icon_rect.offset_right = -4.0
			icon_rect.offset_bottom = -4.0
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(icon_rect)

	# Счётчик стака
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

	# Клик: экипировать / использовать
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_item_clicked(item))


func _on_item_clicked(item: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	var quality := str(item.get("quality", ""))
	var item_key := str(item.get("key", ""))

	if quality == "Herb":
		return
	if quality == "Book":
		if player.learn_book(item_key):
			SoundDB.play(7)
			_refresh_inventory_grid()
			_refresh_equipment()
			inventory_changed.emit()
		return
	if quality in ["Scroll", "SuperScroll"]:
		if player.read_scroll(item_key):
			SoundDB.play(7)
			_refresh_inventory_grid()
			inventory_changed.emit()
		return
	if quality == "Potion":
		var key_l := item_key.to_lower()
		var heal := 0
		var mana := 0
		if "healing" in key_l:
			heal = 60 if "big" in key_l else (30 if "medium" in key_l else 20)
		elif "mana" in key_l:
			mana = 50 if "big" in key_l else (25 if "medium" in key_l else 15)
		elif "regen" in key_l:
			heal = 15; mana = 10
		if heal > 0 or mana > 0:
			if player.remove_item(item_key):
				player.current_hp = mini(player.max_hp, player.current_hp + heal)
				if player.max_mana > 0:
					player.current_mana = mini(player.max_mana, player.current_mana + mana)
				SoundDB.play(11)
				_refresh_inventory_grid()
				inventory_changed.emit()
		return

	# Экипировка
	var slot := str(item.get("slot", ""))
	if slot == "shield" and player.two_handed:
		return
	if player.equip_item(item):
		_set_slot_highlight("")
		_refresh_inventory_grid()
		_refresh_equipment()
		inventory_changed.emit()
	else:
		_refresh_inventory_grid()


# ─────────────────────── Hover cards ───────────────────────

func _ensure_card() -> PanelContainer:
	var card := UiKit.make_hover_card(300.0)
	add_child(card)
	var theme := UiKit.base_theme()
	UiKit.add_hover_card_styles(theme)
	card.theme = theme
	return card


func _item_card_lines(item: Dictionary) -> Array:
	var lines: Array = [str(item.get("name_ru", item.get("key", "Предмет")))]
	var sub: Array[String] = []
	for f in ["quality", "material", "type"]:
		var v := str(item.get(f, ""))
		if v != "" and v != "None":
			sub.append(v)
	if not sub.is_empty():
		lines.append(" · ".join(sub))
	var stats: Array[String] = []
	var dmin := int(item.get("damage_min", 0))
	var dmax := int(item.get("damage_max", 0))
	if dmin > 0 or dmax > 0:
		stats.append("Урон %d–%d" % [dmin, dmax])
	var th := int(item.get("to_hit", 0))
	if th != 0:
		stats.append("Атака +%d" % th)
	var df := int(item.get("defence", 0))
	if df > 0:
		stats.append("Защита %d" % df)
	var ab := int(item.get("absorption", 0))
	if ab > 0:
		stats.append("Поглощение %d" % ab)
	var mc := int(item.get("magcap", 0))
	if mc > 0:
		stats.append("Магия %d" % mc)
	if not stats.is_empty():
		lines.append(" · ".join(stats))
	lines.append("Вес %.1f · Цена %d" % [float(item.get("weight", 0.0)), int(item.get("price", 0))])
	return lines


func _attach_item_card(cell: Control, item: Dictionary) -> void:
	if not is_instance_valid(cell) or item.is_empty():
		return
	cell.mouse_entered.connect(func():
		if _hover_card == null:
			_hover_card = _ensure_card()
		UiKit.show_hover_card(_hover_card, _item_card_lines(item),
			cell.global_position, _DESIGN_SIZE))
	cell.mouse_exited.connect(func():
		if _hover_card != null:
			UiKit.hide_hover_card(_hover_card))
	cell.focus_entered.connect(func():
		if _hover_card == null:
			_hover_card = _ensure_card()
		UiKit.show_hover_card(_hover_card, _item_card_lines(item),
			cell.global_position, _DESIGN_SIZE))
	cell.focus_exited.connect(func():
		if _hover_card != null:
			UiKit.hide_hover_card(_hover_card))


func _attach_slot_card(cell: Control, slot: String) -> void:
	if not is_instance_valid(cell):
		return
	cell.mouse_entered.connect(func(): _show_slot_card(cell, slot))
	cell.mouse_exited.connect(func(): _hide_slot_card())
	cell.focus_entered.connect(func(): _show_slot_card(cell, slot))
	cell.focus_exited.connect(func(): _hide_slot_card())


func _show_slot_card(cell: Control, slot: String) -> void:
	if not is_instance_valid(player):
		return
	var key := str(player.equipped.get(slot, ""))
	if key == "":
		_hide_slot_card()
		return
	var it := ItemDB.find(key)
	if it.is_empty():
		_hide_slot_card()
		return
	if _hover_card == null:
		_hover_card = _ensure_card()
	var lines: Array = _item_card_lines(it)
	lines.append("Слот: %s (клик — снять)" % ItemDB.slot_title(slot))
	UiKit.show_hover_card(_hover_card, lines, cell.global_position, _DESIGN_SIZE)


func _hide_slot_card() -> void:
	if _hover_card != null:
		UiKit.hide_hover_card(_hover_card)


# ─────────────────────── Refresh ───────────────────────

func _refresh() -> void:
	_refresh_equipment()
	_refresh_inventory_grid()
