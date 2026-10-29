class_name ModLoader
extends RefCounted
## Загрузчик модов: папки `res://mods/<id>/` (вшитые наборы) и `user://mods/<id>/`
## (моды игрока). Никакого autoload — статика, как SaveSystem.
##
## Почему так, а не «как в Space Engineers»: там переопределение молчаливое (второй
## мод с тем же SubtypeId просто исчезает), а «не написал поле — взялся дефолт из
## кода». Здесь наоборот — конфликт ключей и потеря ассета это ОШИБКА с именем мода
## и ключом, и запись пропускается (в игре остаётся базовая версия), а наследование
## только явное: `"extends": "<ключ базы>"`.
##
## Структура мода:
##   mods/<id>/mod.json     — манифест (id, name, version, author, priority, ...)
##   mods/<id>/data/*.json  — записи (массив объектов или {"entries": [...]})
##   mods/<id>/assets/*     — свои файлы, ссылки вида `mod://<id>/assets/x.png`
##   mods/<id>/thumb.png    — превью для списка модов (необязательно)
##
## Запись в data:
##   {"kind": "unit", "key": "monsters/warden", "extends": "monsters/wolf",
##    "name_ru": "Сторож топей", "palette": 5}
##   op: "add" (по умолчанию) | "patch" | "remove"
## `kind` — куда класть (item/unit/spell/structure), `key` — ключ внутри базы.
## Остальные поля записи — данные самого объекта; `type` у предмета остаётся
## свободным и означает тип предмета ("Long Sword"), а не базу.
##
## Порядок загрузки: depends_on (жёстко) -> load_after (мягко) -> priority
## (больше = позже, то есть «главнее») -> id по алфавиту. Одно направление,
## оно же показывается в UI: ниже в списке = применяется позже.

const MOD_ROOTS: Array[String] = ["res://mods", "user://mods"]
const MANIFEST_NAME := "mod.json"
const DATA_DIR := "data"
const USER_MODS_DIR := "user://mods"
## Настройки игрока рядом с модами: выключенные и ручной порядок.
const CONFIG_PATH := "user://mods.cfg"

## "type" записи -> база (см. overlay()).
const DB_OF_KIND: Dictionary = {
	"item": "items",
	"unit": "units",
	"spell": "spells",
	"structure": "structures",
	"rule": "rules",
}
## Поле-ключ у баз, которые хранятся массивом. У словарных баз ключ — это ключ словаря.
const DB_KEY_FIELD: Dictionary = {"items": "key", "rules": "key"}
const DB_IS_ARRAY: Dictionary = {
	"items": true, "units": false, "spells": false, "structures": false, "rules": true,
}
const ENTRY_META := ["op", "kind", "key", "extends"]

static var _scanned := false
static var _mods: Array[Dictionary] = []      # включённые, в порядке применения
static var _all: Array[Dictionary] = []       # все найденные (для панели модов)
static var _errors: Array[String] = []
static var _warnings: Array[String] = []
static var _disabled: Array[String] = []      # из user://mods.cfg
static var _manual_order: Array[String] = []  # из user://mods.cfg, ниже = позже
static var _owners: Dictionary = {}     # "db|key" -> id мода, который добавил
static var _patchers: Dictionary = {}   # "db|key" -> Array[String] id модов, которые патчили
static var _orphans: Array[String] = []  # папки в mods/ без mod.json (частая ошибка копирования)
## Моды включены? В headless-прогонах `--script` они ВЫКЛЮЧЕНЫ по умолчанию:
## тесты проверяют базовые данные, а у игрока в user://mods лежат его моды
## (29.10 то, что у игрока стоял `warden`, ломало `gray_tier_smoke`).
## Тесты самих модов включают их через `set_active(true)`.
static var _active := true
static var _active_resolved := false


## Сброс кэша (тесты, пересканирование после включения/выключения мода).
## Настройки (что выключено и ручной порядок) перечитываются из `mods.cfg`.
static func reset() -> void:
	_scanned = false
	_mods.clear()
	_all.clear()
	_errors.clear()
	_warnings.clear()
	_disabled.clear()
	_manual_order.clear()
	_owners.clear()
	_patchers.clear()
	_orphans.clear()


## Папки в `mods/`, где нет `mod.json`. Игроки (и мы) регулярно копируют папку
## на уровень глубже — тогда «модов нет» без объяснения. Панель показывает список.
static func orphan_folders() -> Array[String]:
	_scan()
	var out: Array[String] = []
	out.assign(_orphans)
	return out


