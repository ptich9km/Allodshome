extends SceneTree
##
## Смок звуковой библиотеки: индекс `assets/audio/sound_db.json` против кода.
##
## Проверяет:
##   1. индекс читается, ключи и файлы на месте;
##   2. каждый файл грузится как AudioStream и имеет ненулевую длину;
##   3. каждый ключ из `SoundDB.play("...")` и `spells_db.json` есть в индексе;
##   4. числовых ID Аллодов в коде не осталось;
##   5. шины из индекса входят в разрешённый набор.
##
## Запуск: godot --headless --path . --script res://tests/audio_smoke.gd
## Результат: RESULT: OK audio_smoke (N проверок)

const DB_PATH := "res://assets/audio/sound_db.json"
const SFX_ROOT := "res://assets/audio/sfx/"
const BUSES := ["Music", "SFX", "UI", "Voice", "Ambient"]
const SPELLS_DB := "res://assets/spells/spells_db.json"

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _run() -> void:
	print("-- audio_smoke --")
	var keys := _load_db()
	_check(keys.size() >= 50, "ключей в индексе: %d" % keys.size())

	var used: Array[String] = []
	used.append_array(_keys_from_scripts())
	used.append_array(_keys_from_spells())
	_check(used.size() >= 40, "ключей используется в коде/базе: %d" % used.size())
	for key in used:
		_check(keys.has(key), "ключ используется и существует: " + key)

	var total := 0
	for key in keys:
		var entry: Dictionary = keys[key]
		var bus := str(entry.get("bus", ""))
		_check(bus in BUSES, "%s: шина %s" % [key, bus])
		var files: Array = entry.get("files", [])
		_check(not files.is_empty(), "%s: есть файлы" % key)
		for rel in files:
			total += 1
			var path := SFX_ROOT + str(rel)
			_check(FileAccess.file_exists(path), "%s: файл на месте (%s)" % [key, rel])
			var stream: Variant = load(path)
			_check(stream is AudioStream, "%s: грузится как AudioStream" % key)
			if stream is AudioStream:
				var length := (stream as AudioStream).get_length()
				_check(length > 0.03, "%s: длина %.3f с" % [key, length])
				if key.begins_with("ui."):
					_check(length < 4.0, "%s: UI короче 4 с" % key)
	_check(total >= 150, "файлов в индексе: %d" % total)

	# Числовые ID Аллодов не должны остаться ни в одном скрипте.
	var numeric := _numeric_plays()
	_check(numeric.is_empty(), "числовых SoundDB.play(...): %d" % numeric.size())
	for n in numeric:
		print("      " + n)

	_check_music()

	# Живая проверка: MusicDB создаёт узлы, грузит трек и переключает ключ.
	MusicDB.play("music.menu", 0.1)
	await create_timer(0.2).timeout
	_check(MusicDB.current_key() == "music.menu", "MusicDB: трек меню запущен")
	MusicDB.stop(0.1)
	await create_timer(0.2).timeout

	if _fails.is_empty():
		print("RESULT: OK audio_smoke (%d проверок)" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL audio_smoke (%d проверок, %d провалов)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
		quit(1)


func _load_db() -> Dictionary:
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		_check(false, "не открыть " + DB_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_check(false, "индекс не JSON-объект")
		return {}
	var k: Variant = (parsed as Dictionary).get("keys", {})
	if not (k is Dictionary):
		_check(false, "в индексе нет keys")
		return {}
	_check(true, "индекс прочитан")
	return k


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _keys_from_scripts() -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile('SoundDB\\.play\\("([^"]+)"')
	for path in _gd_files("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			var key := m.get_string(1)
			if "%" in key:  # формат-строка вида "voice.%s.1" проверяется по индексу
				continue
			if not out.has(key):
				out.append(key)
	out.sort()
	return out


func _keys_from_spells() -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(SPELLS_DB, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return out
	for name in parsed:
		var entry: Variant = (parsed as Dictionary)[name]
		if entry is Dictionary:
			var key := str((entry as Dictionary).get("sound", ""))
			_check(key != "" and key.begins_with("magic."), "%s: звук задан ключом" % name)
			if key != "" and not out.has(key):
				out.append(key)
	out.sort()
	return out


func _numeric_plays() -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile('SoundDB\\.play\\(\\s*[0-9]')
	for path in _gd_files("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			out.append(path + ": " + m.get_string(0))
	return out


## Музыка: треки существуют, грузятся, помечены как луп и лежат на шине Music.
func _check_music() -> void:
	var f := FileAccess.open("res://assets/audio/music_db.json", FileAccess.READ)
	if f == null:
		_check(false, "не открыть music_db.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_check(false, "music_db.json не JSON-объект")
		return
	var tracks: Variant = (parsed as Dictionary).get("tracks", {})
	if not (tracks is Dictionary) or (tracks as Dictionary).is_empty():
		_check(false, "в music_db.json нет tracks")
		return
	_check(true, "music_db.json прочитан: %d трек(ов)" % (tracks as Dictionary).size())
	for key in tracks:
		var entry: Dictionary = tracks[key]
		_check(str(entry.get("bus", "")) == "Music", "%s: шина Music" % key)
		var files: Array = entry.get("files", [])
		_check(not files.is_empty(), "%s: есть файлы" % key)
		for rel in files:
			var path := "res://assets/audio/music/" + str(rel)
			_check(FileAccess.file_exists(path), "%s: файл на месте (%s)" % [key, rel])
			var stream: Variant = load(path)
			_check(stream is AudioStream, "%s: грузится" % key)
			if stream is AudioStream:
				_check((stream as AudioStream).get_length() > 60.0,
					"%s: длина больше минуты" % key)
			if stream is AudioStreamOggVorbis:
				# Луп выставляется в MusicDB.play по полю loop: .import в git
				# не хранится, поэтому настройка импорта ненадёжна.
				_check(bool(entry.get("loop", true)), "%s: луп включён" % key)

	# Ключи, которые играет код, должны быть в базе.
	var re := RegEx.new()
	re.compile('MusicDB\\.play(?:\\.call_deferred)?\\("([^"]+)"')
	for path in _gd_files("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			_check((tracks as Dictionary).has(m.get_string(1)),
				"MusicDB.play: ключ есть (%s)" % m.get_string(1))
