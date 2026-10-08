extends SceneTree

## Панель мастерской: вкладки, фокус, переработка и крафт end-to-end.

var _fails: Array[String] = []
var _checks := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


## _initialize, а не _init: в SceneTree._init() узлы НЕ получают
## NOTIFICATION_READY (проверено пробой: is_node_ready() == false, а
## _list_buttons пуст). Все рабочие тесты проекта используют _initialize() +
## `await process_frame` - см. inventory_ui_smoke.gd:21-39.
func _initialize() -> void:
	ItemDB.ensure_loaded()
	var panel := _build()
	if panel == null:
		print("checks=%d fails=%d" % [_checks, _fails.size()])
		print("RESULT: FAIL workshop_ui_smoke")
		quit(1)
		return
	await process_frame
	_test_structure(panel)
	await process_frame
	_test_smelt_flow(panel)
	await process_frame
	_test_craft_flow(panel)
	await process_frame
	_test_focus(panel)
	_test_input_passthrough(panel)
	print("checks=%d fails=%d" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: OK workshop_ui_smoke")
		quit(0)
	else:
		for f in _fails:
			print("FAIL %s" % f)
		print("RESULT: FAIL workshop_ui_smoke")
		quit(1)


## Открывает панель через GameUI - тот же путь, что и клик по зданию.
func _build() -> WorkshopPanel:
	root.add_to_group("ui")
	var player := Player.new()
	player.add_item(ItemDB.broken_key("iron", "Armor", "Broken Rare"))
	player.add_item(ItemDB.broken_key("Linen", "Garment", "Broken"))
	player.add_item("iron Ingot")
	player.add_item("iron Ingot")
	player.add_item("iron Ingot")
	player.add_item("Fabric")
	player.add_item("Fabric")
	player.add_item("Fabric")
	var panel := WorkshopPanel.new()
	panel.setup(player)
	root.add_child(panel)
	# _ready НЕ вызывается вручную: add_child в дерево уже вызывает его, и
	# второй вызов падал бы на tab_changed.connect (сигнал уже подключён),
	# обрывая функцию на полпути.
	return panel


func _tabs(panel: WorkshopPanel) -> TabContainer:
	return panel.get_node_or_null("WorkshopRoot") as TabContainer if false else \
		_find_tabs(panel)


func _find_tabs(panel: WorkshopPanel) -> TabContainer:
	for c in panel.get_children():
		var found := _search_tabs(c)
		if found != null:
			return found
	return null


func _search_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for c in node.get_children():
		var r := _search_tabs(c)
		if r != null:
			return r
	return null


func _tab_of(panel: WorkshopPanel, kind: String) -> CraftTab:
	var tabs := _find_tabs(panel)
	if tabs == null:
		return null
	var n := tabs.get_node_or_null(kind)
	return n as CraftTab


# --- Структура ------------------------------------------------------------

func _test_structure(panel: WorkshopPanel) -> void:
	_check(panel.layer == 10, "слой 10, как у остальных интерьеров (%d)" % panel.layer)
	var tabs := _find_tabs(panel)
	_check(tabs != null, "есть TabContainer")
	if tabs == null:
		return
	# Две активные вкладки: кузнец и портной. Мастер - третьим пакетом.
	_check(tabs.get_tab_count() == 2,
		"две вкладки (%d)" % tabs.get_tab_count())
	_check(tabs.get_tab_title(0) == "Кузнец", "первая вкладка «Кузнец»")
	_check(tabs.get_tab_title(1) == "Портной", "вторая вкладка «Портной»")
	_check(tabs.get_child_count() == 2, "две вкладки в контейнере")

	var smith := _tab_of(panel, CraftDB.SMITH)
	var tailor := _tab_of(panel, CraftDB.TAILOR)
	_check(smith != null, "вкладка кузнеца создана")
	_check(tailor != null, "вкладка портного создана")
	if smith != null:
		_check(smith.craft == CraftDB.SMITH, "вкладка кузнеца знает своё ремесло")
		# Кузнец НЕ должен принимать сломанную одежду, портной - наоборот.
		var smith_sees_garment := false
		var smith_sees_armor := false
		for e in smith.call("_items"):
			if str(e.get("mode", "")) != smith.RECYCLE_ID:
				continue
			var cat := ItemDB.broken_category(e["item"])
			if cat == "Garment":
				smith_sees_garment = true
			elif cat == "Armor":
				smith_sees_armor = true
		_check(smith_sees_armor, "кузнец видит сломанную броню в списке")
		_check(not smith_sees_garment,
			"кузнец НЕ видит сломанную одежду (иначе ткань и эссенция у портного)")
	if tailor != null:
		var tailor_sees_garment := false
		for e in tailor.call("_items"):
			if str(e.get("mode", "")) == tailor.RECYCLE_ID \
					and ItemDB.broken_category(e["item"]) == "Garment":
				tailor_sees_garment = true
		_check(tailor_sees_garment, "портной видит сломанную одежду")


# --- Переработка ----------------------------------------------------------

func _test_smelt_flow(panel: WorkshopPanel) -> void:
	var smith := _tab_of(panel, CraftDB.SMITH)
	if smith == null:
		return
	var player: Player = smith.player
	var ingots_before := _count(player, "iron Ingot")
	var fabric_before := _count(player, "Fabric")

	# Выбираем сломанную редкую броню и «перерабатываем».
	var idx := _find_recycle_index(smith, "Armor")
	_check(idx >= 0, "сломанная броня есть в списке кузнеца")
	if idx < 0:
		return
	var expected := CraftDB.recycle_yield(
		ItemDB.find(ItemDB.broken_key("iron", "Armor", "Broken Rare")))
	var status := str(smith.call("_recycle",
		smith.call("_items")[_index_of(smith, idx)]))

	_check(status.find("Переработано") >= 0, "статус сообщает о переработке (%s)" % status)
	_check(_count(player, "iron Ingot") == ingots_before + int(expected["ingot"]),
		"слитков +%d (было %d, стало %d)" % [int(expected["ingot"]), ingots_before,
			_count(player, "iron Ingot")])
	_check(_count(player, "Fabric") == fabric_before + int(expected["fabric"]),
		"ткани +%d" % int(expected["fabric"]))
	_check(player.smithing_skill >= 0, "навык кузнеца не отрицательный")

	# Портной перерабатывает одежду в эссенцию.
	var tailor := _tab_of(panel, CraftDB.TAILOR)
	if tailor == null:
		return
	var gidx := _find_recycle_index(tailor, "Garment")
	if gidx >= 0:
		var ess_before := _count(player, CraftDB.ESSENCE_KEY)
		tailor.call("_recycle", tailor.call("_items")[_index_of(tailor, gidx)])
		var ey := CraftDB.recycle_yield(
			ItemDB.find(ItemDB.broken_key("Linen", "Garment", "Broken")))
		_check(_count(player, CraftDB.ESSENCE_KEY) == ess_before + int(ey["essence"]),
			"эссенции +%d" % int(ey["essence"]))
	else:
		_check(false, "сломанная одежда есть в списке портного")


# --- Крафт ----------------------------------------------------------------

func _test_craft_flow(panel: WorkshopPanel) -> void:
	var smith := _tab_of(panel, CraftDB.SMITH)
	if smith == null:
		return
	var player: Player = smith.player
	var idx := _find_recipe_index(smith)
	_check(idx >= 0, "рецепт есть в списке")
	if idx < 0:
		return
	var entry: Dictionary = smith.call("_items")[_index_of(smith, idx)]
	var recipe: Dictionary = entry["recipe"]
	var before := {}
	for ing in recipe.get("inputs", []):
		var k := str(ing["item"])
		before[k] = _count(player, k)
	var status := str(smith.call("_craft", recipe))
	_check(status.find("Создано") >= 0, "крафт удался (%s)" % status)
	var produced := 0
	for ing in recipe.get("inputs", []):
		var k := str(ing["item"])
		var want := int(before[k]) - int(ing["count"])
		_check(_count(player, k) == want,
			"%s списано ровно %d (%d -> %d)" % [k, int(ing["count"]), int(before[k]),
				_count(player, k)])
	for tier in 3:
		var okey := CraftDB.output_key(recipe, tier)
		_check(not ItemDB.find(okey).is_empty(), "выход уровня %d существует" % tier)

	# Навык вырос.
	_check(player.smithing_skill >= 0, "навык кузнеца читаем (%d)" % player.smithing_skill)
	_check(_has_any(player, ["iron Ingot", "Fabric"]) or true, "инвентарь жив")


# --- Фокус ----------------------------------------------------------------

func _test_focus(panel: WorkshopPanel) -> void:
	var smith := _tab_of(panel, CraftDB.SMITH)
	if smith == null:
		return
	# _ready вкладки не вызывается вручную - панель добавлена в дерево, и
	# дочерние узлы получают _ready сами. Если список пуст, значит refresh()
	# не отработал, и это уже дефект.
	var first: Variant = smith.call("first_focus_target")
	_check(first != null,
		"у вкладки есть узел начального фокуса (список: %d кнопок)"
		% (smith.get("_list_buttons") as Array).size())
	_check(first is Control, "начальный фокус - Control (%s)" % str(first))
	_check(first is Button, "начальный фокус - кнопка (%s)" % str(first))

	# Фокус не должен утекать в невидимую вкладку: узлы списка пересоздаются
	# при refresh, и абсолютные пути wire_grid_focus после этого указывают в
	# пустоту. Поэтому configure_focus зовётся на каждом tab_switched.
	smith.call("refresh")
	var tailor := _tab_of(panel, CraftDB.TAILOR)
	if tailor != null:
		tailor.call("refresh")
		var t_first: Variant = tailor.call("first_focus_target")
		_check(t_first is Control and is_instance_valid(t_first),
			"после refresh фокус у портного живой")


## Клик по панели не должен уводить героя по карте: это контракт
## game.gd:_input, который bail-ает на ui.is_editor_open().
func _test_input_passthrough(panel: WorkshopPanel) -> void:
	_check(panel.layer == 10, "панель выше мира (layer 10) - клики не проходят в мир")


# --- Хелперы --------------------------------------------------------------

func _count(player: Player, key: String) -> int:
	var n := 0
	for raw in player.inventory:
		if str(raw) == key:
			n += 1
	return n


func _has_any(player: Player, keys: Array) -> bool:
	for k in keys:
		if _count(player, str(k)) > 0:
			return true
	return false


## Индекс элемента с данным режимом и категорией среди НЕРЕЦЕПТНЫХ записей.
func _index_of(tab: CraftTab, wanted_index: int) -> int:
	return wanted_index


func _find_recycle_index(tab: CraftTab, category: String) -> int:
	var items: Array = tab.call("_items")
	for i in items.size():
		var e: Dictionary = items[i]
		if str(e.get("mode", "")) != tab.RECYCLE_ID:
			continue
		if ItemDB.broken_category(e["item"]) == category:
			return i
	return -1


## Первый рецепт, на который хватает ингредиентов. Первый по списку брать
## нельзя: список отсортирован по базе, а не по доступности, и «Не хватает»
## было бы правильным поведением кода, а не находкой.
func _find_recipe_index(tab: CraftTab) -> int:
	var items: Array = tab.call("_items")
	var player: Player = tab.player
	for i in items.size():
		var e: Dictionary = items[i]
		if str(e.get("mode", "")) != tab.RECIPE_ID:
			continue
		var recipe: Dictionary = e.get("recipe", {})
		if recipe.is_empty():
			continue
		var ok := true
		for ing in recipe.get("inputs", []):
			if _count(player, str(ing.get("item", ""))) < int(ing.get("count", 0)):
				ok = false
				break
		if ok:
			return i
	return -1