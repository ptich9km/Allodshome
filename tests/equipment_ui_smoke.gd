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
var _checks := 0
var _sections_done := {}

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
	_checks += 1
	if not ok:
		_fails.append(what)
	print("EQPUI: %s %s" % ["ok  " if ok else "FAIL", what])

## Секция проверок обязана ДОЙТИ до конца и отметиться здесь. Если она
## оборвалась ошибкой (как было с Nil вместо словаря), отметки не будет —
## и _report() упадёт. Раньше этого механизма не было, поэтому оборванная
## секция давала RESULT: OK.
func _finish_section(name: String) -> void:
	_sections_done[name] = true

const SECTIONS := ["panel", "slot_mapping", "rings", "two_handed",
	"unequip", "highlight", "stats_bars"]

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player: Player = game.get("player")
	var ui = game.get("ui")
	await process_frame

	# Открываем склад: слоты экипировки, клик по слоту и подсветка живут в
	# InventoryPanel, а не в GameUI. Пока панель не создана, ui.get("_inventory_panel")
	# возвращает null и все проверки слотов падают вхолостую.
	ui.call("open_inventory_panel")
	await process_frame
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
	# Поле `_equip_slots` живёт в InventoryPanel (scripts/inventory_panel.gd),
	# а НЕ в GameUI. Раньше здесь стояло ui.get("_equip_slots") — это Nil, на
	# присвоении к типизированной Dictionary Godot ронял SCRIPT ERROR, функция
	# прерывалась, а тест всё равно печатал RESULT: OK. То есть ВСЕ проверки
	# экипировки не выполнялись, а тест был зелёным.
	var panel: Node = ui.get("_inventory_panel")
	if panel == null or not is_instance_valid(panel):
		_check(false, "склад открыт: InventoryPanel создан")
		_finish_section("panel")
		return
	_check(true, "склад открыт: InventoryPanel создан")
	var slots_v: Variant = panel.get("_equip_slots")
	if typeof(slots_v) != TYPE_DICTIONARY:
		_check(false, "_equip_slots — словарь (получено %s)" % type_string(typeof(slots_v)))
		_finish_section("panel")
		return
	var slots: Dictionary = slots_v
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
	# Портрет героя. Раньше здесь было `_doll` — такого поля в ui.gd НЕТ ни
	# разу за всё время (проверено), кукла называется mini_portrait. Ошибка была
	# спрятана: секция падала на Nil раньше этой строки и до неё не доходила.
	_check(ui.get("mini_portrait") is TextureRect,
		"мини-портрет героя на месте (поле mini_portrait)")
	var stats_panel: Control = ui.get_node_or_null("StatsPanel")
	if stats_panel != null:
		# Правая панель по дизайну 180×370 (журнал 29.09), поэтому проверяем НЕ
		# 300×400 — на headless-вьюпорте ширину ещё и масштабирует. Ловим только
		# «панель схлопнулась», а не конкретный размер.
		_check(stats_panel.size.x >= 150.0 and stats_panel.size.y >= 300.0,
			"правая панель имеет разумную геометрию (%.0f×%.0f)"
				% [stats_panel.size.x, stats_panel.size.y])
	else:
		_check(false, "StatsPanel существует")
	_check(ui.get("_hp_label") is Label, "метка ЖИЗНЬ создана")
	_check(ui.get("_mp_label") is Label, "метка МАНА создана")
	_finish_section("panel")

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
		"Common bronze Helm": "head",
		"Common Linen Cloak": "cloak",
		"Common bronze Cuirass": "body",
		"Common bronze Bracers": "hands",
		"Common iron Plate Boots": "feet",   # кожа удалена 01.10
		"Common bronze Amulet": "amulet",
		"Elven titanium Ring": "ring",
		"Common bronze Long Sword": "weapon",
		"Common bronze Buckler": "shield",
	}
	for key in expect:
		var it := ItemDB.find(str(key))
		_check(not it.is_empty(), "в базе есть %s" % key)
		if not it.is_empty():
			_check(ItemDB.slot_of(it) == str(expect[key]),
				"%s -> слот %s (получено %s)" % [key, expect[key], ItemDB.slot_of(it)])
	_finish_section("slot_mapping")

# --- 3. Кольца: ring1, затем ring2 -------------------------------------------

