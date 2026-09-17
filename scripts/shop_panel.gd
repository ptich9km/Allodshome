class_name ShopPanel
extends CanvasLayer
## Магазин (Shop): покупка снаряжения/зелий за золото и продажа из склада
## героя. Полки: «Оружие», «Броня», «Зелья». Цены — из item_db (покупка),
## продажа — половина цены. Закрытие: кнопка «Закрыть» или ESC.

signal closed
signal inventory_changed

const SHELVES := ["Оружие", "Броня", "Зелья", "Свитки"]
const SHELF_MAX := 40   # предметов на полку (самые дешёвые)

var player: Player
var _mode := 0          # 0 покупка, 1 продажа
var _shelf := 0
var _grid: GridContainer
var _gold_label: Label
var _mode_hint: Label

static var _all_cache: Array = []   # ItemDB.all() (кэш)

func setup(p: Player) -> void:
	player = p
	layer = 10
	if _all_cache.is_empty():
		_all_cache = ItemDB.all()

	# Затемнение (блокирует клики ниже панели)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(220, 70)
	panel.size = Vector2(840, 660)
	add_child(panel)

	var title := Label.new()
	title.text = "МАГАЗИН"
	title.position = Vector2(20, 14)
	title.size = Vector2(300, 32)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	panel.add_child(title)

	_gold_label = Label.new()
	_gold_label.position = Vector2(330, 20)
	_gold_label.size = Vector2(220, 28)
	_gold_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(_gold_label)

	_mode_hint = Label.new()
	_mode_hint.position = Vector2(560, 20)
	_mode_hint.size = Vector2(260, 28)
	_mode_hint.add_theme_font_size_override("font_size", 15)
	panel.add_child(_mode_hint)

	# Переключатели: Купить/Продать и полки
	var buy_btn := Button.new()
	buy_btn.text = "Купить"
	buy_btn.toggle_mode = true
	buy_btn.button_pressed = true
	buy_btn.position = Vector2(20, 58)
	buy_btn.size = Vector2(110, 34)
	buy_btn.pressed.connect(func(): _set_mode(0))
	panel.add_child(buy_btn)
	var sell_btn := Button.new()
	sell_btn.text = "Продать"
	sell_btn.toggle_mode = true
	sell_btn.position = Vector2(140, 58)
	sell_btn.size = Vector2(110, 34)
	sell_btn.pressed.connect(func(): _set_mode(1))
	panel.add_child(sell_btn)

	for i in range(SHELVES.size()):
		var b := Button.new()
		b.text = SHELVES[i]
		b.toggle_mode = true
		b.button_pressed = (i == 0)
		b.position = Vector2(300 + i * 130, 58)
		b.size = Vector2(120, 34)
		b.pressed.connect(func(idx=i): _set_shelf(idx))
		panel.add_child(b)
		_shelf_buttons[i] = b

	# Сетка предметов
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 104)
	scroll.size = Vector2(800, 500)
	panel.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.position = Vector2(690, 616)
	close_btn.size = Vector2(130, 36)
	close_btn.pressed.connect(close)
	panel.add_child(close_btn)

	_refresh()

var _shelf_buttons := {}

func _set_mode(m: int) -> void:
	_mode = m
	_refresh()

func _set_shelf(s: int) -> void:
	_shelf = s
	_refresh()

func _refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	if not is_instance_valid(player):
		return
	_gold_label.text = "Золото: %d" % player.gold
	_mode_hint.text = "Кликните, чтобы %s" % ("купить" if _mode == 0 else "продать")
	for i in range(_shelf_buttons.size()):
		_shelf_buttons[i].visible = (_mode == 0)
		_shelf_buttons[i].button_pressed = (i == _shelf)
	if _mode == 0:
		_build_buy_shelf(_shelf)
	else:
		_build_sell_list()
	# Обновить подписи золота в слотах
	_update_slot_gold()

## Полка покупки: предметы категории по возрастанию цены.
## Полка «Свитки» (3): свитки — всем, книги магии — только магу.
func _build_buy_shelf(kind: int) -> void:
	var pool: Array = []
	if kind == 3:
		for it in _all_cache:
			var q := str(it.get("quality", ""))
			if q not in ["Scroll", "SuperScroll"]:
				continue
			var price := int(it.get("price", 0))
			if price <= 0 or price > 60000:
				continue
			pool.append(it)
		if is_instance_valid(player) and player.has_mana:
			for spell in SpellDB.catalog_spells():
				pool.append(SpellDB.make_book_item(spell))
	else:
		for it in _all_cache:
			var q := str(it.get("quality", ""))
			if not ItemDB.is_equippable(it) and q != "Potion":
				continue
			var slot := ItemDB.slot_of(it)
			match kind:
				0:
					if slot != "weapon":
						continue
				1:
					if slot == "weapon" or q == "Potion":
						continue
				2:
					if q != "Potion":
						continue
			var price := int(it.get("price", 0))
			if price <= 0 or price > 60000:
				continue   # без бесплатных и «непродаваемых»
			pool.append(it)
	pool.sort_custom(func(a, b): return int(a.get("price", 0)) < int(b.get("price", 0)))
	var shown := mini(SHELF_MAX, pool.size())
	for i in range(shown):
		var it: Dictionary = pool[i]
		_add_shop_slot(it, int(it.get("price", 0)), true)

## Список продажи: владения героя.
func _build_sell_list() -> void:
	if player.inventory.is_empty():
		var lab := Label.new()
		lab.text = "Склад пуст — продавать нечего."
		lab.add_theme_font_size_override("font_size", 16)
		_grid.add_child(lab)
		return
	var seen := {}
	for key in player.inventory:
		var item := ItemDB.find(str(key))
		if item.is_empty():
			continue
		var k := str(key)
		seen[k] = seen.get(k, 0) + 1
	for key in seen:
		var item := ItemDB.find(str(key))
		var price := maxi(1, int(item.get("price", 0)) / 2)
		_add_shop_slot(item, price, false, int(seen[key]))

## Слот: иконка предмета + кнопка действия (купить/продать).
func _add_shop_slot(item: Dictionary, price: int, buying: bool, count: int = 1) -> void:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(120, 92)
	cell.add_theme_constant_override("separation", 2)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(str(item.get("icon", "")))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)

	var btn := Button.new()
	btn.text = "%s%d" % ["Купить" if buying else "Продать", price]
	if count > 1:
		btn.text += " ×%d" % count
	btn.tooltip_text = str(item.get("name_ru", ""))
	var key := str(item.get("key", ""))
	btn.pressed.connect(func():
		if buying:
			_buy_item(key, price)
		else:
			_sell_item(key, price))
	cell.add_child(btn)
	_grid.add_child(cell)

func _buy_item(key: String, price: int) -> void:
	if not is_instance_valid(player):
		return
	if player.gold < price:
		print("Не хватает золота!")
		return
	player.gold -= price
	player.add_item(key)
	SoundDB.play(9)
	inventory_changed.emit()
	_refresh()
	print("Куплено: " + key)

func _sell_item(key: String, price: int) -> void:
	if not is_instance_valid(player):
		return
	if not player.remove_item(key):
		return
	player.gold += price
	SoundDB.play(9)
	inventory_changed.emit()
	_refresh()
	print("Продано: " + key)

func _update_slot_gold() -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	closed.emit()
	queue_free()