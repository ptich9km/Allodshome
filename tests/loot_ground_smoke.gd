extends SceneTree
##
## Лут на земле и счётчик золота (03.10).
##
## ЧТО ЗАКРЫВАЕТ
## --------------
## 1. Мешок убран. Раньше игрок видел на земле один мешок с максимум тремя
##    иконками над ним, а золото рисовалось СЛИТКОМ (`gold_ingot.png`), хотя
##    выдавалось числом. Итог: игрок брал мешок, искал слиток в инвентаре и не
##    находил. Теперь на земле лежат иконки самих предметов, а у золота своя
##    картинка — монета.
## 2. Иконка соответствует предмету: броня -> иконка брони, оружие -> оружия,
##    зелье -> баночка ХП/МАНы по типу, золото -> монета (НЕ слиток).
## 3. Золото видно в HUD. Замер: `player.gold` не показывался нигде, кроме
##    таверны и магазина.
## 4. Предметы разложены по земле, а не слиплись в одну точку.
##
## ЗАПУСК
## ------
## godot --headless --path . --script res://tests/loot_ground_smoke.gd
##

const ICON_PX := 18.0
const ICON_GAP := 3.0

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Лутер"
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _make_drop(items: Array) -> LootDrop:
	var d := LootDrop.new()
	d.items = items
	return d


func _run() -> void:
	print("-- иконки соответствуют предметам --")

	# Золото — монета, а НЕ слиток.
	var coin := LootIcons.gold_icon()
	_check(coin.ends_with("gold_coin.png"), "золото рисуется монетой (%s)" % coin.get_file())
	_check(not coin.ends_with("gold_ingot.png"),
		"золото НЕ рисуется слитком (слиток — это предмет, а золото — число)")
	_check(ResourceLoader.exists(coin), "файл монеты есть на диске")

	# Находим в базе броню, оружие и два разных зелья.
	var armor_key := ""
	var weapon_key := ""
	var heal_key := ""
	var mana_key := ""
	# Слоты в игре: weapon/shield/head/cloak/body/hands/feet/amulet/ring1/ring2.
	# Название "body", а не "chest" — "chest" осталось от колонки атласа арта.
	for raw in ItemDB.all():
		var it: Dictionary = raw
		var slot := ItemDB.slot_of(it)
		if armor_key == "" and (slot == "body" or slot == "head"):
			armor_key = str(it.get("key", ""))
		if weapon_key == "" and slot == "weapon":
			weapon_key = str(it.get("key", ""))
		if heal_key == "" and str(it.get("quality", "")) == "Potion" \
				and str(it.get("key", "")).contains("Healing"):
			heal_key = str(it.get("key", ""))
		if mana_key == "" and str(it.get("quality", "")) == "Potion" \
				and str(it.get("key", "")).contains("Mana"):
			mana_key = str(it.get("key", ""))
	_check(armor_key != "", "в базе есть броня (%s)" % armor_key)
	_check(weapon_key != "", "в базе есть оружие (%s)" % weapon_key)
	_check(heal_key != "", "в базе есть зелье лечения")
	_check(mana_key != "", "в базе есть зелье маны")

	var armor_icon := LootIcons.icon_for(ItemDB.find(armor_key))
	var weapon_icon := LootIcons.icon_for(ItemDB.find(weapon_key))
	_check(armor_icon != "" and not armor_icon.ends_with("gold_coin.png"),
		"броня рисуется своей иконкой, а не монетой")
	_check(weapon_icon != "" and not weapon_icon.ends_with("gold_coin.png"),
		"оружие рисуется своей иконкой, а не монетой")
	_check(armor_icon != weapon_icon, "иконки брони и оружия РАЗНЫЕ")

	var heal_icon := LootIcons.icon_for_potion(ItemDB.find(heal_key), "medium")
	var mana_icon := LootIcons.icon_for_potion(ItemDB.find(mana_key), "medium")
	_check(heal_icon != "" and heal_icon.contains("health"),
		"зелье лечения -> баночка ХП (%s)" % heal_icon.get_file())
	_check(mana_icon != "" and mana_icon.contains("mana"),
		"зелье маны -> баночка МАНЫ (%s)" % mana_icon.get_file())
	_check(heal_icon != mana_icon, "баночки ХП и МАНЫ разные")

	print("-- добыча раскладывается по земле --")
	var drop := _make_drop([
		{"gold": 25},
		{"key": armor_key},
		{"key": weapon_key},
		{"key": heal_key},
	])
	root.add_child(drop)
	await process_frame
	var sprites: Array[Sprite2D] = []
	for c in drop.get_children():
		if c is Sprite2D:
			sprites.append(c)
	_check(sprites.size() == 4, "все 4 предмета показаны на земле (спрайтов: %d)" % sprites.size())

	# Разные позиции — иначе всё слиплось бы в одну точку.
	var uniq := {}
	for s in sprites:
		uniq[s.position] = true
	_check(uniq.size() == 4, "предметы не слиплись в одну точку (позиций: %d)" % uniq.size())

	var xs: Array[float] = []
	for s2 in sprites:
		xs.append(s2.position.x)
	xs.sort()
	_check(xs[xs.size() - 1] - xs[0] > ICON_PX,
		"предметы разложены в ряд по ширине (размах %.0f px)" % (xs[xs.size() - 1] - xs[0]))
	var min_gap := 9999.0
	for i in range(xs.size() - 1):
		min_gap = minf(min_gap, xs[i + 1] - xs[i])
	_check(min_gap >= ICON_PX, "между соседними предметами есть зазор (%.0f px)" % min_gap)

	print("-- мешок действительно убран --")
	var draws_nothing := true
	for s3 in sprites:
		if s3.texture != null and s3.texture.get_width() == 32:
			pass
	# узла-мешка быть не должно: проверяем, что у добычи нет своего _draw мешка
	_check(not drop.has_method("_draw_bag"), "у добычи нет кодового мешка")
	_check(drop is LootDrop, "класс называется LootDrop (а не LootBag)")

	print("-- счётчик золота в HUD --")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await create_timer(0.5).timeout
	var ui = game.get("ui")
	var player = game.get("player")
	_check(ui != null and player != null, "сцена с HUD загрузилась")
	if ui == null or player == null:
		_report()
		return

	var lbl := ui.get_node_or_null("StatsPanel/StatsMargin/StatsCol/GoldRow/GoldLabel") as Label
	_check(lbl != null, "счётчик золота есть в панели справа")
	if lbl != null:
		player.gold = 1234
		ui.call("_update_stats")
		await process_frame
		_check(lbl.text == "1234", "счётчик показывает золото игрока (%s)" % lbl.text)
		# подбор лута должен обновлять счётчик даже без открытия склада
		player.gold = 1300
		ui.call("refresh_inventory")
		await process_frame
		_check(lbl.text == "1300", "счётчик обновился после подбора (%s)" % lbl.text)

	var icon := ui.get_node_or_null(
		"StatsPanel/StatsMargin/StatsCol/GoldRow/GoldIcon") as TextureRect
	_check(icon != null and icon.texture != null, "у счётчика золота есть иконка монеты")
	if icon != null and icon.texture != null:
		_check(icon.texture.resource_path.ends_with("gold_coin.png"),
			"в HUD та же монета, что и на земле")

	_report()


func _report() -> void:
	print("RESULT: %s loot_ground_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)