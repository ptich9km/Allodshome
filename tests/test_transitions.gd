extends SceneTree
## Проверка transition_db + палитры tile1/5/6/7 после доделки переходов.

const DB_PATH := "res://assets/maps/transition_db.json"
const DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
## file в transition_db = палитра редактора (песок/грязь -> tile1)
const DB_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 1, 6: 1}
## file для кодировки типа в .alm (генераторы пересчитывают)
const ALM_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7}

func _init() -> void:
	var fails := 0

	# 1. DB: 336 правил, file у типа A = DB_FILE[A]
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	if f == null:
		print("FAIL: cannot open ", DB_PATH)
		quit(1)
		return
	var json: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (json is Dictionary):
		print("FAIL: bad JSON")
		quit(1)
		return
	var db: Dictionary = json
	var rules: Dictionary = db.get("rules", {})
	var interior: Dictionary = db.get("interior", {})
	print("rules=%d interior=%d" % [rules.size(), interior.size()])
	if rules.size() != 336:
		print("FAIL: expected 336 rules")
		fails += 1

	var bad_file := 0
	var missing := 0
	for a in range(7):
		for b in range(7):
			if a == b:
				continue
			for d in DIRS:
				var key := "%d:%s:%d" % [a, d, b]
				if not rules.has(key):
					missing += 1
					continue
				var spec: Dictionary = rules[key]
				if int(spec.get("file", -1)) != DB_FILE[a]:
					bad_file += 1
					if bad_file <= 5:
						print("  bad file: %s -> %s (want %d)" % [key, str(spec), DB_FILE[a]])
	print("missing=%d bad_file=%d" % [missing, bad_file])
	if missing != 0 or bad_file != 0:
		fails += 1

	for t in range(7):
		var inn: Dictionary = interior.get(str(t), {})
		if int(inn.get("file", -1)) != DB_FILE[t]:
			print("FAIL: interior %d file=%s (want %d)" % [t, str(inn), DB_FILE[t]])
			fails += 1

	# 2. PNG-палитра: tile1 (для песка/грязи) + tile5 (почва) + tile6/7 (рендер)
	for file_n in [1, 5, 6, 7]:
		var ok := 0
		var miss := 0
		var max_r := 14
		var max_v := 16
		for v in range(max_v):
			for r in range(max_r):
				var path := "res://assets/terrain/tiles/tile%d-%02d_%02d.png" % [file_n, v, r]
				if ResourceLoader.exists(path):
					ok += 1
				else:
					miss += 1
		print("tile%d PNG: ok=%d miss=%d" % [file_n, ok, miss])
		if miss != 0:
			fails += 1

	# 3. BMP-полосы tile5/6/7 (рендер .alm)
	for file_n in [5, 6, 7]:
		var path := "res://assets/terrain/tile%d-00.bmp" % file_n
		if not ResourceLoader.exists(path):
			print("FAIL: missing BMP ", path)
			fails += 1
		else:
			var tex: Texture2D = load(path)
			print("tile%d-00.bmp: %dx%d" % [file_n, tex.get_width(), tex.get_height()])

	# 4. tile_from_spec roundtrip: DB file (палитра) -> remap -> ALM type
	for t in range(4, 7):
		var palette_spec := {"file": DB_FILE[t], "variant": 1, "row": 4}
		var alm_spec := {"file": ALM_FILE[t], "variant": 1, "row": 4}
		var tile := AlmLoader.tile_from_spec(alm_spec)
		var back_type := AlmLoader.tile_type(tile)
		print("type %d: palette f%d -> alm f%d -> tile=%d type=%d (want %d)" % [
			t, DB_FILE[t], ALM_FILE[t], tile, back_type, t])
		if back_type != t:
			print("FAIL: roundtrip type")
			fails += 1
		# Палитра tile1 должна существовать для песка/грязи
		if t >= 5:
			var p := "res://assets/terrain/tiles/tile%d-%02d_%02d.png" % [DB_FILE[t], palette_spec["variant"], palette_spec["row"]]
			if not ResourceLoader.exists(p):
				print("FAIL: palette png missing ", p)
				fails += 1

	# 5. Правила песок<->почва (4<->5)
	var pair_ok := true
	for d in DIRS:
		if not rules.has("4:%s:5" % d) or not rules.has("5:%s:4" % d):
			pair_ok = false
	print("pair 4<->5 complete: ", pair_ok)
	if not pair_ok:
		fails += 1

	# 6. Палитра песка/грязи = file 1
	for t in [5, 6]:
		for d in DIRS:
			for b in range(7):
				if b == t:
					continue
				var key := "%d:%s:%d" % [t, d, b]
				var spec: Dictionary = rules.get(key, {})
				if int(spec.get("file", -1)) != 1:
					print("FAIL: sand/mud rule not tile1: %s -> %s" % [key, str(spec)])
					fails += 1
					break

	if fails == 0:
		print("RESULT:OK transition_editor+db")
	else:
		print("RESULT:FAIL %d checks" % fails)
	quit(1 if fails else 0)
