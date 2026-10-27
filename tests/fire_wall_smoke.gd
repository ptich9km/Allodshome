extends SceneTree
## Headless-проверка огненной стены: третий слой «языки пламени».
##
## Что изменилось: `spawn_wall` выдавал обеим стенам стиль "wall", то есть
## Wall_of_Fire рисовалась тем же плоским контуром, что и непроходимая стена
## земли. Игрок решил: огонь должен гореть настоящим языком пламени поверх
## героя, ровным красно-оранжевым, на всём поле 6x2.
##
## Проверяет:
##  1. стена огня и стена земли получили РАЗНЫЕ стили (в оригинале это разные
##     заклинания: огонь жжёт, земля блокирует);
##  2. язык пламени есть только у огня, у земли его нет;
##  3. пламя рисуется ПОВЕРХ слоя юнитов, а заливка зоны — под ним (иначе
##     земля прячет героя, а пламя наоборот говорит, что огонь не опасен);
##  4. ширина пламени РОВНО по прямоугольнику зоны: визуал не имеет права
##     выглядеть так, будто горят лишние клетки;
##  5. пламя поднимается вверх от зоны (огонь растёт, опасная зона от этого
##     не расширяется) и его низ совпадает с низом зоны;
##  6. цвет ровный красно-оранжевый (не «рыжая плёнка» цвета сферы);
##  7. в фазе подсказки пламени нет — подсказка показывает только границы;
##  8. в активной фазе пламя горит, на затухании гаснет плавно, а не рывком;
##  9. шейдер языков пламени компилируется.
##
## Запуск:
##   godot --headless --path . --script res://tests/fire_wall_smoke.gd

const FIRE := "Fire"
const EARTH := "Earth"
const ZONE_Z := 13          ## FLAME_Z в spell_zone.gd
const FILL_Z := 2           ## заливка зоны под юнитами
const RISE := 1.4           ## FLAME_RISE в spell_zone.gd

