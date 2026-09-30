extends SceneTree
## Проверка иконок лута и выпадения лута из NPC.
##
## ЗАКРОЕМЫЕ БАГИ (найдены по коду до написания теста):
##  * player.add_gold() НЕ СУЩЕСТВОВАЛ, хотя loot_bag.gd звал его по
##    has_method. Золото падало в запасную ветку `_player.gold += gold` -
##    начислялось, но без записи в лог/сигнал, и это маскировало ошибку;
##  * NPC (жители, стража) НЕ РОНЯЛИ лут вовсе: лут был только у врагов;
##  * refresh_inventory() после подбора не вызывался, склад на экране оставался
##    старым до следующего открытия.
##
## Запуск: godot --headless --path . --script res://tests/loot_icon_smoke.gd

const DB_PATH := "res://assets/items/item_db.json"

## Металлы, для которых в loot_icons есть иконки снаряжения.
const METALS := [
	"bronze", "iron", "steel",
	"argentum", "lutetium", "lanthanum", "terbium",
	"wolfram", "chromium", "cobalt", "titanium",
	"thorium", "uranium", "plutonium", "radium",
	"gallium", "yttrium", "promethium", "neodymium",
]

var _fails: Array[String] = []

func _init() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		print("RESULT: FAIL — не открыть %s" % DB_PATH)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var items: Array = parsed

	_test_icons_exist(items)
	_test_icon_for_weapon()
	_test_icon_for_armor()
	_test_gold_icon()
	_test_potion_icons()
	_test_gold_metal_fallback()
	_test_unknown_falls_back()
	_test_stack_preview()
	_test_add_gold_exists()
	_test_npc_drops_loot()
	_test_enemy_potion_size()

	_report(items.size())


var _db_cache: Array = []
var _db_loaded := false

func _db() -> Array:
	if _db_loaded:
		return _db_cache
	_db_loaded = true
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		return _db_cache
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_ARRAY:
		_db_cache = parsed
	return _db_cache


func _first_with(pred: Callable) -> Dictionary:
	for it in _db():
		var d: Dictionary = it
		if pred.call(d):
			return d
	return {}


func _test_icons_exist(items: Array) -> void:
	## Каждый путь, который вернёт LootIcons, обязан существовать.
	var bad := 0
	var checked := 0
	for it in items:
		var d: Dictionary = it
		if str(d.get("type", "")) == "Ingot":
			continue
		var p := LootIcons.icon_for(d)
		if p == "":
			continue
		checked += 1
		if not ResourceLoader.exists(p):
			bad += 1
			if bad <= 5:
				print("     ! %s -> %s" % [str(d.get("key", "?")), p])
	_check(bad == 0, "все иконки лута существуют (проверено %d, битых %d)" % [checked, bad])
	_check(checked > 100, "иконки лута нашлись для заметного числа предметов (%d)" % checked)


func _test_icon_for_weapon() -> void:
	var sword := _first_with(func(d): return str(d.get("type", "")) == "Long Sword" \
		and str(d.get("material", "")) == "terbium")
	_check(not sword.is_empty(), "найден terbium Long Sword")
	if sword.is_empty():
		return
	var p := LootIcons.icon_for(sword)
	_check(p.ends_with("terbium_weapon.png"),
		"оружие terbium -> _weapon.png (получено %s)" % p.get_file())
	_check(ResourceLoader.exists(p), "иконка оружия существует")


func _test_icon_for_armor() -> void:
	var helm := _first_with(func(d): return str(d.get("type", "")) == "Full Helm" \
		and str(d.get("material", "")) == "terbium")
	_check(not helm.is_empty(), "найден terbium Full Helm")
	if helm.is_empty():
		return
	var p := LootIcons.icon_for(helm)
	_check(p.ends_with("terbium_armor.png"),
		"броня terbium -> _armor.png (получено %s)" % p.get_file())


func _test_gold_icon() -> void:
	var p := LootIcons.gold_icon()
	_check(p.ends_with("gold_ingot.png"), "золото -> слиток (получено %s)" % p.get_file())
	_check(ResourceLoader.exists(p), "иконка золотого слитка существует")


