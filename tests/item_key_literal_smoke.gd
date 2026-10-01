extends SceneTree
## Проверка того, что предметы, которые КОД достаёт по строковому ключу,
## реально существуют.
##
## ЗАЧЕМ. ItemDB.find() на несуществующем ключе возвращает пустой словарь, а не
## ошибку. Из-за этого строка вида equip_item(ItemDB.find("Common Iron Long Sword"))
## выглядит рабочей, а на деле герой остаётся без оружия: панель предметов
## пустая, слот в инвентаре не заполнен, и никакой тест этого не замечает.
## Реальный случай: после перевода металлов в нижний регистр (bronze, iron)
## стартовое снаряжение воина перестало надеваться - это нашёл
## equipment_combat_smoke через проверку "надето оружие".
##
## Тест статический: он разбирает исходники .gd на строковые литералы вида
## "<Качество> <материал> <тип>" и сверяет их с ключами item_db.json.
##
## Запуск: godot --headless --path . --script res://tests/item_key_literal_smoke.gd

const DB_PATH := "res://assets/items/item_db.json"

## Каталоги с .gd, где строковые ключи предметов допустимы.
const SCAN_DIRS := ["res://scripts"]

## Материалы металлов в том виде, как они лежат в ключах (нижний регистр).
const METALS := [
	"bronze", "iron", "steel", "gold",
	"argentum", "lutetium", "lanthanum", "terbium",
	"wolfram", "chromium", "cobalt", "titanium",
	"thorium", "uranium", "plutonium", "radium",
	"gallium", "yttrium", "promethium", "neodymium",
]

## Неметаллы в ключах остались с заглавной буквы (см. gen_metal_case_migration.py).
const NON_METALS := ["Leather", "Hard Leather", "Dragon Leather", "Wood", "Magic Wood"]

## Типы предметов, по которым ключ узнаётся. Взяты из item_db.gd.
const TYPES := [
	"Dagger", "Short Sword", "Long Sword", "Bastard Sword", "Two Handed Sword",
	"Spiked Club", "Club", "Mace", "Morning Star", "Pick Hammer", "War Hammer",
	"Axe", "Two Handed Axe", "Pike", "Lance", "Halberd", "Staff", "Shaman Staff",
	"Short Bow", "Long Bow", "Crossbow",
	"Buckler", "Small Shield", "Large Shield", "Tower Shield",
	"Helm", "Full Helm", "Plate Helm", "Chain Helm", "Cap", "Hat", "Low Hat",
	"Cloak", "Cape", "Cuirass", "Plate Cuirass", "Chain Mail", "Scale Mail",
	"Robe", "Dress", "Bracers", "Plate Bracers", "Gauntlets", "Plate Gauntlets",
	"Scale Gauntlets", "Chain Gauntlets", "Gloves",
	"Plate Boots", "Boots", "Shoes", "Chain Boots", "Amulet", "Ring", "Mail",
]

