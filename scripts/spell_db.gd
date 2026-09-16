class_name SpellDB
## База заклинаний из assets/spells/spells_db.json (собрана из spells.txt +
## castSpell-свитков item_db + projectiles.reg). Даёт сферу, урон, ману,
## снаряд-анимацию и иконку по имени заклинания ("Fire_Ball").

const DB_PATH := "res://assets/spells/spells_db.json"

static var _db: Dictionary = {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		push_error("SpellDB: не открыть " + DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_db = parsed

## Данные заклинания по имени ("Fire_Ball") или {}.
static func get_spell(name: String) -> Dictionary:
	ensure_loaded()
	return _db.get(name, {})

## Книга стихии ("Book Fire") -> имя сферы ("Fire"). "" если не книга.
static func sphere_of_book(book_name: String) -> String:
	var n := str(book_name).to_lower()
	if n.begins_with("book "):
		var sphere := n.trim_prefix("book ").capitalize()
		if sphere in ["Fire", "Water", "Air", "Earth", "Astral"]:
			return sphere
	return ""

## Какие книги стихий есть (для словаря предметов).
static func book_item_names() -> Array:
	return ["Book Fire", "Book Water", "Book Air", "Book Earth", "Book Astral"]

## Заклинания сферы ("Fire") в порядке базы.
static func spells_of_sphere(sphere: String) -> Array:
	ensure_loaded()
	var out: Array = []
	for name in _db:
		if str(_db[name].get("sphere", "")) == sphere:
			out.append(name)
	out.sort()
	return out

## Урон снаряда из базы (база до бонусов).
static func damage(name: String) -> int:
	return int(get_spell(name).get("damage", 0))

## Стоимость маны.
static func mana_cost(name: String) -> int:
	return int(get_spell(name).get("mana_cost", 0))

## Дальность (пиксели; 0 = на себя/без дальности).
static func range_of(name: String) -> float:
	return float(get_spell(name).get("range", 0))

## Радиус области (0 = одиночная цель).
static func area_of(name: String) -> float:
	return float(get_spell(name).get("area", 0))

## Вид: attack/area/heal/buff/wall/self.
static func kind_of(name: String) -> String:
	return str(get_spell(name).get("kind", "buff"))

## Сфера заклинания.
static func sphere_of(name: String) -> String:
	return str(get_spell(name).get("sphere", ""))

## Папка кадров снаряда (assets/projectiles/<folder>/sprites-NNN.png).
static func projectile_folder(name: String) -> String:
	return str(get_spell(name).get("projectile", ""))

## Иконка заклинания (обычная, из inventory -000.png).
static func icon_of(name: String) -> String:
	var o := get_spell(name)
	var icons: Dictionary = o.get("icons", {})
	return str(icons.get("scroll", ""))

## Число кадров анимации снаряда в папке (считаем файлы sprites-NNN.png).
static func projectile_frames(name: String) -> int:
	var folder := projectile_folder(name)
	if folder == "":
		return 0
	var dir := DirAccess.open("res://assets/projectiles/%s" % folder)
	var n := 0
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.begins_with("sprites-") and fn.ends_with(".png"):
				n += 1
			fn = dir.get_next()
		dir.list_dir_end()
	return n

## Заклинание из названия свитка ("Scroll Fire Ball"/"SuperScroll Fire Ball") или "".
static func spell_from_scroll(item_name: String) -> String:
	var n := str(item_name)
	for prefix in ["Scroll ", "SuperScroll ", "Quest "]:
		if n.begins_with(prefix):
			var rest := n.trim_prefix(prefix)
			# "Fire Ball" -> "Fire_Ball"
			return rest.replace(" ", "_")
	return ""