static func mods() -> Array[Dictionary]:
	_scan()
	var out: Array[Dictionary] = []
	out.assign(_mods)
	return out


## Все найденные моды (включая выключенные) в порядке применения — для панели.
static func all_mods() -> Array[Dictionary]:
	_scan()
	var out: Array[Dictionary] = []
	for m in _all:
		var copy: Dictionary = m.duplicate()
		copy["enabled"] = not _disabled.has(str(m["id"]))
		out.append(copy)
	return out


static func is_enabled(id: String) -> bool:
	_scan()
	return not _disabled.has(id)


## Принудительно включить/выключить моды на весь процесс (тесты).
static func set_active(on: bool) -> void:
	_active = on
	_active_resolved = true
	reset()


static func is_active() -> bool:
	_scan()
	return _active


## Включить/выключить мод. Применяется после перезапуска игры (данные баз уже
## разобраны), поэтому UI обязан сказать это игроку.
static func set_enabled(id: String, on: bool) -> void:
	_scan()
	if on:
		_disabled.erase(id)
	elif not _disabled.has(id):
		_disabled.append(id)
	_save_config()
	reset()


## Сдвинуть мод в ручном порядке: delta > 0 — ниже в списке (то есть позже).
static func move(id: String, delta: int) -> void:
	_scan()
	_ensure_order()
	var i := _manual_order.find(id)
	if i < 0:
		return
	var j := clampi(i + delta, 0, _manual_order.size() - 1)
	if i == j:
		return
	_manual_order.remove_at(i)
	_manual_order.insert(j, id)
	_save_config()
	reset()


static func errors() -> Array[String]:
	_scan()
	var out: Array[String] = []
	out.assign(_errors)
	return out


static func warnings() -> Array[String]:
	_scan()
	var out: Array[String] = []
	out.assign(_warnings)
	return out


## Папка модов игрока (создаётся при первом обращении).
static func user_mods_dir() -> String:
	if DirAccess.open(USER_MODS_DIR) == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_MODS_DIR))
	return USER_MODS_DIR


## Профиль модов для сейва: что было включено и в каком порядке.
static func save_profile() -> Array:
	_scan()
	var out: Array = []
	for m in _mods:
		out.append({"id": m["id"], "version": m["version"], "priority": m["priority"]})
	return out


## `mod://<id>/<путь>` -> реальный путь. Не-mod-пути возвращаются как есть.
static func resolve(path: String) -> String:
	if not path.begins_with("mod://"):
		return path
	var rest := path.substr(6)
	var slash := rest.find("/")
	if slash <= 0:
		return path
	var id := rest.substr(0, slash)
	var rel := rest.substr(slash + 1)
	var dir := _dir_of(id)
	if dir == "":
		return path
	return dir.path_join(rel)


static func is_mod_path(path: String) -> bool:
	return path.begins_with("mod://")


## Наложить моды на данные базы. Вызывается из ensure_loaded() каждой базы ПОСЛЕ
## разбора JSON и ДО построения индексов. `base` мутируется на месте.
static func overlay(db: String, base: Variant) -> void:
	_scan()
	if base == null or _mods.is_empty():
		return
	var is_array: bool = DB_IS_ARRAY.get(db, false)
	var applied := 0
	for m in _mods:
		var entries: Array = m.get("entries", [])
		for raw in entries:
			if not (raw is Dictionary):
				continue
			var e: Dictionary = raw
			if str(DB_OF_KIND.get(str(e.get("kind", "")), "")) != db:
				continue
			if _apply_entry(m, e, base, is_array, db):
				applied += 1
	if applied > 0:
		print("ModLoader: %s — записей из модов: %d (модов: %d)" % [db, applied, _mods.size()])


# --- сканирование -------------------------------------------------------------

