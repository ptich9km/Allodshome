extends SceneTree
## Smoke-проверка кузни (scripts/blacksmith_panel.gd + ItemDB).
##
## Главный баг: переплавка УНИЧТОЖАЛА предмет — player.add_item() не вызывался
## нигде, слиток только показывался иконкой в панели. Плюс слитков не было в
## item_db вовсе, и is_equippable() не исключал их (слиток можно было надеть
## как броню, а кузнец — переплавить слиток в слиток).
##
## Запуск: godot --headless --path . --script res://tests/blacksmith_smoke.gd

var _fails: Array[String] = []

func _init() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player = game.get("player")

	# --- Данные: слитки есть и не экипируются ---
	for metal in ItemDB._SMELTABLE:
		var key := ItemDB.ingot_key(metal)
		_check(key != "", "есть слиток для металла %s" % metal)
		if key == "":
			continue
		var ingot := ItemDB.find(key)
		_check(not ingot.is_empty(), "слиток %s найден в БД" % key)
		_check(str(ingot.get("icon", "")) != "", "у слитка %s есть иконка" % key)
		_check(ResourceLoader.exists(str(ingot.get("icon", ""))),
			"иконка слитка %s существует" % key)
		_check(not ItemDB.is_equippable(ingot), "слиток %s НЕ экипируется" % key)
		# Инвариант экономики: слиток дешевле любой вещи из своего металла.
		var cheapest := 1 << 30
		for it in ItemDB.all():
			var d: Dictionary = it
			if str(d.get("material", "")) == metal and str(d.get("type", "")) != "Ingot":
				cheapest = mini(cheapest, int(d.get("price", 1 << 30)))
		_check(int(ingot.get("price", 0)) < cheapest,
			"слиток %s дешевле самой дешёвой вещи из %s (%d < %d)"
			% [key, metal, int(ingot.get("price", 0)), cheapest])

	# --- Неметаллы кузнец не берёт ---
	for nm in ["Leather", "Hard Leather", "Dragon Leather", "Wood", "Magic Wood", "None"]:
		var sample := _first_item_with_material(nm)
		if sample.is_empty():
			continue
		_check(not ItemDB.is_smeltable(sample), "кузнец не берёт '%s' (пример: %s)" % [nm, str(sample.get("key", ""))])

	# --- Поведение переплавки на живом игроке ---
	var sword := _first_item_with_material("Iron")
	var sword_key := str(sword.get("key", ""))
	_check(sword_key != "", "найден железный предмет для переплавки: %s" % sword_key)
	if sword_key == "":
		_report()
		return
	player.inventory.append(sword_key)
	var before: int = _count(player, sword_key)
	var smelted: bool = await _smelt(player, sword_key)
	var after: int = _count(player, sword_key)
	_check(smelted, "переплавка выполнена")
	_check(after == before - 1, "исходный предмет забран из инвентаря (%d -> %d)" % [before, after])

	var iron_ingot := ItemDB.ingot_key("Iron")
	_check(_count(player, iron_ingot) == 1,
		"в инвентаре появился ровно 1 слиток железа (%d)" % _count(player, iron_ingot))

	# Материал слитка соответствует материалу вещи.
	var steel := _first_item_with_material("Steel")
	var steel_key := str(steel.get("key", ""))
	if steel_key != "":
		player.inventory.append(steel_key)
		var _ignored_smelt: bool = await _smelt(player, steel_key)
		_check(_count(player, steel_key) == 0, "стальной предмет забран")
		_check(_count(player, ItemDB.ingot_key("Steel")) == 1,
			"получен слиток стали, а не железа")
		_check(_count(player, iron_ingot) == 1, "счётчик железного слитка не сбился")

	# Кожу переплавить нельзя: вещь остаётся на месте.
	var leather := _first_item_with_material("Leather")
	var leather_key := str(leather.get("key", ""))
	if leather_key != "":
		player.inventory.append(leather_key)
		var n0: int = _count(player, leather_key)
		var done: bool = await _smelt(player, leather_key)
		_check(not done, "переплавка кожи отклонена")
		_check(_count(player, leather_key) == n0, "кожа осталась в инвентаре целой")

	# Слиток нельзя переплавить в слиток.
	player.inventory.append(iron_ingot)
	var n1: int = _count(player, iron_ingot)
	var ingot_refused: bool = await _smelt(player, iron_ingot)
	_check(not ingot_refused, "слиток не переплавляется")
	_check(_count(player, iron_ingot) == n1, "счётчик слитков не изменился")

	# Отсутствующий предмет и отсутствие игрока не должны ронять панель.
	var missing_refused: bool = await _smelt(player, "Такого предмета нет")
	_check(not missing_refused, "несуществующий ключ отклонён")

	_report()

func _count(player, key: String) -> int:
	return player.inventory.count(key)

## Вызвать _smelt_item панели кузни, как это делает кнопка «Плавить».
## Возвращает, изменился ли инвентарь.
func _smelt(player, key: String) -> bool:
	var before: Array = player.inventory.duplicate()
	var panel := BlacksmithPanel.new()
	panel.setup(player)
	root.add_child(panel)
	for i in range(2):
		await process_frame
	panel.call("_smelt_item", key)
	await process_frame
	var changed: bool = before != player.inventory
	panel.queue_free()
	await process_frame
	return changed

func _first_item_with_material(material: String) -> Dictionary:
	for it in ItemDB.all():
		var d: Dictionary = it
		if str(d.get("material", "")) == material and str(d.get("type", "")) != "Ingot":
			return d
	return {}

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK blacksmith_smoke")
		quit(0)
	else:
		print("RESULT: FAIL blacksmith_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)
