# ============================================================================
# СЛОЙ 1 — WorldState. Чистые данные мира, RefCounted, БЕЗ Godot-нод.
#
# Правила архитектуры (см. AGENTS.md, «Слой 1 Data»):
#  * Реестры юнитов/городов/фракций/армий/регионов — Dictionary {id: Dictionary}.
#  * Ссылки между сущностями — ТОЛЬКО по строковому id ("c-1", "f-2"), никогда
#    по указателю на ноду/объект. SIM читает мир по id, Presentation по id же
#    находит своих «наёмных» юнитов.
#  * Мир — чистый RefCounted; можно гонять headless (sim_runner) без сцены.
#  * to_dict()/from_dict() — полная сериализация (сохранения = только этот слой).
# ============================================================================
extends RefCounted
# NOTE (Слой-2.5): NO `class_name` here on purpose — headless autoload parsing
# does not resolve global class symbols before the class cache is built, so a
# `class_name` + `preload` of this script fails with "Could not preload".
# Cross-references live in world_bus.gd as preload-by-path consts instead.
# ============================================================================

# id-суффиксы (стабильные, не случайные) ------------------------------------
var _u := 0  # юниты
var _c := 0  # города
var _f := 0  # фракции
var _a := 0  # армии
var _r := 0  # регионы

# --- Собственно состояние мира ---------------------------------------------
var units: Dictionary = {}      # "u-1" -> {"id","name","faction_id","city_id","sphere","curr_hp","max_hp","attack","defense",...}
var cities: Dictionary = {}     # "c-1" -> {"id","name","faction_id","region_id","pos","economy":{...},"population","loyalty"}
var factions: Dictionary = {}   # "f-1" -> {"id","name","color","relations":{fid:int},...}
var armies: Dictionary = {}     # "a-1" -> {"id","faction_id","unit_ids":[],"pos","target","owner_player":false}
var regions: Dictionary = {}    # "r-1" -> {"id","name","area_px":Vector2,"cities":[],"roads":[],"faction_ids":[]}

# --- Служебные поля тика (сервисные, тоже часть сериализации) ---------------
var day := 0                 # номер текущего дня мира
var global_threat := 0.0     # глобальная угроза 0..1 (растёт со временем)
var relations := {}          # "fA:fB" -> int (utility-значение, >0 дружелюбно)
var hero := {                # «привилегированный» герой, НО живёт в данных
	"name": "Герой", "faction_id": "", "level": 1,
	"curr_hp": 100, "max_hp": 100, "pos": Vector2.ZERO,
}
var journal := []            # журнал мира: [{"day":int,"kind":String,"text":String}]

# --- Служебные поля тика (чистые данные, сериализуются) --------------------
var day := 0                 # номер дня мира
var global_threat := 0.0     # глобальная угроза 0..1 (растёт со временем)
var relations := {}          # "fA:fB" -> int (>-100..100), матрица отношений
var hero := {                # «привилегированный» герой: в SIM, но щадится угрозой
	"name": "Герой", "faction_id": "", "level": 1,
	"curr_hp": 100, "max_hp": 100, "pos": Vector2.ZERO,
}
var journal: Array[Dictionary] = []   # журнал событий мира (день, вид, текст)

# --- Служебное ----------------------------------------------------------------
static var primer := "мир"

func _id(kind: String) -> String:
	match kind:
		"u": return "u-%d" % (_u += 1)
		"c": return "c-%d" % (_c += 1)
		"f": return "f-%d" % (_f += 1)
		"a": return "a-%d" % (_a += 1)
		"r": return "r-%d" % (_r += 1)
	return "%s-?_%d" % [kind, randi()]

func new_unit(faction_id: String = "", sphere: String = "") -> Dictionary:
	var id := _id("u")
	units[id] = {
		"id": id, "name": "Юнит %s" % id, "faction_id": faction_id, "city_id": "",
		"sphere": sphere, "curr_hp": 100, "max_hp": 100,
		"attack": 10, "defense": 5, "magic": 0, "level": 1,
	}
	return units[id]

func new_city(name: String, faction_id: String = "", region_id: String = "") -> Dictionary:
	var id := _id("c")
	cities[id] = {
		"id": id, "name": name, "faction_id": faction_id, "region_id": region_id,
		"pos": Vector2.ZERO, "population": 100, "loyalty": 60.0,
		"economy": { "gold": 50, "food": 100, "prod": 5, "price_base": {} },
	}
	return cities[id]

func new_faction(name: String) -> Dictionary:
	var id := _id("f")
	factions[id] = { "id": id, "name": name, "color": Color(1,1,1), "relations": {} }
	return factions[id]

func new_army(faction_id: String, pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var id := _id("a")
	armies[id] = { "id": id, "faction_id": faction_id, "unit_ids": [], "pos": pos, "target": Vector2.ZERO, "owner_player": false }
	return armies[id]

func new_region(name: String) -> Dictionary:
	var id := _id("r")
	regions[id] = { "id": id, "name": name, "area_px": Vector2(1024, 768), "cities": [], "roads": [], "faction_ids": [] }
	return regions[id]

func get_unit(u: String) -> Dictionary:
	return units.get(u, {})

func get_city(c: String) -> Dictionary:
	return cities.get(c, {})

func get_faction(f: String) -> Dictionary:
	return factions.get(f, {})

func get_army(a: String) -> Dictionary:
	return armies.get(a, {})

func get_region(r: String) -> Dictionary:
	return regions.get(r, {})

# --- Сериализация -------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"counters": { "u": _u, "c": _c, "f": _f, "a": _a, "r": _r },
		"units": units, "cities": cities, "factions": factions,
		"armies": armies, "regions": regions,
		"day": day, "global_threat": global_threat,
		"relations": relations, "hero": hero, "journal": journal,
	}

static func from_dict(d: Dictionary):
	# NOTE (headless-canon): без class_name мы НЕ можем вызвать WorldState.new() —
	# берём сам-файл через load-по-пути (единственный «глобальный» доступ).
	var ws = (load("res://scripts/world/world_state.gd") as GDScript).new()
	var counters: Dictionary = d.get("counters", {})
	ws._u = int(counters.get("u", 0)); ws._c = int(counters.get("c", 0))
	ws._f = int(counters.get("f", 0)); ws._a = int(counters.get("a", 0))
	ws._r = int(counters.get("r", 0))
	ws.units = d.get("units", {}); ws.cities = d.get("cities", {})
	ws.factions = d.get("factions", {}); ws.armies = d.get("armies", {})
	ws.regions = d.get("regions", {})
	return ws

## Хелпер для ортодоксального Vector2 в JSON/словарь (сериализуемо без нод).
static func vec2_to(v: Vector2) -> Dictionary:
	return { "x": v.x, "y": v.y }

static func vec2_from(d: Dictionary) -> Vector2:
	return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
