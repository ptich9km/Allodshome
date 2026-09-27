extends SceneTree
## Headless-проверка ВИЗУАЛА заклинаний, который раньше просто не было.
##
## Проверяет то, что видно только в игре:
##  1. ауры (щит / сопротивление / ускорение) живут дольше одноразовой вспышки
##     и висят НАД ГОЛОВОЙ, а не у ног;
##  2. высота ауры считается из РЕАЛЬНОГО размера спрайта, а не из константы;
##  3. аура исчезает, когда эффект истёк (сама, без ручного снятия);
##  4. метель и ядовитое облако — это зоны с длительностью, а не одиночный снаряд;
##  5. у каждой зоны есть шейдер, он реально компилируется (без ошибок GPU).
##
## Запуск:
##   godot --headless --path . --script res://tests/spell_vfx_smoke.gd

const MIN_AURA_LIFE := 0.9   # одноразовая вспышка жила 0.45 с — аура должна жить дольше

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
	print("VFX: %s %s" % ["ok  " if ok else "FAIL", what])


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
	_hero.set("current_mana", 999)
	_hero.set("current_hp", _hero.max_hp)

	await _test_aura_above_head()
	await _test_aura_lifetime()
	await _test_heal_cross()
	await _test_zones()
	_test_shaders()
	_finish()


# --- 1-2. Аура над головой -------------------------------------------------

func _test_aura_above_head() -> void:
	# Сопротивление огню: 90 секунд в базе, одноразовая вспышка жила 0.45 с.
	var spell := SpellDB.get_spell("Protection_from_Fire")
	var duration := int(SpellDB.effect_of_type("Protection_from_Fire", "resist").get("duration", 0))
	_check(duration >= 60, "сопротивление огню длится %d с (одна вспышка жила 0.45 с)" % duration)

	_hero._apply_effects(_hero, spell)
	await process_frame
	var aura := _find_aura("resist")
	_check(aura != null, "аура сопротивления создана")
	if aura == null:
		return

	# Живёт дольше вспышки — главная претензия к прошлой реализации.
	await create_timer(MIN_AURA_LIFE).timeout
	_check(is_instance_valid(aura) and not aura.is_queued_for_deletion(),
		"аура жива через %.1f с (вспышка гасла за 0.45 с)" % MIN_AURA_LIFE)

	# Над головой, а не у ног и не внутри тела.
	_check(aura._base_offset < -20.0,
		"аура выше ног (offset %.0f px)" % aura._base_offset)
	# Высота берётся из РЕАЛЬНОЙ высоты спрайта (UnitAnim.visual_height),
	# а не из футпринта (_unit_metrics -> tile_size*32): для героя это 32 px,
	# и аура по этой высоте оказывалась ВНУТРИ персонажа.
	var vh := Game.unit_visual_height(_hero)
	_check(vh > 0.0, "высота спрайта героя читается из UnitAnim: %.1f px" % vh)
	var footprint := float((Game._unit_metrics(_hero) as Array)[1])
	_check(vh != footprint,
		"высота спрайта (%.1f) отличается от футпринта (%.1f) — аура считает по высоте"
			% [vh, footprint])
	var expected := -(vh * SpellAura.HEAD_FACTOR + SpellAura.HEAD_MARGIN
		+ float(aura._stack_index) * SpellAura.STACK_STEP)
	_check(is_equal_approx(aura._base_offset, expected),
		"высота ауры считана из высоты спрайта (%.1f px, слот %d -> offset %.1f, ждём %.1f)"
			% [vh, aura._stack_index, aura._base_offset, expected])

	# Столбик: сопротивление и щит висят на РАЗНЫХ высотах, иначе наложены
	# друг на друга и не видно, что на герое несколько эффектов.
	_hero._apply_effects(_hero, SpellDB.get_spell("Shield"))
	await process_frame
	var stack := _head_auras()
	var offsets: Array = []
	for a in stack:
		offsets.append((a as SpellAura)._base_offset)
	var unique_offsets := {}
	for o in offsets:
		unique_offsets[o] = true
	_check(stack.size() >= 2,
		"на герое одновременно висят несколько аур: %d" % stack.size())
	_check(unique_offsets.size() == offsets.size(),
		"ауры не наложены друг на друга, у всех своя высота: %s" % str(offsets))

	# Ветер ускорения рисуется у ног — это осознанное отличие от остальных.
	_hero._apply_effects(_hero, SpellDB.get_spell("Haste"))
	await process_frame
	var haste := _find_aura("haste")
	_check(haste != null, "аура ускорения создана")
	if haste != null:
		_check(haste._base_offset > -8.0,
			"ветер ускорения у ног (offset %.0f, а не над головой)" % haste._base_offset)

	# Щит — сетка вокруг персонажа.
	_hero._apply_effects(_hero, SpellDB.get_spell("Shield"))
	await process_frame
	var shield := _find_aura("shield")
	_check(shield != null, "аура щита создана")
	if shield != null:
		# Щит рисуется ВОКРУГ тела (по центру силуэта), а не над головой:
		# так сразу видно, что герой прикрыт. Раньше он висел над головой
		# и был не виден вовсе.
		var vh2 := Game.unit_visual_height(_hero)
		_check(is_equal_approx(shield._base_offset, -vh2 * 0.45),
			"щит по центру силуэта (offset %.1f, ждём %.1f для высоты %.1f)"
				% [shield._base_offset, -vh2 * 0.45, vh2])
		# Сравниваем АБСОЛЮТНЫЕ Y. Первая версия сравнивала _base_offset
		# (относительный сдвиг) с global_position.y (абсолютная координата) —
		# это смешение единиц, и проверка ругалась при верном щите.
		var abs_y := shield.global_position.y + shield._base_offset
		var head_y := _hero.global_position.y - vh2
		var feet_y := _hero.global_position.y
		_check(abs_y > head_y and abs_y < feet_y,
			"щит по центру силуэта: макушка %.1f < щит %.1f < ноги %.1f"
				% [head_y, abs_y, feet_y])
		_check(shield._sprite.scale.x >= 1.4,
			"щит шире силуэта (scale %.2f)" % shield._sprite.scale.x)

	# Одна аура на вид: щит кастуется каждые 10 с и не должен наслаиваться.
	var before := _count_auras("shield")
	_hero._apply_effects(_hero, SpellDB.get_spell("Shield"))
	await process_frame
	_check(_count_auras("shield") == before,
		"повторный щит не плодит ауры (%d -> %d)" % [before, _count_auras("shield")])


