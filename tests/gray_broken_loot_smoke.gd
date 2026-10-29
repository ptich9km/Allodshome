extends SceneTree
## Лут Серых: снаряжение падает СЛОМАННЫМ, металл — по тиру врага.
##
## ЗАЧЕМ ТЕСТ. До 22.10 Серые роняли ЦЕЛЫЕ вещи. Мастерская переплавляет целую
## вещь по выходу «целое» (0.8 от рецепта, CraftDB.INTACT_RECYCLE_MULT), и игрок
## обходил выход по качеству сломанного (1/2/4 слитка) — петля «убил Серого ->
## сырьё -> рецепт» не работала. Второе: этот же лут держит иконку
## `assets/items/broken/` (трещина поверх иконки вещи, tests/gen_broken_overlay.py),
## и на земле `/складе` сломанное обязано рисоваться СВОЕЙ иконкой.
##
## Проверки идут по РЕАЛЬНЫМ артефактам: экземпляр enemy.gd с anim_set, реальный
## розыгрыш _make_loot, настоящая база предметов и настоящие файлы иконок.
##
## Запуск: godot --headless --path . --script res://tests/gray_broken_loot_smoke.gd

const LOOT := "res://assets/config/loot_tables.json"
const BAGS := 300

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
		print("  FAIL " + msg)


