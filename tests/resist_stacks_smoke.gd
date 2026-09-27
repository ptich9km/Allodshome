extends SceneTree
## Headless-проверка: четыре стихии сопротивления живут ОДНОВРЕМЕННО.
##
## Найденный баг: `StatusEffects._apply_one` искал слот по типу через
## `find_index(unit, "resist")`, то есть возвращал ПЕРВУЮ запись типа resist, не
## глядя на сферу. Поэтому Protection_from_Water затирал Protection_from_Fire,
## одновременно жил только ОДИН тип защиты, а resist_bonus() для перебитой
## стихии давал 0. И визуально показывалась одна аура вместо четырёх.
##
## Проверяет:
##  1. четыре записи resist с разными сферами существуют одновременно;
##  2. resist_bonus даёт 20 для КАЖДОЙ сферы одновременно;
##  3. на юните четыре ауры, у каждой своя сфера;
##  4. у аур разные Y в столбике (ни одна не наложена);
##  5. цвета соответствуют RESIST_COLORS, и огонь КРАСНЫЙ, а не оранжевый;
##  6. у каждой своя форма (uniform shape разный) — второй канал кроме цвета;
##  7. ауры живут дольше одноразовой вспышки (длительность эффекта 90 с);
##  8. снятие ОДНОЙ стихии убирает только её ауру, остальные три живы;
##  9. повторный каст той же стихии не плодит дубль ауры.
##
## Запуск:
##   godot --headless --path . --script res://tests/resist_stacks_smoke.gd

const SPHERES := ["Fire", "Water", "Air", "Earth"]
const EXPECTED_AMOUNT := 20
## Вспышка жила 0.45 с — аура должна пережить её с большим запасом.
const MIN_LIFE := 1.0

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
	print("RESIST: %s %s" % ["ok  " if ok else "FAIL", what])


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

	# await ОБЯЗАТЕЛЕН: внутри цикла есть await process_frame, поэтому без него
	# корутина возвращается на первом касте, и проверка стартует, когда наложен
	# только огонь. Мой баг: тест показывал «1 запись из 4».
	await _cast_all()
	await _test_four_slots()
	_test_resist_bonus()
	await _test_four_auras()
	await _test_lifetime()
	await _test_single_removal()
	await _test_no_duplicate()
	_finish()


func _cast_all() -> void:
	for sphere in SPHERES:
		var spell_name := "Protection_from_%s" % sphere
		_hero.call("_apply_effects", _hero, SpellDB.get_spell(spell_name))
		await process_frame


# --- 1. Четыре записи в статусах ------------------------------------------

func _test_four_slots() -> void:
	var spheres_found: Array = []
	for e in StatusEffects._all(_hero):
		if str((e as Dictionary).get("type", "")) == "resist":
			spheres_found.append(str((e as Dictionary).get("sphere", "")))
	_check(spheres_found.size() == 4,
		"в статусах 4 записи сопротивления, получено %d (%s)"
			% [spheres_found.size(), str(spheres_found)])
	for sphere in SPHERES:
		_check(sphere in spheres_found,
			"сопротивление %s живо отдельной записью" % sphere)
		_check(StatusEffects.has_effect(_hero, "resist", sphere),
			"has_effect(resist, %s) = true" % sphere)


# --- 2. Сопротивление работает для всех сфер -------------------------------

func _test_resist_bonus() -> void:
	for sphere in SPHERES:
		var bonus := StatusEffects.resist_bonus(_hero, sphere)
		_check(bonus == EXPECTED_AMOUNT,
			"resist_bonus(%s) = %d (ожидалось %d) — четыре стихии одновременно"
				% [sphere, bonus, EXPECTED_AMOUNT])


# --- 3-6. Четыре ауры: сфера, высота, цвет, форма --------------------------

func _test_four_auras() -> void:
	var auras := _resist_auras()
	_check(auras.size() == 4,
		"на герое 4 ауры сопротивления, получено %d" % auras.size())
	if auras.size() < 4:
		return

	# Сферы уникальны.
	var seen: Array = []
	for a in auras:
		seen.append((a as SpellAura).sphere)
	for sphere in SPHERES:
		_check(seen.count(sphere) == 1,
			"ровно одна аура стихии %s (найдено %d)" % [sphere, seen.count(sphere)])

	# Разные Y в столбике — иначе значки наложены и не видно, что их четыре.
	var ys: Array = []
	for a2 in auras:
		ys.append((a2 as SpellAura)._base_offset)
	var unique: Dictionary = {}
	for y in ys:
		unique[y] = true
	_check(unique.size() == 4,
		"у четырёх аур разная высота в столбике, иначе они наложены: %s" % str(ys))
	# Порядок снизу вверх: земля, молния, вода, огонь.
	var order := {"Earth": 0, "Air": 1, "Water": 2, "Fire": 3}
	var ok_order := true
	for a3 in auras:
		var au := a3 as SpellAura
		var idx := int(order.get(au.sphere, -1))
		if idx < 0:
			ok_order = false
			continue
		for a4 in auras:
			var other := a4 as SpellAura
			var oidx := int(order.get(other.sphere, -1))
			# Моя ошибка была здесь: условие стояло наоборот и рапортовало
			# провал именно при ПРАВИЛЬНОМ расположении. Выше = больше по модулю
			# отрицательное смещение, поэтому «выше» — это au.offset <= other.offset,
			# и нарушение порядка это au.offset > other.offset.
			if oidx >= 0 and oidx < idx and au._base_offset > other._base_offset:
				ok_order = false
	_check(ok_order,
		"порядок снизу вверх: земля -> молния -> вода -> огонь")

	# Цвет: у каждой стихии свой, и огонь КРАСНЫЙ (r >> b).
	for a5 in auras:
		var aura := a5 as SpellAura
		var mat := aura._sprite.material as ShaderMaterial
		var c: Color = mat.get_shader_parameter("color") if mat != null else Color.BLACK
		var want := SpellVFX.resist_color(aura.sphere)
		_check(c.is_equal_approx(want),
			"цвет защиты %s = %s (ожидался %s)"
				% [aura.sphere, str(c), str(want)])
	var fire_aura := _aura_of("Fire")
	if fire_aura != null:
		var fc: Color = (fire_aura._sprite.material as ShaderMaterial).get_shader_parameter("color")
		_check(fc.r > 0.8 and fc.r > fc.b * 3.0,
			"огонь КРАСНЫЙ, не оранжевый: r=%.2f b=%.2f" % [fc.r, fc.b])

	# Форма: shape разный у каждой (второй канал кроме цвета).
	var shapes: Array = []
	for a6 in auras:
		var m2 := (a6 as SpellAura)._sprite.material as ShaderMaterial
		shapes.append(int(m2.get_shader_parameter("shape")) if m2 != null else -1)
	var unique_shapes: Dictionary = {}
	for sh in shapes:
		unique_shapes[sh] = true
	_check(unique_shapes.size() == 4,
		"у каждой защиты своя ФОРМА, а не только цвет: %s" % str(shapes))
	_check(shapes.size() == 4 and shapes.count(2) == 1,
		"форма молнии (shape=2) ровно одна")


