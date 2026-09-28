class_name SaveSystem
extends RefCounted
## Сохранения: слоты, автосейв, версионирование, атомарная запись.
##
## Статический класс, НАМЕРЕННО без autoload — добавление autoload в
## project.godot это approval gate (AGENTS §9.4), а оно тут не нужно:
## все методы статические, состояния у класса нет.
##
## Формат: один JSON на слот, user://saves/. Версия в поле "version";
## загрузка файла новее CURRENT отклоняется целиком, а не «читается как
## есть» — иначе битые/чужие данные молча портят игровое состояние.
##
## Атомарность (save-systems): запись идёт в .tmp → flush → переименование.
## На Windows rename поверх существующего файла ненадёжен, поэтому порядок
## такой: сначала текущий файл уходит в .bak, потом .tmp становится
## основным. В любой момент на диске лежит либо целый старый файл, либо
## целый новый, а .bak страхует битую запись. При откате .bak копируется
## обратно, поэтому следующая запись снова имеет предыдущую версию.

const DIR := "user://saves/"
const VERSION := 1
const SLOT_COUNT := 3
const AUTOSAVE_SLOT := "autosave"

## Слоты, которые показываются игроку.
const PLAYER_SLOTS := ["slot_0", "slot_1", "slot_2"]


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


static func slot_path(slot: String) -> String:
	return DIR + slot + ".json"


static func tmp_path(slot: String) -> String:
	return DIR + slot + ".json.tmp"


static func bak_path(slot: String) -> String:
	return DIR + slot + ".json.bak"


# --- Запись ---

## Записать слот. payload — словарь v1 (см. build_payload). Возвращает
## сообщение об ошибке или "" при успехе.
static func save(slot: String, payload: Dictionary) -> String:
	ensure_dir()
	var doc := {
		"version": VERSION,
		"meta": payload.get("meta", {}),
		"data": JsonSafe.encode(payload),
	}
	var text := JSON.stringify(doc)
	# 1. Пишем во временный файл и flush'им: без flush данные могут остаться
	#    в буфере ОС и потеряться при вылете.
	var f := FileAccess.open(tmp_path(slot), FileAccess.WRITE)
	if f == null:
		return "не удалось открыть %s для записи (код %d)" % [tmp_path(slot), FileAccess.get_open_error()]
	f.store_string(text)
	f.flush()
	f.close()
	# 2. Старый файл -> .bak (старый .bak предварительно убираем).
	if FileAccess.file_exists(slot_path(slot)):
		if FileAccess.file_exists(bak_path(slot)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path(slot)))
		var err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(slot_path(slot)),
			ProjectSettings.globalize_path(bak_path(slot)))
		if err != OK:
			return "не удалось сделать .bak: %d" % err
	# 3. .tmp -> основной файл.
	var err2 := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path(slot)),
		ProjectSettings.globalize_path(slot_path(slot)))
	if err2 != OK:
		return "не удалось переименовать .tmp: %d" % err2
	# 4. Проверяем, что записанное читается. Если файл побился — откат.
	if not _reads_ok(slot_path(slot)):
		restore_from_backup(slot)
		return "записанный файл не читается, выполнен откат на .bak"
	return ""