## Режим по умолчанию: в игре моды включены, в `--script`-прогонах — нет
## (там проверяются базовые данные; `--with-mods` в аргументах после `--` включает).
static func _resolve_active() -> void:
	if _active_resolved:
		return
	_active_resolved = true
	if OS.get_cmdline_args().has("--script"):
		_active = OS.get_cmdline_user_args().has("--with-mods")


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true   # ставим сразу: resolve() может звать _dir_of -> _scan
	_resolve_active()
	if not _active:
		return
	_load_config()
	var found: Array[Dictionary] = []
	var seen: Dictionary = {}
	for root in MOD_ROOTS:
		var da := DirAccess.open(root)
		if da == null:
			continue
		da.list_dir_begin()
		var folder := da.get_next()
		while folder != "":
			if da.current_is_dir() and not folder.begins_with("."):
				var mod_dir := root.path_join(folder)
				if not FileAccess.file_exists(mod_dir.path_join(MANIFEST_NAME)):
					_orphans.append(mod_dir)
					folder = da.get_next()
					continue
				var m := _read_mod(mod_dir, folder)
				if not m.is_empty():
					if seen.has(m["id"]):
						_errors.append("мод '%s' объявлен дважды: %s и %s" % [m["id"], seen[m["id"]], m["dir"]])
					else:
						seen[m["id"]] = m["dir"]
						found.append(m)
			folder = da.get_next()
		da.list_dir_end()

	# Жёсткие зависимости: отсутствует — мод не грузится (иначе тихо получим мод,
	# который читает данные несуществующего соседа).
	var ids: Dictionary = {}
	for m in found:
		ids[m["id"]] = true
	var good: Array[Dictionary] = []
	for m in found:
		var ok := true
		for dep in m.get("depends_on", []):
			if not ids.has(str(dep)):
				_errors.append("мод '%s': нет зависимости '%s'" % [m["id"], dep])
				ok = false
		if ok:
			good.append(m)
	_all = _sort_mods(good)
	_mods.clear()
	for m in _all:
		if _disabled.has(str(m["id"])):
			continue
		# Зависимость выключена — включённый мод не должен грузиться «наполовину».
		var off := ""
		for dep in m.get("depends_on", []):
			if _disabled.has(str(dep)):
				off = str(dep)
				break
		if off != "":
			_errors.append("мод '%s' не загружен: зависимость '%s' выключена" % [m["id"], off])
			continue
		_mods.append(m)
	if not _all.is_empty() or not _errors.is_empty():
		print("ModLoader: найдено %d, включено %d, ошибок %d, предупреждений %d" %
			[_all.size(), _mods.size(), _errors.size(), _warnings.size()])


## Настройки игрока: что выключено и ручной порядок (`user://mods.cfg`).
static func _load_config() -> void:
	_disabled.clear()
	_manual_order.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for v in _as_array(cfg.get_value("mods", "disabled", [])):
		_disabled.append(v)
	for v in _as_array(cfg.get_value("mods", "order", [])):
		_manual_order.append(v)


static func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("mods", "disabled", _disabled)
	cfg.set_value("mods", "order", _manual_order)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("ModLoader: не записать %s (%d)" % [CONFIG_PATH, err])


static func _as_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(str(v))
	return out


## Ручной порядок: дописывает новых модов в конец, ничего не теряя.
static func _ensure_order() -> void:
	for m in _all:
		var id := str(m["id"])
		if not _manual_order.has(id):
			_manual_order.append(id)


## Место в ручном порядке. Моды, которых в списке нет, — в конце.
static func _rank_of(id: String) -> int:
	var i := _manual_order.find(id)
	return i if i >= 0 else 100000


static func _read_mod(dir: String, folder: String) -> Dictionary:
	var man_path := dir.path_join(MANIFEST_NAME)
	if not FileAccess.file_exists(man_path):
		return {}
	var parsed: Variant = _parse_json(man_path)
	if not (parsed is Dictionary):
		_errors.append("мод '%s': битый %s" % [folder, MANIFEST_NAME])
		return {}
	var man: Dictionary = parsed
	var id := str(man.get("id", "")).strip_edges()
	if id == "":
		_errors.append("мод '%s': в %s нет поля id" % [folder, MANIFEST_NAME])
		return {}
	if id != folder:
		_warnings.append("мод '%s': id '%s' не совпадает с именем папки" % [folder, id])
	var m: Dictionary = {
		"id": id,
		"dir": dir,
		"name": str(man.get("name", id)),
		"version": str(man.get("version", "0.0.0")),
		"author": str(man.get("author", "")),
		"description": str(man.get("description", "")),
		"priority": int(man.get("priority", 0)),
		"affects_save": bool(man.get("affects_save", true)),
		"depends_on": _str_array(man.get("depends_on", [])),
		"load_after": _str_array(man.get("load_after", [])),
		"entries": _read_entries(dir, id),
	}
	var thumb := dir.path_join(str(man.get("thumb", "thumb.png")))
	m["thumb"] = thumb if FileAccess.file_exists(thumb) else ""
	return m


