class_name CraftDB
extends RefCounted

## Правила мастерской: рецепты, переработка, шансы трёх уровней вещи.
##
## ЕДИНСТВЕННЫЙ читатель ключей секции [craft] из game.cfg. Причина именно
## так: tests/config_dead_keys_smoke.gd падает на любом ключе, который не
## встречается строковым литералом в коде. Двенадцать ключей, размазанных по
## панелям и дропу, — это двенадцать мест, где легко забыть ключ при
## рефакторинге. Исключения оговорены у самих функций ниже.
##
## ТИРЫ КРАФТОВОЙ ВЕЩИ. Рецепт хранит все три выхода явно, веса — базовые,
## а навык сдвигает их в рантайме. Три записи в базе вместо одного:
## инвентарь хранит `Array[String]` ключей (player.gd:39), и две крафтовые
## вещи одного рецепта с РАЗНЫМ уровнем невозможно различить иначе. Цена
## решения — база растёт на число рецептов x 3.
##
## Почему шансы зашиты формулой, а не таблицей по уровням: сумма должна быть
## ровно 100 при ЛЮБОМ навыке, а таблица из 40 строк разъезжается при первой
## же правке. Сумма здесь сохраняется тождественно:
##     (80 - 1.4*s) + (15 + 0.9*s) + (5 + 0.5*s) = 100.

const RECIPE_DIR := "res://assets/professions/workshop/"

## Виды ремесла. Индексы фиксированы: третья вкладка (мастер) введётся
## позже, и сдвигать их нельзя — иначе сломается сохранённый фокус панели.
const SMITH := "smith"
const TAILOR := "tailor"
const MASTER := "master"

const CRAFT_KINDS := [SMITH, TAILOR, MASTER]

## Навык крафта по виду ремесла. У каждого ремесла СВОЙ счётчик: крафт в
## кузне не должен качать портново, иначе игрок не выбирает, а «прокачивает
## всё понемногу». Алхимия живёт в своём здании, но навык общий с ремеслами,
## поэтому вынесена в отдельную константу.
const SKILL_OF := {
	SMITH: "smithing",
	TAILOR: "tailoring",
	MASTER: "mastering",
}
const ALCHEMY_SKILL := "alchemy"

## Ресурсы крафта. Ключи из item_db (gen_broken_items.py).
const FABRIC_KEY := "Fabric"
const ESSENCE_KEY := "Magic Essence"

## Три уровня крафтовой вещи. Обычная без эффекта, улучшенная и мастерская
## получают шейдер свечения (scripts/craft_vfx.gd).
const TIER_ORDINARY := 0
const TIER_IMPROVED := 1
const TIER_MASTER := 2

## Префикс качества у записей базы по уровню. Обычная - пусто, поэтому её
## ключ совпадает с «крафтовой вещью без приставки».
const TIER_QUALITY := ["", "Fine ", "Master "]
const TIER_QUALITY_LONG := ["Crafted", "Crafted Fine", "Crafted Master"]

static var _recipes: Dictionary = {}
static var _loaded := false


static func clear_cache() -> void:
	_recipes = {}
	_loaded = false


# --- Загрузка рецептов ----------------------------------------------------

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for kind in CRAFT_KINDS:
		_recipes[kind] = []
	for kind in [SMITH, TAILOR]:
		var path := "%s%s_recipes.json" % [RECIPE_DIR, kind]
		# FileAccess, а не ResourceLoader.exists: JSON не импортируется движком
		# как ресурс, и проверка существования через ResourceLoader врёт.
		# Тот же приём в alchemy_panel.gd:138.
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("CraftDB: не открыть " + path)
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not (parsed is Dictionary):
			push_error("CraftDB: рецепты " + path + " - не объект JSON")
			continue
		var list: Variant = (parsed as Dictionary).get("recipes", [])
		if not (list is Array):
			continue
		for raw in list:
			var r: Variant = _validate(raw, kind, path)
			if not r.is_empty():
				_recipes[kind].append(r)


static func _validate(raw: Variant, kind: String, path: String) -> Dictionary:
	if not (raw is Dictionary):
		push_error("CraftDB: рецепт не объект в " + path)
		return {}
	var d: Dictionary = raw
	var id := str(d.get("id", ""))
	if id == "":
		push_error("CraftDB: рецепт без id в " + path)
		return {}
	var inputs: Variant = d.get("inputs", [])
	if not (inputs is Array) or (inputs as Array).is_empty():
		push_error("CraftDB: рецепт %s без ингредиентов" % id)
		return {}
	for ing in inputs as Array:
		if not (ing is Dictionary):
			push_error("CraftDB: ингредиент %s не объект" % id)
			return {}
		var key := str((ing as Dictionary).get("item", ""))
		if key == "" or ItemDB.find(key).is_empty():
			push_error("CraftDB: неизвестный ингредиент '%s' в %s" % [key, id])
			return {}
		if int((ing as Dictionary).get("count", 0)) <= 0:
			push_error("CraftDB: неположительный count в %s" % id)
			return {}
	var outs: Variant = d.get("outputs", [])
	if not (outs is Array) or (outs as Array).is_empty():
		push_error("CraftDB: рецепт %s без выходов" % id)
		return {}
	for out in outs as Array:
		if not (out is Dictionary):
			push_error("CraftDB: выход %s не объект" % id)
			return {}
		var okey := str((out as Dictionary).get("key", ""))
		if ItemDB.find(okey).is_empty():
			push_error("CraftDB: неизвестный выход '%s' в %s" % [okey, id])
			return {}
		if float((out as Dictionary).get("weight", 0.0)) <= 0.0:
			push_error("CraftDB: неположительный weight в %s" % okey)
			return {}
	d["craft"] = str(d.get("craft", kind))
	d["inputs"] = (inputs as Array).duplicate(true)
	d["outputs"] = (outs as Array).duplicate(true)
	return d