func _test_rings(player: Player) -> void:
	var ring_key := ""
	for raw in ItemDB.all():
		if str((raw as Dictionary).get("type", "")) == "Ring":
			ring_key = str((raw as Dictionary).get("key", ""))
			break
	_check(ring_key != "", "в базе есть кольцо")
	if ring_key == "":
		_finish_section("rings")
		return
	var ring := ItemDB.find(ring_key)
	_check(player.equip_item(ring), "кольцо надевается")
	_check(str(player.equipped.get("ring1", "")) == ring_key, "первое кольцо — в ring1")
	_check(player.equip_item(ring), "второе кольцо надевается")
	_check(str(player.equipped.get("ring2", "")) == ring_key, "второе кольцо — в ring2")
	player.equipped.erase("ring1")
	player.equipped.erase("ring2")
	_finish_section("rings")

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
		_finish_section("two_handed")
		return
	player.equip_item(ItemDB.find("Common bronze Buckler"))
	_check(player.equipped.has("shield"), "щит надет перед двуручником")
	player.equip_item(ItemDB.find(th_key))
	_check(not player.equipped.has("shield"), "двуручный меч снял щит")
	player.unequip_slot("weapon")
	_finish_section("two_handed")

# --- 5. Клик по заполненному слоту снимает предмет ---------------------------

func _test_unequip_slot(ui, player: Player) -> void:
	player.equip_item(ItemDB.find("Common iron Long Sword"))
	_check(player.equipped.has("weapon"), "оружие надето перед снятием")
	var key := str(player.equipped.get("weapon", ""))
	# _on_slot_clicked живёт в InventoryPanel, а не в GameUI: слоты экипировки
	# переехали в отдельную панель склада (scripts/inventory_panel.gd:249).
	# Раньше тест дёргал ui.call("_on_slot_clicked", ...) и получал Nil.
	var inv = ui.get("_inventory_panel")
	_check(inv != null and inv.has_method("_on_slot_clicked"),
		"панель склада обрабатывает клик по слоту")
	if inv != null and inv.has_method("_on_slot_clicked"):
		inv.call("_on_slot_clicked", "weapon")
	_check(not player.equipped.has("weapon"), "клик по слоту снял оружие")
	_check(player.inventory.has(key), "снятый предмет вернулся в инвентарь (%s)" % key)
	_finish_section("unequip")

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
		_finish_section("highlight")
		return
	# Подсветка слотов живёт в InventoryPanel (_highlight_slot,
	# _item_matches_slot), а не в GameUI: слоты экипировки переехали в панель
	# склада. Раньше тест звал ui.call("_set_slot_highlight", ...) - такой
	# функции в ui.gd нет.
	var inv = ui.get("_inventory_panel")
	if inv == null or not inv.has_method("_item_matches_slot"):
		_check(false, "панель склада доступна для проверки подсветки")
		_finish_section("highlight")
		return
	inv.set("_highlight_slot", "head")
	_check(str(inv.get("_highlight_slot")) == "head", "подсветка включена для слота head")
	_check(bool(inv.call("_item_matches_slot", ItemDB.find(helm_key))),
		"шлем подходит слоту head")
	_check(not bool(inv.call("_item_matches_slot", ItemDB.find("Common iron Long Sword"))),
		"меч НЕ подходит слоту head")
	inv.set("_highlight_slot", "")
	_check(str(inv.get("_highlight_slot")) == "", "подсветка сброшена")
	_check(bool(inv.call("_item_matches_slot", ItemDB.find("Common iron Long Sword"))),
		"без подсветки подходит любой предмет")
	_finish_section("highlight")

# --- 7. Статы обновлены ------------------------------------------------

func _test_stats_bars(ui, player: Player) -> void:
	ui.call("_update_stats")
	var hp: Label = ui.get("_hp_label")
	_check(hp != null and hp.text.contains(str(player.current_hp)),
		"метка ЖИЗНЬ показывает текущее HP (%s)" % str(hp.text if hp else ""))
	var labels: Dictionary = ui.get("_stat_labels")
	if labels.has("attrs"):
		var t := str((labels["attrs"] as Label).text)
		_check(t.contains("Тело"), "строка атрибутов заполнена (%s)" % t)
	_finish_section("stats_bars")

func _report() -> void:
	# Каждая секция обязана была отметиться. Оборванная секция = недочитанные
	# проверки, и раньше это молча считалось успехом.
	var lost: Array[String] = []
	for s in SECTIONS:
		if not _sections_done.get(s, false):
			lost.append(s)
	if not lost.is_empty():
		_fails.append("секции не дошли до конца: %s (их проверки НЕ выполнялись)"
				% ", ".join(lost))
		print("EQPUI: FAIL секции не дошли до конца: %s" % ", ".join(lost))
	print("EQPUI: checks=%d fails=%d" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: OK")
		quit(0)
	else:
		print("RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)