extends SceneTree
##
## Смок тумана войны (19.10): маска, reveal-диск, RLE, сокрытие юнитов,
## конфиг + интеграция в сцене (Game.fog, текстура слоя, mini_img).
## Запуск: godot --headless --path . --script res://tests/fog_of_war_smoke.gd
## Результат: RESULT: OK fog_of_war_smoke
##
## Регресс: 19.10 были найдены два тихих бага - Game.fog никем не
## присваивался (весь гейтинг молча отключался) и у FogLayer не было
## текстуры (спрайт без текстуры ничего не рисует). Оба здесь проверяются.

var _checks := 0
var _fails: Array[String] = []
var _done := false


func _init() -> void:
	var watchdog := create_timer(120.0)
	watchdog.timeout.connect(_force_quit)
	call_deferred("_run")


func _force_quit() -> void:
	if _done:
		return
	_done = true
	print("  FAIL тест не завершился за 120 с — принудительный выход")
	print("RESULT: FAIL fog_of_war_smoke (таймаут)")
	quit(1)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _run() -> void:
	print("-- fog_of_war_smoke --")
	# --- 1. Чистая логика маски (без сцены) ---
	var fog := FogOfWar.new()
	fog.enabled = true
	fog.width = 40
	fog.height = 40
	fog.mask.resize(40 * 40)
	fog.mask.fill(FogOfWar.STATE_BLACK)
	fog.reveal_around(Vector2i(20, 20))
	_check(fog.state_at(Vector2i(20, 20)) == FogOfWar.STATE_VISIBLE,
		"центр радиуса виден")
	_check(fog.state_at(Vector2i(31, 31)) == FogOfWar.STATE_EXPLORED,
		"кольцо за радиусом исследовано (диагональ 15-16)")
	_check(fog.state_at(Vector2i(0, 0)) == FogOfWar.STATE_BLACK,
		"далёкий угол не исследован")
	_check(fog.state_at(Vector2i(-5, 20)) == FogOfWar.STATE_VISIBLE,
		"за границей карты ничего не прячем")
	# RLE round-trip
	fog.mask[3] = FogOfWar.STATE_VISIBLE
	fog.mask[7] = FogOfWar.STATE_VISIBLE
	var rle := fog.mask_rle()
	_check(rle != "", "RLE не пустой")
	var back := FogOfWar.rle_decode(rle, 40 * 40)
	_check(back.size() == 1600 and back[3] == FogOfWar.STATE_VISIBLE
		and back[7] == FogOfWar.STATE_VISIBLE,
		"RLE round-trip сохраняет значения")
	# сокрытие юнитов: state_at_world без карты — тайл 32 по умолчанию
	_check(not fog.blocks_process(Vector2(20.5 * 32.0, 20.5 * 32.0)),
		"видимая клетка не блокирует тик юнита")
	_check(fog.blocks_process(Vector2(64.0, 64.0)),
		"неисследованная клетка блокирует тик юнита")
	# Регресс 19.10: клетка, вышедшая из радиуса, гаснет 2 -> 1
	# (иначе весь пройденный путь навсегда оставался «видимым»).
	fog.reveal_around(Vector2i(4, 4))
	_check(fog.state_at(Vector2i(20, 20)) == FogOfWar.STATE_EXPLORED,
		"вышедшая из радиуса клетка гаснет до «исследовано»")
	# конфиг: ключ живой и 0/1
	var fog_key := GameConfig.geti("debug", "fog_of_war")
	_check(fog_key == 0 or fog_key == 1, "[debug] fog_of_war — 0/1 (сейчас %d)" % fog_key)

	# --- 2. Интеграция в дереве (регресс на Game.fog и текстуру слоя) ---
	var map: Node = load("res://scripts/alm_map.gd").new()
	map.alm_path = "res://assets/maps/gen/gen_smart_01.alm"
	root.add_child(map)
	var fog2: FogOfWar = load("res://scripts/fog_of_war.gd").new()
	root.add_child(fog2)
	_check(Game.fog == fog2, "Game.fog присвоен узлом (_ready)")
	_check(fog2.enabled, "туман включён из конфига (fog_of_war=1)")
	_check(fog2.width == int(map.get("map_width")), "ширина маски = ширине карты")
	_check(fog2._layer != null and fog2._layer.texture != null,
		"у FogLayer назначена текстура (иначе он ничего не рисует)")
	_check(fog2._layer.visible, "FogLayer видим")
	_check(fog2.mini_img != null
		and fog2.mini_img.get_width() == fog2.width,
		"мини-картинка тумана создана (для миникарты)")
	# Герой в центре: физ-тик должен открыть радиус вокруг него.
	var hero := Node2D.new()
	hero.name = "SmokeHero"
	hero.position = Vector2(96 * 32.0, 96 * 32.0)
	root.add_child(hero)
	Game.hero = hero
	fog2._physics_process(0.016)
	var hero_cell := Vector2i(96, 96)
	_check(fog2.state_at(hero_cell) == FogOfWar.STATE_VISIBLE,
		"клетка героя видима после тика")
	_check(fog2.state_at(hero_cell + Vector2i(FogOfWar.RADIUS_CELLS + 1, 0))
		== FogOfWar.STATE_EXPLORED, "кольцо за радиусом от героя исследовано")
	_check(fog2.state_at(Vector2i(0, 0)) == FogOfWar.STATE_BLACK,
		"дальний угол карты остаётся чёрным")
	# Скрытие юнита по туману в живом узле.
	_check(fog2.blocks_process(Vector2(64.0, 64.0)),
		"далёкая клетка блокирует тик юнита (живой узел)")
	# Отписка при выходе
	root.remove_child(fog2)
	_check(Game.fog == null, "Game.fog очищается при выходе узла")
	Game.hero = null
	root.remove_child(hero)
	_done = true
	_report()


func _report() -> void:
	_done = true
	print("RESULT: %s fog_of_war_smoke (проверок: %d, провалов: %d)"
			% ["OK" if _fails.is_empty() else "FAIL", _checks, _fails.size()])
	for f in _fails:
		print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)
