class_name ObjectDB
## База объектов карты из assets/map-objects/object_db.json (сгенерирована из
## objects.txt оригинала). По имени объекта (папка map-objects) даёт кадры,
## анимацию, размер/якорь и разрушенный (dead) вариант.

const DB_PATH := "res://assets/map-objects/object_db.json"
const ANIM_TICK := 0.06  # множитель тайминга кадра (anim_time)
const DEFAULT_FRAME_TIME := 0.1  # секунд на кадр, если расписания нет

static var _db: Dictionary = {}
static var _loaded := false

## Загрузить базу один раз.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		push_error("ObjectDB: не открыть " + DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_db = parsed

## Данные объекта по имени папки ("pine1") или {}.
static func get_obj(name: String) -> Dictionary:
	ensure_loaded()
	return _db.get(name, {})

static func has(name: String) -> bool:
	ensure_loaded()
	return _db.has(name)

## Число кадров (sprites-00N.png).
static func frame_count(name: String) -> int:
	var o := get_obj(name)
	return int(o.get("frames", 0))

## Путь к кадру (1-based, как sprites-001.png).
static func frame_path(name: String, frame: int) -> String:
	return "res://assets/map-objects/%s/sprites-%03d.png" % [name, frame]

## Путь к разрушенному кадру (первый кадр dead-анимации) или "" если объекта нет.
static func dead_path(name: String) -> String:
	var o := get_obj(name)
	var dead := str(o.get("dead", ""))
	if dead == "" or dead == "null" or dead == "<null>":
		return ""
	return "res://assets/map-objects/%s-001.png" % dead

## Разрушаем ли объект: есть ли dead-папка на диске (из базы).
static func is_destructible(name: String) -> bool:
	return dead_path(name) != ""

## Массив длительности кадров анимации (секунды).
## Если явного расписания нет, но кадров >1 — дефолтный тайминг на каждый кадр.
static func anim_times(name: String) -> Array:
	var o := get_obj(name)
	var raw: Variant = o.get("anim_time", null)
	if raw is Array and not raw.is_empty():
		var out: Array = []
		for t in raw:
			out.append(float(t) * ANIM_TICK)
		return out
	var frames: int = frame_count(name)
	var def: Array = []
	for i in range(maxi(frames, 1)):
		def.append(DEFAULT_FRAME_TIME)
	return def

## Массив порядка кадров анимации (индексы 0..N-1).
## Если явного расписания нет, но кадров >1 — все кадры по порядку (зациклено).
static func anim_frames(name: String) -> Array:
	var o := get_obj(name)
	var raw: Variant = o.get("anim_frame", null)
	if raw is Array and not raw.is_empty():
		return raw
	var frames: int = frame_count(name)
	var seq: Array = []
	for i in range(frames):
		seq.append(i)
	return seq

## Из спецификации объекта получить имя (поддержка нового "obj" и старого "path").
static func object_name_from_spec(spec: Dictionary) -> String:
	var name := str(spec.get("obj", ""))
	if name != "":
		return name
	var path := str(spec.get("path", ""))
	# res://assets/map-objects/<name>/sprites-001.png
	var marker := "map-objects/"
	var idx := path.find(marker)
	if idx >= 0:
		var rest := path.substr(idx + marker.length())
		var slash := rest.find("/")
		if slash > 0:
			return rest.substr(0, slash)
	return ""