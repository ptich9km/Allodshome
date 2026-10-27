extends SceneTree
## Headless-проверка ТАКТИЧЕСКОЙ ПАУЗЫ для магии.
##
## Причина бага: корень сцены (`Main`, `game.gd`) ставит себе
## PROCESS_MODE_ALWAYS, и ВСЕ дети наследовали это через INHERIT. Поэтому
## `get_tree().paused = true` останавливал только тех, кто проверял
## `Game.is_paused` вручную (герой, враг, НПЦ, наёмник). У магии таких
## проверок не было:
##   * зона продолжала жить, тикать урон и считать время шейдера;
##   * снаряд долетал и наносил урон;
##   * аура продолжала следить и покачиваться;
##   * твины вспышек/телеграфов/света играли (BOUND к Always-узлу);
##   * `Game._input` на паузе запускал прицеливание и каст.
##
## Проверяет:
##  1. зона паузабельна: жизнь, время шейдера и накопитель тика стоят;
##  2. снаряд паузабелен: не двигается на паузе, летит после;
##  3. аура паузабельна и не покачивается на паузе;
##  4. `cast_spell` на паузе отказывает, мана и кулдаун не тратятся;
##  5. хоткей 1..9 на паузе НЕ входит в прицеливание;
##  6. твин эффекта (`SpellVFX.world_tween`) замирает на паузе;
##  7. Space на паузе её снимает (управление не заблокировано целиком).
##
## Запуск:
##   godot --headless --path . --script res://tests/magic_pause_smoke.gd

