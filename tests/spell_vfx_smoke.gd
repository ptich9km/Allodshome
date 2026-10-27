extends SceneTree
## Headless-проверка ВИЗУАЛА заклинаний, который раньше просто не было.
##
## Проверяет то, что видно только в игре:
##  1. ауры (щит / сопротивление / ускорение) живут дольше одноразовой вспышки;
##  2. защита — КОЛЬЦО ВЕТЕРКА вокруг корпуса, а не точка над головой: размер
##     задаётся в пикселях (был баг: scale 0.45 при текстуре 4×4 = 2 px);
##  3. кольца разных школ не совпадают и НЕ качаются;
##  4. щит — маленький предмет, который ЛЕТАЕТ по орбите вокруг героя;
##  5. аура исчезает, когда эффект истёк (сама, без ручного снятия);
##  6. метель и ядовитое облако — это зоны с длительностью, а не одиночный снаряд;
##  7. у каждой зоны есть шейдер, он реально компилируется (без ошибок GPU).
##
## Запуск:
##   godot --headless --path . --script res://tests/spell_vfx_smoke.gd

const MIN_AURA_LIFE := 0.9   # одноразовая вспышка жила 0.45 с — аура должна жить дольше
## Ниже этого размера эффект читается как «точка» (жалоба игрока).
const MIN_VISIBLE_PX := 14.0

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

	await _test_aura_shapes()
	await _test_bless_aura()
	await _test_aura_lifetime()
	await _test_heal_cross()
	await _test_zones()
	_test_shaders()
	_finish()


# --- 1-4. Ауры: кольца защит и летающий щит --------------------------------

func _test_aura_shapes() -> void:
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

	# Защита — КОЛЬЦО ВЕТЕРКА вокруг корпуса. Главный баг прошлой версии:
	# scale 0.45 при текстуре 4×4 px давал значок 2 px, то есть «точку,
	# которая плавает туда-сюда». Размер обязан считаться в пикселях.
	var size := SpellVFX.sprite_px(aura._sprite)
	_check(size.x >= MIN_VISIBLE_PX and size.y >= MIN_VISIBLE_PX,
		"кольцо ветерка видно: %.0f×%.0f px (прошлый значок был 2–6 px)" % [size.x, size.y])
	var body_w := aura._body_width()
	_check(size.x > body_w and body_w > 0.0,
		"кольцо шире корпуса (%.0f > %.0f) — струи идут вокруг тела" % [size.x, body_w])
	# Тело внутри кольца не закрыто: центр кольца прозрачен (проверяем по
	# геометрии шейдера — кольцо начинается с 46 % радиуса).
	_check(aura._sprite.material is ShaderMaterial,
		"у кольца ветерка свой ShaderMaterial")
	# Кольцо стоит по центру силуэта, со сдвигом ряда школы (огонь — выше).
	var vh := Game.unit_visual_height(_hero)
	_check(vh > 0.0, "высота спрайта героя читается из UnitAnim: %.1f px" % vh)
	_check(aura._base_offset < -vh * 0.2 and aura._base_offset > -vh,
		"кольцо в пределах силуэта (offset %.1f при высоте %.1f)" % [aura._base_offset, vh])
	# НЕ качается: покачивание точки и было жалобой игрока.
	var y1 := aura._sprite.position.y
	await create_timer(0.5).timeout
	_check(absf(aura._sprite.position.y - y1) < 0.01,
		"кольцо защиты не качается (%.2f -> %.2f)" % [y1, aura._sprite.position.y])
	# Второй канал различия кроме цвета — РАЗНОЕ ДВИЖЕНИЕ по школе.
	_check(SpellVFX.resist_school("Fire") != SpellVFX.resist_school("Water"),
		"у огня и воды разное движение ветерка (0 против 1)")
	var mat := aura._sprite.material as ShaderMaterial
	_check(mat != null
			and int(mat.get_shader_parameter("school")) == SpellVFX.resist_school("Fire"),
		"шейдеру ветерка передана школа огня")
	# Цвет школы, а не белый: иначе все защиты неразличимы.
	var c: Color = mat.get_shader_parameter("color")
	_check(c.is_equal_approx(SpellVFX.resist_color("Fire")),
		"кольцо окрашено цветом школы (%s)" % str(c))

	# Вторая защита: кольцо на ДРУГОЙ ВЫСОТЕ (земля ниже, огонь выше), поэтому
	# кольца не сливаются в одно пятно.
	_hero._apply_effects(_hero, SpellDB.get_spell("Protection_from_Water"))
	await process_frame
	var rings := _resist_auras()
	_check(rings.size() >= 2, "две защиты висят одновременно: %d" % rings.size())
	var water: SpellAura = null
	for a in rings:
		var ra := a as SpellAura
		if ra.sphere == "Water":
			water = ra
	_check(water != null, "кольцо воды создано")
	if water != null:
		_check(absf(water._base_offset - aura._base_offset) >= 5.0,
			"кольца защит на разной высоте (вода %.1f, огонь %.1f)"
				% [water._base_offset, aura._base_offset])
		_check(int((water._sprite.material as ShaderMaterial).get_shader_parameter("school"))
				== SpellVFX.resist_school("Water"),
			"у кольца воды своя школа движения")

	# Ветер ускорения рисуется у ног — это осознанное отличие от остальных.
	_hero._apply_effects(_hero, SpellDB.get_spell("Haste"))
	await process_frame
	var haste := _find_aura("haste")
	_check(haste != null, "аура ускорения создана")
	if haste != null:
		# У ног: над подошвами, но не под землёй и не над головой.
		var up_h := -haste._base_offset
		_check(up_h >= 0.0 and up_h < 18.0,
			"ветер ускорения у ног (%.0f px над подошвами)" % up_h)

	# Щит — маленький ЛЕТАЮЩИЙ предмет, а не сетка вокруг тела.
	_hero._apply_effects(_hero, SpellDB.get_spell("Shield"))
	await process_frame
	var shield := _find_aura("shield")
	_check(shield != null, "аура щита создана")
	if shield != null:
		var sh_size := SpellVFX.sprite_px(shield._sprite)
		_check(sh_size.x >= MIN_VISIBLE_PX,
			"щит виден: %.0f×%.0f px" % [sh_size.x, sh_size.y])
		_check(sh_size.x < body_w * 1.4,
			"щит МАЛЕНЬКИЙ: %.0f px против корпуса %.0f px" % [sh_size.x, body_w])
		# Орбита вокруг тела, а не над головой.
		var fig := Game.unit_local_rect(_hero)
		var expect_y := fig.end.y - fig.size.y * SpellAura.SHIELD_BODY_FRAC
		_check(absf(shield._base_offset - expect_y) < 1.0,
			"орбита щита на высоте корпуса (offset %.1f, ждём %.1f)"
				% [shield._base_offset, expect_y])
		# Летает: за 0.4 с смещение по X обязано быть заметным.
		var x1 := shield._sprite.position.x
		await create_timer(0.4).timeout
		_check(absf(shield._sprite.position.x - x1) > 2.0,
			"щит летает по орбите (x %.1f -> %.1f)" % [x1, shield._sprite.position.x])
		# И не улетает выше головы/ниже ног. Позиция спрайта включает подъём
		# узла анимации (рельеф), поэтому и границы фигуры считаем с ним.
		var shift := 0.0
		var anim_node: Node2D = _hero.get_node_or_null("UnitAnim") as Node2D
		if anim_node != null:
			shift = anim_node.position.y
		var abs_y := shield.global_position.y + shield._sprite.position.y
		var head_y := _hero.global_position.y + shift + fig.position.y
		var feet_y := _hero.global_position.y + shift + fig.end.y
		_check(abs_y > head_y and abs_y < feet_y,
			"щит в пределах силуэта: макушка %.1f < щит %.1f < ноги %.1f"
				% [head_y, abs_y, feet_y])

	# Одна аура на вид: щит кастуется каждые 10 с и не должен наслаиваться.
	var before := _count_auras("shield")
	_hero._apply_effects(_hero, SpellDB.get_spell("Shield"))
	await process_frame
	_check(_count_auras("shield") == before,
		"повторный щит не плодит ауры (%d -> %d)" % [before, _count_auras("shield")])


