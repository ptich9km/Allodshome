class_name UnitDB
## База юнитов из assets/units/units_db.json (сгенерирована из units.txt).
## Даёт фазы движения/атаки/смерти, тайминги, размер и якорь по имени набора
## ("heroes/swordsman", "monsters/orc", "humans/mage_st").

const DB_PATH := "res://assets/units/units_db.json"
const TICK := 0.05  # множитель тайминга (единицы "тиков" из units.txt)

static var _db: Dictionary = {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		push_error("UnitDB: не открыть " + DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_db = parsed

## Данные набора по имени ("heroes/swordsman") или {}.
static func get_set(name: String) -> Dictionary:
	ensure_loaded()
	return _db.get(name, {})

static func has(name: String) -> bool:
	ensure_loaded()
	return _db.has(name)

## Число кадров в наборе (sprites-00N.png).
static func frame_count(name: String) -> int:
	return int(get_set(name).get("frames", 0))

## Путь к кадру (1-based): res://assets/units/<folder>/<prefix>-NNN.png
## У наборов часть имени файла отличается (sprites | swordsman | ...).
static func frame_path(folder: String, prefix: String, frame: int) -> String:
	return "res://assets/units/%s/%s-%03d.png" % [folder, prefix, frame]

## Префикс кадров набора ("sprites" | "swordsman" | ...) из базы.
static func frame_prefix(name: String) -> String:
	var o := get_set(name)
	var p := str(o.get("prefix", ""))
	if p != "" and p != "null":
		return p
	return "sprites"

## Фазы (число направлений x фаз в блоке), с fallback на значения по умолчанию.
static func move_phases(name: String) -> int:
	return int(get_set(name).get("move", 8))

static func attack_phases(name: String) -> int:
	return int(get_set(name).get("attack", 4))

static func dying_phases(name: String) -> int:
	return int(get_set(name).get("dying", 4))

static func cast_phases(name: String) -> int:
	return int(get_set(name).get("cast", 0))

static func idle_phases(name: String) -> int:
	return int(get_set(name).get("idle_phases", 0))

static func decay_phases(name: String) -> int:
	return int(get_set(name).get("decay", 0))

## Число нарисованных направлений в файле (5 для героя с зеркалом правых).
static func dirs(name: String) -> int:
	return int(get_set(name).get("dirs", 8))

## Тайминги (секунды) по фазам блока. Если расписания нет — равномерный дефолт.
static func block_times(name: String, key: String, phases: int) -> Array:
	var o := get_set(name)
	var raw: Variant = o.get(key, null)
	if raw is Array and not raw.is_empty():
		var out: Array = []
		for t in raw:
			out.append(float(t) * TICK)
		return out
	var def: Array = []
	for i in range(phases):
		def.append(0.15)
	return def

## Порядок кадров в блоке (номера фаз). Если пусто — 0..phases-1 по порядку.
static func block_frames(name: String, key: String, phases: int) -> Array:
	var o := get_set(name)
	var raw: Variant = o.get(key, null)
	if raw is Array and not raw.is_empty():
		return raw
	var seq: Array = []
	for i in range(phases):
		seq.append(i)
	return seq

func _unused() -> void:
	pass