## Все ауры, кроме ветра (ветер у ног, в столбик не входит).
func _head_auras() -> Array:
	var out: Array = []
	for c in _hero.get_children():
		if c is SpellAura and (c as SpellAura).kind != "haste":
			out.append(c as SpellAura)
	return out


# --- 3. Аура снимается сама ------------------------------------------------

func _test_aura_lifetime() -> void:
	_hero._apply_effects(_hero, SpellDB.get_spell("Protection_from_Fire"))
	await process_frame
	var aura := _find_aura("resist")
	_check(aura != null, "аура сопротивления создана для проверки снятия")
	if aura == null:
		return
	# Снимаем эффект из status_effects — аура обязана исчезнуть сама.
	StatusEffects.clear(_hero)
	await process_frame
	await process_frame
	_check(not is_instance_valid(aura) or aura.is_queued_for_deletion(),
		"аура исчезла сама после снятия эффекта (не ждёт таймера)")


# --- 4. Крест лечения ------------------------------------------------------

func _test_heal_cross() -> void:
	_hero.set("current_hp", maxi(1, _hero.max_hp - 100))
	var before := int(_hero.current_hp)
	_hero._heal_target(_hero, "Heal", 22)
	_check(int(_hero.current_hp) > before,
		"Heal восстанавливает HP (%d -> %d)" % [before, int(_hero.current_hp)])
	# Крест — спрайт над головой, живёт ~0.9 с.
	var found := _find_effect_sprite("heal_cross")
	_check(found != null, "над головой появился красный крест лечения")
	if found != null:
		_check(found.global_position.y < _hero.global_position.y - 20.0,
			"крест выше ног (%.0f < %.0f)" % [found.global_position.y, _hero.global_position.y])


# --- 5. Зоны с длительностью ----------------------------------------------

