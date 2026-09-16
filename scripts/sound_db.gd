class_name SoundDB
## Звуки игры: индекс ID (из sfx.reg) -> файл .wav в assets/audio/sfx.
## Индекс сгенерирован скриптом build_sound_index.py; звуковые массивы юнитов
## (units.txt Sound): [атака, удар по цели, боль1, боль2, смерть].
##
## Статический класс — не требует автозагрузки: пул плееров создаётся
## в корне сцены при первом проигрывании.

const INDEX_PATH := "res://assets/audio/sound_index.json"
const SFX_ROOT := "res://assets/audio/"
const POOL_SIZE := 10

static var _paths: Dictionary = {}
static var _loaded := false
static var _bus: Node = null
static var _pool: Array = []
static var _round_robin := 0

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null:
		push_error("SoundDB: не открыть " + INDEX_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for key in parsed:
			_paths[int(key)] = str(parsed[key])

## Проиграть звук по ID (0 или неизвестный — молча). True если сыграл.
static func play(id: int, volume_db: float = 0.0) -> bool:
	if id <= 0:
		return false
	ensure_loaded()
	var rel: String = str(_paths.get(id, ""))
	if rel == "":
		return false
	var stream: Variant = load(SFX_ROOT + rel)
	if stream == null:
		return false
	var player := _borrow_player()
	if player == null:
		return false
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0
	player.play()
	return true

## Случайная боль юнита (позиции [2]/[3] массива звуков), тихо если нет.
static func play_pain(sounds: Array) -> void:
	var a := _indexed(sounds, 2)
	var b := _indexed(sounds, 3)
	if a <= 0 and b > 0:
		a = b
	if b <= 0 and a > 0:
		b = a
	if a > 0 or b > 0:
		play(a if randi() % 2 == 0 else b)

## Звук из массива юнита по позиции (0, если нет).
static func sound_at(sounds: Array, idx: int) -> int:
	if idx >= 0 and idx < sounds.size():
		return int(sounds[idx])
	return 0

static func _indexed(sounds: Array, idx: int) -> int:
	return sound_at(sounds, idx)

static func _borrow_player() -> AudioStreamPlayer:
	_ensure_bus()
	if _pool.is_empty():
		return null
	for p in _pool:
		if not p.playing:
			return p
	var p2: AudioStreamPlayer = _pool[_round_robin % _pool.size()]
	_round_robin += 1
	return p2

static func _ensure_bus() -> void:
	if _bus != null and is_instance_valid(_bus):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_bus = null
		return
	_bus = Node.new()
	_bus.name = "SoundBus"
	tree.root.add_child(_bus)
	_pool.clear()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%02d" % i
		_bus.add_child(p)
		_pool.append(p)