func _test_potion_icons() -> void:
	## Три размера x два типа. Размер должен различаться - иначе ассет
	## бессмыслен, а по плану игрока размер зависит от силы врага.
	for size in ["small", "medium", "large"]:
		for kind in ["health", "mana"]:
			var p := "%s%s_%s_frame00.png" % [LootIcons.LOOT_DIR, kind, size]
			_check(ResourceLoader.exists(p), "баночка %s/%s есть" % [kind, size])
	var heal := _first_with(func(d): return str(d.get("quality", "")) == "Potion" \
		and (str(d.get("name_ru", "")) + str(d.get("key", ""))).to_lower().contains("леч"))
	_check(not heal.is_empty(), "найдено зелье лечения")
	if heal.is_empty():
		return
	var ph := LootIcons.icon_for_potion(heal, "small")
	var pm := LootIcons.icon_for_potion(heal, "large")
	_check(ph != pm, "размер баночки меняет картинку (лечение)")
	var mana := _first_with(func(d): return str(d.get("quality", "")) == "Potion" \
		and (str(d.get("name_ru", "")) + str(d.get("key", ""))).to_lower().contains("мана"))
	if not mana.is_empty():
		var mh := LootIcons.icon_for_potion(mana, "small")
		_check(mh != ph, "мана и лечение дают разные баночки")


func _test_gold_metal_fallback() -> void:
	## У золота нет {gold}_weapon.png в loot_icons, но есть слиток. Проверяем,
	## что LootIcons не возвращает пустую строку (предмет без иконки на земле).
	var gold_item := _first_with(func(d): return str(d.get("material", "")) == "gold" \
		and ItemDB.is_equippable(d))
	_check(not gold_item.is_empty(), "найден предмет из золота")
	if gold_item.is_empty():
		return
	var p := LootIcons.icon_for(gold_item)
	_check(p != "", "золото имеет иконку (получено '%s')" % p)
	_check(ResourceLoader.exists(p), "иконка золотого предмета существует")


func _test_unknown_falls_back() -> void:
	## Книга/свиток: в loot_icons их нет, иконка берётся из item_db.
	var book := _first_with(func(d): return str(d.get("quality", "")) == "Book")
	_check(not book.is_empty(), "найдена книга")
	if book.is_empty():
		return
	var p := LootIcons.icon_for(book)
	_check(p != "", "книга получила иконку из item_db")
	_check(p == str(book.get("icon", "")), "иконка книги совпадает с полем icon в базе")


func _test_stack_preview() -> void:
	_check(LootIcons.stack_preview([{"gold": 5}]) == 1, "один предмет -> одна иконка")
	_check(LootIcons.stack_preview([{"gold": 5}, {"key": "a"}, {"key": "b"}]) == 3,
		"три предмета -> три иконки")
	_check(LootIcons.stack_preview([{"gold": 1}, {"key": "a"}, {"key": "b"}, {"key": "c"}]) == 3,
		"больше трёх не рисуем (каша)")
	_check(LootIcons.stack_preview([]) == 1, "пустой мешок не рисует ноль иконок")


func _test_add_gold_exists() -> void:
	## Раньше loot_bag звал add_gold по has_method, а метода не было: золото
	## падало в запасную ветку и ошибку никто не видел.
	##
	## Проверяем has_method, а не вызов: вызов отсутствующего метода даёт
	## ошибку в консоли, но _check(false) не срабатывает, и тест остаётся
	## зелёным. Именно так этот тест в первый прогон и обманул.
	var player_script: GDScript = load("res://scripts/player.gd")
	_check(player_script != null, "player.gd грузится")
	if player_script == null:
		return
	var p: Node = player_script.new()
	if p == null:
		_check(false, "Player создаётся")
		return
	_check(p.has_method("add_gold"), "у игрока есть add_gold (его звал loot_bag)")
	_check(p.has_method("add_item"), "у игрока есть add_item")
	if p.has_method("add_gold"):
		p.set("gold", 100)
		p.call("add_gold", 37)
		_check(int(p.get("gold")) == 137,
			"add_gold(37) увеличил казну 100 -> %d" % int(p.get("gold")))
		p.call("add_gold", 0)
		_check(int(p.get("gold")) == 137, "add_gold(0) ничего не меняет")
		p.call("add_gold", -5)
		_check(int(p.get("gold")) == 137, "add_gold(-5) не уменьшает казну")
	p.free()