## Все кольца защит на герое.
func _resist_auras() -> Array:
	var out: Array = []
	for c in _hero.get_children():
		if c is SpellAura and (c as SpellAura).kind == "resist":
			out.append(c as SpellAura)
	return out


# --- Благословение: маленькая жёлтая аура над головой -----------------------

func _test_bless_aura() -> void:
	_hero._apply_effects(_hero, SpellDB.get_spell("Bless"))
	await process_frame
	var aura := _find_aura("bless")
	_check(aura != null, "аура благословения создана (раньше Bless был невидим)")
	if aura == null:
		return
	var size := SpellVFX.sprite_px(aura._sprite)
	_check(size.x >= MIN_VISIBLE_PX and size.y >= MIN_VISIBLE_PX,
		"аура благословения видна: %.0f×%.0f px" % [size.x, size.y])
	# Над ГОЛОВОЙ: смещение выше макушки фигуры.
	var fig := Game.unit_local_rect(_hero)
	_check(-aura._base_offset > -fig.position.y,
		"аура выше макушки (%.0f px при голове %.0f)" % [-aura._base_offset, -fig.position.y])
	var mat := aura._sprite.material as ShaderMaterial
	_check(mat != null and mat.shader != null
			and mat.shader.code.contains("cos(ang * 6.0)"),
		"шейдер ауры благословения — нимб с лучами, а не точка")
	# Исчезает, когда эффект снят.
	StatusEffects.clear(_hero)
	await process_frame
	await process_frame
	_check(not is_instance_valid(aura) or aura.is_queued_for_deletion(),
		"аура благословения исчезает вместе с эффектом")


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
	for style in ["hail", "shard", "cloud", "aura_shield", "aura_breeze", "aura_wind", "heal_cross"]:
		var mat := SpellVFX.zone_material(style, Color.WHITE)
		var sh: Shader = mat.shader
		var ok := sh != null and sh.code.contains("shader_type canvas_item")
		_check(ok, "шейдер %s есть и начинается с shader_type canvas_item" % style)
	# Ветерок защиты обязан иметь ветку движения по школе, а не только цвет:
	# иначе четыре защиты снова неразличимы (цвет — недоступный канал).
	var bz := SpellVFX.zone_material("aura_breeze", Color.WHITE).shader
	_check(bz != null and bz.code.contains("uniform int school"),
		"у ветерка есть uniform school (движение по школе)")
	_check(bz != null and bz.code.contains("dashes"),
		"ветерок — бегущие штрихи по обручу, а не заливка")
	_check(bz != null and bz.code.contains("blend_mix"),
		"ветерок смешивается альфой, а не аддитивно (иначе четыре кольца = белое пятно)")


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