var _fails: Array = []
var _hero: Player = null
var _game: Node = null


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
	print("MAGICPAUSE: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "загрузка main.tscn: %d" % err)
		_finish()
		return
	await process_frame
	await create_timer(0.6).timeout
	_hero = get_first_node_in_group("player") as Player
	_game = current_scene
	_check(_hero != null, "герой загружен со сцены")
	if _hero == null:
		_finish()
		return
	_hero.known_spells["Fire_Ball"] = {"charges": -1}
	_clear_hostiles()

	await _test_zone()
	await _test_projectile()
	await _test_aura()
	await _test_tween_stop()
	_test_input_blocked()
	_test_particles()

	_finish()


## Убрать чужих с карты: тест про паузу, а не про бой. Живые враги бьют
## героя и пишут в лог, мешая читать результат.
func _clear_hostiles() -> void:
	for arr in [Game.enemies, Game.npcs, Game.party]:
		for u in arr.duplicate():
			arr.erase(u)
			if is_instance_valid(u) and u is Node:
				(u as Node).queue_free()
	_check(true, "карта очищена от чужих")


func _set_pause(on: bool) -> void:
	Game.is_paused = on
	paused = on


# --- 1. Зона ---------------------------------------------------------------

func _test_zone() -> void:
	var zone := SpellVFX.spawn_zone(_hero.global_position + Vector2(140, 0),
		"cloud", "Water", _hero, 5.0, Vector2i(3, 3), 10, 0.5)
	_check(zone != null, "зона создана")
	if zone == null:
		return
	await process_frame
	_check(zone.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"зона паузабельна (process_mode = PAUSABLE)")
	# Переживаем телеграф, чтобы зона была в активной фазе.
	await create_timer(0.7).timeout
	var life_before := zone.life_left
	var elapsed_before := zone._elapsed
	var accum_before := zone._tick_accum

	_set_pause(true)
	await create_timer(0.6, true).timeout
	_check(is_equal_approx(zone.life_left, life_before),
		"жизнь зоны не идёт на паузе (%.2f -> %.2f)" % [life_before, zone.life_left])
	_check(is_equal_approx(zone._elapsed, elapsed_before),
		"время шейдера зоны не идёт на паузе")
	_check(is_equal_approx(zone._tick_accum, accum_before),
		"тик урона не копится на паузе")

	_set_pause(false)
	await create_timer(0.3).timeout
	_check(zone.life_left < life_before, "после паузы жизнь зоны продолжается")
	_check(zone._elapsed > elapsed_before, "после паузы время шейдера продолжается")
	zone.queue_free()


# --- 2. Снаряд -------------------------------------------------------------

func _test_projectile() -> void:
	_hero.create_spell_projectile("Fire_Ball", _hero.global_position + Vector2(0, 80),
		_hero.global_position + Vector2(600, 80), 5, 0.0)
	await process_frame
	var proj := _find_projectile()
	_check(proj != null, "снаряд создан")
	if proj == null:
		return
	_check(proj.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"снаряд паузабелен (process_mode = PAUSABLE)")
	var pos_before := proj.global_position
	_set_pause(true)
	await create_timer(0.5, true).timeout
	var moved := proj != null and is_instance_valid(proj) \
		and proj.global_position.distance_to(pos_before) > 0.01
	_check(not moved, "снаряд не летит на паузе")
	_set_pause(false)
	await create_timer(0.25).timeout
	var resumed := proj == null or not is_instance_valid(proj) \
		or proj.global_position.distance_to(pos_before) > 1.0
	_check(resumed, "после паузы снаряд снова летит")
	if is_instance_valid(proj):
		proj.queue_free()


# --- 3. Аура ---------------------------------------------------------------

func _test_aura() -> void:
	StatusEffects.apply_spell(_hero, SpellDB.get_spell("Protection_from_Fire"), _hero)
	var aura := SpellAura.attach(_hero, "resist", "Fire", "resist")
	await process_frame
	_check(aura != null, "аура защиты создана")
	if aura == null:
		return
	_check(aura.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"аура паузабельна (process_mode = PAUSABLE)")
	# Дать покачиванию уйти с нуля, иначе проверка «не двигается» проходит
	# на неподвижной точке и ничего не доказывает.
	await create_timer(0.4).timeout
	var y_before := aura._sprite.position.y
	_set_pause(true)
	await create_timer(0.5, true).timeout
	_check(absf(aura._sprite.position.y - y_before) < 0.01,
		"аура не покачивается на паузе (%.2f -> %.2f)" % [y_before, aura._sprite.position.y])
	_set_pause(false)


# --- 4-5. Ввод и каст ------------------------------------------------------

func _test_input_blocked() -> void:
	_set_pause(true)
	# Хоткей 1..9 на паузе не должен входить в прицеливание.
	Game.hotbar[0] = {"kind": "spell", "name": "Fire_Ball"}
	Game.pending_spell = {}
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	_game._input(key)
	_check(Game.pending_spell.is_empty(), "хоткей на паузе не входит в прицеливание")

	# Прямой вызов каста (свиток, авто-каст) тоже отказывает.
	var mana_before := _hero.current_mana
	var ok: bool = _hero.cast_spell("Fire_Ball", _hero.global_position + Vector2(60, 0), null)
	_check(not ok, "cast_spell на паузе отказывает")
	_check(_hero.current_mana == mana_before, "мана на паузе не тратится")
	_check(float(_hero.cast_cooldowns.get("Fire_Ball", 0.0)) == 0.0,
		"кулдаун на паузе не запускается")

	# Space обязан снимать паузу даже в этом режиме.
	var sp := InputEventKey.new()
	sp.keycode = KEY_SPACE
	sp.pressed = true
	_game._input(sp)
	_check(not Game.is_paused and not paused, "Space на паузе снимает её")


# --- 6. Твин эффекта -------------------------------------------------------

func _test_tween_stop() -> void:
	var holder := Node2D.new()
	holder.modulate.a = 1.0
	current_scene.add_child(holder)
	var tw := SpellVFX.world_tween(current_scene)
	tw.tween_property(holder, "modulate:a", 0.0, 1.0)
	await process_frame
	await process_frame
	var a_before := holder.modulate.a
	_set_pause(true)
	await create_timer(0.4, true).timeout
	_check(absf(holder.modulate.a - a_before) < 0.001,
		"твин эффекта замирает на паузе (%.2f -> %.2f)" % [a_before, holder.modulate.a])
	_set_pause(false)
	await create_timer(0.2).timeout
	_check(holder.modulate.a < a_before, "после паузы твин продолжается")
	holder.queue_free()


# --- 7. Частицы ------------------------------------------------------------

## GPUParticles2D симулируются движком, а не _process: они наследовали Always
## от корня сцены и продолжали летать на паузе.
func _test_particles() -> void:
	var p := SpellParticles.impact_sparks(current_scene, _hero.global_position, Color.WHITE)
	_check(p != null, "частицы попадания созданы")
	if p != null:
		_check(p.process_mode == Node.PROCESS_MODE_PAUSABLE,
			"частицы паузабельны (process_mode = PAUSABLE)")


# --- поиск -----------------------------------------------------------------

func _find_projectile() -> Projectile:
	for c in current_scene.get_children():
		if c is Projectile:
			return c as Projectile
	return null


func _finish() -> void:
	_set_pause(false)
	if _fails.is_empty():
		print("MAGICPAUSE: RESULT: OK")
	else:
		print("MAGICPAUSE: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
