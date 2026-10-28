extends SceneTree
## Проверка материалов item_db: 4 металла в нижнем регистре, серебро
## удалено, неметаллы на месте, кузница знает все металлы.
##
## ОБНОВЛЁН (пакет A, 28.10): 16 фракционных металлов удалены из игры —
## слитки, вещи, лом, иконки. Раньше здесь были 20 металлов и покрытие
## слотов у 12 сгенерированных; теперь вместо них работает сторож
## REMOVED_FACTION: фракционные металлы не должны вернуться в базу.
##
## Запуск: godot --headless --path . --script res://tests/material_migration_smoke.gd

const DB_PATH := "res://assets/items/item_db.json"
const INGOT_DIR := "res://assets/professions/blacksmith/"

## Металлы кузницы (ровно ItemDB._SMELTABLE): пакет A оставил 4 общих.
const METALS := [
	"bronze", "iron", "steel", "gold",
]

## 16 фракционных металлов, удалённых пакетом A (28.10). Ни слитка, ни
## вещи, ни лома, ни иконки - проверяем всё, чтобы чистка не откатилась.
const REMOVED_FACTION := [
	"argentum", "lutetium", "lanthanum", "terbium",
	"wolfram", "chromium", "cobalt", "titanium",
	"thorium", "uranium", "plutonium", "radium",
	"gallium", "yttrium", "promethium", "neodymium",
]

## Пережиток Аллодов, заменён argentum.
const DROPPED := ["Silver", "silver"]

## Неметаллы: кузнец их не берёт (решение игрока), но предметы живы.
## Регистр СОХРАНЁН с заглавной - см. gen_metal_case_migration.py.
## "Linen" - лён, ткань для плащей (gen_cloak_items.py): игрок уточнил, что
## плащ и рубашка - тряпки, поэтому им не нужны вариации по металлам.
## "Fabric"/"Essence" добавлены 07.10 вместе с мастерской. Это НЕ ткань в
## смысле одежды (она осталась "Linen"), а ресурсы крафта: ткань
## (переработка сломанной одежды) и магическая эссенция. Их нельзя было
## сделать material: "Linen": тогда is_smeltable() их не отсеял бы и логика
## «ломается только ткань» стала бы нечитаемой.
const NON_METALS := ["Linen", "None", "Fabric", "Essence"]

## Материалы, удалённые из базы 01.10 по решению игрока: кожа и дерево не
## нужны в игре, в Аллодах II их не было. Проверяем, что они не вернулись.
## Исключение - посохи: их арт под металлы будет нарезан отдельно, до тех
## пор деревянный посох мага должен существовать.
const REMOVED_MATERIALS := ["Leather", "Hard Leather", "Dragon Leather",
	"Wood", "Magic Wood"]
const REMOVED_EXCEPT_TYPES := ["Staff", "Shaman Staff"]

## Фэнтезийные имена оригинала: не должны встретиться нигде в файле.
const FANTASY := ["Mithrill", "Adamantium", "Meteoric", "Crystal",
	"мифрил", "адамантий", "метеорит", "кристалл"]

## Русские словоформы металлов, которые должны быть в name_ru.
const RU_WORD := {
	"bronze": "бронз", "iron": "желез", "steel": "стал", "gold": "золот",
}

## Предметы, у которых поля material нет ВООБЩЕ (книги, зелья, свитки).
## Это не «неизвестный материал» - это отсутствие поля, и такие предметы
## не должны попадать под проверку списка известных материалов.
const NO_MATERIAL_TYPES := ["Book", "Potion", "Scroll", "SuperScroll", "Quest", "Herb"]

var _fails: Array[String] = []

