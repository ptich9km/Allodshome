class_name ContentRules
extends RefCounted
## Правила контента, которые раньше были зашиты в код: сферы магии, типы
## предметов и слоты, расы, папки городских зданий, семейства лута, наёмники
## в таверне. Теперь — данные в `assets/config/content_rules.json`, а мод может
## их расширить (kind `rule`, op `append`/`patch`).
##
## Формат файла: массив записей `{"key": "<точечный путь>", "value": <любое>}`.
## Двоичные данные (Dictionary/Array) отдаются КОПИЕЙ: иначе первый же
## вызывающий, дописавший элемент в список, испортил бы правила для всех.
##
## Зачем: без этого мод мог добавить запись в существующую таблицу, но не новый
## ТИП (новую школу магии, новую категорию брони, новую расу).

const PATH := "res://assets/config/content_rules.json"

static var _data: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = _read_json()
	var entries: Array = []
	if parsed is Array:
		entries = parsed
	else:
		push_error("ContentRules: %s — ожидался массив записей" % PATH)
		return
	# Моды применяются к самим записям, а не к словарю: так работает общий
	# движок (add/patch/remove/append по полю key).
	ModLoader.overlay("rules", entries)
	for raw in entries:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var key := str(e.get("key", ""))
		if key == "":
			continue
		_data[key] = e.get("value", null)


static func has(key: String) -> bool:
	ensure_loaded()
	return _data.has(key)


## Копия значения (список/словарь можно менять без страха).
static func value(key: String, fallback: Variant = null) -> Variant:
	ensure_loaded()
	if not _data.has(key):
		return fallback
	var v: Variant = _data[key]
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v


## Общий (НЕ копия) список — для горячих путей, где элементы только читают
## (проверки `t in list`). Мутировать результат нельзя.
static func shared_list(key: String) -> Array:
	ensure_loaded()
	var v: Variant = _data.get(key, null)
	return v if v is Array else []


static func list(key: String) -> Array:
	var v: Variant = value(key, [])
	return v if v is Array else []


static func dict(key: String) -> Dictionary:
	var v: Variant = value(key, {})
	return v if v is Dictionary else {}


static func str_value(key: String, fallback: String = "") -> String:
	var v: Variant = value(key, fallback)
	return str(v) if v != null else fallback


static func int_value(key: String, fallback: int = 0) -> int:
	var v: Variant = value(key, fallback)
	return int(v) if v != null else fallback


## Раса по id из списка `races` ({} если такой нет).
static func race(id: String) -> Dictionary:
	for r in list("races"):
		if r is Dictionary and str((r as Dictionary).get("id", "")) == id:
			return r
	return {}


## Сброс кэша правил. В игре правила читаются один раз при старте; сброс нужен
## тестам (и будущему «перечитать данные без перезапуска»).
static func reload() -> void:
	_loaded = false
	_data.clear()


static func _read_json() -> Variant:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("ContentRules: не открыть " + PATH)
		return null
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK:
		push_error("ContentRules: битый JSON в %s (строка %d)" % [PATH, json.get_error_line()])
		return null
	return json.data