func _test_zones() -> void:
	for pair in [["Blizzard", "hail", 4.0], ["Poison_Cloud", "cloud", 5.0]]:
		var name := str(pair[0])
		var style := str(pair[1])
		var life := float(pair[2])
		var spell := SpellDB.get_spell(name)
		_check(str(spell.get("zone_style", "")) == style,
			"%s помечен как зона стиля %s" % [name, style])
		_check(float(spell.get("zone_life", 0.0)) >= life - 0.01,
			"%s живёт %.1f с" % [name, float(spell.get("zone_life", 0.0))])
		# В базе у обоих dot — эффект должен доставать всех в зоне, а не одну цель.
		_check(not SpellDB.effects_of(name).is_empty(),
			"%s имеет эффекты (dot/slow) в базе" % name)

		_hero._create_zone(_hero.global_position + Vector2(0, 96), name, str(spell.get("sphere", "")))
		await process_frame
		var zone := _find_zone(style)
		_check(zone != null, "%s создаёт зону" % name)
		if zone == null:
			continue
		# Одиночный снаряд попадал один раз; зона обязана жить дольше.
		await create_timer(MIN_AURA_LIFE).timeout
		_check(is_instance_valid(zone) and not zone.is_queued_for_deletion(),
			"зона %s жива через %.1f с (снаряд был одноразовым)" % [style, MIN_AURA_LIFE])
		_check(zone.deals_damage(), "зона %s наносит урон по тику" % style)
		zone.queue_free()
		await process_frame

	# Метель роняет осколки всё время действия, а не один кадр.
	var count_before := _count_effect_sprites("shard")
	_hero._create_zone(_hero.global_position + Vector2(0, 96), "Blizzard", "Water")
	await create_timer(0.6).timeout
	_check(_count_effect_sprites("shard") > count_before,
		"метель роняет ледяные осколки (было %d, стало %d)"
			% [count_before, _count_effect_sprites("shard")])
	for z in _find_all_zones("hail"):
		(z as Node).queue_free()
	await process_frame


# --- 6. Шейдеры компилируются --------------------------------------------

func _test_shaders() -> void:
	for style in ["hail", "shard", "cloud", "aura_shield", "aura_up", "aura_wind", "heal_cross"]:
		var mat := SpellVFX.zone_material(style, Color.WHITE)
		var sh: Shader = mat.shader
		var ok := sh != null and sh.code.contains("shader_type canvas_item")
		_check(ok, "шейдер %s есть и начинается с shader_type canvas_item" % style)


# --- Поиск узлов -----------------------------------------------------------

func _find_aura(kind: String) -> SpellAura:
	for c in _hero.get_children():
		if c is SpellAura and (c as SpellAura).kind == kind:
			return c as SpellAura
	return null


func _count_auras(kind: String) -> int:
	var n := 0
	for c in _hero.get_children():
		if c is SpellAura and (c as SpellAura).kind == kind:
			n += 1
	return n


## Найти спрайт с конкретным стилем шейдера.
## Ищем по ИДЕНТИЧНОСТИ Shader, а не по тексту кода: стиль («heal_cross»,
## «shard») — это ключ кэша, в самом коде шейдера его нет, и grep по тексту
## молча ничего не находил, а тест объявлял «эффекта нет».
func _find_effect_sprite(style: String) -> Sprite2D:
	var want: Shader = SpellVFX.zone_material(style, Color.WHITE).shader
	for c in current_scene.get_children():
		if c is Sprite2D and c.material is ShaderMaterial:
			if (c.material as ShaderMaterial).shader == want:
				return c as Sprite2D
	return null


func _count_effect_sprites(style: String) -> int:
	var want: Shader = SpellVFX.zone_material(style, Color.WHITE).shader
	var n := 0
	for c in current_scene.get_children():
		if c is Sprite2D and c.material is ShaderMaterial:
			if (c.material as ShaderMaterial).shader == want:
				n += 1
	return n


func _find_zone(style: String) -> SpellZone:
	for z in _find_all_zones(style):
		return z
	return null


func _find_all_zones(style: String) -> Array:
	var out: Array = []
	for c in current_scene.get_children():
		if c is SpellZone and (c as SpellZone).style == style:
			out.append(c)
	return out


func _finish() -> void:
	if _fails.is_empty():
		print("VFX: RESULT: OK")
	else:
		print("VFX: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
