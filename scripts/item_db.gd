class_name ItemDB
extends Node
## База всех 491 предметов игры: assets/items/item_db.json (из data.bin + иконки).
## Данные настоящие: цена/вес/урон/защита из оригинальной игры (англ. релиз),
## имена на русском сгенерированы по матрицам качество+материал+тип.
## Классификация слота/оружия — для экипировки героя.

const DB_PATH := "res://assets/items/item_db.json"

const _WEAPON_TYPES := [
	"Dagger", "Short Sword", "Long Sword", "Bastard Sword", "Two Handed Sword",
	"Spiked Club", "Club", "Mace", "Morning Star", "Pick Hammer", "War Hammer",
	"Axe", "Two Handed Axe", "Pike", "Lance", "Halberd",
	"Staff", "Shaman Staff", "Short Bow", "Long Bow", "Crossbow"]
const _SHIELD_TYPES := ["Buckler", "Small Shield", "Large Shield", "Tower Shield"]
const _SWORD_TYPES := ["Dagger", "Short Sword", "Long Sword", "Bastard Sword", "Two Handed Sword"]
const _CLUB_TYPES := ["Spiked Club", "Club", "Mace", "Morning Star", "Pick Hammer", "War Hammer"]
const _TWO_HANDED_TYPES := [
	"Two Handed Sword", "Two Handed Axe", "Staff", "Shaman Staff",
	"Short Bow", "Long Bow", "Crossbow"]

## Слоты экипировки (порядок = порядок на панели персонажа). Типы — из item_db.json:
## шлемы (Helm/Full Helm/Plate Helm/Chain Helm/Cap/Hat/Low Hat), броня тела
## (Cuirass/Plate Cuirass/Mail/Chain Mail/Scale Mail/Robe/Dress), плащи (Cloak/Cape),
## руки (Bracers/Plate Bracers/Scale Gauntlets/Gauntlets/Gloves/Chain Gauntlets),
## ноги (Plate Boots/Boots/Shoes/Chain Boots), амулеты и кольца. Раньше всё это
## схлопывалось в один слот "armor" — теперь у каждой части тела свой слот.
const _HEAD_TYPES := ["Helm", "Full Helm", "Plate Helm", "Chain Helm", "Cap", "Hat", "Low Hat"]
const _CLOAK_TYPES := ["Cloak", "Cape"]
const _BODY_TYPES := ["Cuirass", "Plate Cuirass", "Mail", "Chain Mail", "Scale Mail", "Robe", "Dress"]
const _HANDS_TYPES := ["Bracers", "Plate Bracers", "Scale Gauntlets", "Gauntlets", "Gloves", "Chain Gauntlets"]
const _FEET_TYPES := ["Plate Boots", "Boots", "Shoes", "Chain Boots"]
const _AMULET_TYPES := ["Amulet"]
const _RING_TYPES := ["Ring"]

## Все слоты экипировки героя, в порядке отображения на панели персонажа.
const EQUIP_SLOTS: Array[String] = [
	"weapon", "shield", "head", "cloak", "body", "hands", "feet", "amulet", "ring1", "ring2",
]

## Русское название слота для подписи/тултипа панели персонажа.
static func slot_title(slot: String) -> String:
	match slot:
		"weapon": return "Оружие"
		"shield": return "Щит"
		"head": return "Шлем"
		"cloak": return "Плащ"
		"body": return "Броня"
		"hands": return "Перчатки"
		"feet": return "Сапоги"
		"amulet": return "Амулет"
		"ring1", "ring2": return "Кольцо"
	return "—"

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

## Слот экипировки: weapon / shield / head / cloak / body / hands / feet / amulet / ring.
## Кольцо возвращает "ring" — конкретный слот ring1/ring2 выбирает player.equip_item().
## "" — предмет не экипируется или тип неизвестен.
static func slot_of(item: Dictionary) -> String:
	var t := str(item.get("type", ""))
	if t in _WEAPON_TYPES:
		return "weapon"
	if t in _SHIELD_TYPES:
		return "shield"
	if t in _HEAD_TYPES:
		return "head"
	if t in _CLOAK_TYPES:
		return "cloak"
	if t in _BODY_TYPES:
		return "body"
	if t in _HANDS_TYPES:
		return "hands"
	if t in _FEET_TYPES:
		return "feet"
	if t in _AMULET_TYPES:
		return "amulet"
	if t in _RING_TYPES:
		return "ring"
	return ""

## Подходит ли предмет в слот (ring принимает и ring1/ring2).
static func fits_slot(item: Dictionary, slot: String) -> bool:
	var s := slot_of(item)
	if s == "":
		return false
	if s == "ring":
		return slot == "ring" or slot == "ring1" or slot == "ring2"
	return s == slot

## Все предметы базы, подходящие в слот (для подсветки совместимых предметов инвентаря).
static func items_for_slot(slot: String) -> Array:
	ensure_loaded()
	var out: Array = []
	for it in _items:
		if fits_slot(it, slot):
			out.append(it)
	return out

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
	# "Linen" - лён (ткань плащей, tests/gen_cloak_items.py). Плащи и рубашки
	# относятся к тряпкам по ТИПУ (is_cloth ниже), но материал перечислен и
	# здесь, чтобы одежда из льна была лёгкой и если тип когда-то изменится.
	# Кожа и дерево удалены из базы (01.10), остались только металлы и лён.
	var is_light_mat := m in ["Linen", "None"]
	var is_cloth := t in ["Cloak", "Cape", "Robe", "Dress", "Hat", "Low Hat", "Cap"]
	if is_light_mat or is_cloth:
		return "light"
	return "heavy"

