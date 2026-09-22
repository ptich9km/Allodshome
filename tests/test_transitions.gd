extends SceneTree
## Проверка transition_db (вкл. тип 7 «Гора непроходимая») + палитры + WalkTable.
##
## Формат DB (текущий): directional-ключи "A:DIRn:B" (8 направлений × subs 1/2 = 16
## на пару A->B), interior-ключи "A:An:A" (A1..A6, само-переходы), словарь "interior"
## хранит РЕАЛЬНЫЙ ALM-file типа. Тип 7 = tile2 variant 12 (непроходимый через
## walk_speeds.json "2-12": 0).

const DB_PATH := "res://assets/maps/transition_db.json"
const DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
## file directional-правил в transition_db = ПАЛИТРА редактора
## (песок(5)/грязь(6)/почва(4) выбираются из tile1)
const DB_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 1, 5: 1, 6: 1, 7: 2}
## file в словаре interior = реальный ALM-файл типа (для рендера .alm)
const ALM_FILE := {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 2}
## support-пары редактора (тип A -> допустимые B)
const SUPPORTED_PAIRS := {
	0: [4], 1: [0, 4, 6, 7], 2: [4], 3: [4],
	4: [0, 1, 2, 3, 5, 6], 5: [4], 6: [4], 7: [1],
}

func _init() -> void:
	var fails := 0

	# 1. DB: 224 правила (16 на пару A->B × 11 пар + 8×6 interior A-правил),
	#    interior содержит все 8 типов
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
	if rules.size() != 224:
		print("FAIL: expected 224 rules")
		fails += 1
	for t in range(8):
		if not interior.has(str(t)):
			print("FAIL: interior missing type %d" % t)
			fails += 1

	# 2. Все directional-ключи имеют вид A:DIRn:B (16 на пару), file = DB_FILE[A]
	var file_violations := 0
	for a in range(8):
		for b in range(8):
			if a == b:
				continue
			var ids: Array[String] = []
			for d in DIRS:
				for sub in [1, 2]:
					ids.append("%d:%s%d:%d" % [a, d, sub, b])
			var present := 0
			for key in ids:
				if rules.has(key):
					present += 1
					if int(rules[key].get("file", -1)) != DB_FILE[a]:
						file_violations += 1
						if file_violations <= 5:
							print("  bad file: %s -> %s (want %d)" % [key, str(rules[key]), DB_FILE[a]])
			if present > 0 and present != 16:
				print("  partial pair %d->%d: %d/16" % [a, b, present])
				fails += 1
			if present > 0 and a not in SUPPORTED_PAIRS:
				print("  pair %d->%d not in SUPPORTED_PAIRS" % [a, b])
				fails += 1
	print("file_violations=%d" % file_violations)
	if file_violations != 0:
		fails += 1

	# 3. Interior A-правила: 6 на каждый тип
	for t in range(8):
		for iv in range(1, 7):
			if not rules.has("%d:A%d:%d" % [t, iv, t]):
				print("FAIL: missing interior A-rule %d:A%d:%d" % [t, iv, t])
				fails += 1

	# 4. Словарь interior: file = REAL ALM file
	for t in range(8):
		var inn: Dictionary = interior.get(str(t), {})
		if int(inn.get("file", -1)) != ALM_FILE[t]:
			print("FAIL: interior %d file=%s (want %d)" % [t, str(inn), ALM_FILE[t]])
			fails += 1

	# 5. Тип 7 «Гора непроходимая» — специальные проверки:
	#    - пара 1<->7 полная (16+16)
	#    - 7->1 (непроходимая сторона) = tile2 variant 12,
	#      1->7 (проходимая сторона) — обычные горные края (variant != 12)
	for d in DIRS:
		for sub in [1, 2]:
			var s1: Dictionary = rules.get("7:%s%d:1" % [d, sub], {})
			if s1.is_empty():
				print("FAIL: missing type7 rule 7:%s%d:1" % [d, sub])
				fails += 1
			elif int(s1.get("variant", -1)) != 12:
				print("FAIL: 7:%s%d:1 variant %s (want 12)" % [d, sub, str(s1)])
				fails += 1
			var s2: Dictionary = rules.get("1:%s%d:7" % [d, sub], {})
			if s2.is_empty():
				print("FAIL: missing type7 rule 1:%s%d:7" % [d, sub])
				fails += 1
			elif int(s2.get("variant", -1)) == 12:
				print("FAIL: 1:%s%d:7 must not use reserved variant 12" % [d, sub])
				fails += 1
	# interior-правила типа 7
	var i7: Dictionary = interior.get("7", {})
	if int(i7.get("variant", -1)) != 12 or int(i7.get("file", -1)) != 2:
		print("FAIL: interior 7 = %s (want tile2 variant 12)" % str(i7))
		fails += 1
	# палитра tile2 для типа 7 должна существовать
	var pal := "res://assets/terrain/tiles/tile2-12_00.png"
	if not ResourceLoader.exists(pal):
		print("FAIL: missing palette PNG ", pal)
		fails += 1
	else:
		print("type7 palette: ", pal, " exists")

	# 6. WalkTable: tile2 variant 12 непроходим ("2-12": 0), остальные горы — проходимы
	if WalkTable.walkable(2, 12):
		print("FAIL: tile2 variant 12 should be UNWALKABLE")
		fails += 1
	else:
		print("OK: tile2 variant 12 unwalkable (cost 0)")
	for v in [0, 1, 11, 13, 15]:
		if not WalkTable.walkable(2, v):
			print("FAIL: tile2 variant %d should be walkable" % v)
			fails += 1

	# 7. PNG-палитра tile1 (песок/грязь) + tile2 (горы/непрох.) + tile5 (почва)
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

	# 8. BMP-полосы (рендер .alm)
	for file_n in [1, 2, 5, 6, 7]:
		var path := "res://assets/terrain/tile%d-00.bmp" % file_n
		if not ResourceLoader.exists(path):
			print("FAIL: missing BMP ", path)
			fails += 1
		else:
			var tex: Texture2D = load(path)
			print("tile%d-00.bmp: %dx%d" % [file_n, tex.get_width(), tex.get_height()])

	# 9. tile_from_spec roundtrip: файл-1, вариант, кадр
	for t in range(4, 8):
		var spec := {"file": ALM_FILE[t], "variant": 4, "row": 9}
		var tile := AlmLoader.tile_from_spec(spec)
		var n: int = AlmLoader.tile_file(tile)  # = file*16 + variant (0..51)
		var file_n: int = (n >> 4) + 1
		var variant: int = n & 0xF
		var frame: int = AlmLoader.tile_frame(tile)
		print("type %d: alm f%d -> file_n=%d var=%d frame=%d (want %d/%d/9)" % [
			t, ALM_FILE[t], file_n, variant, frame, ALM_FILE[t], 4])
		if file_n != ALM_FILE[t] or variant != 4 or frame != 9:
			print("FAIL: roundtrip type %d" % t)
			fails += 1

	if fails == 0:
		print("RESULT:OK transition_editor+db+type7")
	else:
		print("RESULT:FAIL %d checks" % fails)
	quit(1 if fails else 0)