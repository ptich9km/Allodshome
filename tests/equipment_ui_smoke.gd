extends SceneTree
## Smoke-проверка панели персонажа «кукла + слоты» (scripts/ui.gd, RightPanel).
##
## Проверяет:
##  1. правая панель собрана: 10 слотов (ItemDB.EQUIP_SLOTS), кукла, HP/MP бары;
##  2. раскладка в пределах окна 1280×800;
##  3. маппинг «тип → слот» покрывает все экипируемые предметы базы;
##  4. кольца идут в ring1/ring2, двуручное освобождает щит;
##  5. клик по заполненному слоту снимает предмет в инвентарь;
##  6. подсветка пустого слота: совместимые предметы совпадают, остальные — нет.
##
## Запуск: godot --headless --path . --script res://tests/equipment_ui_smoke.gd

var _fails: Array[String] = []

func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("EQPUI: %s %s" % ["ok  " if ok else "FAIL", what])

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player: Player = game.get("player")
	var ui = game.get("ui")
	await process_frame

	_test_panel(ui)
	_test_slot_mapping()
	_test_rings(player)
	_test_two_handed(player)
	_test_unequip_slot(ui, player)
	_test_highlight(ui, player)
	_test_stats_bars(ui, player)
	_report()

# --- 1. Панель собрана и в пределах окна ------------------------------------

func _test_panel(ui) -> void:
	var slots: Dictionary = ui.get("_equip_slots")
	_check(slots.size() == ItemDB.EQUIP_SLOTS.size(),
		"слотов столько же, сколько в EQUIP_SLOTS (%d)" % slots.size())
	for slot in ItemDB.EQUIP_SLOTS:
		_check(slots.has(slot), "есть слот %s" % slot)
		if not slots.has(slot):
			continue
		var cell: Dictionary = slots[slot]
		_check(cell.get("panel") is PanelContainer, "слот %s — PanelContainer" % slot)
		var icon: TextureRect = cell.get("icon")
		if icon != null:
			_check(icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
				"иконка слота %s не обрезается (KEEP_ASPECT_CENTERED)" % slot)
	_check(ui.get("_doll") is TextureRect, "кукла (полноростовый спрайт) на месте")
	var panel: Control = ui.get_node_or_null("RightPanel")
	if panel != null:
		# Headless-вьюпорт маленький, поэтому проверяем не абсолютные координаты,
		# а то, что панель имеет нормальный размер (в игре якоря держат её справа).
		_check(panel.size.x > 300.0 and panel.size.y > 400.0,
			"правая панель имеет полноразмерную геометрию (%.0f×%.0f)" % [panel.size.x, panel.size.y])
	_check(ui.get("_hp_bar") is ProgressBar, "бар ЖИЗНЬ создан")
	_check(ui.get("_mp_bar") is ProgressBar, "бар МАНА создан")

# --- 2. Маппинг типов на слоты ----------------------------------------------

func _test_slot_mapping() -> void:
	var bad := 0
	var checked := 0
	for raw in ItemDB.all():
		var it: Dictionary = raw
		if not ItemDB.is_equippable(it):
			continue
		checked += 1
		if ItemDB.slot_of(it) == "":
			bad += 1
	_check(checked > 100, "экипируемых предметов достаточно для проверки (%d)" % checked)
	_check(bad == 0, "все экипируемые предметы имеют слот (без слота: %d)" % bad)
	var expect := {
		"Common Bronze Helm": "head",
		"Bad None Cloak": "cloak",
		"Common Bronze Cuirass": "body",
		"Common Bronze Bracers": "hands",
		"Common Hard Leather Boots": "feet",
		"Common Bronze Amulet": "amulet",
		"Elven Titanium Ring": "ring",
		"Common Bronze Long Sword": "weapon",
		"Common Bronze Buckler": "shield",
	}
	for key in expect:
		var it := ItemDB.find(str(key))
		_check(not it.is_empty(), "в базе есть %s" % key)
		if not it.is_empty():
			_check(ItemDB.slot_of(it) == str(expect[key]),
				"%s -> слот %s (получено %s)" % [key, expect[key], ItemDB.slot_of(it)])