## Типы, которые нельзя надеть, хотя quality у них обычный.
## Слиток — сырьё, но slot_of() относит всё не-оружие-не-щит к "armor",
## поэтому без этого игрок надел бы слиток как броню, а кузнец (он фильтрует
## инвентарь по is_equippable) переплавлял бы слитки в слитки.
const _INGOT_TYPE := "Ingot"

## Экипируемое ли (не книги/свитки/зелья/квест/слитки/сломанное/ресурсы
## крафта). Качество — единственный общий барьер для всего, что не является
## боевой вещью; вторым барьером служит пустой слот у type из is_broken/ресурсов.
static func is_equippable(item: Dictionary) -> bool:
	var q := str(item.get("quality", ""))
	if q in NON_GEAR_QUALITY:
		return false
	if str(item.get("type", "")) == _INGOT_TYPE:
		return false
	return true

## Качества, которые нельзя надеть. Сломанные вещи и ресурсы крафта
## (ткань/эссенция) - это СЫРЬЁ, а не броня: надетое сломанное не должно
## менять get_defense()/get_absorption() героя.
const NON_GEAR_QUALITY := [
	"Book", "Potion", "Scroll", "SuperScroll", "Quest", "Herb",
	"Broken", "Broken Fine", "Broken Rare",
	"Fabric", "Essence",
]

## --- Сломанные вещи и ресурсы крафта (мастерская, 07.10) -----------------
## Качество сломанной вещи. "" - если это не сломанная вещь.
const BROKEN_QUALITIES := ["Broken", "Broken Fine", "Broken Rare"]

## Ключ сломанной вещи для ровно этой пары (материал, категория, качество).
## Категория: "Armor" | "Weapon" | "Garment". "" если такой записи нет.
## Порядок слов в ключе ("Broken Fine iron Armor") обязателен: контракт
## tests/item_key_literal_smoke.gd:111 требует, чтобы сегмент материала в
## ключе совпадал с полем `material` в ТОЧНОМ регистре.
static func broken_key(material: String, category: String, quality: String) -> String:
	if material == "" or category == "" or not BROKEN_QUALITIES.has(quality):
		return ""
	var parts := ["Broken"]
	if quality != "Broken":
		parts.append(quality.split(" ", 1)[1])
	parts.append(material)
	parts.append(category)
	return " ".join(parts)

## Качество сломанной вещи ("Broken"/"Broken Fine"/"Broken Rare") или "".
static func broken_quality(item: Dictionary) -> String:
	var q := str(item.get("quality", ""))
	return q if BROKEN_QUALITIES.has(q) else ""

## Сломанная вещь? Читает ТОЛЬКО качество, а не type: у ресурсов крафта type
## тоже не в списках слотов, и путать их нельзя.
static func is_broken(item: Dictionary) -> bool:
	return broken_quality(item) != ""

## Ресурс крафта (ткань/эссенция)? Нужен, чтобы исключить их из продажи в
## лавке и из подсчёта «сколько вещей можно надеть».
static func is_craft_material(item: Dictionary) -> bool:
	var q := str(item.get("quality", ""))
	return q == "Fabric" or q == "Essence"

## Запись базы по (материал, категория, качество). {} если нет.
static func broken_item_for(material: String, category: String, quality: String) -> Dictionary:
	var key := broken_key(material, category, quality)
	return find(key) if key != "" else {}

## Категория сломанной вещи: "Armor" | "Weapon" | "Garment" или "".
static func broken_category(item: Dictionary) -> String:
	if not is_broken(item):
		return ""
	var t := str(item.get("type", ""))
	return t.substr("Broken ".length()) if t.begins_with("Broken ") else ""

## Есть ли сломанная вещь этой категории из этого материала хоть в каком-то
## качестве. Нужно дропу: «есть ли вообще что уронить».
static func has_broken(material: String, category: String) -> bool:
	for q in BROKEN_QUALITIES:
		if broken_key(material, category, q) != "":
			return true
	return false

## Металлы, которые переплавляет кузница. Регистр важен: материал в item_db
## хранится в нижнем регистре (bronze, terbium...) - так же, как названы файлы
## иконок в faction/, faction_w/ и blacksmith/. 20 металлов из faction_palette.json.
## Кожа/дерево/ткань сюда НЕ входят: кузнец их не берёт (см. is_smeltable).
const _SMELTABLE := [
	# common
	"bronze", "iron", "steel", "gold",
	# Альянс Света
	"argentum", "lutetium", "lanthanum", "terbium",
	# Орды Огня
	"wolfram", "chromium", "cobalt", "titanium",
	# Пожинатели
	"thorium", "uranium", "plutonium", "radium",
	# Круг Друидов
	"gallium", "yttrium", "promethium", "neodymium",
]

static func is_smeltable(item: Dictionary) -> bool:
	# Слиток — это уже результат переплавки. Материал у него металлический, но
	# переплавлять его в себя нельзя (иначе «iron Ingot → iron Ingot»).
	if str(item.get("type", "")) == _INGOT_TYPE:
		return false
	return str(item.get("material", "")) in _SMELTABLE

## Ключ предмета-слитка для материала ("", если такого металла нет).
## Материал приходит в нижнем регистре, и ключ слитка такой же: "terbium Ingot".
## Раньше ключ строился как "%s Ingot" % material, что работало только при
## заглавном регистре в базе; после перевода металлов вниз переплавка находила
## слиток лишь у части металлов, молча ничего не выдавая.
static func ingot_key(material: String) -> String:
	if material == "":
		return ""
	var ingot: Dictionary = find("%s Ingot" % material.to_lower())
	return str(ingot.get("key", ""))

## Предметы для инвентаря: все экипируемые в порядке базы.
static func equippable_items() -> Array:
	ensure_loaded()
	var out: Array = []
	for it in _items:
		if is_equippable(it):
			out.append(it)
	return out