static func _read_entries(dir: String, mod_id: String) -> Array:
	var out: Array = []
	var data_dir := dir.path_join(DATA_DIR)
	if DirAccess.open(data_dir) == null:
		return out
	var files := _json_files(data_dir)
	files.sort()
	for path in files:
		var parsed: Variant = _parse_json(path)
		if parsed is Array:
			for e in parsed:
				if e is Dictionary:
					out.append(e)
				else:
					_errors.append("мод '%s': в %s запись не объект" % [mod_id, path])
		elif parsed is Dictionary and parsed.get("entries", null) is Array:
			for e in parsed["entries"]:
				if e is Dictionary:
					out.append(e)
		else:
			_errors.append("мод '%s': битый JSON в %s (нужен массив записей)" % [mod_id, path])
	return out


static func _json_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var path := dir.path_join(name)
		if da.current_is_dir():
			out.append_array(_json_files(path))
		elif name.to_lower().ends_with(".json"):
			out.append(path)
		name = da.get_next()
	da.list_dir_end()
	return out


## JSON через экземпляр парсера: `JSON.parse_string` при ошибке печатает
## движковый ERROR в stderr, и битый мод в логе выглядит как падение игры.
static func _parse_json(path: String) -> Variant:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return null
	var json := JSON.new()
	if json.parse(txt) != OK:
		return null
	return json.data


static func _str_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(str(v))
	return out


## Топосорт: depends_on -> load_after -> priority -> id.
static func _sort_mods(list: Array[Dictionary]) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for m in list:
		by_id[m["id"]] = m
	var pending: Array[Dictionary] = []
	pending.assign(list)
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := _rank_of(str(a["id"]))
		var rb := _rank_of(str(b["id"]))
		if ra != rb:
			return ra < rb
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa != pb:
			return pa < pb
		return str(a["id"]) < str(b["id"]))

	var out: Array[Dictionary] = []
	var done: Dictionary = {}
	while not pending.is_empty():
		var moved := false
		for i in range(pending.size()):
			var m: Dictionary = pending[i]
			if _deps_ready(m, by_id, done):
				out.append(m)
				done[m["id"]] = true
				pending.remove_at(i)
				moved = true
				break
		if not moved:
			var names: Array[String] = []
			for m in pending:
				names.append(str(m["id"]))
			_errors.append("цикл зависимостей, не загружены: %s" % ", ".join(names))
			break
	return out


static func _deps_ready(m: Dictionary, by_id: Dictionary, done: Dictionary) -> bool:
	for dep in m.get("depends_on", []):
		if not done.has(str(dep)):
			return false
	for after in m.get("load_after", []):
		# load_after — мягкое: ждём только если такой мод вообще есть.
		if by_id.has(str(after)) and not done.has(str(after)):
			return false
	return true


static func _dir_of(id: String) -> String:
	_scan()
	for m in _mods:
		if str(m["id"]) == id:
			return str(m["dir"])
	return ""


# --- применение записей -------------------------------------------------------

static func _apply_entry(m: Dictionary, e: Dictionary, base: Variant, is_array: bool, db: String) -> bool:
	var mod_id := str(m.get("id", ""))
	var key := str(e.get("key", "")).strip_edges()
	var op := str(e.get("op", "add")).to_lower()
	if key == "":
		_errors.append("мод '%s': запись без key (kind=%s)" % [mod_id, str(e.get("kind", "?"))])
		return false
	if op != "add" and op != "patch" and op != "remove" and op != "append":
		_errors.append("мод '%s': неизвестная op '%s' у '%s'" % [mod_id, op, key])
		return false

	if op == "remove":
		if not _has_def(base, key, is_array, db):
			_warnings.append("мод '%s': remove '%s' — такого ключа нет" % [mod_id, key])
			return false
		_erase_def(base, key, is_array, db)
		return true

	var missing: Array[String] = []
	var fields: Dictionary = {}
	for k in e:
		if str(k) in ENTRY_META:
			continue
		fields[str(k)] = _expand(e[k], missing)
	if not missing.is_empty():
		# Потерянный ассет — не «розовый квадрат в игре», а отказ от записи.
		_errors.append("мод '%s': '%s' — не найдены файлы: %s" % [mod_id, key, ", ".join(missing)])
		return false

	var existing: Variant = _get_def(base, key, is_array, db)
	var exists: bool = existing is Dictionary

	# append: дописать элементы к списку внутри записи — так мод добавляет
	# новую сферу магии или новый тип брони, не переписывая весь список
	# (перезапись легко теряет правки соседнего мода).
	if op == "append":
		if not exists:
			_errors.append("мод '%s': append '%s' — ключа нет" % [mod_id, key])
			return false
		var cur: Variant = (existing as Dictionary).get("value", null)
		var add: Variant = fields.get("value", null)
		if not (cur is Array) or not (add is Array):
			_errors.append("мод '%s': append '%s' — значение не список" % [mod_id, key])
			return false
		var merged: Dictionary = (existing as Dictionary).duplicate(true)
		var merged_list: Array = (cur as Array).duplicate()
		merged_list.append_array(add as Array)
		merged["value"] = merged_list
		_put_def(base, key, merged, is_array, db)
		_note_patch(db, key, mod_id)
		return true

	if op == "patch":
		if not exists:
			_errors.append("мод '%s': patch '%s' — ключа нет (для нового используйте add)" % [mod_id, key])
			return false
		_put_def(base, key, _deep_merge(existing, fields), is_array, db)
		_note_patch(db, key, mod_id)
		return true

	# op == "add"
	if exists:
		_errors.append("мод '%s': ключ '%s' уже занят (%s) — нужен op \"patch\"" % [mod_id, key, _owner_of(db, key)])
		return false
	var ext := str(e.get("extends", "")).strip_edges()
	var def: Dictionary = {}
	if ext != "":
		var parent: Variant = _get_def(base, ext, is_array, db)
		if not (parent is Dictionary):
			_errors.append("мод '%s': '%s' — extends '%s' не найден в %s" % [mod_id, key, ext, db])
			return false
		def = _deep_merge(parent, fields)
	else:
		def = fields
	_put_def(base, key, def, is_array, db)
	_owners[db + "|" + key] = mod_id
	return true


