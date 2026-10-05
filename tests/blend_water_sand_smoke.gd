extends SceneTree
## Пилот мягкой смеси вода–песок на ReliefMesh (alm_map.gd, 05.10).
##
## Вторая поверхность меша: клетки воды(2)/песка(5) рисуются шейдером
## mix(water, sand) по размытой маске биомов + лёгкий шум. Остальные биомы —
## прежний атлас (surface 0).
##
## Проверяет:
##   1. карта грузится, меш собран;
##   2. есть surface 0 (атлас) и surface 1 (бленд), если на карте вода/песок;
##   3. _blend_cells > 0 при наличии воды/песка;
##   4. маска/текстуры бленда созданы;
##   5. шейдер surface 1 — canvas_item с u_water/u_sand/u_biome.
##
## Запуск: godot --headless --path . --script res://tests/blend_water_sand_smoke.gd

const SEED := 4242

var _fails: Array[String] = []
var _checks := 0

func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	Game.hero_class = "warrior"
	Game.hero_name = "Герой"
	call_deferred("_run")

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)

func _run() -> void:
	Game.request_map_by_seed(SEED, "mid")
	var err := change_scene_to_file("res://scenes/main.tscn")
	_check(err == OK, "main.tscn сменилась")
	await process_frame
	await create_timer(0.5).timeout

	var am = get_first_node_in_group("alm_map")
	_check(am != null, "AlmMap в дереве")
	if am == null:
		_report()
		return

	var mi: MeshInstance2D = am.get("mesh")
	_check(mi != null, "ReliefMesh есть")
	if mi == null or mi.mesh == null:
		_report()
		return

	var m: ArrayMesh = mi.mesh
	var n_surf: int = m.get_surface_count()
	print("INFO surfaces=%d atlas_cells=%d blend_cells=%d blend_node=%s" % [
		n_surf, int(am.get("_atlas_cells")), int(am.get("_blend_cells")),
		"yes" if am.get("blend_mesh") != null else "no"])

	_check(n_surf >= 1, "есть surface 0 (атлас) (%d)" % n_surf)
	_check(int(am.get("_blend_cells")) > 0,
		"на карте есть клетки воды/песка для бленда (%d)" % int(am.get("_blend_cells")))
	_check(am.get("_biome_mask") != null, "маска биомов создана")
	_check(am.get("_blend_water") != null, "текстура воды для бленда")
	_check(am.get("_blend_sand") != null, "текстура песка для бленда")

	var bm = am.get("blend_mesh")
	_check(bm != null, "узел BlendMesh создан")
	if bm != null:
		_check(bm is MeshInstance2D, "BlendMesh — MeshInstance2D")
		_check(bm.mesh != null, "у BlendMesh есть меш")
		var mat: Material = bm.material
		_check(mat is ShaderMaterial, "BlendMesh — ShaderMaterial")
		if mat is ShaderMaterial:
			var sh: Shader = (mat as ShaderMaterial).shader
			_check(sh != null and sh.code.contains("shader_type canvas_item"),
				"шейдер бленда canvas_item")
			if sh != null:
				_check(sh.code.contains("u_water") and sh.code.contains("u_sand"),
					"шейдер сэмплирует u_water и u_sand")
				_check(sh.code.contains("u_biome"), "шейдер читает u_biome")
	else:
		_check(false, "BlendMesh отсутствует, хотя blend_cells=%d" % int(am.get("_blend_cells")))

	# Ширина карты и что атласная часть не пустая
	_check(int(am.get("map_width")) == 128, "карта 128 (mid)")
	_check(int(am.get("_atlas_cells")) > 0, "атласные клетки есть (%d)" % int(am.get("_atlas_cells")))

	_report()

func _report() -> void:
	if _fails.is_empty():
		print("RESULT: OK blend_water_sand_smoke (%d)" % _checks)
		quit(0)
	else:
		print("RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
		quit(1)