static func recipes(kind: String) -> Array:
	_load()
	return _recipes.get(kind, [])


static func recipe_by_id(id: String) -> Dictionary:
	_load()
	for kind in CRAFT_KINDS:
		for r in recipes(kind):
			if str(r.get("id", "")) == id:
				return r
	return {}


# --- Шансы трёх уровней ---------------------------------------------------

## Веса уровней для навыка skill. Сумма ровно 100 при ЛЮБОМ навыке.
##
## Сумма тождественно сохранялась бы простой формулой
## (80-1.4s) + (15+0.9s) + (5+0.5s) = 100, но только пока обычная не упирается
## в floor_ordinary. На навыке 44+ она упирается, и сумма начинает расти
## (на 100 было бы 165) - а сумма больше 100 означает, что шансы перестали быть
## вероятностями, и игрок получает вещь "бесплатно". Поэтому после клампа
## улучшенная и мастерская масштабируются пропорционально.
static func tier_weights(skill: int) -> Array[float]:
	var s := float(maxi(0, skill))
	var floor_ordinary := GameConfig.getf("craft", "floor_ordinary")
	var ordinary := GameConfig.getf("craft", "chance_ordinary") \
		- GameConfig.getf("craft", "ordinary_step") * s
	var improved := GameConfig.getf("craft", "chance_improved") \
		+ GameConfig.getf("craft", "improved_step") * s
	var master := GameConfig.getf("craft", "chance_master") \
		+ GameConfig.getf("craft", "master_step") * s
	if ordinary < floor_ordinary:
		# Деление перераспределяет остаток между двумя другими уровнями в том
		# же соотношении, в каком они выросли, - иначе мастерская забирала бы
		# себе всё, а улучшенная стояла бы на месте.
		var rest := improved + master
		if rest > 0.0:
			var scale := (100.0 - floor_ordinary) / rest
			improved *= scale
			master *= scale
		ordinary = floor_ordinary
	return [ordinary, improved, master]


## Уровень по весу шанса. roll в [0, 100).
static func tier_for_roll(roll: float, skill: int) -> int:
	var w := tier_weights(skill)
	var acc := 0.0
	for i in w.size():
		acc += w[i]
		if roll < acc:
			return i
	return TIER_ORDINARY


## Случайный уровень крафтовой вещи при данном навыке.
static func roll_tier(skill: int, rng: RandomNumberGenerator = null) -> int:
	var r := randf() * 100.0 if rng == null else rng.randf() * 100.0
	return tier_for_roll(r, skill)


## Ключ выхода рецепта для уровня tier ("" если такого выхода нет).
static func output_key(recipe: Dictionary, tier: int) -> String:
	var outs: Array = recipe.get("outputs", [])
	if outs.is_empty():
		return ""
	var idx := clampi(tier, 0, outs.size() - 1)
	return str((outs[idx] as Dictionary).get("key", ""))


# --- Переработка сломанного ----------------------------------------------

## Выход переработки: {"ingot": int, "fabric": int, "essence": int}.
## Качество вещи решает, сколько слитков; ткань из металла идёт «вразрез» с
## портным (см. комментарий к [craft] в game_config.gd).
static func recycle_yield(item: Dictionary) -> Dictionary:
	var q := ItemDB.broken_quality(item)
	if q == "":
		return {"ingot": 0, "fabric": 0, "essence": 0}
	var fine := q == "Broken Fine"
	var rare := q == "Broken Rare"
	var out := {"ingot": 0, "fabric": 0, "essence": 0}
	match ItemDB.broken_category(item):
		"Armor":
			out.ingot = _tier(fine, rare, "yield_broken", "yield_broken_fine", "yield_broken_rare")
			out.fabric = _tier(fine, rare, "fabric_from_armor", "fabric_from_armor_fine", "fabric_from_armor_rare")
		"Weapon":
			out.ingot = _tier(fine, rare, "yield_broken", "yield_broken_fine", "yield_broken_rare")
			out.fabric = _tier(fine, rare, "fabric_from_weapon", "fabric_from_weapon_fine", "fabric_from_weapon_rare")
		"Garment":
			out.fabric = _tier(fine, rare, "fabric_from_garment", "fabric_from_garment_fine", "fabric_from_garment_rare")
			out.essence = _tier(fine, rare, "essence_from_garment", "essence_from_garment_fine", "essence_from_garment_rare")
	return out


static func _tier(fine: bool, rare: bool, k0: String, k1: String, k2: String) -> int:
	if rare:
		return GameConfig.geti("craft", k2)
	if fine:
		return GameConfig.geti("craft", k1)
	return GameConfig.geti("craft", k0)


## Может ли этот вид ремесла переработать такую вещь?
static func can_recycle(kind: String, item: Dictionary) -> bool:
	if not ItemDB.is_broken(item):
		return false
	var cat := ItemDB.broken_category(item)
	if cat == "Garment":
		return kind == TAILOR
	return kind == SMITH


# --- Опыт навыка ----------------------------------------------------------

## Опыт за крафт: базовый + надбавка за уровень вещи.
static func xp_for_craft(tier: int) -> int:
	var xp := GameConfig.geti("craft", "xp_per_craft")
	if tier == TIER_IMPROVED:
		xp += GameConfig.geti("craft", "xp_tier_bonus")
	elif tier == TIER_MASTER:
		xp += GameConfig.geti("craft", "xp_tier_bonus") * 2
	return maxi(1, xp)


static func xp_for_recycle() -> int:
	return maxi(1, GameConfig.geti("craft", "xp_per_recycle"))