static func _owner_of(db: String, key: String) -> String:
	return str(_owners.get(db + "|" + key, "база игры"))


static func _note_patch(db: String, key: String, mod_id: String) -> void:
	var k := db + "|" + key
	if not _patchers.has(k):
		_patchers[k] = []
	var list: Array = _patchers[k]
	if mod_id in list:
		return
	list.append(mod_id)
	if list.size() == 2:
		_warnings.append("'%s' (%s) правят два мода: %s — применяется последний" % [key, db, ", ".join(list)])


static func _get_def(base: Variant, key: String, is_array: bool, db: String) -> Variant:
	if is_array:
		var field := str(DB_KEY_FIELD.get(db, "key"))
		for raw in (base as Array):
			if raw is Dictionary and str((raw as Dictionary).get(field, "")) == key:
				return raw
		return null
	return (base as Dictionary).get(key, null)


static func _has_def(base: Variant, key: String, is_array: bool, db: String) -> bool:
	return _get_def(base, key, is_array, db) is Dictionary


static func _put_def(base: Variant, key: String, def: Dictionary, is_array: bool, db: String) -> void:
	var copy: Dictionary = def.duplicate(true)
	if is_array:
		var arr: Array = base
		var field := str(DB_KEY_FIELD.get(db, "key"))
		for i in range(arr.size()):
			var raw: Variant = arr[i]
			if raw is Dictionary and str((raw as Dictionary).get(field, "")) == key:
				arr[i] = copy
				return
		if not copy.has(field):
			copy[field] = key
		arr.append(copy)
		return
	(base as Dictionary)[key] = copy


static func _erase_def(base: Variant, key: String, is_array: bool, db: String) -> void:
	if is_array:
		var arr: Array = base
		var field := str(DB_KEY_FIELD.get(db, "key"))
		for i in range(arr.size() - 1, -1, -1):
			var raw: Variant = arr[i]
			if raw is Dictionary and str((raw as Dictionary).get(field, "")) == key:
				arr.remove_at(i)
		return
	(base as Dictionary).erase(key)


static func _deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over:
		var v: Variant = over[k]
		if out.has(k) and out[k] is Dictionary and v is Dictionary:
			out[k] = _deep_merge(out[k], v)
		else:
			out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return out


## Разворачивает `mod://<id>/...` в реальный путь; собирает ненайденные файлы.
static func _expand(value: Variant, missing: Array[String]) -> Variant:
	match typeof(value):
		TYPE_STRING:
			var s: String = value
			if not s.begins_with("mod://"):
				return s
			var resolved := resolve(s)
			if resolved == s or not FileAccess.file_exists(resolved):
				missing.append(s)
			return resolved
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var out: Dictionary = {}
			for k in d:
				out[k] = _expand(d[k], missing)
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for v in (value as Array):
				arr.append(_expand(v, missing))
			return arr
	return value