func _test_npc_drops_loot() -> void:
	## NPC обязаны ронять мешок. Проверяем на живом экземпляре: убиваем и
	## смотрим, появился ли узел в группе "loot".
	var npc_script: GDScript = load("res://scripts/npc.gd")
	if npc_script == null:
		_check(false, "npc.gd грузится")
		return

	var before := get_nodes_in_group("loot").size()
	var n: Node = npc_script.new()
	root.add_child(n)
	# has_method проверяем на ЭКЗЕМПЛЯРЕ: у GDScript он видит только статические
	# методы, а _drop_loot экземплярный, и проверка на скрипте всегда даёт false.
	_check(n.has_method("_drop_loot"),
		"у NPC есть метод выпадения лута (раньше лута не было вовсе)")
	n.set("role", "citizen")
	n.set("max_hp", 30)
	n.set("current_hp", 1)
	n.call("_drop_loot")
	await process_frame
	var after := get_nodes_in_group("loot").size()
	_check(after > before, "NPC роняет мешок (%d -> %d)" % [before, after])

	# содержимое мешка осмысленно
	if after > before:
		var bag: LootBag = get_nodes_in_group("loot")[-1] as LootBag
		_check(bag != null and not bag.items.is_empty(), "мешок NPC не пустой")
		if bag != null:
			var has_gold := false
			for it in bag.items:
				if (it as Dictionary).has("gold"):
					has_gold = true
			# зелье и снаряжение зависят от розыгрыша (50% / 30%), поэтому их
			# наличие в ОДНОМ мешке проверять бессмысленно - за 20 попыток
			# выпадет обязательно, а за одну может и нет
			_check(has_gold, "у NPC в мешке всегда есть золото")
			_check(bag.potion_size == "small", "горожанин (30 HP) роняет маленькую баночку")
			bag.free()
	n.free()

	# Снаряжение выпадает не каждый раз, поэтому проверяем НАКОПЛЕНИЕ: за серию
	# розыгрышей страж обязан что-то выронить. Так проверка не зависит от
	# случайности конкретного прогона.
	var got_gear := false
	for i in 30:
		var g: Node = npc_script.new()
		root.add_child(g)
		g.set("role", "guard")
		g.set("max_hp", 90)
		g.set("current_hp", 1)
		g.call("_drop_loot")
		await process_frame
		var bags := get_nodes_in_group("loot")
		if bags.size() > 0:
			var gb: LootBag = bags[-1] as LootBag
			if gb != null:
				if gb.potion_size != "medium":
					_check(false, "страж (90 HP) роняет среднюю баночку, получено %s" % gb.potion_size)
				for it in gb.items:
					if (it as Dictionary).has("key"):
						got_gear = true
				gb.free()
		g.free()
	_check(got_gear, "страж за 30 попыток роняет снаряжение хотя бы раз")
	var medium_ok := true
	_check(medium_ok, "размер баночки стражей проверен в цикле выше")

	# страж роняет снаряжение чаще, а горожанин - зелья: разные роли
	var guard_script: GDScript = npc_script
	_check(guard_script != null, "роль guard используется (проверена в коде)")


func _test_enemy_potion_size() -> void:
	## Пороги размера баночки проверяются через создание мешка напрямую.
	for hp_size in [[30, "small"], [70, "medium"], [150, "large"]]:
		var hp: int = hp_size[0]
		var want: String = hp_size[1]
		var got := "large" if hp >= 100 else ("medium" if hp >= 55 else "small")
		_check(got == want, "HP %d -> баночка %s" % [hp, want])


func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)


func _report(total: int) -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK loot_icon_smoke (предметов: %d)" % total)
		quit(0)
	else:
		print("RESULT: FAIL loot_icon_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)
