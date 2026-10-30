class_name ContentRules
extends RefCounted
## Content rules that used to be hard-coded: magic spheres, item types and
## equipment slots, races, city building folders, loot families, inn recruits.
## Now they live in `assets/config/content_rules.json` and a mod can extend them
## (`into: "rule"`, `op: "append"` / `"patch"`).
##
## File format: an array of records `{"key": "<dotted path>", "value": <any>}`.
## Containers (Dictionary/Array) are returned as a COPY: otherwise the first
## caller appending to a list would corrupt the rules for everyone.
##
## Why this exists: without it a mod could add a row to an existing table but
## not a new TYPE (a new magic school, a new armor category, a new race).

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
		push_error("ContentRules: %s — expected an array of records" % PATH)
		return
	# Mods are applied to the records themselves, not to the dictionary: that is
	# how the shared engine works (add/patch/remove/append by the "key" field).
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


## Copy of a value (a returned list/dictionary is safe to mutate).
static func value(key: String, fallback: Variant = null) -> Variant:
	ensure_loaded()
	if not _data.has(key):
		return fallback
	var v: Variant = _data[key]
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v


## Shared (NOT a copy) list for hot paths where elements are only read
## (`t in list` checks). Never mutate the result.
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


## Race record by id from the `races` list ({} when there is no such race).
static func race(id: String) -> Dictionary:
	for r in list("races"):
		if r is Dictionary and str((r as Dictionary).get("id", "")) == id:
			return r
	return {}


## Drops the rules cache. In game the rules are read once at startup; the reset
## is for tests (and for a future "reload data without restart").
static func reload() -> void:
	_loaded = false
	_data.clear()


static func _read_json() -> Variant:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("ContentRules: cannot open " + PATH)
		return null
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK:
		push_error("ContentRules: broken JSON in %s (line %d)" % [PATH, json.get_error_line()])
		return null
	return json.data
