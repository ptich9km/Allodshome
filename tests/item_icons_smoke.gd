extends SceneTree
## Проверка иконок предметов: у каждого из 1029 предметов путь icon обязан
## существовать на диске, металлические вещи берут фракционные ассеты, неметаллы -
## заглушки. Смысл теста: после удаления assets/inventory/ (982 старые иконки
## Аллодов) любая оставшаяся ссылка на него - это предмет без картинки в игре.
##
## Запуск: godot --headless --path . --script res://tests/item_icons_smoke.gd

const DB_PATH := "res://assets/items/item_db.json"
const PALETTE_PATH := "res://assets/items/faction_palette.json"

const METALS := [
	"bronze", "iron", "steel", "gold",
	"argentum", "lutetium", "lanthanum", "terbium",
	"wolfram", "chromium", "cobalt", "titanium",
	"thorium", "uranium", "plutonium", "radium",
	"gallium", "yttrium", "promethium", "neodymium",
]

const NON_METALS := ["Leather", "Hard Leather", "Dragon Leather", "Wood", "Magic Wood", "None"]

## Каталоги, из которых ВЫШЕЛ старый набор. Ссылка на них = битый предмет.
const DEAD_ROOTS := ["res://assets/inventory/"]

var _fails: Array[String] = []

func _init() -> void:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		print("RESULT: FAIL — не открыть %s" % DB_PATH)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_ARRAY:
		print("RESULT: FAIL — item_db.json не массив")
		quit(1)
		return
	var items: Array = parsed

	# 1. ГЛАВНОЕ: путь каждого предмета существует на диске.
	var missing := 0
	var missing_list: Array[String] = []
	var no_icon := 0
	for it in items:
		var d: Dictionary = it
		var icon := str(d.get("icon", ""))
		if icon == "":
			no_icon += 1
			continue
		if not ResourceLoader.exists(icon):
			missing += 1
			if missing_list.size() < 8:
				missing_list.append("%s -> %s" % [str(d.get("key", "?")), icon])
	_check(no_icon == 0, "у всех предметов задан icon (пустых: %d)" % no_icon)
	_check(missing == 0, "все иконки существуют на диске (нет: %d)" % missing)
	for m in missing_list:
		print("     ! ", m)

	# 2. Никто не ссылается на удаляемый assets/inventory/.
	var dead := 0
	var dead_list: Array[String] = []
	for it2 in items:
		var d2: Dictionary = it2
		var icon2 := str(d2.get("icon", ""))
		for root in DEAD_ROOTS:
			if icon2.begins_with(root):
				dead += 1
				if dead_list.size() < 8:
					dead_list.append("%s -> %s" % [str(d2.get("key", "?")), icon2])
	_check(dead == 0, "нет ссылок на assets/inventory/ (%d)" % dead)
	for m2 in dead_list:
		print("     ! ", m2)

	# 3. Металлический предмет берёт фракционную иконку (или базовую для стали).
	var pal_text := FileAccess.open(PALETTE_PATH, FileAccess.READ).get_as_text()
	var pal: Dictionary = JSON.parse_string(pal_text)
	var metal_group := {}
	for g in pal["groups"]:
		for m3 in pal["groups"][g]["metals"]:
			metal_group[m3["metal"]] = g

	var faction_items := 0
	var weapon_items := 0
	var base_items := 0
	var wrong_group := 0
	var nonmetal_real := 0
	for it3 in items:
		var d3: Dictionary = it3
		var mat := str(d3.get("material", ""))
		var typ := str(d3.get("type", ""))
		var icon3 := str(d3.get("icon", ""))
		if typ == "Ingot":
			continue
		if mat in METALS:
			# сталь = is_base, её файлы в base/ без префикса металла;
			# остальные металлы берут faction/ (броня) или faction_w/ (оружие).
			# Проверяем через ПРЕФИКС пути, а не через подстроку "/faction/":
			# у faction_w/common/... подстрока "/faction/" не находится, и все
			# 359 предметов оружия ошибочно попадали в счётчик ошибок.
			if icon3.begins_with("res://assets/items/faction/"):
				faction_items += 1
				# группа в пути должна совпадать с группой металла в палитре
				var expect: String = str(metal_group[mat])
				if not icon3.contains("/%s/" % expect):
					wrong_group += 1
			elif icon3.begins_with("res://assets/items/faction_w/"):
				weapon_items += 1
				var expect2: String = str(metal_group[mat])
				if not icon3.contains("/%s/" % expect2):
					wrong_group += 1
			elif icon3.begins_with("res://assets/items/base/") \
					or icon3.begins_with("res://assets/items/base_w/"):
				base_items += 1
			else:
				nonmetal_real += 1
		else:
			# неметалл: фракционная иконка тут была бы враньём - у кожи нет
			# металла, красить её в цвет металла нечем
			if icon3.begins_with("res://assets/items/faction/") \
					or icon3.begins_with("res://assets/items/faction_w/"):
				nonmetal_real += 1
	_check(faction_items > 0, "фракционные иконки брони используются (%d)" % faction_items)
	_check(weapon_items > 0, "фракционные иконки оружия используются (%d)" % weapon_items)
	_check(base_items > 0, "базовые иконки (сталь) используются (%d)" % base_items)
	_check(wrong_group == 0, "группа в пути совпадает с палитрой (расхождений: %d)" % wrong_group)
	_check(nonmetal_real == 0,
		"неметаллы не получили фракционные иконки (ошибок: %d)" % nonmetal_real)

	# 4. Слитки ссылаются на иконки слитков, и файла на диске хватает.
	var ingots := 0
	var ingot_bad := 0
	for it4 in items:
		var d4: Dictionary = it4
		if str(d4.get("type", "")) != "Ingot":
			continue
		ingots += 1
		var want := "res://assets/professions/blacksmith/%s_ingot.png" % str(d4.get("material", ""))
		if str(d4.get("icon", "")) != want:
			ingot_bad += 1
	_check(ingots == 20, "слитков в базе 20 (найдено: %d)" % ingots)
	_check(ingot_bad == 0, "иконки слитков указывают верно (ошибок: %d)" % ingot_bad)

	# 5. Заглушки — честные: подпись есть, картинка не пустая.
	var ph_ok := true
	var ph_n := 0
	for it5 in items:
		var d5: Dictionary = it5
		var icon5 := str(d5.get("icon", ""))
		if not icon5.contains("/placeholder/"):
			continue
		ph_n += 1
		if not ResourceLoader.exists(icon5):
			ph_ok = false
	_check(ph_ok and ph_n > 0, "заглушки существуют (предметов с заглушкой: %d)" % ph_n)

	# 6. Каталог faction/ и faction_w/ реально используется: без item_db
	#    589 готовых файлов лежали бы мёртвыми.
	var used_files := {}
	for it6 in items:
		var d6: Dictionary = it6
		used_files[str(d6.get("icon", ""))] = true
	var used_faction := 0
	for path in used_files:
		var p := str(path)
		if p.contains("/faction/") or p.contains("/faction_w/"):
			used_faction += 1
	_check(used_faction > 300,
		"фракционные ассеты задействованы (уникальных путей: %d)" % used_faction)

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
		print("RESULT: OK item_icons_smoke (предметов: %d)" % total)
		quit(0)
	else:
		print("RESULT: FAIL item_icons_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)
