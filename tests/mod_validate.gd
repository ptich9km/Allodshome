extends SceneTree
## Mod validator: checks a folder BEFORE the game runs, so a typo does not turn
## into "the mod silently did not load".
##
## Run:
##   godot --headless --path . --script res://tests/mod_validate.gd
##       (no arguments — check every mod in user://mods and res://mods)
##
##   godot --headless --path . --script res://tests/mod_validate.gd -- C:/path/to/mod
##       (check one specific folder that is not installed yet)
##
## What is checked:
##  * mod.json exists, parses, id matches the folder name;
##  * every data/**/*.json parses, every record has into/key/op;
##  * `into` is known, `op` is known;
##  * add does not override an existing key, patch/append/remove point at real keys;
##  * extends refers to an existing key;
##  * files mod://<id>/... and res://... paths exist;
##  * hints about optional things (no thumb, no data).
##
## A standalone script rather than part of ModLoader: an author needs to check a
## folder the game does not know yet and get the errors as a list, not one by one
## in the log at startup.

var _errors := 0
var _warnings := 0
var _base: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_base = _load_base()
	var targets := _targets()
	if targets.is_empty():
		print("Нет папок модов для проверки.")
		print("RESULT: OK mod_validate (модов: 0)")
		quit(0)
		return
	for path in targets:
		_validate(path)
	print("---")
	if _errors == 0:
		print("RESULT: OK mod_validate (модов: %d, предупреждений: %d)" % [targets.size(), _warnings])
		quit(0)
	else:
		print("RESULT: FAIL mod_validate (модов: %d, ошибок: %d, предупреждений: %d)" %
			[targets.size(), _errors, _warnings])
		quit(1)


## No arguments — every installed mod; with an argument — one specific folder.
func _targets() -> Array[String]:
	var out: Array[String] = []
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var p := str(args[0]).replace("\\", "/").trim_suffix("/")
		if DirAccess.open(p) == null:
			_err("папка не найдена: " + p)
			return out
		out.append(p)
		return out
	for root in ["user://mods", "res://mods"]:
		var da := DirAccess.open(root)
		if da == null:
			continue
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			if da.current_is_dir() and not name.begins_with("."):
				out.append(root.path_join(name))
			name = da.get_next()
		da.list_dir_end()
	return out


# --- validating one mod -------------------------------------------------------

func _validate(path: String) -> void:
	print("=== %s" % path)
	var folder := path.get_file()
	var man_path := path.path_join("mod.json")
	if not FileAccess.file_exists(man_path):
		_err("нет mod.json")
		return
	var man: Variant = _parse(man_path)
	if not (man is Dictionary):
		_err("mod.json — битый JSON")
		return
	var id := str((man as Dictionary).get("id", "")).strip_edges()
	if id == "":
		_err("mod.json: нет поля id")
	elif id != folder:
		_warn("id '%s' не совпадает с папкой '%s' — мод не загрузится" % [id, folder])
	if str((man as Dictionary).get("version", "")) == "":
		_warn("mod.json: нет version (не критично, но сейв не отследит версию)")
	for dep in _as_strings((man as Dictionary).get("depends_on", [])):
		var dep_dir := _resolve_mod_dir(path, dep)
		if dep_dir == "":
			_err("depends_on: мод '%s' не найден рядом" % dep)
	if not FileAccess.file_exists(path.path_join("thumb.png")):
		_warn("нет thumb.png — в списке модов будет буква вместо превью")
	if DirAccess.open(path.path_join("data")) == null:
		_warn("нет папки data/ — мод ничего не добавляет")

	var entries := _read_entries(path)
	if entries.is_empty():
		_warn("в data/ нет ни одной записи")
		return
	var seen: Dictionary = {}
	for e in entries:
		_check_entry(path, id, e, seen)


func _check_entry(path: String, id: String, e: Dictionary, seen: Dictionary) -> void:
	var into := str(e.get("into", ""))
	var key := str(e.get("key", "")).strip_edges()
	var op := str(e.get("op", "add")).to_lower()
	if into == "":
		_err("запись без into (key='%s') — нужен into: item/unit/spell/structure/rule" % key)
		return
	if not ModLoader.DB_OF_KIND.has(into):
		_err("неизвестный into '%s' (есть: %s)" % [into, ", ".join(ModLoader.DB_OF_KIND.keys())])
		return
	if key == "":
		_err("into '%s': запись без key" % into)
		return
	if not ["add", "patch", "remove", "append"].has(op):
		_err("into '%s' '%s': неизвестная op '%s'" % [into, key, op])
		return

	var db := str(ModLoader.DB_OF_KIND[into])
	var exists: bool = _base.has(db) and (_base[db] as Dictionary).has(key)
	var tag := "%s '%s'" % [into, key]

	if op == "add":
		if exists:
			_err("%s: ключ уже есть в игре — используйте op \"patch\" или другое имя" % tag)
		elif seen.has(key):
			_err("%s: ключ повторяется внутри мода" % tag)
	elif op == "append":
		if not exists:
			_err("%s: append по несуществующему ключу (для нового — add)" % tag)
		elif not ((_base[db] as Dictionary)[key] is Array):
			_err("%s: append работает только со списками" % tag)
	else:
		if not exists:
			_err("%s: %s по несуществующему ключу" % [tag, op])

	var ext := str(e.get("extends", "")).strip_edges()
	if ext != "":
		if not (_base.has(db) and (_base[db] as Dictionary).has(ext)):
			_err("%s: extends '%s' не найден в %s" % [tag, ext, db])

	seen[key] = true
	_check_assets(path, id, tag, e)


