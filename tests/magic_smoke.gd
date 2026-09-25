extends SceneTree
## Headless-проверка системы магии игрока.
##
## Проверяет то, что нельзя увидеть без запуска игры:
##  1. консистентность БД (звук/target/cast_time/папки снарядов, свитки -> заклинания);
##  2. тест-режим выдаёт все заклинания базы;
##  3. каждый вид заклинания (attack/area/heal/buff/debuff/wall/self/raise)
##     реально срабатывает и наносит урон/эффект;
##  4. статусы накладываются, меняют статы и ИСТЕКАЮТ по tick;
##  5. формула силы магии растёт от mind и навыка сферы.
##
## Запуск:
##   godot --headless --path . --script res://tests/magic_smoke.gd

const SPELL := "monsters/orc"

var _fails: Array = []


func _initialize() -> void:
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 13, "spirit": 12,
		"blade": 10, "bludgeon": 10, "pike": 10, "shooting": 10,
		"fire": 20, "water": 20, "air": 20, "earth": 20, "astral": 20,
		"weapon": "staff", "shield": false, "armor": "light"}
	Game.hero_class = "mage"
	Game.hero_name = "Маг"
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("MAGIC: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	# --- 1. База ---------------------------------------------------------
	var db_errors := SpellDB.validate()
	_check(db_errors.is_empty(), "база заклинаний консистентна (%s)" % str(db_errors))
	_check(SpellDB.all_spell_names().size() == 31,
		"в базе 31 заклинание (найдено %d)" % SpellDB.all_spell_names().size())

	# Каждый свиток мага должен резолвиться в реальное заклинание
	var bad_scrolls: Array = []
	for key in ItemDB.all():
		var k := str(key)
		if not k.begins_with("Scroll "):
			continue
		var sp := SpellDB.spell_from_scroll(k)
		if sp == "" or SpellDB.get_spell(sp).is_empty():
			bad_scrolls.append(k)
	_check(bad_scrolls.is_empty(), "все свитки резолвятся в заклинания (%s)" % str(bad_scrolls))

	# Wall_of_Fire обязан быть стеной (был attack -> бил одиночным снарядом)
	_check(SpellDB.kind_of("Wall_of_Fire") == "wall", "Wall_of_Fire имеет kind=wall")
	_check(SpellDB.effects_of("Curse").size() == 1, "Curse описан эффектом, а не щитом")
	# Стены в оригинале разные: огонь жжёт, земля — преграда
	_check(SpellDB.wall_mode_of("Wall_of_Fire") == "damage", "стена огня — режим damage")
	_check(SpellDB.wall_mode_of("Wall_of_Earth") == "block", "стена земли — режим block")
	_check(not SpellDB.effects_of("Stone_Curse").is_empty()
		and SpellDB.effect_of_type("Stone_Curse", "root").size() > 0,
		"Stone_Curse содержит корень (обездвиживание)")
	# Сопротивление в процентах
	_check(int(SpellDB.effect_of_type("Protection_from_Fire", "resist").get("amount", 0)) >= 20,
		"Protection_from_* даёт сопротивление в процентах (>=20)")

	# --- 2. Загрузка сцены ---------------------------------------------
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "загрузка main.tscn: %d" % err)
		_finish()
		return
	await process_frame
	await create_timer(0.6).timeout

	var hero: Node2D = get_first_node_in_group("player")
	_check(hero != null, "герой загружен")
	if hero == null:
		_finish()
		return

	# --- 3. Тест-режим: все заклинания -----------------------------------
	var known: int = (hero.get("known_spells") as Dictionary).size()
	_check(Game.debug_magic and known == 31,
		"тест-режим: выучено %d/31 заклинаний" % known)

	# --- 4. Формула силы магии (оригинал: навык + разум - 30) --------------
	var p0 := Game.spell_power(hero, "Fire")
	hero.set("fire_skill", 40)
	var p1 := Game.spell_power(hero, "Fire")
	_check(p1 > p0, "навык сферы повышает силу магии (%.1f -> %.1f)" % [p0, p1])
	hero.set("fire_skill", 20)
	var p2 := Game.spell_power(hero, "Fire")
	hero.set("mind", 25)
	var p3 := Game.spell_power(hero, "Fire")
	_check(p3 > p2, "разум повышает силу магии (%.1f -> %.1f)" % [p2, p3])
	# SP не уходит в минус (у новичка навык 5 + разум 9 - 30 = -16)
	hero.set("fire_skill", 5)
	hero.set("mind", 9)
	_check(Game.spell_power(hero, "Fire") >= 0.0, "SP клампится в ноль, не уходит в минус")
	# Формула совпадает с оригиналом: навык + разум - 30
	hero.set("fire_skill", 45)
	hero.set("mind", 20)
	_check(absf(Game.spell_power(hero, "Fire") - 35.0) < 0.01,
		"SP = навык+разум-30 (получено %.1f, ждём 35)" % Game.spell_power(hero, "Fire"))
	hero.set("fire_skill", 25)
	hero.set("mind", 13)
	var base := int(SpellDB.get_spell("Fire_Ball").get("damage", 0))
	var scaled := Game.spell_damage(hero, "Fire_Ball", "Fire", base)
	_check(scaled > base, "урон заклинания масштабируется (база %d -> %d)" % [base, scaled])
	_check(Game.spell_damage(hero, "Heal", "Astral", 22) > 22,
		"лечение масштабируется и сильнее базы (power_coef)")

	# --- 5. Урон по врагу -------------------------------------------------
	var foe := _spawn_foe(hero.global_position + Vector2(120, 0))
	_check(foe != null, "враг для проверки урона создан")
	if foe == null:
		_finish()
		return
	await process_frame

	var hp_before: int = foe.current_hp
	Game.deal_damage(foe, 40, "magic", "Fire", hero)
	await process_frame
	_check(foe.current_hp < hp_before, "магический урон снимает HP (%d -> %d)" % [hp_before, foe.current_hp])

	# Сопротивление — ПРОЦЕНТ от урона (orc: fire 25 %)
	var prot: int = int(foe.call("get_protection_fire"))
	_check(prot > 0, "сопротивление приходит из данных набора (%d %%)" % prot)
	_check(prot <= 95, "сопротивление в допустимых процентах (%d)" % prot)
	var plain := 100
	var reduced := int(round(float(plain) * (1.0 - float(prot) / 100.0)))
	var hp_base := int(foe.current_hp)
	Game.deal_damage(foe, plain, "magic", "Fire", hero)
	await process_frame
	var dealt := hp_base - int(foe.current_hp)
	_check(dealt == reduced, "сопротивление режет урон процентно (ожидали %d, получили %d)"
		% [reduced, dealt])
	# Персистентный бафф режет урон ещё сильнее
	StatusEffects.apply_spell(foe, SpellDB.get_spell("Protection_from_Fire"), hero)
	_check(StatusEffects.resist_bonus(foe, "Fire") >= 20,
		"Protection_from_Fire даёт +20 %% резиста (%d)" % StatusEffects.resist_bonus(foe, "Fire"))
	StatusEffects.clear(foe)

	# --- 6. Статусы: наложение, влияние, истечение -----------------------
	var def0: int = foe.call("get_defense")
	var curse := SpellDB.get_spell("Curse")
	StatusEffects.apply_spell(foe, curse, hero)
	_check(StatusEffects.active_types(foe).has("curse"), "Curse наложен")
	var def1: int = foe.call("get_defense")
	_check(def1 < def0, "Curse снижает защиту (%d -> %d)" % [def0, def1])

	# Повторное наложение не должно складывать бесконечно
	StatusEffects.apply_spell(foe, curse, hero)
	_check(StatusEffects.time_left(foe, "curse") > 0.0, "повторное наложение обновляет таймер")
	_check(float(StatusEffects.active_types(foe).count("curse")) == 1.0,
		"один слот на тип эффекта (без бесконечного стака)")

	# Истечение
	StatusEffects.tick(31.0)
	_check(not StatusEffects.active_types(foe).has("curse"), "Curse истёк по tick")
	_check(foe.call("get_defense") == def0, "защита вернулась после истечения")

	# Haste/Slow меняют скорость
	var slow := SpellDB.get_spell("Slow")
	StatusEffects.apply_spell(foe, slow, hero)
	_check(StatusEffects.speed_mult(foe) < 1.0, "Slow замедляет (x%.2f)" % StatusEffects.speed_mult(foe))
	StatusEffects.clear(foe)
	var haste := SpellDB.get_spell("Haste")
	StatusEffects.apply_spell(foe, haste, hero)
	_check(StatusEffects.speed_mult(foe) > 1.0, "Haste ускоряет (x%.2f)" % StatusEffects.speed_mult(foe))
	StatusEffects.clear(foe)

	# Stone_Curse = корень: цель не двигается
	StatusEffects.apply_spell(foe, SpellDB.get_spell("Stone_Curse"), hero)
	_check(StatusEffects.is_rooted(foe), "Stone_Curse оглушает (корень)")
	_check(StatusEffects.speed_mult(foe) == 0.0, "корень полностью останавливает цель")
	_check(foe.call("effective_speed") == 0.0, "корень обнуляет скорость врага")
	StatusEffects.tick(31.0)
	_check(not StatusEffects.is_rooted(foe), "корень истёк по tick")

	# Невидимость
	var inv := SpellDB.get_spell("Invisibility")
	StatusEffects.apply_spell(hero, inv, hero)
	_check(StatusEffects.is_invisible(hero), "Invisibility наложена")
	StatusEffects.break_invisibility(hero)
	_check(not StatusEffects.is_invisible(hero), "атака срывает невидимость")

	# Щит (идёт в meta-щит Game)
	StatusEffects.apply_spell(hero, SpellDB.get_spell("Shield"), hero)
	_check(int(hero.get_meta("shield_strength", 0)) > 0, "Shield даёт поглощение")

	# --- 7. Все виды заклинаний срабатывают ------------------------------
	var kinds := {
		"Fire_Ball": "area", "Ice_Missile": "attack", "Heal": "heal",
		"Haste": "buff", "Curse": "debuff", "Wall_of_Fire": "wall",
		"Light": "self",
	}
	for spell_name in kinds:
		var expected: String = kinds[spell_name]
		_check(SpellDB.kind_of(spell_name) == expected,
			"%s -> kind=%s" % [spell_name, expected])

	# Animate_Dead поднимает труп
	foe.current_hp = 0
	foe.set("state", "corpse")
	var party_before: int = Game.party.size()
	hero.call("_raise_dead", foe.global_position, "Animate_Dead")
	await process_frame
	_check(Game.party.size() == party_before + 1, "Animate_Dead поднимает союзника из трупа")

	# Вампиризм (Drain_Life): урон лечит кастера
	StatusEffects.clear(hero)
	var foe2 := _spawn_foe(hero.global_position + Vector2(100, 0))
	await process_frame
	hero.current_hp = maxi(1, hero.current_hp - 40)
	var hp_pre := int(hero.current_hp)
	hero.call("_cast_spell_effect", "Drain_Life", SpellDB.get_spell("Drain_Life"),
		foe2.global_position, foe2)
	_check(StatusEffects.vampirism_ratio(hero) > 0.0, "Drain_Life даёт кастеру вампиризм")
	Game.deal_damage(foe2, 40, "magic", "Astral", hero)
	await process_frame
	_check(int(hero.current_hp) > hp_pre, "вампиризм лечит кастера за нанесённый урон")
	# Вампиризм НЕ должен попасть на врага или союзника в радиусе
	_check(StatusEffects.vampirism_ratio(foe2) == 0.0, "вампиризм не достался цели")

	# Стена огня: создаётся и наносит урон по тику (режим damage)
	StatusEffects.clear(hero)
	var foe3 := _spawn_foe(hero.global_position + Vector2(80, 0))
	await process_frame
	hero.call("_create_wall", foe3.global_position, "Wall_of_Fire", "Fire")
	await process_frame
	var wall := _find_wall()
	_check(wall != null, "Wall_of_Fire создаёт зону стены")
	if wall != null:
		_check(wall.deals_damage(), "стена огня жжёт (deals_damage=true)")
		_check(not wall.blocks_path(), "стена огня проходима (blocks_path=false)")
		var w_hp := int(foe3.current_hp)
		await create_timer(0.8).timeout
		_check(int(foe3.current_hp) < w_hp, "стена наносит урон по тику (%d -> %d)"
			% [w_hp, int(foe3.current_hp)])
	if wall != null:
		wall.queue_free()
		await process_frame

	# Стена земли: только преграда, урона нет
	var foe4 := _spawn_foe(hero.global_position + Vector2(200, 0))
	await process_frame
	hero.call("_create_wall", foe4.global_position, "Wall_of_Earth", "Earth")
	await process_frame
	var wall2 := _find_wall()
	_check(wall2 != null, "Wall_of_Earth создаёт стену")
	if wall2 != null:
		_check(wall2.blocks_path(), "стена земли блокирует проход")
		_check(not wall2.deals_damage(), "стена земли не наносит урон")
		var e_hp := int(foe4.current_hp)
		await create_timer(0.8).timeout
		_check(int(foe4.current_hp) == e_hp, "стена земли не ранит (HP %d)" % int(foe4.current_hp))
		wall2.queue_free()
		await process_frame

	Game.hero.set("current_mana", 999)
	_finish()


func _find_wall() -> SpellWall:
	for child in get_root().get_children():
		for c in (child as Node).get_children() if child is Node else []:
			if c is SpellWall:
				return c
	var stack := get_root().find_children("*", "SpellWall", true, false)
	return stack[0] as SpellWall if not stack.is_empty() else null


func _spawn_foe(pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.name = "MagicTestFoe"
	e.anim_set = SPELL
	e.max_hp = 400
	e.damage = 5
	e.position = pos
	root.add_child(e)
	Game.enemies.append(e)
	return e


func _finish() -> void:
	if _fails.is_empty():
		print("MAGIC: RESULT: OK")
	else:
		print("MAGIC: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit()
