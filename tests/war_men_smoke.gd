## Сторож наборов героя (1 ракурс + зеркало, UnitAnim dirs=1).
##
## Проверяет инварианты, которые нарезка и подключение обязана держать:
## - в базе 12 кадров (idle1+move4+attack3+dying4), dirs=1, холст 64x64, низ y=62;
## - все 12 файлов грузятся, кадры не пустые;
## - зеркало: восток (6) без flip_h, запад (2) с flip_h, север/юг скользят
##   прежним боком (не переключаются на мёртвой зоне);
## - индексы блоков: idle=0, move=1..4, attack=5..7, dying=8..11;
## - freeze_last_frame(DYING) оставляет последний кадр (12);
## - герой реально подключён: player.PILOT_HERO_SET = "hero/war_men";
## - пол героя выбирает набор: female -> hero/war_women, иначе war_men (14.10);
## - раса тоже выбирает набор: ork -> hero/orc_men|orc_women (15.10),
##   остальные расы (нежить, друид) берут людский набор.
##
## Проверки набора идут по всем четырём: контракт у них один.
##
## Запуск:
##   godot --headless --path . --script res://tests/war_men_smoke.gd

extends SceneTree

const SET := "hero/war_men"
const SET_F := "hero/war_women"
const SET_ORK := "hero/orc_men"
const SET_ORK_F := "hero/orc_women"
const SET_UNDEAD := "hero/undead_men"
const SET_DRUID := "hero/druid_men"
const SET_UNDEAD_F := "hero/undead_women"
const SET_DRUID_F := "hero/druid_women"
const CANVAS := 64
const FEET_Y := 62
const DIRS := 1
const IDLE_PHASES := 1
const MOVE_PHASES := 4
const ATTACK_PHASES := 3
const DYING_PHASES := 4
const TOTAL := IDLE_PHASES + (MOVE_PHASES + ATTACK_PHASES + DYING_PHASES) * DIRS

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)


func _run() -> void:
	_run_set(SET, "PILOT_HERO_SET")
	_run_set(SET_F, "PILOT_HERO_SET_F")
	_run_set(SET_ORK, "PILOT_HERO_SET_ORK")
	_run_set(SET_ORK_F, "PILOT_HERO_SET_ORK_F")
	_run_set(SET_UNDEAD_F, "PILOT_HERO_SET_UNDEAD_F")
	_run_set(SET_DRUID_F, "PILOT_HERO_SET_DRUID_F")
	_test_race_and_gender_switch()
	_finish()


## Раса и пол выбирают набор. Проверяется на НАСТОЯЩЕМ Player: значения
## обязаны совпасть с тем, что пишет экран создания героя, иначе герой-орк
## получил бы человеческий спрайт молча (ровно тот случай, что 15.10).
func _test_race_and_gender_switch() -> void:
	var p = load("res://scripts/player.gd").new()
	var saved_gender: String = str(Game.hero_gender)
	var saved_race: String = str(Game.hero_race)

	# раса, пол -> ожидаемый набор. "" означает «старый сейв без расы».
	var matrix := [
		["human", "male", SET], ["human", "female", SET_F],
		["human", "", SET], ["", "male", SET],
		["ork", "male", SET_ORK], ["ork", "female", SET_ORK_F],
		["ork", "", SET_ORK], ["orc", "male", SET_ORK],
		# 21.10: у нежити и друида есть женские наборы.
		["necro", "male", SET_UNDEAD], ["necro", "female", SET_UNDEAD_F],
		["druid", "male", SET_DRUID], ["druid", "female", SET_DRUID_F],
	]
	for row in matrix:
		var race := str(row[0])
		var gender := str(row[1])
		var want := str(row[2])
		Game.hero_race = race
		Game.hero_gender = gender
		_check(p.anim_set_name() == want,
			"раса %s / пол %s -> %s (получено %s)" % [
				race if race != "" else "(пусто)", gender if gender != "" else "(пусто)",
				want, p.anim_set_name()])

	Game.hero_race = saved_race
	Game.hero_gender = saved_gender
	p.free()


