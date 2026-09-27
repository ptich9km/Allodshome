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
	var flame := _flame_of(fire)
	_check(flame != null, "у стены огня есть слой пламени")
	_check(_flame_of(earth) == null, "у стены земли слоя пламени нет")
	if flame == null:
		return
	# Пламя поверх юнитов — это решение игрока. Заливка при этом обязана
	# остаться ПОД ними, иначе земля спрячет героя стоящего в огне.
	_check(flame.z_index >= ZONE_Z,
		"пламя поверх юнитов (z=%d, нужно >= %d)" % [flame.z_index, ZONE_Z])
	var fill := _fill_of(fire)
	_check(fill != null and fill.z_index <= FILL_Z,
		"заливка зоны под юнитами (z=%s, нужно <= %d)" % [
			str(fill.z_index) if fill != null else "-", FILL_Z])
	if fill != null and flame != null:
		_check(fill.z_index < flame.z_index,
			"заливка ниже пламени — границы опасных клеток не перекрыты огнём")


# --- 4-5. Геометрия -------------------------------------------------------

func _test_geometry(fire: SpellWall) -> void:
	var flame := _flame_of(fire)
	if flame == null:
		return
	var ps := fire.pixel_size()
	# Ширина спрайта в пикселях = scale.x * 32 (текстура 32x32).
	var width := flame.scale.x * 32.0
	_check(absf(width - ps.x) <= 1.0,
		("ширина пламени = ширине зоны (%.1f против %.1f) — визуал не врёт "
			+ "про лишние клетки") % [width, ps.x])
	# Вверх пламя выходит за прямоугольник зоны: огонь растёт вверх.
	var height := flame.scale.y * 32.0
	_check(height > ps.y,
		("пламя выше прямоугольника зоны (%.1f против %.1f)" % [height, ps.y]))
	_check(absf(height - (ps.y + 32.0 * RISE)) <= 1.0,
		("высота пламени = зона + подъём %.1f клетки (ожидалось %.1f)"
			% [RISE, ps.y + 32.0 * RISE]))
	# Низ пламени совпадает с низом зоны: иначе огонь висит в воздухе.
	# Спрайт растёт вверх от центра, поэтому центр смещён вниз на пол
	# добавленной высоты.
	_check(absf(flame.position.y + rise_px() * 0.5) <= 1.0,
		("низ пламени совпадает с низом зоны (смещение %.2f)"
			% (flame.position.y + rise_px() * 0.5)))


# --- 6. Цвет --------------------------------------------------------------

func _test_color(fire: SpellWall) -> void:
	var flame := _flame_of(fire)
	if flame == null or not (flame.material is ShaderMaterial):
		_check(false, "у пламени есть ShaderMaterial")
		return
	var c: Color = (flame.material as ShaderMaterial).get_shader_parameter("color")
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
	var f := _flame_of(fresh)
	if f == null:
		_check(false, "у свежей стены есть пламя")
		return
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


func _flame_of(wall: SpellWall) -> Sprite2D:
	if wall == null:
		return null
	for c in wall.get_children():
		if c is Sprite2D and (c as Sprite2D).z_index >= ZONE_Z:
			return c as Sprite2D
	return null


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
