extends SceneTree
## Мир 4x3: топология, детерминизм, карта сектора (23.10).
##
## Запуск: godot --headless --path . --script res://tests/world_map_smoke.gd
##
## Проверяет:
##  1. 12 секторов, 4 столицы, старт (4:1), центр (2:2) только через столицы;
##  2. соседей только по сторонам и симметрию связей;
##  3. размеры и тиры по игровому плану;
##  4. детерминизм сидов секторов;
##  5. WorldState.init_world: 4 разные фракции в столицах, старт — раса героя;
##  6. генерацию стартового и среднего сектора: размер, порталы по границам,
##     достижимость порталов и НПЦ от спавна, доля непроходимого.

const DIR := "user://maps/_world_map_check/"

var _checks := 0
var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
	print(("  OK  " if ok else "  FAIL") + " " + what)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	# Генератор берёт расу городов из Game.hero_race (как в игре).
	Game.hero_race = "human"
	var wm = load("res://scripts/world/world_map.gd")

	# --- 1. Сетка ---
	var ids: Array = wm.ids()
	_check(ids.size() == 12, "12 секторов (найдено %d)" % ids.size())
	_check(str(wm.start_id()) == "s41", "старт = s41 (4:1)")
	_check(str(wm.center_id()) == "s22", "центр = s22 (2:2)")
	var caps: Array = wm.capital_ids()
	_check(caps.size() == 4, "4 столицы (найдено %d)" % caps.size())
	for c in caps:
		_check(wm.tier_of(str(c)) == "faction", "столица %s имеет тир faction" % c)
	_check(wm.tier_of("s41") == "start", "s41 — start")
	_check(wm.tier_of("s31") == "mid" and wm.tier_of("s42") == "mid", "s31/s42 — mid")
	_check(wm.size_of("s41") == 96, "старт 96x96")
	_check(wm.size_of("s31") == 128, "mid 128x128")
	_check(wm.size_of("s33") == 160, "hard 160x160")
	_check(wm.size_of("s21") == 192, "столица 192x192")

	# --- 2. Соседи только по сторонам ---
	var center_ns: Array = wm.neighbors("s22")
	_check(center_ns.size() == 4, "у центра 4 соседа")
	for c in caps:
		_check(center_ns.has(c), "центр граничит со столицей %s" % c)
	for id in ids:
		for n in wm.neighbors(str(id)):
			_check(wm.neighbors(str(n)).has(str(id)), "связь %s<->%s симметрична" % [id, n])
		_check(wm.neighbors(str(id)).size() <= 4, "у %s не больше 4 соседей" % id)
	# Центр без столиц недостижим: убираем столицы из графа.
	var seen := {"s41": true}
	var queue: Array = ["s41"]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in wm.neighbors(cur):
			var nid := str(n)
			if caps.has(nid) or seen.has(nid):
				continue
			seen[nid] = true
			queue.append(nid)
	_check(not seen.has("s22"), "центр недостижим без прохода через столицы")
	_check(seen.size() == 5, "без столиц доступно 5 секторов (найдено %d)" % seen.size())

	# --- 3. Детерминизм сидов ---
	var s_a := int(wm.seed_of(777, "s41"))
	var s_b := int(wm.seed_of(777, "s41"))
	var s_c := int(wm.seed_of(777, "s42"))
	var s_other := int(wm.seed_of(778, "s41"))
	_check(s_a == s_b, "сид сектора детерминирован")
	_check(s_a != s_c, "разные секторы — разные сиды")
	_check(s_a != s_other, "разные миры — разные сиды")
	_check(s_a > 0, "сид положительный")

	# --- 4. Состояние мира ---
	var ws_script: GDScript = load("res://scripts/world/world_state.gd")
	var ws = ws_script.new()
	ws.init_world(4242, "humans")
	_check(ws.sectors.size() == 12, "init_world создал 12 секторов")
	_check(str(ws.sector_state("s41").get("owner", "")) == "humans", "старт принадлежит расе героя")
	var cap_owners: Array = []
	for c in caps:
		var o := str(ws.sector_state(str(c)).get("owner", ""))
		cap_owners.append(o)
		_check(o != "", "у столицы %s есть владелец" % c)
	cap_owners.sort()
	var want: Array = ws.WORLD_CAPITAL_FACTIONS.duplicate()
	want.sort()
	_check(cap_owners == want, "четыре столицы — четыре разные фракции (%s)" % str(cap_owners))
	var ws2 = ws_script.new()
	ws2.init_world(4242, "humans")
	_check(str(ws2.sector_state("s21").get("owner", "")) == str(ws.sector_state("s21").get("owner", "")),
		"раскладка столиц детерминирована сидом мира")
	_check(int(ws.sector_state("s41").get("seed", 0)) == int(wm.seed_of(4242, "s41")),
		"сид сектора в состоянии совпадает с WorldMap")
	# JSON round-trip
	var back = ws_script.from_json_text(ws.to_json_text())
	_check(back != null and back.sectors.size() == 12, "секторы переживают JSON round-trip")
	_check(int(back.world_seed) == 4242, "world_seed переживает JSON round-trip")

	# --- 5. Новая игра стартует на s41 ---
	Game.new_random_map("start")
	_check(Game.map_sector == "s41", "новая игра: сектор s41 (сейчас %s)" % Game.map_sector)
	_check(Game.map_zone == "start", "новая игра: тир start (сейчас %s)" % Game.map_zone)
	_check(Game.map_seed == int(wm.seed_of(Game.world_seed, "s41")),
		"новая игра: сид карты = сид сектора")

	# --- 6. Генерация карт секторов ---
	_gen_and_check(wm, "s41", "humans")
	_gen_and_check(wm, "s31", "humans")
	_gen_and_check(wm, "s22", "humans")

	print("")
	if _fails.is_empty():
		print("RESULT: OK world_map_smoke (%d checks)" % _checks)
	else:
		print("RESULT: FAIL world_map_smoke (%d checks, %d fails)" % [_checks, _fails.size()])
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)


