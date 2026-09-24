class_name ItemDB
extends Node
## База всех 491 предметов игры: assets/items/item_db.json (из data.bin + иконки).
## Данные настоящие: цена/вес/урон/защита из оригинальной игры (англ. релиз),
## имена на русском сгенерированы по матрицам качество+материал+тип.
## Классификация слота/оружия — для экипировки героя.

const DB_PATH := "res://assets/items/item_db.json"

const _WEAPON_TYPES := [
	"Dagger", "Short Sword", "Long Sword", "Bastard Sword", "Two Handed Sword",
	"Spiked Club", "Mace", "Morning Star", "Pick Hammer", "War Hammer",
	"Axe", "Two Handed Axe", "Pike", "Lance", "Halberd",
	"Staff", "Shaman Staff", "Short Bow", "Long Bow", "Crossbow"]
const _SHIELD_TYPES := ["Buckler", "Small Shield", "Large Shield", "Tower Shield"]
const _SWORD_TYPES := ["Dagger", "Short Sword", "Long Sword", "Bastard Sword", "Two Handed Sword"]
const _CLUB_TYPES := ["Spiked Club", "Mace", "Morning Star", "Pick Hammer", "War Hammer"]
const _TWO_HANDED_TYPES := [
	"Two Handed Sword", "Two Handed Axe", "Staff", "Shaman Staff",
	"Short Bow", "Long Bow", "Crossbow"]

static var _items: Array = []
static var _by_key := {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		push_error("ItemDB: не открыть " + DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is not Array:
		push_error("ItemDB: битый JSON")
		return
	for raw in parsed:
		if raw is Dictionary:
			var it: Dictionary = raw
			_items.append(it)
			_by_key[str(it.get("key", ""))] = it
	print("ItemDB: загружено %d предметов" % _items.size())

static func all() -> Array:
	ensure_loaded()
	return _items

static func find(key: String) -> Dictionary:
	ensure_loaded()
	return _by_key.get(key, {})

## Слот экипировки: weapon / shield / armor (всё остальное — одежда/аксессуары).
static func slot_of(item: Dictionary) -> String:
	var t := str(item.get("type", ""))
	if t in _WEAPON_TYPES:
		return "weapon"
	if t in _SHIELD_TYPES:
		return "shield"
	return "armor"

## Тип оружия для анимаций героя (unarmed/sword/axe/club/pike/bow/xbow/staff/magic).
static func weapon_kind(item: Dictionary) -> String:
	var t := str(item.get("type", ""))
	if t in _SWORD_TYPES:
		return "sword"
	if t in _CLUB_TYPES:
		return "club"
	if t in ["Axe", "Two Handed Axe"]:
		return "axe"
	if t in ["Pike", "Lance", "Halberd"]:
		return "pike"
	if t in ["Staff", "Shaman Staff"]:
		return "staff"
	if t in ["Short Bow", "Long Bow"]:
		return "bow"
	if t in ["Crossbow"]:
		return "xbow"
	return "unarmed"

static func is_two_handed(item: Dictionary) -> bool:
	var t := str(item.get("type", ""))
	return t in _TWO_HANDED_TYPES

## Лёгкая броня (кожа/ткань) — набор heroes_l/, тяжёлая (металл) — heroes/.
static func armor_kind(item: Dictionary) -> String:
	var m := str(item.get("material", ""))
	var t := str(item.get("type", ""))
	var is_light_mat := m in ["Leather", "Hard Leather", "Dragon Leather", "None"]
	var is_cloth := t in ["Cloak", "Cape", "Robe", "Dress", "Hat", "Low Hat", "Cap"]
	if is_light_mat or is_cloth:
		return "light"
	return "heavy"

## Экипируемое ли (не книги/свитки/зелья/квест).
static func is_equippable(item: Dictionary) -> bool:
	var q := str(item.get("quality", ""))
	return not (q in ["Book", "Potion", "Scroll", "SuperScroll", "Quest", "Herb"])

## Предметы для инвентаря: все экипируемые в порядке базы.
static func equippable_items() -> Array:
	ensure_loaded()
	var out: Array = []
	for it in _items:
		if is_equippable(it):
			out.append(it)
	return out