static func _reads_ok(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	return j.parse(text) == OK and j.data is Dictionary


# --- Чтение ---

## Прочитать слот. Пустая строка — читать нечего. "version" — файл новее
## текущего кода. "corrupt" — файл есть, но не читается и .bak не помог.
static func load_slot(slot: String) -> Dictionary:
	var doc := _read_doc(slot_path(slot))
	if doc.is_empty():
		# Основной файл не читается. Если .bak есть и читается - чиним
		# основной файл молча. Раньше условие стояло наоборот, и живой .bak
		# приводил к "corrupt" вместо восстановления.
		var backup := _read_doc(bak_path(slot))
		if backup.is_empty():
			return {} if not FileAccess.file_exists(slot_path(slot)) else {"error": "corrupt"}
		_write_raw(slot_path(slot), FileAccess.get_file_as_string(bak_path(slot)))
		doc = backup
	return _unwrap(doc, slot)


static func _unwrap(doc: Dictionary, slot: String) -> Dictionary:
	var version := int(doc.get("version", -1))
	if version < 0:
		return {"error": "corrupt"}
	if version > VERSION:
		# Отказ целиком: лучше «не грузится», чем частично применённое
		# состояние из будущей версии.
		return {"error": "version", "file_version": version, "current": VERSION}
	var data: Variant = doc.get("data", null)
	if not (data is Dictionary):
		return {"error": "corrupt"}
	return {
		"meta": doc.get("meta", {}),
		"data": JsonSafe.decode(data) as Dictionary,
	}


static func _read_doc(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	if not (j.data is Dictionary):
		return {}
	return j.data as Dictionary


## Откатить слот на .bak. true, если откат выполнен.
static func restore_from_backup(slot: String) -> bool:
	if not FileAccess.file_exists(bak_path(slot)):
		return false
	var text := FileAccess.get_file_as_string(bak_path(slot))
	if not _is_json(text):
		return false
	return _write_raw(slot_path(slot), text)


static func _is_json(text: String) -> bool:
	var j := JSON.new()
	return j.parse(text) == OK


static func _write_raw(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	return true


# --- Список слотов для экрана ---

## Метаданные всех слотов для UI. Не грузит тяжёлые данные, только "meta".
static func list_slots() -> Array:
	ensure_dir()
	var out: Array = []
	for slot in PLAYER_SLOTS:
		var doc := _read_doc(slot_path(slot))
		out.append({
			"slot": slot,
			"exists": not doc.is_empty(),
			"version": int(doc.get("version", -1)),
			"meta": doc.get("meta", {}),
		})
	var auto := _read_doc(slot_path(AUTOSAVE_SLOT))
	out.append({
		"slot": AUTOSAVE_SLOT,
		"exists": not auto.is_empty(),
		"version": int(auto.get("version", -1)),
		"meta": auto.get("meta", {}),
		"auto": true,
	})
	return out


static func has_autosave() -> bool:
	return not _read_doc(slot_path(AUTOSAVE_SLOT)).is_empty()


## Самая свежая запись среди всех слотов. "" — сохранять нечего.
## Сравнение по meta.stamp: порядок файлов в каталоге о порядке сохранений
## ничего не говорит, а полагаться на него нельзя.
static func newest_slot() -> String:
	var best := ""
	var best_stamp := -1
	for entry in list_slots():
		if not bool(entry.get("exists", false)):
			continue
		var stamp := int((entry.get("meta", {}) as Dictionary).get("stamp", 0))
		if stamp > best_stamp:
			best_stamp = stamp
			best = str(entry.get("slot", ""))
	return best


# --- Состав сохранения (v1) ---

## Собрать payload из живого состояния игры.
##
## Отряд (Game.party) в v1 НЕ сохраняется намеренно: наёмники описаны
## в hero.party, и без их восстановления из mercenary_db они были бы
## мусором в партии. Вернём вместе с ними состав в v2.
##
## map хранится сидом и зоной, а не путём: карта детерминированно
## пересобирается (MapGenerator.ensure_map), а абсолютный путь к .alm
## сломал бы сохранение после переноса установки.
static func build_payload(player, world_dict: Dictionary, world_meta: Dictionary = {}) -> Dictionary:
	var hero := {
		"class": Game.hero_class,
		"gender": Game.hero_gender,
		"name": Game.hero_name,
		"character_id": Game.hero_character_id,
		"stats": Game.hero_stats.duplicate(true),
		"start_book": Game.hero_start_book,
		"max_hp": int(player.max_hp),
		"max_mana": int(player.max_mana),
		"current_hp": int(player.current_hp),
		"current_mana": int(player.current_mana),
		"gold": int(player.gold),
		"inventory": player.inventory.duplicate(),
		"equipped": player.equipped.duplicate(true),
		"experience": player.experience.duplicate(true),
		"known_spells": player.known_spells.duplicate(true),
		"sphere_books": player.sphere_books.duplicate(true),
		"position": player.global_position,
	}
	var payload := {
		"version": VERSION,
		"map": { "seed": int(Game.map_seed), "zone": str(Game.map_zone) },
		"hero": hero,
		"world": world_dict,
		"quests": [],  # системы квестов в проекте нет; блок заведён сразу,
		              # чтобы не мигрировать формат потом
	}
	var meta := {
		"hero_name": Game.hero_name,
		"hero_class": Game.hero_class,
		"level": _hero_level(player),
		"day": int(world_dict.get("day", 0)),
		"zone": str(Game.map_zone),
		"seed": int(Game.map_seed),
		# Unix-время записи: экран «Продолжить» обязан уметь выбрать самый
		# свежий слот, а порядок в списке определяется только им.
		"stamp": int(Time.get_unix_time_from_system()),
	}
	meta.merge(world_meta, true)
	payload["meta"] = meta
	return payload


static func _hero_level(player) -> int:
	var t := 0
	if player.experience is Dictionary:
		for key in player.experience:
			t += int(player.experience[key])
	return player.exp_to_skill(t)


## Применить payload к игре. Вызывать ДО загрузки сцены карты: сначала
## ставим Game.map_seed/map_zone, потом создаём мир.
##
## player может быть null - тогда применяются только Game.* (выбор героя на
## экране character_select применяет их ДО перехода на игровую сцену, где
## игрока ещё нет). Раньше проверка player == null стояла выше блока
## Game.hero_*, и весь герой молча терялся.
static func apply_payload(d: Dictionary, player) -> void:
	var map_d: Dictionary = d.get("map", {})
	Game.map_seed = int(map_d.get("seed", 0))
	Game.map_zone = str(map_d.get("zone", "mid"))
	var h: Dictionary = d.get("hero", {})
	Game.hero_class = str(h.get("class", Game.hero_class))
	Game.hero_gender = str(h.get("gender", Game.hero_gender))
	Game.hero_name = str(h.get("name", Game.hero_name))
	Game.hero_character_id = str(h.get("character_id", Game.hero_character_id))
	var st: Variant = h.get("stats", null)
	if st is Dictionary:
		Game.hero_stats = (st as Dictionary).duplicate(true)
	Game.hero_start_book = str(h.get("start_book", ""))
	if player == null:
		return
	player.max_hp = int(h.get("max_hp", 100))
	player.max_mana = int(h.get("max_mana", 50))
	player.current_hp = int(h.get("current_hp", player.max_hp))
	player.current_mana = int(h.get("current_mana", player.max_mana))
	player.gold = int(h.get("gold", 0))
	player.inventory = _str_array(h.get("inventory", []))
	player.equipped = _dict(h.get("equipped", {}))
	player.experience = _dict(h.get("experience", {}))
	player.known_spells = _dict(h.get("known_spells", {}))
	player.sphere_books = _dict(h.get("sphere_books", {}))
	player._recall_speed()


static func _str_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for item in v:
			out.append(str(item))
	return out


static func _dict(v: Variant) -> Dictionary:
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}