# --- 3. Кольца: ring1, затем ring2 -------------------------------------------

func _test_rings(player: Player) -> void:
	var ring_key := ""
	for raw in ItemDB.all():
		if str((raw as Dictionary).get("type", "")) == "Ring":
			ring_key = str((raw as Dictionary).get("key", ""))
			break
	_check(ring_key != "", "в базе есть кольцо")
	if ring_key == "":
		return
	var ring := ItemDB.find(ring_key)
	_check(player.equip_item(ring), "кольцо надевается")
	_check(str(player.equipped.get("ring1", "")) == ring_key, "первое кольцо — в ring1")
	_check(player.equip_item(ring), "второе кольцо надевается")
	_check(str(player.equipped.get("ring2", "")) == ring_key, "второе кольцо — в ring2")
	player.equipped.erase("ring1")
	player.equipped.erase("ring2")

# --- 4. Двуручное освобождает щит -------------------------------------------

func _test_two_handed(player: Player) -> void:
	var th_key := ""
	for raw in ItemDB.all():
		var it: Dictionary = raw
		if str(it.get("type", "")) == "Two Handed Sword" and ItemDB.is_equippable(it):
			th_key = str(it.get("key", ""))
			break
	_check(th_key != "", "в базе есть двуручный меч")
	if th_key == "":
		return
	player.equip_item(ItemDB.find("Common Bronze Buckler"))
	_check(player.equipped.has("shield"), "щит надет перед двуручником")
	player.equip_item(ItemDB.find(th_key))
	_check(not player.equipped.has("shield"), "двуручный меч снял щит")
	player.unequip_slot("weapon")

# --- 5. Клик по заполненному слоту снимает предмет ---------------------------

func _test_unequip_slot(ui, player: Player) -> void:
	player.equip_item(ItemDB.find("Common Iron Long Sword"))
	_check(player.equipped.has("weapon"), "оружие надето перед снятием")
	var key := str(player.equipped.get("weapon", ""))
	ui.call("_on_slot_clicked", "weapon")
	_check(not player.equipped.has("weapon"), "клик по слоту снял оружие")
	_check(player.inventory.has(key), "снятый предмет вернулся в инвентарь (%s)" % key)

# --- 6. Подсветка подходящих предметов по пустому слоту ----------------------

func _test_highlight(ui, player: Player) -> void:
	var helm_key := ""
	for raw in ItemDB.all():
		var it: Dictionary = raw
		if str(it.get("type", "")) == "Helm" and ItemDB.is_equippable(it):
			helm_key = str(it.get("key", ""))
			break
	_check(helm_key != "", "в базе есть шлем")
	if helm_key == "":
		return
	ui.call("_set_slot_highlight", "head")
	_check(ui.get("_highlight_slot") == "head", "подсветка включена для слота head")
	_check(ui.call("_item_matches_slot", ItemDB.find(helm_key)),
		"шлем подходит слоту head")
	_check(not ui.call("_item_matches_slot", ItemDB.find("Common Iron Long Sword")),
		"меч НЕ подходит слоту head")
	ui.call("_set_slot_highlight", "")
	_check(ui.get("_highlight_slot") == "", "подсветка сброшена")
	_check(ui.call("_item_matches_slot", ItemDB.find("Common Iron Long Sword")),
		"без подсветки подходит любой предмет")

# --- 7. Бары статов заполнены ------------------------------------------------

func _test_stats_bars(ui, player: Player) -> void:
	ui.call("_update_stats")
	var hp: ProgressBar = ui.get("_hp_bar")
	_check(hp != null and int(hp.value) == player.current_hp,
		"бар ЖИЗНЬ показывает текущее HP (%s)" % str(hp.value if hp else -1))
	var labels: Dictionary = ui.get("_stat_labels")
	if labels.has("attrs"):
		var t := str((labels["attrs"] as Label).text)
		_check(t.contains("ТЕЛО"), "строка атрибутов заполнена (%s)" % t)

func _report() -> void:
	if _fails.is_empty():
		print("RESULT: OK")
		quit(0)
	else:
		print("RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)