## Шаблон ключа: качество + материал + тип. Порядок именно такой в item_db.
const KEY_RE := "^((?:[A-Z][a-z]+ )?)(bronze|iron|steel|gold|argentum|lutetium|lanthanum|terbium|wolfram|chromium|cobalt|titanium|thorium|uranium|plutonium|radium|gallium|yttrium|promethium|neodymium|Leather|Hard Leather|Dragon Leather|Wood|Magic Wood) (.+)$"

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

	var keys := {}
	for it in items:
		keys[str((it as Dictionary).get("key", ""))] = true
	print("КЛЮЧЕЙ В БАЗЕ: %d" % keys.size())

	# Собираем ВСЕ строковые литералы из .gd, похожие на ключ предмета.
	var literals := {}   # literal -> "file:line"
	for dir in SCAN_DIRS:
		_scan_dir(dir, keys, literals)

	print("ПОХОЖИХ ЛИТЕРАЛОВ: %d" % literals.size())
	var missing := 0
	for lit in literals:
		if not keys.has(lit):
			missing += 1
			print("   НЕТ В БАЗЕ: '%s'  (%s)" % [lit, str(literals[lit])])
	_check(missing == 0, "все ключевые литералы есть в item_db (нет: %d)" % missing)

	# Отдельно: стартовое снаряжение обязано надеваться (реальный баг).
	_check(_starter_keys_exist(keys), "стартовое снаряжение существует в базе")

	# Отдельно: если материал - металл, он обязан встречаться в ключе С ТОЧНЫМ
	# регистром: металлы внизу ("Common iron Helm"). Неметаллов, кроме льна,
	# в базе больше нет (кожа и дерево удалены 01.10).
	# Материал "None"/"<null>" в ключ не входит вовсе (травы "Herb Green Leaf"),
	# поэтому для него проверка не выполняется.
	var bad_case: Array[String] = []
	for it2 in items:
		var d: Dictionary = it2
		var mat := str(d.get("material", ""))
		var key := str(d.get("key", ""))
		if mat == "" or key == "" or mat == "None" or mat == "<null>":
			continue
		if mat in METALS:
			# слитки построены как "bronze Ingot" - материал в начале без ведущего
			# пробела, остальные ключи как "Common bronze Helm"
			if not key.contains(mat):
				bad_case.append("%s (material=%s, ожидалось слово '%s' в нижнем регистре)"
					% [key, mat, mat])
		elif mat in NON_METALS:
			if not key.contains(mat):
				bad_case.append("%s (material=%s, ожидалось слово '%s' с заглавной)"
					% [key, mat, mat])
	_check(bad_case.is_empty(),
		"регистр материала в ключе совпадает с полем material (расхождений: %d)"
		% bad_case.size())
	for b in bad_case.slice(0, 8):
		print("     ! ", b)

	_report(items.size())

func _starter_keys_exist(keys: Dictionary) -> bool:
	## Ключи из player.gd:_grant_starter_set. Дублируются здесь намеренно:
	## если в коде поменяют стартовый набор, тест об этом скажет.
	var want := ["Common iron Long Sword", "Common Wood Staff",
		"Common iron Buckler"]
	var ok := true
	for w in want:
		if not keys.has(w):
			print("   НЕТ СТАРТОВОГО: '%s'" % w)
			ok = false
	return ok

func _scan_dir(dir_path: String, keys: Dictionary, literals: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			_scan_dir(dir_path.path_join(name), keys, literals)
		elif name.ends_with(".gd"):
			_scan_file(FileAccess.open(dir_path.path_join(name), FileAccess.READ),
				dir_path.path_join(name), keys, literals)
		name = dir.get_next()
	dir.list_dir_end()

func _scan_file(f: FileAccess, path: String, keys: Dictionary, literals: Dictionary) -> void:
	if f == null:
		return
	var line_no := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_no += 1
		# пропускаем комментарии: они не исполняются и ключами не являются
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		var rx := RegEx.new()
		rx.compile("\"([^\"]+)\"")
		for m in rx.search_all(line):
			var lit := m.get_string(1)
			if not _looks_like_key(lit, keys):
				continue
			if literals.has(lit):
				continue
			literals[lit] = "%s:%d" % [path.get_file(), line_no]
		f = f  # keep static analyzer quiet about unused reassign

## Похож ли литерал на ключ предмета: есть металл/неметалл + известный тип.
func _looks_like_key(lit: String, keys: Dictionary) -> bool:
	if keys.has(lit):
		return true   # существующий ключ - точно литерал-ключ
	var re := RegEx.new()
	re.compile(KEY_RE)
	if re.search(lit) == null:
		return false
	var m := re.search(lit)
	var typ := str(m.get_string(3))
	for t in TYPES:
		if typ == t or typ.begins_with(t):
			return true
	return false

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report(total: int) -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK item_key_literal_smoke (предметов: %d)" % total)
		quit(0)
	else:
		print("RESULT: FAIL item_key_literal_smoke (провалено: %d)" % _fails.size())
		for x in _fails:
			print("  - ", x)
		quit(1)