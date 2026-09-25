extends SceneTree
## Smoke-проверка параметрической генерации карт по сиду.
##
## Проверяет то, ради чего генератор был переработан в MapGenerator:
##   1. карты по РАЗНЫМ сидам действительно различаются (раньше всегда был gen_smart_01);
##   2. один и тот же сид даёт побайтово ту же карту (детерминизм → можно сохранять сид);
##   3. зона влияет на результат;
##   4. sidecar-ы присутствуют, валидны и не затирают друг друга.
##
## Запуск: godot --headless --path . --script res://tests/gen_seeds_smoke.gd

const DIR := "user://maps/"
const DIR_DET := "user://maps/_det_check/"
const SEED_A := 1001
const SEED_B := 2002
const W := 128
const H := 128
const ALM_MAGIC := 0x0052374D
const SIDECARS := [".spawn.json", ".portal.json", ".structures.json", ".npcs.json", ".herbs.json"]

var _fails: Array[String] = []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	DirAccess.make_dir_recursive_absolute(DIR_DET)

	# --- 1. Два разных сида ---
	var path_a: String = MapGenerator.new().generate(SEED_A, "mid", DIR)
	var path_b: String = MapGenerator.new().generate(SEED_B, "mid", DIR)
	_check(path_a != "" and path_b != "", "оба сида сгенерировались")
	_check(path_a != path_b, "разные сиды дают разные пути")

	_check_files(path_a, "A")
	_check_files(path_b, "B")

	var hash_a: String = _hash(path_a)
	var hash_b: String = _hash(path_b)
	_check(hash_a != "", "файл A читается")
	_check(hash_b != "", "файл B читается")
	_check(hash_a != hash_b, "карты по разным сидам РАЗЛИЧАЮТСЯ (sha256)")

	# Sidecar-ы тоже должны отличаться — доказательство, что варьируется весь рандом,
	# а не только рельеф (структуры/НПЦ/травы идут по своим потокам).
	for ext in SIDECARS:
		var sa: String = _sha(_basename(path_a) + ext)
		var sb: String = _sha(_basename(path_b) + ext)
		_check(sa != sb and sa != "" and sb != "", "sidecar %s различается" % ext)

	# --- 2. Детерминизм: тот же сид → та же карта ---
	# Кладём в ДРУГОЙ каталог с тем же basename: имя карты пишется в заголовок .alm
	# (смещение 68), поэтому переименование сделало бы файлы разными по байтам
	# независимо от рельефа. Здесь меняется только путь.
	var path_a2: String = MapGenerator.new().generate(SEED_A, "mid", DIR_DET)
	_check(_hash(path_a2) == hash_a, "тот же сид даёт ПОБАЙТОВО ту же карту (детерминизм)")
	_check(path_a2 != path_a, "повторная генерация идёт в другой каталог")

	# --- 3. Зона влияет ---
	var path_a_start: String = MapGenerator.new().generate(SEED_A, "start", DIR)
	_check(_hash(path_a_start) != hash_a, "zone=start отличается от zone=mid")
	_check(_hash(path_a_start) != "", "zone=start сгенерировалась")

	# --- 4. Спавн/портал в границах карты ---
	_check_marker(_basename(path_a) + ".spawn.json", "spawn")
	_check_marker(_basename(path_a) + ".portal.json", "portal")
	_check_marker(_basename(path_b) + ".spawn.json", "spawn B")

	_report()

func _basename(alm_path: String) -> String:
	return alm_path.get_basename()

func _sha(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)

func _hash(path: String) -> String:
	return _sha(path)

## .alm + все sidecar-ы существуют и непустые; заголовок .alm валиден.
func _check_files(alm_path: String, tag: String) -> void:
	_check(FileAccess.file_exists(alm_path), "[%s] .alm существует" % tag)
	if FileAccess.file_exists(alm_path):
		var f := FileAccess.open(alm_path, FileAccess.READ)
		if f == null:
			_check(false, "[%s] .alm открывается" % tag)
			return
		var len_buf := f.get_buffer(4)
		f.close()
		var magic := len_buf[0] | (len_buf[1] << 8) | (len_buf[2] << 16) | (len_buf[3] << 24)
		_check(magic == ALM_MAGIC, "[%s] заголовок .alm валиден (magic M7R)" % tag)
	for ext in SIDECARS:
		var p: String = _basename(alm_path) + ext
		_check(FileAccess.file_exists(p), "[%s] sidecar %s существует" % [tag, ext])
		if FileAccess.file_exists(p):
			_check(FileAccess.get_file_as_bytes(p).size() > 2, "[%s] sidecar %s непустой" % [tag, ext])

## Спавн/портал внутри поля 128x128.
func _check_marker(path: String, tag: String) -> void:
	if not FileAccess.file_exists(path):
		_check(false, "[%s] маркер %s существует" % [tag, path.get_file()])
		return
	var txt: String = FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		_check(false, "[%s] %s — валидный JSON" % [tag, path.get_file()])
		return
	var x: int = int(d.get("x", -1))
	var y: int = int(d.get("y", -1))
	_check(x >= 0 and x < W and y >= 0 and y < H, "[%s] %s в границах карты (%d,%d)" % [tag, tag, x, y])

func _check(cond: bool, label: String) -> void:
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK gen_seeds_smoke")
		quit(0)
	else:
		print("RESULT: FAIL gen_seeds_smoke (провалено: %d)" % _fails.size())
		for f in _fails:
			print("  - ", f)
		quit(1)