var _fails: Array = []
var _hero: Player = null


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 13, "spirit": 12,
		"blade": 10, "bludgeon": 10, "pike": 10, "shooting": 10,
		"fire": 20, "water": 20, "air": 20, "earth": 20, "astral": 20,
		"weapon": "staff", "shield": false, "armor": "light"}
	Game.hero_class = "mage"
	Game.debug_magic = true
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("FIREWALL: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "загрузка main.tscn: %d" % err)
		_finish()
		return
	await process_frame
	await create_timer(0.6).timeout
	_hero = get_first_node_in_group("player") as Player
	if _hero == null:
		_check(false, "герой не загружен")
		_finish()
		return

	var pos := _hero.global_position + Vector2(0, 120)
	var fire := SpellVFX.spawn_wall(pos, FIRE, _hero, 6.0, "damage", Vector2i(6, 2), 25)
	var earth := SpellVFX.spawn_wall(pos + Vector2(0, 200), EARTH, _hero, 8.0, "block",
		Vector2i(6, 2), 0)
	_check(fire != null, "стена огня создаётся")
	_check(earth != null, "стена земли создаётся")
	if fire == null or earth == null:
		_finish()
		return
	await process_frame

	_test_styles(fire, earth)
	await _test_layers(fire, earth)
	_test_geometry(fire)
	_test_color(fire)
	await _test_phases(fire)
	_test_shader()

	_finish()


# --- 1. Стили по сфере ----------------------------------------------------

func _test_styles(fire: SpellWall, earth: SpellWall) -> void:
	_check(fire.style == "wall_fire", "стена огня стиль wall_fire (%s)" % fire.style)
	_check(earth.style == "wall_earth", "стена земли стиль wall_earth (%s)" % earth.style)
	_check(fire.style != earth.style,
		"стили стен различаются — в оригинале это разные заклинания")
	_check(fire.flame, "стена огня включает пламя (flame = true)")
	_check(not earth.flame,
		"стена земли БЕЗ пламени: земля — непроходимая преграда, не огонь")
	# Поведение из оригинала не должно смешаться: огонь жжёт, земля блокирует.
	_check(fire.deals_damage(), "огонь наносит урон")
	_check(not earth.deals_damage(), "земля не наносит урон")
	_check(earth.blocks_path(), "земля блокирует проход")
	_check(not fire.blocks_path(), "огонь проходим (по оригиналу жжёт, не глушит)")


# --- 2-3. Слои ------------------------------------------------------------

func _test_layers(fire: SpellWall, earth: SpellWall) -> void:
	var flames := _flames_of(fire)
	# Пламя есть в КАЖДОЙ клетке; у дальнего ряда оно тише (иначе 12
	# аддитивных очагов выжигают цвет в белую плёнку).
	_check(flames.size() == fire.cells.x * fire.cells.y,
		"у стены огня очаг в каждой клетке: %d из %d"
			% [flames.size(), fire.cells.x * fire.cells.y])
	var near := 0.0
	var far := 10.0
	for f in flames:
		var b := float(f.get_meta("base_alpha", 1.0))
		near = maxf(near, b)
		far = minf(far, b)
	_check(near > far + 0.2,
		"дальний ряд пламени тише ближнего (%.2f против %.2f)" % [far, near])
	_check(_flames_of(earth).is_empty(), "у стены земли пламени нет")
	_check(_stones_of(earth).size() == earth.cells.x * earth.cells.y,
		"у стены земли валун в каждой клетке: %d" % _stones_of(earth).size())
	if flames.is_empty():
		return
	# Пламя поверх юнитов — это решение игрока. Заливка при этом обязана
	# остаться ПОД ними, иначе земля спрячет героя стоящего в огне.
	_check(flames[0].z_index >= ZONE_Z,
		"пламя поверх юнитов (z=%d, нужно >= %d)" % [flames[0].z_index, ZONE_Z])
	# Валуны — наоборот, ниже юнитов: стена не должна прятать героя.
	if not _stones_of(earth).is_empty():
		_check(_stones_of(earth)[0].z_index < ZONE_Z,
			"валуны ниже юнитов (z=%d)" % _stones_of(earth)[0].z_index)
	var fill := _fill_of(fire)
	_check(fill != null and fill.z_index <= FILL_Z,
		"заливка зоны под юнитами (z=%s, нужно <= %d)" % [
			str(fill.z_index) if fill != null else "-", FILL_Z])


# --- 4-5. Геометрия -------------------------------------------------------

func _test_geometry(fire: SpellWall) -> void:
	var flames := _flames_of(fire)
	if flames.is_empty():
		return
	var ps := fire.pixel_size()
	# Каждый очаг — ровно клетка в ширину и клетка+подъём в высоту.
	var bad_w := 0
	var bad_h := 0
	for f in flames:
		var tex: Vector2 = f.texture.get_size()
		var w: float = f.scale.x * tex.x
		var h: float = f.scale.y * tex.y
		if absf(w - 32.0) > 0.5:
			bad_w += 1
		if absf(h - (32.0 + rise_px())) > 0.5:
			bad_h += 1
	_check(bad_w == 0, "каждый очаг шириной в клетку (промахов: %d)" % bad_w)
	_check(bad_h == 0, "каждый очаг = клетка + подъём %.1f (промахов: %d)"
		% [RISE, bad_h])
	# Низ каждого очага совпадает с низом СВОЕЙ клетки — огонь не в воздухе.
	var bad_bottom := 0
	for f in flames:
		var tex2: Vector2 = f.texture.get_size()
		var h2: float = f.scale.y * tex2.y
		var bottom_local: float = f.position.y + h2 * 0.5
		var bottom_world: float = fire.global_position.y + bottom_local
		# Клетка должна содержать эту нижнюю точку (низ клетки = её y+32).
		var cell_y := int(floor((bottom_world - 1.0) / 32.0))
		var cell_bottom := float(cell_y + 1) * 32.0
		if absf(bottom_world - cell_bottom) > 1.0:
			bad_bottom += 1
	_check(bad_bottom == 0, "низ очагов на границах клеток (промахов: %d)"
		% bad_bottom)
	# Зона осталась прежней: 6×2 = 192×64.
	_check(absf(ps.x - 192.0) <= 1.0 and absf(ps.y - 64.0) <= 1.0,
		"размер зоны 6×2 (%s)" % str(ps))


# --- 6. Цвет --------------------------------------------------------------

func _test_color(fire: SpellWall) -> void:
	var flames := _flames_of(fire)
	if flames.is_empty() or not (flames[0].material is ShaderMaterial):
		_check(false, "у пламени есть ShaderMaterial")
		return
	var c: Color = (flames[0].material as ShaderMaterial).get_shader_parameter("color")
	_check(c.is_equal_approx(SpellVFX.FLAME_WALL_COLOR),
		"цвет пламени = заданному красно-оранжевому (%s против %s)"
			% [str(c), str(SpellVFX.FLAME_WALL_COLOR)])
	# Ровный красно-оранжевый: красный канал главный, зелёный заметно ниже,
	# синий почти отсутствует. Рыжая плёнка цвета сферы тут не годится.
	_check(c.r > 0.9, "красный канал доминирует (r=%.2f)" % c.r)
	_check(c.g < c.r * 0.5, "зелёного мало — это красно-оранжевый, не рыжий (g=%.2f)" % c.g)
	_check(c.b < c.r * 0.25, "синего почти нет (b=%.2f)" % c.b)


# --- 7-8. Фазы ------------------------------------------------------------

func _test_phases(fire: SpellWall) -> void:
	# Свежая стена: у исходной к этому моменту телеграф давно прошёл, и
	# alpha = 1.0 было ПРАВИЛЬНЫМ поведением. Мой тест проверял не то.
	var fresh := SpellVFX.spawn_wall(_hero.global_position + Vector2(0, 320), FIRE,
		_hero, 3.0, "damage", Vector2i(6, 2), 20)
	if fresh == null:
		_check(false, "свежая стена огня для проверки фаз создана")
		return
	await process_frame
	var flames := _flames_of(fresh)
	if flames.is_empty():
		_check(false, "у свежей стены есть пламя")
		return
	# Пульс проверяем на БЛИЖНЕМ ряду: у дальнего своя базовая яркость 0.5.
	var f: Sprite2D = flames[0]
	for s in flames:
		if float((s as Sprite2D).get_meta("base_alpha", 1.0)) > 0.99:
			f = s as Sprite2D
			break
	# В фазе подсказки огонь ещё не бьёт — пламени быть не должно, иначе
	# подсказка ничего не сообщает.
	_check(fresh.telegraph > 0.0,
		"свежая стена в фазе подсказки (осталось %.2f с)" % fresh.telegraph)
	_check(f.modulate.a < 0.05,
		"в фазе подсказки пламени нет (alpha=%.2f)" % f.modulate.a)
	# Ждём конца телеграфа (0.55 с) — огонь должен загореться.
	await create_timer(0.75).timeout
	_check(f.modulate.a > 0.2,
		"после подсказки пламя горит (alpha=%.2f)" % f.modulate.a)
	# Пламя должно пульсировать, а не стоять на 1.0: иначе при HDR поле
	# выглядит залитой плёнкой. Период пульса ~1 с, поэтому окно наблюдения
	# должно быть не короче периода — 6 кадров подряд (0.1 с) попадали в одно
	# и то же место кривой у самого минимума и выглядели как «не пульсирует».
	var samples: Array = []
	for i in range(9):
		await create_timer(0.13).timeout
		samples.append(f.modulate.a)
	var lo := 99.0
	var hi := -1.0
	for v in samples:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_check(hi - lo > 0.05,
		"яркость пламени пульсирует за ~1.2 с (%.2f..%.2f, размах %.3f)"
			% [lo, hi, hi - lo])
	_check(lo >= 0.69 and hi <= 1.01,
		"пульс в ожидаемой полосе 0.70..1.00 — не проваливается в ноль и "
			+ "не пересвечивает")


# --- 9. Шейдер ------------------------------------------------------------

func _test_shader() -> void:
	var mat := SpellVFX.flame_wall_material(SpellVFX.FLAME_WALL_COLOR)
	_check(mat != null and mat.shader != null, "шейдер языков пламени создан")
	if mat != null and mat.shader != null:
		var code := mat.shader.code
		_check(code.contains("shader_type canvas_item"), "шейдер объявлен как canvas_item")
		_check(code.contains("blend_add") and code.contains("unshaded"),
			"пламя самосветящееся (blend_add + unshaded) — сцена без ambient")
		_check(code.contains("fbm"), "шейдер использует fBm, а не синус")
		_check(code.contains("domain") or code.contains("warp"),
			"есть доменное искажение — язык пламени не периодический")


# --- поиск ----------------------------------------------------------------

func rise_px() -> float:
	return 32.0 * RISE


func _flames_of(wall: SpellWall) -> Array:
	var out: Array = []
	if wall == null:
		return out
	for c in wall.get_children():
		if c is Sprite2D and (c as Sprite2D).z_index >= ZONE_Z:
			out.append(c as Sprite2D)
	return out


## Валуны каменной стены — по идентичности шейдера (а не по z: слой контура
## тоже лежит между заливкой и пламенем).
func _stones_of(wall: SpellWall) -> Array:
	var out: Array = []
	if wall == null:
		return out
	var want: Shader = SpellVFX.stone_wall_material(0.0).shader
	for c in wall.get_children():
		if c is Sprite2D and (c as Sprite2D).material is ShaderMaterial:
			if ((c as Sprite2D).material as ShaderMaterial).shader == want:
				out.append(c as Sprite2D)
	return out


func _fill_of(wall: SpellWall) -> Sprite2D:
	if wall == null:
		return null
	for c in wall.get_children():
		if c is Sprite2D and (c as Sprite2D).z_index <= FILL_Z:
			return c as Sprite2D
	return null


func _finish() -> void:
	if _fails.is_empty():
		print("FIREWALL: RESULT: OK")
	else:
		print("FIREWALL: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
