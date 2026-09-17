class_name StructureDB
## База зданий из assets/structures/structure_db.json (сгенерирована из
## structures.txt оригинала). Ключи — ID структур (1..179); folder может
## дублироваться (Church ID 11 и Saving Place ID 66 — одна папка church).
## Даёт сетку кадров, хитбокс выделения, фазы анимации, тень и свойства.

const DB_PATH := "res://assets/structures/structure_db.json"
const TICK := 0.05  # множитель тайминга (AnimTime в "тиках" из structures.txt)

static var _db: Dictionary = {}
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		push_error("StructureDB: не открыть " + DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_db = parsed

## Данные строения по ID (type_id из .alm) или {}.
static func get_by_id(id: int) -> Dictionary:
	ensure_loaded()
	return _db.get(str(id), _db.get(id, {}))

## Все ID структур (для палитры редактора), по возрастанию.
static func ids() -> Array:
	ensure_loaded()
	var out: Array = []
	for k in _db:
		out.append(int(k))
	out.sort()
	return out

## Статичный превью-кадр структуры по ID (первый кадр house-001.png) или null.
static func preview_texture(id: int) -> Texture2D:
	var o := get_by_id(id)
	var folder := str(o.get("folder", ""))
	var prefix := str(o.get("prefix", "house"))
	if folder == "":
		return null
	return load("res://assets/structures/%s/%s-%03d.png" % [folder, prefix, 1])

## Подпись здания по ID (DescText) для интерфейса.
static func display_name_by_id(id: int) -> String:
	return str(get_by_id(id).get("desc", ""))

## Данные строения по имени папки ("church") — первое совпадение или {}.
## Для папок с несколькими записями (церковь/дом) это неоднозначно,
## в рендере используйте get_by_id.
static func get_structure(name: String) -> Dictionary:
	ensure_loaded()
	var key := name.to_lower()
	for id in _db:
		var rec: Dictionary = _db[id]
		if str(rec.get("folder", "")).to_lower() == key:
			return rec
	return {}

## Есть ли запись с таким ID / папкой.
static func has(name: String) -> bool:
	return not get_structure(name).is_empty()

## Сетка кадров: ширина (TileWidth).
static func grid_w(name: String) -> int:
	return int(get_structure(name).get("tile_width", 1))

## Высота корпуса в клетках (TileHeight — нижние ряды, где стоит здание).
static func grid_h(name: String) -> int:
	return int(get_structure(name).get("tile_height", 1))

## Полная визуальная высота (FullHeight — включая верхние ряды крыши).
static func full_h(name: String) -> int:
	return int(get_structure(name).get("full_height", grid_h(name)))

## Путь к кадру базы (1-based: house-001.png).
static func frame_path(name: String, frame: int) -> String:
	var folder := str(get_structure(name).get("folder", name))
	var prefix := str(get_structure(name).get("prefix", "house"))
	return "res://assets/structures/%s/%s-%03d.png" % [folder, prefix, frame]

## Путь к кадру тени (houseb-001.png); "" если тени нет.
static func shadow_path(name: String, frame: int) -> String:
	var folder := str(get_structure(name).get("folder", name))
	return "res://assets/structures/%s/houseb-%03d.png" % [folder, frame]

## Хитбокс выделения [x1,x2,y1,y2] в пикселях (SelectionX1..Y2).
static func sel_box(name: String) -> Rect2i:
	var o := get_structure(name)
	var sel: Variant = o.get("sel", null)
	if sel is Array and sel.size() == 4:
		return Rect2i(int(sel[0]), int(sel[2]), int(sel[1]) - int(sel[0]), int(sel[3]) - int(sel[2]))
	# дефолт: почти весь корпус в пикселях (по клеткам сетки)
	var w := grid_w(name) * 32
	var h := full_h(name) * 32
	return Rect2i(2, 2, w - 4, h - 4)

## Сдвиг тени по Y (ShadowY).
static func shadow_y(name: String) -> int:
	return int(get_structure(name).get("shadow_y", 0))

## Число фаз анимации (Phases).
static func phases(name: String) -> int:
	return int(get_structure(name).get("phases", 1))

## Время кадра фазы в секундах (AnimTime), fallback — равномерный дефолт.
static func anim_time(name: String, phases: int) -> Array:
	var o := get_structure(name)
	var raw: Variant = o.get("anim_time", null)
	if raw is Array and not raw.is_empty():
		var out: Array = []
		for t in raw:
			out.append(float(t) * TICK)
		return out
	var def: Array = []
	for i in range(phases):
		def.append(0.15)
	return def

## Порядок фаз (AnimFrame), fallback — 0..phases-1.
static func anim_frames(name: String, phases: int) -> Array:
	var o := get_structure(name)
	var raw: Variant = o.get("anim_frame", null)
	if raw is Array and not raw.is_empty():
		return raw
	var seq: Array = []
	for i in range(phases):
		seq.append(i)
	return seq

## Подпись здания (DescText) для интерфейса.
static func display_name(name: String) -> String:
	return str(get_structure(name).get("desc", ""))

## Портрет здания (Picture) — файл assets/portraits/<picture>.png (lowercase).
static func picture(name: String) -> String:
	return str(get_structure(name).get("picture", ""))

## Неразрушаемое ли здание (Indestructible).
static func is_indestructible(name: String) -> bool:
	return int(get_structure(name).get("indestructible", 0)) != 0

## Можно ли взаимодействовать (Usable — двери, алтари, телепорты).
static func is_usable(name: String) -> bool:
	return int(get_structure(name).get("usable", 0)) != 0