func _run_set(set_name: String, const_name: String) -> void:
	var o: Dictionary = UnitDB.get_set(set_name)
	_check(not o.is_empty(), "набор %s есть в units_db" % set_name)
	if o.is_empty():
		return

	_check(int(o.get("frames", -1)) == TOTAL,
		"frames в базе = %d (ожидалось %d)" % [int(o.get("frames", -1)), TOTAL])
	_check(int(o.get("dirs", -1)) == DIRS, "dirs = 1 (один ракурс + зеркало)")
	_check(int(o.get("idle_phases", -1)) == IDLE_PHASES, "idle_phases = 1")
	_check(int(o.get("move", -1)) == MOVE_PHASES, "move = %d" % MOVE_PHASES)
	_check(int(o.get("attack", -1)) == ATTACK_PHASES, "attack = %d" % ATTACK_PHASES)
	_check(int(o.get("dying", -1)) == DYING_PHASES,
		"dying = %d" % DYING_PHASES)
	_check(int(o.get("decay", 0)) == 0, "decay = 0")
	_check(int(o.get("w", 0)) == CANVAS and int(o.get("h", 0)) == CANVAS, "холст 64x64")
	_check(int(o.get("cy", 0)) == FEET_Y, "cy = 62 (точка земли)")

	var folder := str(o.get("folder", set_name))
	var prefix := str(o.get("prefix", "sprites"))
	for i in range(1, TOTAL + 1):
		var p := UnitDB.frame_path(folder, prefix, i)
		_check(ResourceLoader.exists(p), "кадр существует: %s" % p)

	var anim := UnitAnim.new()
	anim.name = "UnitAnim"  # имя узла — часть контракта (game.gd ищет по нему)
	root.add_child(anim)
	anim.setup(set_name)
	_check(anim.set_name == set_name, "setup() принял набор")
	_check(anim.frames.size() == TOTAL,
		"загружено кадров: %d (ожидалось %d)" % [anim.frames.size(), TOTAL])

	# --- зеркало и индексы ---
	# восток (октант 6): как нарисовано, без flip
	_set_dir(anim, 6)
	anim.play(1)  # MOVE — иначе _frame_index остаётся в ветке IDLE
	anim.anim_idx = 0
	_check(anim._sprite.flip_h == false, "восток (6): flip_h = false")
	_check(anim._frame_index(1) == 1, "move восток фаза0 -> кадр 1")

	# запад (октант 2): зеркало восточного арта
	_set_dir(anim, 2)
	_check(anim._sprite.flip_h == true, "запад (2): flip_h = true")
	_check(anim._frame_index(1) == 1, "move запад фаза0 -> тот же файл 1 (зеркало)")

	# север (0) после запада: скользит западом, flip не сбрасывается
	_set_dir(anim, 0)
	_check(anim._sprite.flip_h == true, "север (0) после запада: flip остаётся true")
	# юг (4) после востока: скользит востоком
	_set_dir(anim, 6)
	_set_dir(anim, 4)
	_check(anim._sprite.flip_h == false, "юг (4) после востока: flip остаётся false")

	# --- блоки ---
	_set_dir(anim, 6)
	anim.play(0)  # IDLE
	anim.anim_idx = 0
	_check(anim._frame_index(0) == 0, "idle -> кадр 0")
	anim.play(1)  # MOVE
	anim.anim_idx = 0
	_check(anim._frame_index(1) == 1, "move фаза0 -> кадр 1")
	anim.anim_idx = MOVE_PHASES - 1
	_check(anim._frame_index(1) == MOVE_PHASES, "move последняя фаза -> кадр %d" % MOVE_PHASES)
	anim.play(2)  # ATTACK
	anim.anim_idx = 0
	_check(anim._frame_index(2) == 5, "attack фаза0 -> кадр 5")
	anim.play(3)  # DYING
	anim.anim_idx = 0
	_check(anim._frame_index(3) == 8, "dying фаза0 -> кадр 8")

	# доигрывание смерти и заморозка последнего кадра
	var guard := 0
	var done := false
	while guard < 200 and not done:
		done = anim.advance(0.2)
		guard += 1
	_check(done, "dying доигрывает (advance вернул true)")
	anim.freeze_last_frame(3)
	_check(anim.anim_idx == DYING_PHASES - 1, "freeze_last_frame: индекс = %d" % anim.anim_idx)
	_check(anim._frame_index(3) == TOTAL - 1, "freeze_last_frame: кадр %d (последний)" % (TOTAL - 1))
	var last_tex := load(UnitDB.frame_path(folder, prefix, TOTAL))
	_check(anim._sprite.texture == last_tex, "текстура трупа = sprites-%03d" % TOTAL)

	# --- герой подключён ---
	# Константы читаются картой скрипта: обращение вида `player_script.CONST`
	# требует имени литералом, а наборов четыре и список должен быть данными.
	var player_script := load("res://scripts/player.gd")
	var consts: Dictionary = player_script.get_script_constant_map()
	_check(consts.has(const_name), "player.gd объявляет %s" % const_name)
	if consts.has(const_name):
		_check(str(consts[const_name]) == set_name,
			"player.%s = %s (получено %s)" % [const_name, set_name, str(consts[const_name])])
	_check(bool(consts.get("PILOT_RIG", true)) == false, "player.PILOT_RIG = false (спрайт-лист)")

	anim.queue_free()


func _set_dir(anim: UnitAnim, world_dir: int) -> void:
	anim.dir = world_dir
	anim.target_dir = -1
	anim._apply_frame()


func _finish() -> void:
	for m in _fails:
		print("FAIL: ", m)
	print("war_men_smoke: %d checks, %d fails" % [_checks, _fails.size()])
	quit(0 if _fails.is_empty() else 1)