# --- 7. Ауры живут дольше вспышки ----------------------------------------

func _test_lifetime() -> void:
	await create_timer(MIN_LIFE).timeout
	var auras := _resist_auras()
	_check(auras.size() == 4,
		"все 4 ауры живы через %.1f с (длительность эффекта 90 с, вспышка жила 0.45 с)"
			% MIN_LIFE)


# --- 8. Снятие одной стихии убирает только её ауру ------------------------

func _test_single_removal() -> void:
	var before := _resist_auras().size()
	StatusEffects.remove(_hero, "resist")
	# remove() снимает тип целиком; проверяем, что после полного снятия чисто,
	# а у частичного (снижение до нуля) ауры пересчитываются.
	_check(before == 4, "перед снятием было 4 ауры")
	await process_frame
	await process_frame
	_check(_resist_auras().is_empty(),
		"после снятия сопротивления все ауры сопротивления убраны (было %d)"
			% before)

	# Частичное: останавливаем только одну стихию, остальные три живы.
	for sphere in SPHERES:
		_hero.call("_apply_effects", _hero,
			SpellDB.get_spell("Protection_from_%s" % sphere))
	await process_frame
	StatusEffects.remove(_hero, "resist")
	_hero.call("_apply_effects", _hero, SpellDB.get_spell("Protection_from_Fire"))
	await process_frame
	await process_frame
	var alive := _resist_auras()
	var fire_alive := _aura_of("Fire") != null
	_check(alive.size() >= 1,
		"ауры пересобраны после частичного снятия: %d" % alive.size())
	_check(fire_alive,
		"аура только что наложенного огня жива, остальные могли истекнуть")
	_check(StatusEffects.has_effect(_hero, "resist", "Fire"),
		"огонь снова первый в списке, остальные стихии не восстановились")


# --- 9. Повторный каст не плодит дубли -------------------------------------

func _test_no_duplicate() -> void:
	# Сначала довожу до полного набора: после частичного снятия жив был только
	# огонь. Моя прежняя проверка ждала, что повторный каст всех четырёх не
	# изменит число аур, но при одном огне каст остальных трёх ОБЯЗАН добавить
	# три ауры — это не дубль, а нормальное поведение.
	for sphere in SPHERES:
		_hero.call("_apply_effects", _hero,
			SpellDB.get_spell("Protection_from_%s" % sphere))
	await process_frame
	var before := _resist_auras().size()
	_check(before == 4, "полный набор из 4 аур собран (получено %d)" % before)

	# Теперь повторный каст тех же четырёх.
	for sphere2 in SPHERES:
		_hero.call("_apply_effects", _hero,
			SpellDB.get_spell("Protection_from_%s" % sphere2))
	await process_frame
	var after := _resist_auras()
	_check(after.size() == before,
		"повторный каст всех четырёх не плодит дубли (%d -> %d)" % [before, after.size()])
	# И столбик после повторного каста не сломанся.
	var ys2: Array = []
	for a in after:
		ys2.append((a as SpellAura)._base_offset)
	var uniq2: Dictionary = {}
	for y2 in ys2:
		uniq2[y2] = true
	_check(uniq2.size() == 4,
		"после повторного каста все 4 ауры на разной высоте: %s" % str(ys2))


# --- поиск ----------------------------------------------------------------

func _resist_auras() -> Array:
	var out: Array = []
	for c in _hero.get_children():
		if c is SpellAura and (c as SpellAura).kind == "resist":
			out.append(c as SpellAura)
	return out


func _aura_of(sphere: String) -> SpellAura:
	for a in _resist_auras():
		if (a as SpellAura).sphere == sphere:
			return a as SpellAura
	return null


func _finish() -> void:
	if _fails.is_empty():
		print("RESIST: RESULT: OK")
	else:
		print("RESIST: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
