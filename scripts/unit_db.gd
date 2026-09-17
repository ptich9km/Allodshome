class_name UnitDB
## База юнитов из assets/units/units_db.json (сгенерирована из units.txt).
## Даёт фазы движения/атаки/смерти, тайминги, размер и якорь по имени набора
## ("heroes/swordsman", "monsters/orc", "humans/mage_st").

const DB_PATH := "res://assets/units/units_db.json"
const TICK := 0.05  # множитель тайминга (единицы "тиков" из units.txt)

static var _db: Dictionary = {}
static var _loaded := false
static var _by_id := {}

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
	# Индекс: ID юнита (из units.txt) -> имя набора (для спавна НПЦ из .alm)
	_by_id = {}
	for name in _db:
		var ids: Variant = _db[name].get("ids", null)
		if ids is Array:
			for uid in ids:
				_by_id[int(uid)] = name

## Данные набора по имени ("heroes/swordsman") или {}.
static func get_set(name: String) -> Dictionary:
	ensure_loaded()
	return _db.get(name, {})

## Имя набора по ID юнита (type_id из секции units .alm) или "".
static func set_name_for_id(unit_id: int) -> String:
	ensure_loaded()
	return str(_by_id.get(unit_id, ""))

## Данные набора по ID юнита или {} (если ID неизвестен).
static func get_set_by_id(unit_id: int) -> Dictionary:
	return get_set(set_name_for_id(unit_id))

## Агрессивный ли юнит: наборы монстров с палитрой 5 (орки, гоблины, звери)
## атакуют игрока. Мирные жители/животные (палитра != 5) — не нападают.
static func is_hostile(name: String) -> bool:
	if not str(name).begins_with("monsters/"):
		return false
	return int(get_set(name).get("palette", 0)) == 5

## Первый кадр набора (для статичного превью в редакторе/палитре).
static func preview_frame(name: String) -> Texture2D:
	var o := get_set(name)
	var folder := str(o.get("folder", name))
	var prefix := str(o.get("prefix", "sprites"))
	if prefix == "" or prefix == "null":
		prefix = "sprites"
	return load(frame_path(folder, prefix, 1))

## Все имена наборов с указанным префиксом ("humans/", "monsters/"), по алфавиту.
static func all_names(prefix: String = "") -> Array:
	ensure_loaded()
	var out: Array = []
	for name in _db:
		if prefix == "" or str(name).begins_with(prefix):
			out.append(name)
	out.sort()
	return out

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

# --- Поля, перенесённые из units.txt (полный порт) ---

## Хитбокс выделения юнита [x1,y1,x2,y2] (для клика/выбора).
static func sel_box(name: String) -> Rect2i:
	var o := get_set(name)
	var raw: Variant = o.get("sel_box", null)
	if raw is Array and raw.size() == 4:
		return Rect2i(int(raw[0]), int(raw[1]), int(raw[2]) - int(raw[0]), int(raw[3]) - int(raw[1]))
	# дефолт: почти весь спрайт
	return Rect2i(16, 16, 96, 96)

## Задержка атаки в тиках (из units.txt AttackDelay).
static func attack_delay(name: String) -> float:
	return float(get_set(name).get("attack_delay", 4)) * TICK

## Номер палитры спрайта (0..7; монстры 5, скелеты 1-2, люди 0).
static func palette(name: String) -> int:
	return int(get_set(name).get("palette", 0))

## Портрет юнита (имя из units.txt InfoPicture).
static func info_picture(name: String) -> String:
	return str(get_set(name).get("info_picture", ""))

## Размер юнита в клетках (1 = обычный, 2 = тролль/огр/катапульта, 3 = дракон).
static func tile_size(name: String) -> int:
	return int(get_set(name).get("tile_size", 1))

## Зеркалить ли спрайт юнита (Flip=1 — тролли, дракон, летающие).
static func flip(name: String) -> bool:
	return int(get_set(name).get("flip", 0)) != 0

## Высота полёта в пикселях (Z — бат/дракон/саккуб парят над землёй).
static func fly_z(name: String) -> int:
	return int(get_set(name).get("z", 0))

## Фазы анимации костей после смерти (BonePhases — у нежити).
static func bone_phases(name: String) -> int:
	return int(get_set(name).get("bone", 0))

## Тип снаряда дальнобойного юнита (-1 = не стреляет; 1.. = снаряд из проекта).
static func projectile(name: String) -> int:
	return int(get_set(name).get("projectile", -1))

## Задержка выстрела (ShootDelay в тиках).
static func shoot_delay(name: String) -> float:
	return float(get_set(name).get("shoot_delay", 8)) * TICK

## Точка вылета снаряда [x0,y0,x1,y1,...] — 8 пар на каждое направление.
static func shoot_offset(name: String) -> Array:
	var o := get_set(name)
	var raw: Variant = o.get("shoot_offset", null)
	if raw is Array:
		return raw
	return []

## Звуки юнита [атака, ?, ?, смерть, ...] — ID из sfx (assets/audio/sfx/monsters|magic).
static func unit_sound(name: String) -> Array:
	var o := get_set(name)
	var raw: Variant = o.get("sound", null)
	if raw is Array:
		return raw
	return []

func _unused() -> void:
	pass