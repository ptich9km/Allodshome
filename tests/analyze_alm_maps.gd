# ============================================================================
# ANALYZE: карты .alm из assets/maps/pvm — как профессионалы раскладывают мир.
#
# Запуск:
#   & 'C:\Games\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Work\Allodshome' --script "res://tests/analyze_alm_maps.gd"
#
# Для каждой карты выводит: размер, распределение terrain-типов, топ-level
# структур по type_id с папками, распределение юнитов по type_id, разброс высот.
# Цель — понять паттерны генерации: что где кладёт сценарист.
# ============================================================================
extends SceneTree

const PV := "res://assets/maps/pvm/"

const MAPS := [
	"sb_anp_greenlnd_1_1.alm",  # равнина
	"sb_anp_tropic_1_0.alm",    # тропики
	"sb_anp_canyon_1_0.alm",    # каньон
	"sb_anp_orcish_1_0.alm",    # орочья
	"sb_anp_gothic_1_2.alm",    # готика
	"sb_anp_som_1_0.alm",       # пустыня
	"sc_an_nord_3_2.alm",       # север
	"hc_an_4islands_4_6.alm",   # острова
	"sc_an_madp_2_1.alm",       # ?
"sc_acp_taonas_1_2.alm",   # ?
]


func _init() -> void:
	for f in MAPS:
		var p: String = PV + f
		if not FileAccess.file_exists(p):
			print("!!! нет файла: " + p)
			continue
		_analyze(p)
	quit(0)


func _analyze(path: String) -> void:
	var m: Dictionary = AlmLoader.load_map(path)
	if m.is_empty():
		return
	var w := int(m["width"])
	var h := int(m["height"])
	print("")
	print("================ %s  %dx%d ================" % [path.get_file(), w, h])

	# --- Распределение terrain-типов по тайлам ---
	var counts := { 0: 0, 1: 0, 2: 0, 3: 0 }        # grass/mountain/water/road
	var hflags_hist := {}                           # гистограмма hflags
	var tiles: Variant = m["tiles"]
	for j in range(tiles.size()):
		var t := int(tiles[j])
		var tt := AlmLoader.tile_type(t)
		counts[tt] = counts.get(tt, 0) + 1
		var hf: int = (t >> 8) & 0xFF
		hflags_hist[hf] = int(hflags_hist.get(hf, 0)) + 1
	var total := maxi(1, w * h)
	print("terrain: трава=%d (%.1f%%) горы=%d (%.1f%%) вода=%d (%.1f%%) дорога=%d (%.1f%%)" % [
		counts[0], counts[0] * 100.0 / total,
		counts[1], counts[1] * 100.0 / total,
		counts[2], counts[2] * 100.0 / total,
		counts[3], counts[3] * 100.0 / total,
	])

	# --- Высоты ---
	var hg: Variant = m.get("heights", PackedByteArray())
	if hg.size() > 0:
		var hmin: int = 255
		var hmax: int = 0
		var hsum := 0.0
		for k in range(hg.size()):
			var v := int(hg[k])
			hmin = mini(hmin, v)
			hmax = maxi(hmax, v)
			hsum += v
		print("высоты: min=%d max=%d avg=%.1f" % [hmin, hmax, hsum / hg.size()])

	# --- Структуры: топ папок по числу ---
	var structs: Array = m.get("structures", [])
	if structs.size() > 0:
		var folders := {}
		var players := {}
		var per_player := {}
		for s in structs:
			var sid := int(s.get("type_id", 0))
			var player := int(s.get("player", 0))
			var rec: Dictionary = StructureDB.get_by_id(sid)
			var folder := str(rec.get("folder", "?"))
			folders[folder] = int(folders.get(folder, 0)) + 1
			players[player] = int(players.get(player, 0)) + 1
			var key := "%d:%s" % [player, folder]
			per_player[key] = int(per_player.get(key, 0)) + 1
		print("структур всего: %d, по игрокам: %s" % [structs.size(), _sorted(players)])
		var top := _top(folders, 12)
		print("топ структур: %s" % [top])
		var pp := _top(per_player, 20)
		print("структуры по игроку: %s" % [pp])

	# --- Юниты: по type_id (с именами наборов из UnitDB) ---
	var units: Array = m.get("units", [])
	if units.size() > 0:
		var ucount := {}
		for u in units:
			var tid := int(u.get("type_id", 0))
			ucount[tid] = int(ucount.get(tid, 0)) + 1
		var uitems := []
		for tid in ucount:
			uitems.append([int(ucount[tid]), int(tid), UnitDB.set_name_for_id(int(tid))])
		uitems.sort_custom(func(a, b): return a[0] > b[0])
		var us := []
		for i in range(mini(20, uitems.size())):
			us.append("%s#%d x%d" % [uitems[i][2], uitems[i][1], uitems[i][0]])
		print("юнитов: %d, топ: %s" % [units.size(), " | ".join(us)])


func _top(d: Dictionary, n: int) -> String:
	var items := []
	for k in d:
		items.append([int(d[k]), str(k)])
	items.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for i in range(mini(n, items.size())):
		out.append("%s x%d" % [items[i][1], items[i][0]])
	return " | ".join(out)


func _sorted(d: Dictionary) -> String:
	var keys := []
	for k in d:
		keys.append(int(k))
	keys.sort()
	var out := []
	for k in keys:
		out.append("%s:%d" % [k, d[k]])
	return ", ".join(out)