extends SceneTree
## Headless-проверка НАЗЕМНЫХ ЭФФЕКТОВ (пакет C).
##
## Жалобы игрока 28.10: «стена огня выглядит как огонь на все клетки,
## расплывчатый», «стена камней — что-то горит и видна сетка», «яд и метель —
## что-то горит и сетка», «когда герой смотрит влево/вправо, стена должна
## вставать вертикально».
##
## Проверяет:
##  1. ориентация стены: прицел вбок → 2×6, прицел вниз → 6×2;
##  2. стили различаются ЦВЕТОМ и рисунком (огонь/камень/яд/метель);
##  3. у огня свой очаг на каждую клетку переднего ряда, у камня — валун в клетке;
##  4. сетки больше нет: маска соседей считается в шейдере по клетке, а мягкий
##     край — от внешнего прямоугольника зоны, а не от каждой клетки;
##  5. метель и яд — 3×3.
##
## Запуск:
##   godot --headless --path . --script res://tests/ground_zone_style_smoke.gd

var _fails: Array = []
var _hero: Player = null


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 13, "spirit": 12,
		"blade": 10, "bludgeon": 10, "pike": 10, "shooting": 10,
		"fire": 20, "water": 20, "air": 20, "earth": 20, "astral": 20,
		"weapon": "staff", "shield": false, "armor": "light"}
	Game.hero_class = "mage"
	Game.hero_name = "Маг"
	Game.debug_magic = true
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("GROUND: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	_test_colors()
	_test_shader()
	_test_data()
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "main.tscn не загрузился")
		_finish()
		return
	await process_frame
	await create_timer(0.8).timeout
	_hero = get_first_node_in_group("player") as Player
	_check(_hero != null, "герой загружен")
	if _hero != null:
		await _test_orientation()
	_finish()


# --- 2. Цвета стилей -------------------------------------------------------

func _test_colors() -> void:
	var fire := SpellVFX.style_color("wall_fire")
	var earth := SpellVFX.style_color("wall_earth")
	var hail := SpellVFX.style_color("hail")
	var cloud := SpellVFX.style_color("cloud")
	_check(fire.r > 0.8 and fire.g < fire.r * 0.6,
		"огонь красно-оранжевый (%s)" % str(fire))
	_check(cloud.g > cloud.r and cloud.g > cloud.b,
		"яд ЗЕЛЁНЫЙ, а не синий цветом сферы Water (%s)" % str(cloud))
	_check(hail.b > hail.r, "метель холодная (синий выше красного, %s)" % str(hail))
	_check(absf(earth.r - earth.g) < 0.15 and absf(earth.g - earth.b) < 0.15,
		"стена камней — нейтральный камень (%s)" % str(earth))
	# Плотность заливки: огонь почти без заливки (всё читаемое — языки пламени),
	# яд наоборот — сам туман.
	_check(SpellVFX.style_fill("wall_fire") < SpellVFX.style_fill("cloud"),
		"заливка огня легче, чем у яда (%.2f < %.2f)"
			% [SpellVFX.style_fill("wall_fire"), SpellVFX.style_fill("cloud")])


# --- 4. Шейдер: нет сетки --------------------------------------------------

func _test_shader() -> void:
	var mat := SpellVFX.ground_material("Fire", "wall_fire")
	var code: String = mat.shader.code
	_check(code.contains("cell.y <= 0.0") and code.contains("cell.x <= 0.0"),
		"маска соседей считается В ШЕЙДЕРЕ по клетке (раньше приходила одна на зону)")
	_check(not code.contains("min(min(cuv.x"),
		"мягкий край не считается по каждой клетке — сетки нет")
	_check(code.contains("d_edge") and code.contains("smoothstep(0.0, 6.0, d_edge)"),
		"мягкий край — от внешнего прямоугольника зоны")
	_check(code.contains("style == 1") and code.contains("style == 2")
			and code.contains("style == 0"),
		"у каждого стиля свой рисунок, а не один «огонь на всё»")


# --- 5. Данные -------------------------------------------------------------

func _test_data() -> void:
	var blizzard := SpellDB.get_spell("Blizzard")
	var cells: Array = blizzard.get("zone_cells", [])
	_check(cells.size() == 2 and int(cells[0]) == 3 and int(cells[1]) == 3,
		"метель 3×3 (%s)" % str(cells))
	var poison := SpellDB.get_spell("Poison_Cloud")
	var pcells: Array = poison.get("zone_cells", [])
	_check(pcells.size() == 2 and int(pcells[0]) == 3 and int(pcells[1]) == 3,
		"яд 3×3 (%s)" % str(pcells))


# --- 1. Ориентация стены ---------------------------------------------------

func _await_wall() -> SpellWall:
	for i in range(20):
		await process_frame
		for c in current_scene.get_children():
			if c is SpellWall:
				return c as SpellWall
	return null


func _test_orientation() -> void:
	# Смотрим ВБОК (прицел вправо) — стена встаёт вертикально 2×6.
	_hero.call("_create_wall", _hero.global_position + Vector2(150, 0),
		"Wall_of_Fire", "Fire")
	var wall := await _await_wall()
	_check(wall != null, "стена по прицелу вбок создана")
	if wall != null:
		_check(wall.cells == Vector2i(2, 6),
			"прицел вбок → стена 2×6 (%s)" % str(wall.cells))
		wall.queue_free()
		await process_frame

	# Смотрим ВНИЗ — горизонтальная 6×2.
	_hero.call("_create_wall", _hero.global_position + Vector2(0, 150),
		"Wall_of_Fire", "Fire")
	var wall2 := await _await_wall()
	_check(wall2 != null, "стена по прицелу вниз создана")
	if wall2 != null:
		_check(wall2.cells == Vector2i(6, 2),
			"прицел вниз → стена 6×2 (%s)" % str(wall2.cells))
		# Очагов огня — по числу клеток, в обеих линиях.
		var flames := 0
		for c in wall2.get_children():
			if c is Sprite2D and (c as Sprite2D).z_index >= 13:
				flames += 1
		_check(flames == 12, "у стены 6×2 двенадцать очагов огня (%d)" % flames)
		wall2.queue_free()
		await process_frame

	# Яд: туман + ЗЕЛЁНОЕ пламя (просьба игрока 28.10).
	_hero.call("_create_zone", _hero.global_position + Vector2(0, 150),
		"Poison_Cloud", "Water")
	await process_frame
	var clouds: Array = []
	for c in current_scene.get_children():
		if c is SpellZone and (c as SpellZone).style == "cloud":
			clouds.append(c)
	_check(clouds.size() == 1, "яд создан как зона (%d)" % clouds.size())
	if clouds.size() == 1:
		var zone := clouds[0] as SpellZone
		var green := 0
		for c in zone.get_children():
			if c is Sprite2D and (c as Sprite2D).z_index >= 13 \
					and (c as Sprite2D).material is ShaderMaterial:
				var col: Color = ((c as Sprite2D).material as ShaderMaterial).get_shader_parameter("color")
				if col.g > col.r and col.g > col.b:
					green += 1
		_check(green == 9, "у яда 3×3 девять ЗЕЛЁНЫХ языков пламени (%d)" % green)
		zone.queue_free()
		await process_frame


func _finish() -> void:
	if _fails.is_empty():
		print("GROUND: RESULT: OK")
	else:
		print("GROUND: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