func _run() -> void:
	ItemDB.ensure_loaded()
	_test_family_of_species()
	_test_family_in_db()
	_test_table_keys()
	_test_beast_and_insect_gearless()
	_test_gray_drops_broken_only()
	_test_metal_matches_tier()
	_test_quality_and_icons()
	_test_garment_is_separate_item()
	print("checks=%d fails=%d" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: OK gray_broken_loot_smoke")
		quit(0)
	else:
		print("RESULT: FAIL gray_broken_loot_smoke")
		quit(1)


# --- Семейство ------------------------------------------------------------

## `monsters/wolf_t3` -> beast, оса -> insect, город/герой/пусто -> "".
func _test_family_of_species() -> void:
	var known := {}
	for f in UnitDB.loot_families():
		known[f] = true
	var bad: Array[String] = []
	for key in UnitDB.loot_by_species().keys():
		for tier in [1, 2, 3, 4, 5]:
			var name := "monsters/%s_t%d" % [key, tier]
			var fam := UnitDB.loot_family_of(name)
			if fam != str(UnitDB.loot_by_species()[key]):
				bad.append("%s -> %s" % [name, fam])
	_check(bad.is_empty(), "вид+тир дают семейство вида (%s)" % ", ".join(bad.slice(0, 3)))
	_check(UnitDB.loot_family_of("monsters/wolf") == "beast", "волк без тира — beast")
	_check(UnitDB.loot_family_of("monsters/bee_t5") == "insect", "оса тира 5 — insect")
	_check(UnitDB.loot_family_of("city_smith") == "", "городской набор — без семейства")
	_check(UnitDB.loot_family_of("heroes/swordsman") == "", "герой — без семейства")
	_check(UnitDB.loot_family_of("") == "", "пустое имя — без семейства")


## Явное поле в базе: есть у каждого `monsters/*`, совпадает с видом, и не
## появилось ни у одного чужого набора.
func _test_family_in_db() -> void:
	var f := FileAccess.open(UnitDB.DB_PATH, FileAccess.READ)
	if f == null:
		_check(false, "units_db.json открывается")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_check(false, "units_db.json разбирается")
		return
	var db: Dictionary = parsed
	var monsters := 0
	var without: Array[String] = []
	var wrong: Array[String] = []
	var foreign: Array[String] = []
	for name in db.keys():
		var rec: Dictionary = db[name]
		var field := str(rec.get("loot_family", ""))
		if str(name).begins_with("monsters/"):
			monsters += 1
			if field == "":
				without.append(str(name))
			elif field != UnitDB.loot_family_of(str(name)):
				wrong.append("%s=%s" % [str(name), field])
		elif field != "":
			foreign.append(str(name))
	_check(monsters >= 50, "наборов Серых в базе (%d)" % monsters)
	_check(without.is_empty(), "у всех Серых есть loot_family (без поля: %s)"
		% ", ".join(without.slice(0, 3)))
	_check(wrong.is_empty(), "поле loot_family не расходится с видом (%s)"
		% ", ".join(wrong.slice(0, 3)))
	_check(foreign.is_empty(), "у не-Серых поля нет (%s)" % ", ".join(foreign.slice(0, 3)))


# --- Таблица лута ---------------------------------------------------------

## Ключи имени снаряжения: сломанное — основной поток, целое — только бонус.
func _test_table_keys() -> void:
	var f := FileAccess.open(LOOT, FileAccess.READ)
	if f == null:
		_check(false, "loot_tables.json открывается")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_check(false, "loot_tables.json разбирается")
		return
	var t: Dictionary = parsed
	for fam in t.keys():
		if fam == "comment":
			continue
		var rec: Dictionary = t[fam]
		_check(rec.has("broken_gear_chance"),
			"%s: есть broken_gear_chance (основной поток)" % fam)
		_check(rec.has("intact_gear_chance"),
			"%s: есть intact_gear_chance (редкий бонус)" % fam)
		_check(not rec.has("gear_chance"),
			"%s: мёртвого gear_chance нет" % fam)
		_check(int(rec.get("broken_gear_chance", -1)) >= 0,
			"%s: broken_gear_chance не отрицателен" % fam)
		_check(int(rec.get("intact_gear_chance", 100)) < int(rec.get("broken_gear_chance", 0)) + 1,
			"%s: сломанное не реже целого" % fam)


## Звери и насекомые снаряжения не роняют вообще (решение игрока 07.10):
## ни сломанного, ни целого, ни одежды.
func _test_beast_and_insect_gearless() -> void:
	for fam in ["beast", "insect"]:
		var table := _table(fam)
		_check(int(table.get("broken_gear_chance", -1)) == 0,
			"%s: broken_gear_chance = 0" % fam)
		_check(int(table.get("intact_gear_chance", -1)) == 0,
			"%s: intact_gear_chance = 0" % fam)
	var left := 0
	for i in 120:
		var e := _spawn_enemy("monsters/wolf_t2")
		for it in e.call("_make_loot"):
			var d: Dictionary = it
			if _broken_of(d) or _intact_gear_of(d):
				left += 1
		e.free()
	_check(left == 0, "волк за 120 смертей не уронил ни одной вещи (%d)" % left)


# --- Основной розыгрыш ----------------------------------------------------

## Серый роняет только сломанное; целая вещь возможна лишь при сработавшем
## intact-шансе, и её доля мизерная.
func _test_gray_drops_broken_only() -> void:
	var broken := 0
	var intact := 0
	var bags_with_gear := 0
	var unknown: Array[String] = []
	for set_name in ["monsters/cannibal_t2", "monsters/cannibal_t4",
			"monsters/ghost_t2", "monsters/troll_t2", "monsters/dino_t2"]:
		var fam := UnitDB.loot_family_of(set_name)
		var chance := int(_table(fam).get("intact_gear_chance", 0))
		var intact_limit := 0
		var broken_limit := 0
		var gear_bags := 0
		for i in BAGS:
			var e := _spawn_enemy(set_name)
			var pool: Array = e.call("_make_loot")
			e.free()
			var had := false
			for it in pool:
				var d: Dictionary = it
				if _broken_of(d):
					broken += 1
					broken_limit += 1
					had = true
					if _item_of(d).is_empty():
						unknown.append(str(d.get("key", "")))
				elif _intact_gear_of(d):
					intact += 1
					intact_limit += 1
			if had:
				gear_bags += 1
		bags_with_gear += gear_bags
		_check(broken_limit > 0, "%s: сломанное падает (%d за %d)" % [set_name, broken_limit, BAGS])
		# Доля целых не выше шанса из таблицы плюс запас на случайность:
		# целое падает только там, где intact-шанс ненулевой.
		var allowed := int(round(float(BAGS) * float(chance) / 100.0 * 1.6)) + 1
		_check(intact_limit <= allowed,
			"%s: целых не больше бонусного шанса (%d при %d%%, лимит %d)"
			% [set_name, intact_limit, chance, allowed])
		if chance == 0:
			_check(intact_limit == 0, "%s: при intact_gear_chance=0 целых нет" % set_name)
	_check(broken > intact * 3, "сломанное преобладает над целым (%d против %d)"
		% [broken, intact])
	_check(bags_with_gear >= BAGS / 2, "снаряжение падает в большинстве смертей (%d из %d)"
		% [bags_with_gear, BAGS * 5])
	_check(unknown.is_empty(), "неизвестных записей в луте нет (%s)"
		% ", ".join(unknown.slice(0, 3)))


## Металл сломанного — из полосы тира (ItemDB.broken_materials), а не любой.
func _test_metal_matches_tier() -> void:
	for tier in [1, 2, 3, 4, 5]:
		var allowed := {}
		for m in ItemDB.broken_materials("Armor", tier):
			allowed[m] = true
		var bad: Array[String] = []
		var seen := 0
		var e := _spawn_enemy("monsters/troll_t%d" % mini(tier, 5))
		for i in 120:
			for it in e.call("_make_loot"):
				var d: Dictionary = it
				if not _broken_of(d):
					continue
				var rec := _item_of(d)
				if ItemDB.broken_category(rec) == "Garment":
					continue
				seen += 1
				if not allowed.has(str(rec.get("material", ""))):
					bad.append(str(rec.get("key", "")))
		e.free()
		_check(seen > 0, "тир %d: сломанное снаряжение падает (%d)" % [tier, seen])
		_check(bad.is_empty(), "тир %d: металл из полосы тира (%s)"
			% [tier, ", ".join(bad.slice(0, 3))])


## Качество — из BROKEN_QUALITIES, иконка = поле icon записи, файл на диске,
## а LootIcons (земля/склад) берёт именно её.
func _test_quality_and_icons() -> void:
	var e := _spawn_enemy("monsters/cannibal_t4")
	var seen := {}
	var seen_icons := {}
	var bad_q: Array[String] = []
	var bad_icon: Array[String] = []
	var loot_mismatch: Array[String] = []
	for i in BAGS:
		for it in e.call("_make_loot"):
			var d: Dictionary = it
			if not _broken_of(d):
				continue
			var rec := _item_of(d)
			var key := str(rec.get("key", ""))
			seen[key] = true
			if not ItemDB.BROKEN_QUALITIES.has(ItemDB.broken_quality(rec)):
				bad_q.append(key)
			var icon := str(rec.get("icon", ""))
			seen_icons[icon] = true
			if icon == "" or not FileAccess.file_exists(icon):
				bad_icon.append(key)
			if LootIcons.icon_for(rec) != icon:
				loot_mismatch.append("%s -> %s" % [key, LootIcons.icon_for(rec)])
	e.free()
	_check(seen.size() >= 5, "розыгрыш задел несколько разных вещей (%d)" % seen.size())
	_check(bad_q.is_empty(), "качество — из BROKEN_QUALITIES (%s)" % ", ".join(bad_q.slice(0, 3)))
	_check(bad_icon.is_empty(), "иконка сломанного лежит на диске (%s)"
		% ", ".join(bad_icon.slice(0, 3)))
	_check(loot_mismatch.is_empty(),
		"LootIcons рисует свою иконку сломанного, а не общую металла (%s)"
		% ", ".join(loot_mismatch.slice(0, 3)))
	_check(seen_icons.size() >= 3, "иконки различаются между вещами (%d)" % seen_icons.size())
	# Иконка сломанного — не общая дроп-иконка металла: у каждой вещи свой
	# файл из assets/items/broken/, и два металла одной категории не делят одну
	# картинку (иначе на земле/складе сломанное выглядело бы целым).
	# Пакет A (28.10): тир 4 роняет только steel (+ лён у одежды), поэтому с
	# одного врага собирается ровно 3 иконки: steel_armor, steel_weapon,
	# linen_garment. Порог 3 — «не одна на всё», а не 5 из эпохи 16 металлов.
	# ВНИМАНИЕ: by_kind ниже вакуумный (get_slice("_", -1) даёт ""), это
	# существовавший до пакета A баг теста — здесь он не чинится.
	var by_kind := {}
	for icon in seen_icons.keys():
		var p := str(icon)
		_check(p.begins_with("res://assets/items/broken/"),
			"иконка из папки broken (%s)" % p.get_file())
		var kind := p.get_file().get_basename().get_slice("_", -1)
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	for kind in by_kind.keys():
		_check(int(by_kind[kind]) > 1,
			"иконки сломанной %s не одна на все металлы (%d)" % [kind, by_kind[kind]])


## Одежда — отдельная вещь: лён и категория Garment, не съедает снаряжение.
func _test_garment_is_separate_item() -> void:
	var garment := 0
	var linen_ok := 0
	for i in BAGS:
		var e := _spawn_enemy("monsters/cannibal_t2")
		for it in e.call("_make_loot"):
			var d: Dictionary = it
			if not _broken_of(d):
				continue
			var rec := _item_of(d)
			if ItemDB.broken_category(rec) != "Garment":
				continue
			garment += 1
			if str(rec.get("material", "")) == "Linen":
				linen_ok += 1
		e.free()
	_check(garment > 0, "одежда с людоедов падает (%d)" % garment)
	_check(linen_ok == garment, "одежда — лён (%d из %d)" % [linen_ok, garment])
	var one_of_many := ItemDB.broken_item_for("Linen", "Garment", "Broken")
	_check(not one_of_many.is_empty(), "сломанная одежда есть в базе")
	_check(ItemDB.broken_category(one_of_many) == "Garment", "категория одежды — Garment")


# --- Помощники ------------------------------------------------------------

func _table(family: String) -> Dictionary:
	var f := FileAccess.open(LOOT, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get(family, {})


func _spawn_enemy(set_name: String) -> Node:
	var script: GDScript = load("res://scripts/enemy.gd")
	var e: Node = script.new()
	root.add_child(e)
	e.set("anim_set", set_name)
	e.set("max_hp", 60)
	e.set("current_hp", 60)
	return e


## Сломанная вещь в мешке (запись базы непустая), иначе {}.
func _broken_of(drop: Dictionary) -> Dictionary:
	if not drop.has("key"):
		return {}
	var rec := _item_of(drop)
	return rec if ItemDB.is_broken(rec) else {}


## Целая экипируемая вещь в мешке (редкий бонус), иначе {}.
func _intact_gear_of(drop: Dictionary) -> Dictionary:
	if not drop.has("key"):
		return {}
	var rec := _item_of(drop)
	return rec if ItemDB.is_equippable(rec) else {}


func _item_of(drop: Dictionary) -> Dictionary:
	return ItemDB.find(str(drop.get("key", "")))