func _gen_and_check(wm, sector: String, race: String) -> void:
	var tier := str(wm.tier_of(sector))
	var size := int(wm.size_of(sector))
	var seed_value := 12345
	var ns: Array = wm.neighbors(sector)
	var path: String = MapGenerator.new().generate(seed_value, tier, DIR, "", "", race,
		sector, size, ns, str(wm.relief_of(sector)))
	_check(path != "", "%s: карта сгенерирована" % sector)
	_check(path.get_file().contains("_" + sector + "_"), "%s: имя файла содержит сектор" % sector)
	if path == "":
		return
	var m: Dictionary = AlmLoader.load_map(path)
	_check(int(m.get("width", 0)) == size and int(m.get("height", 0)) == size,
		"%s: размер %dx%d" % [sector, size, size])
	var hflags: PackedByteArray = m.get("hflags", PackedByteArray())
	var tiles: PackedInt32Array = m.get("tiles", PackedInt32Array())
	_check(tiles.size() == size * size, "%s: tiles заполнены" % sector)
	_check(hflags.size() == size * size, "%s: hflags заполнены" % sector)
	if hflags.size() != size * size:
		hflags = PackedByteArray()
		hflags.resize(size * size)
	var terrain := PackedByteArray()
	terrain.resize(size * size)
	for ti in range(terrain.size()):
		terrain[ti] = AlmLoader.terrain_type(int(hflags[ti]))

	# Портал: по одному на соседа, адреса совпадают.
	var portal_path := path.get_basename() + ".portal.json"
	_check(FileAccess.file_exists(portal_path), "%s: sidecar порталов есть" % sector)
	var recs: Array = []
	if FileAccess.file_exists(portal_path):
		var f := FileAccess.open(portal_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			recs = (parsed as Dictionary).get("portals", []) as Array
	_check(recs.size() == ns.size(), "%s: порталов %d, соседей %d" % [sector, recs.size(), ns.size()])
	var dests: Array = []
	for r in recs:
		var rec: Dictionary = r as Dictionary
		dests.append(str(rec.get("to", "")))
		_check(str(wm.dir_of(sector, str(rec.get("to", "")))) == str(rec.get("dir", "")),
			"%s: направление портала %s верное" % [sector, rec.get("to", "")])
	dests.sort()
	var want_ns: Array = ns.duplicate()
	want_ns.sort()
	_check(dests == want_ns, "%s: адреса порталов = соседи" % sector)

	# Достижимость от спавна: порталы и городские НПЦ.
	var spawn := _spawn_cell(path)
	_check(spawn.x >= 0, "%s: спавн есть" % sector)
	var reach := _reachable(terrain, size, spawn)
	_check(not reach.is_empty(), "%s: от спавна есть проходимая область" % sector)
	for r in recs:
		var rec: Dictionary = r as Dictionary
		_check(reach.has(Vector2i(int(rec.get("x", -1)), int(rec.get("y", -1)))),
			"%s: портал %s достижим пешком" % [sector, rec.get("dir", "")])
	var npcs_path := path.get_basename() + ".npcs.json"
	if FileAccess.file_exists(npcs_path):
		var nf := FileAccess.open(npcs_path, FileAccess.READ)
		var np: Variant = JSON.parse_string(nf.get_as_text())
		nf.close()
		var npcs: Array = (np as Dictionary).get("npcs", []) if np is Dictionary else []
		var bad := 0
		var city_npcs := 0
		for raw in npcs:
			var n: Dictionary = raw as Dictionary
			var role := str(n.get("role", ""))
			if role == "guard" or role == "citizen":
				city_npcs += 1
				if not reach.has(Vector2i(int(n.get("x", -1)), int(n.get("y", -1)))):
					bad += 1
					var bx := int(n.get("x", -1))
					var by := int(n.get("y", -1))
					var bt := int(terrain[by * size + bx]) if bx >= 0 and by >= 0 else -1
					print("    UNREACHABLE NPC %s role=%s cell=(%d,%d) terrain=%d" % [sector, role, bx, by, bt])
		_check(city_npcs > 0, "%s: городские НПЦ есть (%d)" % [sector, city_npcs])
		_check(bad == 0, "%s: все городские НПЦ достижимы (недостижимых %d)" % [sector, bad])

	# Доля непроходимого: горы+вода не должны съесть карту.
	var hard := 0
	for i in range(terrain.size()):
		var t: int = int(terrain[i])
		if t == 1 or t == 2:
			hard += 1
	var frac := float(hard) / float(maxi(1, terrain.size()))
	_check(frac <= 0.35, "%s: непроходимого %.1f%% (<= 35%%)" % [sector, frac * 100.0])
	print("    %s: порталов=%d, непроходимого=%.1f%%, НПЦ города=%d" %
		[sector, recs.size(), frac * 100.0, 0])


func _spawn_cell(path: String) -> Vector2i:
	var p := path.get_basename() + ".spawn.json"
	if not FileAccess.file_exists(p):
		return Vector2i(-1, -1)
	var f := FileAccess.open(p, FileAccess.READ)
	var j: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (j is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(int((j as Dictionary).get("x", -1)), int((j as Dictionary).get("y", -1)))


func _reachable(terrain: PackedByteArray, size: int, start: Vector2i) -> Dictionary:
	var out := {}
	if start.x < 0 or start.y < 0:
		return out
	out[start] = true
	var queue: Array = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 1 or q.y < 1 or q.x >= size - 1 or q.y >= size - 1:
				continue
			if out.has(q):
				continue
			var t: int = int(terrain[q.y * size + q.x])
			if t == 1 or t == 2:
				continue
			out[q] = true
			queue.append(q)
	return out