func _init() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		print("RESULT: FAIL — не открыть %s" % DB_PATH)
		quit(1)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		print("RESULT: FAIL — item_db.json не массив")
		quit(1)
		return
	var items: Array = parsed

	# 1. Фэнтезийных имён не осталось НИГДЕ в файле.
	for old in FANTASY:
		var hits := text.count(old)
		_check(hits == 0, "нет остатков '%s' (%d)" % [old, hits])

	# 2. Серебра нет ни в одном поле.
	for drop in DROPPED:
		var d_hits := text.count(drop)
		_check(d_hits == 0, "серебро '%s' отсутствует (%d)" % [drop, d_hits])

	# 3. Все 4 металла присутствуют, в нижнем регистре, и 16 фракционных
	#    металлов не вернулись (слиток/вещь/лом - любого типа).
	ItemDB.ensure_loaded()
	var by_material := {}
	var types_by_material := {}
	for it in items:
		var d: Dictionary = it
		var m := str(d.get("material", ""))
		# JSON null приходит в Godot как строка "<null>", и без этой проверки
		# 96 книг/зелий/свитков попадали в список "неизвестных материалов".
		if m == "" or m == "<null>":
			continue
		by_material[m] = int(by_material.get(m, 0)) + 1
		var t := str(d.get("type", ""))
		if t == "Ingot":
			continue
		if not types_by_material.has(m):
			types_by_material[m] = {}
		types_by_material[m][t] = true

	for metal in METALS:
		var count: int = int(by_material.get(metal, 0))
		_check(count > 0, "металл '%s' есть в item_db (%d предметов)" % [metal, count])
		_check(metal == metal.to_lower(), "металл '%s' в нижнем регистре" % metal)

	var resurrected: Array[String] = []
	for metal4 in REMOVED_FACTION:
		if int(by_material.get(metal4, 0)) > 0:
			resurrected.append(metal4)
	_check(resurrected.is_empty(),
		"фракционные металлы удалены навсегда (вернулись: %s)"
		% (", ".join(resurrected) if not resurrected.is_empty() else "-"))

	# 4. Нет никаких металлов кроме 4 известных + неметаллов. Предметы без
	#    поля material (книги, зелья, свитки) пропускаем: у них материала нет
	#    по построению, и раньше такой тест ловил "<null> в списке известных".
	var unknown := 0
	var unknown_list: Array[String] = []
	for m2 in by_material:
		var known: bool = m2 in METALS or m2 in NON_METALS \
			or m2 in REMOVED_MATERIALS
		if not known:
			unknown += 1
			unknown_list.append(m2)
	_check(unknown == 0, "все известные материалы в списке (%s)"
		% ", ".join(unknown_list))

	# 5. Неметаллы остались на месте.
	for nm in NON_METALS:
		_check(int(by_material.get(nm, 0)) > 0,
			"неметалл '%s' на месте (%d)" % [nm, int(by_material.get(nm, 0))])

	# 5b. Кожа и дерево удалены и не вернулись (кроме посохов).
	var leaked: Array[String] = []
	for it_rm in items:
		var d_rm: Dictionary = it_rm
		var m_rm := str(d_rm.get("material", ""))
		var t_rm := str(d_rm.get("type", ""))
		if m_rm in REMOVED_MATERIALS and not (t_rm in REMOVED_EXCEPT_TYPES):
			leaked.append(str(d_rm.get("key", "")))
	_check(leaked.is_empty(),
		"кожа/дерево удалены, кроме посохов (найдено: %d%s)" % [
			leaked.size(), (": " + ", ".join(leaked)) if not leaked.is_empty() else ""])

	# 6. У каждого металла есть слиток, ключ в нижнем регистре, иконка на диске.
	var ingot_by_material := {}
	for it2 in items:
		var d2: Dictionary = it2
		if str(d2.get("type", "")) == "Ingot":
			ingot_by_material[str(d2.get("material", ""))] = d2
	for metal2 in METALS:
		var has: bool = ingot_by_material.has(metal2)
		_check(has, "слиток для '%s' есть" % metal2)
		if not has:
			continue
		var ing: Dictionary = ingot_by_material[metal2]
		var want_key := "%s Ingot" % metal2
		_check(str(ing.get("key", "")) == want_key,
			"ключ слитка '%s' = '%s' (получено '%s')"
			% [metal2, want_key, str(ing.get("key", ""))])
		_check(ResourceLoader.exists("%s%s_ingot.png" % [INGOT_DIR, metal2]),
			"иконка слитка %s_ingot.png есть" % metal2)

	# 7. Код кузницы: ingot_key() находит слиток для каждого металла.
	# Проверяем именно через API, а не через поле key в базе: раньше панель
	# строила ключ с заглавной и молча отдавала дефолтный iron.
	for metal3 in METALS:
		var ik := ItemDB.ingot_key(metal3)
		_check(ik != "", "ItemDB.ingot_key('%s') находит слиток" % metal3)

	# 8. is_smeltable: все металлы переплавляются, неметаллы и слитки - нет.
	var smelt_ok := true
	var nonsmelt_ok := true
	for it3 in items:
		var d3: Dictionary = it3
		var m3 := str(d3.get("material", ""))
		var t3 := str(d3.get("type", ""))
		if t3 == "Ingot":
			if ItemDB.is_smeltable(d3):
				nonsmelt_ok = false
		elif m3 in METALS:
			if not ItemDB.is_smeltable(d3):
				smelt_ok = false
		elif m3 in NON_METALS:
			if ItemDB.is_smeltable(d3):
				nonsmelt_ok = false
	_check(smelt_ok, "все металлы переплавляются")
	_check(nonsmelt_ok, "неметаллы и слитки не переплавляются")

	# 9. Кожа и ткань — лёгкая броня, металл — тяжёлая.
	var light_ok := true
	var heavy_ok := true
	for it4 in items:
		var d4: Dictionary = it4
		var kind := ItemDB.armor_kind(d4)
		var m4 := str(d4.get("material", ""))
		if m4 in ["Linen", "None"]:
			if kind != "light":
				light_ok = false
		elif m4 in METALS:
			# Металл = тяжёлая броня, КРОМЕ ткани: Cloak/Cape остаются лёгкими
			# независимо от материала (item_db.gd:158 - is_cloth). Иначе плащ из
			# стали натягивался бы на тяжёлый набор анимации.
			var is_cloth := str(d4.get("type", "")) in ["Cloak", "Cape"]
			if is_cloth:
				if kind != "light":
					light_ok = false
			elif kind != "heavy":
				heavy_ok = false
	_check(light_ok, "кожа/ткань и плащи по-прежнему лёгкая броня")
	_check(heavy_ok, "металлы по-прежнему тяжёлая броня")

	# 10. name_ru каждого металлического предмета содержит русское слово металла.
	var ru_missing := 0
	for it5 in items:
		var d5: Dictionary = it5
		var m5 := str(d5.get("material", ""))
		if not m5 in METALS:
			continue
		var word: String = str(RU_WORD.get(m5, ""))
		var ru := str(d5.get("name_ru", ""))
		if word != "" and not ru.to_lower().contains(word):
			ru_missing += 1
	_check(ru_missing == 0, "name_ru содержит русское имя металла (пропущено: %d)" % ru_missing)

	_report(items.size())

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report(total: int) -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK material_migration_smoke (предметов: %d)" % total)
		quit(0)
	else:
		print("RESULT: FAIL material_migration_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)