## Any string of a record: mod://<id>/... must exist; res://... too.
func _check_assets(path: String, id: String, tag: String, node: Variant) -> void:
	match typeof(node):
		TYPE_STRING:
			var s: String = node
			if s.begins_with("mod://"):
				var rest := s.substr(6)
				var slash := rest.find("/")
				if slash <= 0:
					_err("%s: кривой путь '%s' (нужно mod://<id>/...)" % [tag, s])
					return
				var mod_id := rest.substr(0, slash)
				if mod_id != id:
					_err("%s: путь '%s' указывает на чужой мод 'id'" % [tag, s])
					return
				var fs := path.path_join(rest.substr(slash + 1))
				if not FileAccess.file_exists(fs):
					_err("%s: файл не найден: %s" % [tag, s])
			elif s.begins_with("res://") and s.get_extension() in ["png", "bmp", "ogg", "wav", "json", "tres"]:
				if not FileAccess.file_exists(s):
					_err("%s: файл не найден: %s" % [tag, s])
		TYPE_DICTIONARY:
			for k in (node as Dictionary):
				_check_assets(path, id, tag, (node as Dictionary)[k])
		TYPE_ARRAY:
			for v in (node as Array):
				_check_assets(path, id, tag, v)


# --- data ---------------------------------------------------------------------

func _read_entries(path: String) -> Array:
	var out: Array = []
	var files: Array[String] = []
	_collect_json(path.path_join("data"), files)
	files.sort()
	for f in files:
		var parsed: Variant = _parse(f)
		if parsed is Array:
			for e in parsed:
				if e is Dictionary:
					out.append(e)
				else:
					_err("%s: запись не объект" % f.get_file())
		elif parsed is Dictionary and parsed.get("entries", null) is Array:
			for e in parsed["entries"]:
				if e is Dictionary:
					out.append(e)
		else:
			_err("%s: битый JSON или не массив записей" % f.get_file())
	return out


func _collect_json(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var p := dir.path_join(name)
		if da.current_is_dir():
			_collect_json(p, out)
		elif name.to_lower().ends_with(".json"):
			out.append(p)
		name = da.get_next()
	da.list_dir_end()


## Base game keys (WITHOUT mods): the reference for add/patch/extends.
func _load_base() -> Dictionary:
	var base := {"items": {}, "units": {}, "spells": {}, "structures": {}, "rules": {}}
	_fill_keys(base["items"], "res://assets/items/item_db.json")
	_fill_dict(base["units"], "res://assets/units/units_db.json")
	_fill_dict(base["spells"], "res://assets/spells/spells_db.json")
	_fill_dict(base["structures"], "res://assets/structures/structure_db.json")
	_fill_rules(base["rules"], "res://assets/config/content_rules.json")
	return base


func _fill_keys(into: Dictionary, path: String) -> void:
	var parsed: Variant = _parse(path)
	if not (parsed is Array):
		return
	for raw in parsed:
		if raw is Dictionary:
			into[str((raw as Dictionary).get("key", ""))] = true


## Rules: key -> the value itself. The validator must tell an append to a list
## from an append to a number, so the value is stored instead of a flag.
func _fill_rules(into: Dictionary, path: String) -> void:
	var parsed: Variant = _parse(path)
	if not (parsed is Array):
		return
	for raw in parsed:
		if raw is Dictionary:
			var e: Dictionary = raw
			into[str(e.get("key", ""))] = e.get("value", null)


func _fill_dict(into: Dictionary, path: String) -> void:
	var parsed: Variant = _parse(path)
	if not (parsed is Dictionary):
		return
	for k in (parsed as Dictionary):
		into[str(k)] = true


func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return null
	var json := JSON.new()
	if json.parse(txt) != OK:
		return null
	return json.data


func _resolve_mod_dir(from_dir: String, id: String) -> String:
	var sibling := from_dir.get_base_dir().path_join(id)
	if DirAccess.open(sibling) != null:
		return sibling
	var user := "user://mods".path_join(id)
	if DirAccess.open(user) != null:
		return user
	return ""


func _as_strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(str(v))
	return out


func _err(text: String) -> void:
	_errors += 1
	print("ERROR ", text)


func _warn(text: String) -> void:
	_warnings += 1
	print("WARN  ", text)
