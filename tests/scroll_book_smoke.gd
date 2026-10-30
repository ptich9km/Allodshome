extends SceneTree
## Headless-проверка КНИГИ СВИТКОВ (воин) и силы эльфийских свитков.
##
## Требования игрока (28.10):
##  1. у воина книга магии пустая, но купленные свитки появляются в ней и
##     назначаются на хоткей;
##  2. у мага свитки в книгу НЕ попадают (затирали бы книжную магию);
##  3. автокаст — только один свиток, помеченный ПКМ, и только «на себя»;
##  4. эльфийские свитки сильнее обычных (сила 100 против 50) и заметны.
##
## Запуск:
##   godot --headless --path . --script res://tests/scroll_book_smoke.gd

var _fails: Array = []
var _hero: Player = null
var _ui: Node = null


func _initialize() -> void:
	Game.hero_stats = {"body": 14, "agility": 12, "mind": 8, "spirit": 8,
		"blade": 14, "bludgeon": 12, "pike": 10, "shooting": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Воин"
	Game.auto_scroll_item = ""
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("SCROLLBOOK: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "main.tscn не загрузился")
		_finish()
		return
	await process_frame
	await create_timer(0.8).timeout
	_hero = get_first_node_in_group("player") as Player
	_ui = current_scene.get_node_or_null("UI")
	_check(_hero != null and _ui != null, "герой и интерфейс загружены")
	if _hero == null or _ui == null:
		_finish()
		return
	_check(not _hero.has_mana, "воин без маны (книга — свитки)")

	# 1. Свитки в складе → ячейки книги.
	_hero.add_item("Scroll Heal")
	_hero.add_item("Scroll Heal")
	_hero.add_item("Scroll Haste")
	_hero.add_item("SuperScroll Bless")
	_ui.call("refresh_spell_book")
	await process_frame
	var cells := _scroll_cells()
	_check(cells.size() == 3,
		"в книге три типа свитков из склада (=%d)" % cells.size())
	var keys: Array = []
	for c in cells:
		keys.append(str((c as Control).get_meta("scroll_item", "")))
	_check(keys.has("Scroll Heal") and keys.has("Scroll Haste")
			and keys.has("SuperScroll Bless"),
		"в книге именно купленные свитки: %s" % str(keys))

	# Тот же свиток в двух экземплярах = одна ячейка (склад — источник правды).
	_check(_hero.inventory.count("Scroll Heal") == 2,
		"склад по-прежнему хранит оба свитка Heal")

	# 30.10: у ячейки обязана быть подложка. `flat = true` в Godot 4 не рисует
	# stylebox в обычном состоянии, и иконки «парили» над панелью без фона.
	var first := cells[0] as Button
	var sb: StyleBox = first.get_theme_stylebox("normal")
	_check(not first.flat, "ячейка свитка не flat (иначе фон не рисуется)")
	_check(sb is StyleBoxFlat, "у ячейки свитка есть StyleBoxFlat")
	if sb is StyleBoxFlat:
		var alpha := (sb as StyleBoxFlat).bg_color.a
		_check(alpha >= 0.5 and alpha < 1.0,
			"подложка ячейки полупрозрачная (alpha=%.2f)" % alpha)
	_check(first.has_node("Cooldown"), "у ячейки свитка есть счётчик секунд")
	_check(first.has_node("CooldownVeil"), "у ячейки свитка есть пелена кулдауна")

	# 30.10: книга пересобирается при ОТКРЫТИИ, а не живёт с того момента, как
	# загрузился мир (раньше свитки, добытые позже, не появлялись вовсе).
	_hero.add_item("Scroll Slow")
	_check(_scroll_cells().size() == 3, "книга ещё не пересобрана (склад уже вырос)")
	_ui.call("toggle_spells")   # закрыть
	_ui.call("toggle_spells")   # открыть -> пересборка
	await process_frame
	_check(_scroll_cells().size() == 4,
		"книга пересобрана при открытии (=%d)" % _scroll_cells().size())

	# 30.10: свиток, купленный в лавке, не попадал в книгу — open_shop() не
	# подключал inventory_changed, и сигнал панели уходил в пустоту.
	_ui.call("open_shop")
	await process_frame
	var shop: ShopPanel = _ui.get("_shop")
	_check(shop != null, "лавка открылась через интерфейс")
	if shop != null:
		_check(shop.inventory_changed.get_connections().size() > 0,
			"лавка сообщает интерфейсу об изменении склада")
		var before := _scroll_cells().size()
		shop.call("_buy_item", "Scroll Shield", 0)
		await process_frame
		_check(_scroll_cells().size() == before + 1,
			"купленный свиток сразу попал в книгу (=%d)" % _scroll_cells().size())
		# Без close(): он зовёт автосейв и перезаписал бы сохранение игрока.
		shop.queue_free()

	# 3. ПКМ по свитку: пометка только для «на себя».
	_ui.call("_toggle_auto_scroll", "Scroll Heal")
	await process_frame
	_check(Game.auto_scroll_item == "Scroll Heal",
		"ПКМ пометил свиток лечения как автокаст")
	_ui.call("_toggle_auto_scroll", "Scroll Fire Ball")
	await process_frame
	_check(Game.auto_scroll_item == "Scroll Heal",
		"боевой свиток автокастом не помечается")
	_ui.call("_toggle_auto_scroll", "Scroll Heal")
	await process_frame
	_check(Game.auto_scroll_item == "",
		"повторное ПКМ снимает пометку")

	# 2. Магу свитки в книгу не идут.
	_hero.has_mana = true
	_ui.call("refresh_spell_book")
	await process_frame
	_check(_scroll_cells().size() == 0,
		"у мага свитки в книгу не попадают (=%d)" % _scroll_cells().size())
	_hero.has_mana = false
	_ui.call("refresh_spell_book")
	await process_frame

	# 30.10: у воина книга — свитки из склада. Без подсказки пустая панель
	# выглядела как «B не открывает меню магии» (жалоба игрока).
	var saved_inv: Array = _hero.inventory.duplicate()
	_hero.inventory.clear()
	_ui.call("refresh_spell_book")
	await process_frame
	var hint: Label = _ui.get("_book_empty_hint")
	_check(hint != null and is_instance_valid(hint) and hint.text != "",
		"пустая книга воина показывает подсказку")
	_hero.inventory.assign(saved_inv)
	_ui.call("refresh_spell_book")
	await process_frame
	_check(_ui.get("_book_empty_hint") == null, "подсказка убирается, когда свитки вернулись")

	# 4. Сила свитка: 50 обычный / 100 эльфийский, и она реально влияет.
	var base_item := ItemDB.find("Scroll Fire Ball")
	var elf_item := ItemDB.find("SuperScroll Fire Ball")
	_check(absf(SpellDB.scroll_power_of(base_item) - 50.0) < 0.01,
		"сила обычного свитка = 50")
	_check(absf(SpellDB.scroll_power_of(elf_item) - 100.0) < 0.01,
		"сила эльфийского свитка = 100")
	var d50 := Game.spell_damage(_hero, "Fire_Ball", "Fire", 10, 50.0)
	var d100 := Game.spell_damage(_hero, "Fire_Ball", "Fire", 10, 100.0)
	_check(d100 > d50, "эльфийский свиток бьёт сильнее (%d > %d)" % [d100, d50])

	# Кулдаун считается по МАГИИ ВНУТРИ свитка (50/100), а не по применению.
	var base_cd := SpellDB.cooldown_of("Haste")
	var cd50 := Game.spell_cooldown(_hero, "Haste", 50.0)
	var cd100 := Game.spell_cooldown(_hero, "Haste", 100.0)
	_check(cd50 < base_cd and cd100 < cd50,
		"кулдаун свитка от его силы: %.2f (100) < %.2f (50) < %.2f (нет магии)"
			% [cd100, cd50, base_cd])
	_check(absf(cd50 - base_cd * 0.75) < 0.01 and absf(cd100 - base_cd * 0.5) < 0.01,
		"сила 50 → 75 %% базы, сила 100 → 50 %% базы")

	# Ручной каст свитка тоже ставит кулдаун (раньше не ставил вовсе).
	_hero.cast_cooldowns.clear()
	_hero.current_hp = maxi(1, _hero.max_hp / 2)
	_hero.apply_scroll_to_target("Heal", _hero, 50.0)
	var cd_after := float(_hero.cast_cooldowns.get("Heal", 0.0))
	_check(cd_after > 0.0, "ручной каст свитка ставит кулдаун (%.2f с)" % cd_after)
	_check(absf(cd_after - Game.spell_cooldown(_hero, "Heal", 50.0)) < 0.01,
		"кулдаун ручного свитка = расчётный по его силе")

	# Имена и свечение.
	var elf_bless := ItemDB.find("SuperScroll Bless")
	_check(str(elf_bless.get("name_ru", "")).begins_with("Эльфийский свиток"),
		"эльфийский свиток назван по-человечески: %s" % str(elf_bless.get("name_ru", "")))
	_check(str(ItemDB.find("Scroll Bless").get("name_ru", "")).begins_with("Свиток"),
		"обычный свиток тоже назван: %s" % str(ItemDB.find("Scroll Bless").get("name_ru", "")))
	_check(CraftVFX.is_elven(elf_bless) and not CraftVFX.is_elven(base_item),
		"эльфийский определяется по качеству SuperScroll")
	var icon := TextureRect.new()
	CraftVFX.apply_elven(icon, elf_bless)
	_check(icon.material is ShaderMaterial, "на иконке эльфийского — свечение")
	CraftVFX.apply_elven(icon, base_item)
	_check(icon.material == null, "на обычном свитке свечения нет")
	icon.free()

	_ui.call("refresh_spell_book")
	Game.auto_scroll_item = ""
	_finish()


func _scroll_cells() -> Array:
	var out: Array = []
	if _ui == null:
		return out
	var grid: Node = _ui.get_node_or_null("BottomPanel/SpellPanel/SpellGrid")
	if grid == null:
		return out
	for c in grid.get_children():
		if c is Control and (c as Control).has_meta("scroll_item"):
			out.append(c)
	return out


func _finish() -> void:
	Game.auto_scroll_item = ""
	if _fails.is_empty():
		print("SCROLLBOOK: RESULT: OK")
	else:
		print("SCROLLBOOK: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
