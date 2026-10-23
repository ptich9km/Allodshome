class_name MusicDB
## Музыка: один активный трек с кроссфейдом, шина Music.
##
## Отдельно от `SoundDB`, потому что у музыки другой жизненный цикл: трек
## играет минутами, требует лупа и не должен занимать пул коротких one-shot
## плееров. Узлы живут в корне дерева, поэтому смена сцены (меню → мир)
## музыку не обрывает.
##
## Файлы и громкости — `assets/audio/music_db.json`; OGG, чтобы не тянуть
## в git WAV-мастера (мастера лежат в `import/audio_src/music/`).

const DB_PATH := "res://assets/audio/music_db.json"
const ROOT := "res://assets/audio/music/"

static var _tracks: Dictionary = {}
static var _loaded := false
static var _root: Node = null
static var _players: Array = []
static var _active := 0
static var _current := ""

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		push_error("MusicDB: не открыть " + DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var t: Variant = (parsed as Dictionary).get("tracks", {})
		if t is Dictionary:
			_tracks = t

static func has(key: String) -> bool:
	ensure_loaded()
	return _tracks.has(key)

static func current_key() -> String:
	return _current

## Играть ключ. Повтор того же ключа — no-op, чтобы смена сцены не
## перезапускала трек с начала.
static func play(key: String, fade_override: float = -1.0) -> bool:
	ensure_loaded()
	var entry: Variant = _tracks.get(key, null)
	if not (entry is Dictionary):
		push_warning("MusicDB: нет трека " + key)
		return false
	if key == _current and not _players.is_empty() and (_players[_active] as AudioStreamPlayer).playing:
		return true
	if not _ensure_nodes():
		return false
	var files: Variant = (entry as Dictionary).get("files", [])
	if not (files is Array) or (files as Array).is_empty():
		return false
	var rel := str((files as Array)[randi() % (files as Array).size()])
	var stream: Variant = load(ROOT + rel)
	if stream == null:
		push_warning("MusicDB: не загрузить " + rel)
		return false
	if bool(entry.get("loop", true)) and stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = true
		ogg.loop_offset = 0.0
	var fade := fade_override
	if fade < 0.0:
		fade = float((entry as Dictionary).get("fade", 2.5))
	var target := float((entry as Dictionary).get("gain_db", -6.0))
	var old := _players[_active] as AudioStreamPlayer
	var next := _players[1 - _active] as AudioStreamPlayer
	next.stream = stream
	next.bus = "Music"
	next.volume_db = -45.0
	next.play()
	var tw := next.create_tween()
	tw.set_parallel(true)
	tw.tween_property(next, "volume_db", target, fade)
	if old.playing:
		tw.tween_property(old, "volume_db", -45.0, fade)
		tw.chain().tween_callback(old.stop)
	_active = 1 - _active
	_current = key
	return true

## Плавно остановить музыку (например, при выходе в меню с другой темой —
## там просто вызывается play("music.menu")).
static func stop(fade: float = 1.5) -> void:
	if _players.is_empty():
		return
	var p := _players[_active] as AudioStreamPlayer
	if not p.playing:
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(p.stop)
	_current = ""

static func _ensure_nodes() -> bool:
	if _root != null and is_instance_valid(_root):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	SoundDB.ensure_buses()
	_root = Node.new()
	_root.name = "MusicBus"
	_root.tree_exiting.connect(_on_root_exiting)
	tree.root.add_child(_root)
	_players.clear()
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.name = "Music%02d" % i
		p.bus = "Music"
		p.volume_db = -45.0
		_root.add_child(p)
		_players.append(p)
	_active = 0
	return true

## Сбросить статические ссылки при выходе, иначе AudioStream остаётся
## «в использовании» до выгрузки скрипта.
static func _on_root_exiting() -> void:
	_players.clear()
	_root = null
	_current = ""
