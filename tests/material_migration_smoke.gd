extends SceneTree
## Проверка миграции материалов: фэнтезийные мифрил/метеорит/адамант/кристалл
## заменены на придуманные тербий/плутоний/титаний/радий
## (tests/gen_material_migration.py, assets/loot_icons/README.md).
##
## Материал вшит в четыре поля (material, key, name_en, name_ru) — проверяем все.
##
## Запуск: godot --headless --path . --script res://tests/material_migration_smoke.gd

const DB_PATH := "res://assets/items/item_db.json"
const INGOT_DIR := "res://assets/professions/blacksmith/"

## старое имя -> (новое имя, старая ru-форма, новая ru-форма, ожидаемое число)
const RENAMES := {
	"Adamantium": {"to": "Titanium", "ru_old": "адамантий", "ru_new": "титаний", "count": 61},
	"Mithrill":   {"to": "Terbium",   "ru_old": "мифрил",   "ru_new": "тербий",   "count": 43},
	"Meteoric":   {"to": "Plutonium", "ru_old": "метеорит", "ru_new": "плутоний", "count": 32},
	"Crystal":    {"to": "Radium",    "ru_old": "кристалл", "ru_new": "радий",     "count": 16},
}
## Металлы, которые переплавляются в слиток (id иконки = id в loot_icons).
const SMELTABLE := {
	"Bronze": "bronze", "Iron": "iron", "Steel": "steel",
	"Silver": "argentum", "Gold": "lutetium",
	"Titanium": "titanium", "Terbium": "terbium",
	"Plutonium": "plutonium", "Radium": "radium",
}
## Неметаллы: кузнец их не берёт (решение игрока).
const NON_METALS := ["Leather", "Hard Leather", "Dragon Leather", "Wood", "Magic Wood", "None"]

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

	# 1. Старых имён не осталось НИГДЕ в файле.
	for old in RENAMES:
		var info: Dictionary = RENAMES[old]
		var hits: int = text.count(old) + text.count(str(info["ru_old"]))
		_check(hits == 0, "нет остатков '%s'/'%s' в файле (%d)" % [old, str(info["ru_old"]), hits])

	# 2. Новые материалы на месте, с ожидаемым числом предметов.
	# Считаем ТОЛЬКО перенесённые предметы оригинала: слитки из
	# gen_ingot_items.py — отдельная сущность со своим названием в родительном
	# падеже («Слиток титания»), их проверяет blacksmith_smoke.
	var by_material := {}
	for it in items:
		var d: Dictionary = it
		var m := str(d.get("material", ""))
		if m == "" or str(d.get("type", "")) == "Ingot":
			continue
		by_material[m] = int(by_material.get(m, 0)) + 1
	for old in RENAMES:
		var info2: Dictionary = RENAMES[old]
		var new_name := str(info2["to"])
		var got: int = int(by_material.get(new_name, 0))
		_check(got == int(info2["count"]),
			"%s: %d предметов (ожидалось %d)" % [new_name, got, int(info2["count"])])

	# 3. Все четыре поля переписаны согласованно.
	var key_mismatch := 0
	var ru_mismatch := 0
	var en_mismatch := 0
	for it in items:
		var d: Dictionary = it
		if str(d.get("type", "")) == "Ingot":
			continue  # слитки не участвовали в миграции
		var m := str(d.get("material", ""))
		var key := str(d.get("key", ""))
		var en := str(d.get("name_en", ""))
		var ru := str(d.get("name_ru", ""))
		for old2 in RENAMES:
			var info3: Dictionary = RENAMES[old2]
			var new_name := str(info3["to"])
			if m != new_name:
				continue
			# key/en содержат новое имя и НЕ содержат старое
			if not key.contains(new_name) or key.contains(old2):
				key_mismatch += 1
			if not en.contains(new_name) or en.contains(old2):
				en_mismatch += 1
			# ru содержит новое слово и не содержит старое
			if not ru.contains(str(info3["ru_new"])) or ru.contains(str(info3["ru_old"])):
				ru_mismatch += 1
	_check(key_mismatch == 0, "key переписан у всех (расхождений: %d)" % key_mismatch)
	_check(en_mismatch == 0, "name_en переписан у всех (расхождений: %d)" % en_mismatch)
	_check(ru_mismatch == 0, "name_ru переписан у всех (расхождений: %d)" % ru_mismatch)

	# 4. Каждый переплавляемый металл есть в данных, и для него есть иконка слитка.
	for metal in SMELTABLE:
		var count: int = int(by_material.get(metal, 0))
		_check(count > 0, "металл '%s' есть в item_db (%d предметов)" % [metal, count])
		var icon_id := str(SMELTABLE[metal])
		_check(ResourceLoader.exists("%s%s_ingot.png" % [INGOT_DIR, icon_id]),
			"иконка слитка %s_ingot.png есть" % icon_id)

	# 5. Неметаллы остались на месте (их кузнец не берёт, но предметы живы).
	for nm in NON_METALS:
		_check(int(by_material.get(nm, 0)) > 0,
			"неметалл '%s' на месте (%d)" % [nm, int(by_material.get(nm, 0))])

	# 6. Лёгкая/тяжёлая броня не сломалась: кожа и ткань — light, металл — heavy.
	ItemDB.ensure_loaded()
	var light_ok := true
	var heavy_ok := true
	for it2 in items:
		var d2: Dictionary = it2
		var kind := ItemDB.armor_kind(d2)
		if str(d2.get("material", "")) in ["Leather", "Hard Leather", "Dragon Leather", "None"]:
			if kind != "light":
				light_ok = false
		elif str(d2.get("material", "")) in SMELTABLE:
			if kind != "heavy":
				heavy_ok = false
	_check(light_ok, "кожа/ткань по-прежнему лёгкая броня")
	_check(heavy_ok, "металлы по-прежнему тяжёлая броня")

	# 7. Фэнтезийных материалов больше нет в наборе вообще.
	var fantasy := 0
	for m2 in by_material:
		if str(m2) in RENAMES:
			fantasy += 1
	_check(fantasy == 0, "фэнтезийных материалов в наборе не осталось")

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
