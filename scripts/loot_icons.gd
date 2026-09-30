class_name LootIcons
extends RefCounted
## Иконки для мешка лута: какой спрайт показать на земле и в тултипе.
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ КЛАСС. assets/loot_icons/ содержит 19 металлов x {оружие,
## броня} плюс баночки зелий трёх размеров - это "видно с расстояния" версии
## предметов, мелкие и читаемые. Фракционные иконки из assets/items/faction/
## годятся для склада, но не для мешка на земле: там нужно опознать вещь за
## секунду, а не рассмотреть.
##
## ПРАВИЛА.
##  * золото -> слиток из assets/professions/blacksmith/, отдельной иконки
##    монеты в loot_icons нет;
##  * снаряжение -> {material}_weapon.png или {material}_armor.png, выбор по
##    ItemDB.slot_of(): оружие и щиты считаются оружием, остальное бронёй;
##  * зелья -> баночка по типу (health/mana) и размеру; размер задаёт вызывающий
##    код, потому что сила врага известна только там;
##  * всё остальное (книги, свитки, травы) -> иконка самого предмета из item_db.
##
## ВСЁ СТАТИКА: класс состояния не имеет, его нечему инстанцировать.

const LOOT_DIR := "res://assets/loot_icons/"
const INGOT_DIR := "res://assets/professions/blacksmith/"

## Слоты, которые в loot_icons показаны "оружием", остальные - "бронёй".
## Shield отдельно от оружия, но иконка у него одна - shield_weapon.
const WEAPON_SLOTS := ["weapon", "shield"]

## Тип зелья -> префикс баночки. Определяется по name_ru, потому что у зелий
## нет поля "материал" и общего признака в данных.
const POTION_HEALTH_WORDS := ["healing", "health", "regeneration", "леч", "здоров"]
const POTION_MANA_WORDS := ["mana", "мана", "маги"]


static func icon_for(item: Dictionary) -> String:
	## Путь к иконке лута для предмета ("" если иконки нет).
	if item.is_empty():
		return ""
	var key := str(item.get("key", ""))
	if key == "":
		return ""
	var mat := str(item.get("material", "")).to_lower()
	var slot := ItemDB.slot_of(item)
	var glyph := _loot_icon_for_material(mat, slot)
	if glyph != "":
		return glyph
	# не снаряжение - берём иконку самого предмета из item_db
	return str(item.get("icon", ""))


static func gold_icon() -> String:
	return "%sgold_ingot.png" % INGOT_DIR


static func icon_for_potion(item: Dictionary, size: String) -> String:
	## Баночка по типу (health/mana) и размеру ("small"/"medium"/"large").
	## size определяет вызывающий код: слабый врач -> small, босс -> large.
	if size not in ["small", "medium", "large"]:
		size = "small"
	var kind := "mana" if _is_mana_potion(item) else "health"
	var p := "%s%s_%s_frame00.png" % [LOOT_DIR, kind, size]
	return p if ResourceLoader.exists(p) else ""


static func _loot_icon_for_material(mat: String, slot: String) -> String:
	if mat == "" or mat == "none":
		return ""
	# золото: слиток есть, а {gold}_weapon - нет (в loot_icons 19 металлов)
	if mat == "gold":
		return gold_icon()
	if slot in WEAPON_SLOTS:
		return _existing("%s%s_weapon.png" % [LOOT_DIR, mat])
	# броня, аксессуары, плащи - всё идёт в *_armor. Аксессуаров в loot_icons
	# нет, поэтому для них честно возвращаем "" и вызывающий код берёт иконку
	# из item_db: кольцо, нарисованное как кольцо из того же металла, честнее
	# нагрудника.
	return _existing("%s%s_armor.png" % [LOOT_DIR, mat])


static func _existing(path: String) -> String:
	return path if ResourceLoader.exists(path) else ""


static func _is_mana_potion(item: Dictionary) -> bool:
	var text := (str(item.get("name_ru", "")) + " " + str(item.get("key", ""))).to_lower()
	for w in POTION_MANA_WORDS:
		if text.contains(w):
			return true
	for w in POTION_HEALTH_WORDS:
		if text.contains(w):
			return false
	return false


## Золото в мешке: сколько монет показать стопкой.
static func stack_preview(items: Array) -> int:
	## Сколько иконок рисовать на мешке (1..3). Больше трёх - каша: игрок всё
	## равно не разглядит, зато мешок станет неопознаваемым.
	var n := 0
	for it in items:
		if it is Dictionary:
			if it.has("gold") or it.has("key"):
				n += 1
		if n >= 3:
			break
	return maxi(1, n)
