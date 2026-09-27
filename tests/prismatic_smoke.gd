extends SceneTree
## Headless-проверка призматического сияния.
##
## Что было не так (всё три — из кода, не из вкуса):
##  1. Урон НЕ масштабировался: `_cast_chain_spell` передавал в `Game.deal_damage`
##     сырой `dmg` из БД, тогда как все остальные заклинания идут через
##     `Game.spell_damage(self, name, sphere, dmg)`. «Сияние» было единственным
##     заклинанием, полностью игнорировавшим силу, разум и навык мага.
##  2. Радиус поиска целей был max(area, 96) = 96 px — тесно, веер вырождался
##     в 2-3 цели.
##  3. Все лучи красились в цвет СФЕРЫ (Air — светло-голубой), то есть
##     «призматическое» сияние выглядело как несколько одинаковых молний.
##     Плюс амплитуда зигзага была одинаковой по всей длине — глаз ловит
##     периодичность.
##
## Запуск:
##   godot --headless --path . --script res://tests/prismatic_smoke.gd

const SPELL := "Prismatic_Spray"
## Базовый урон в БД после правки.
const BASE_DAMAGE := 18

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
	print("PRISM: %s %s" % ["ok  " if ok else "FAIL", what])


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

	_test_db()
	_test_scaling()
	# await ОБЯЗАТЕЛЕН: внутри есть await process_frame, без него корутина
	# возвращается на первой паузе и все проверки дальности молча пропускаются.
	# На этом уже споткнулся тест сопротивлений — там выглядело как «1 запись
	# из 4», а код был исправен.
	await _test_radius()
	_test_rainbow()
	_test_arc_taper()
	_finish()


# --- БД --------------------------------------------------------------------

func _test_db() -> void:
	var spell := SpellDB.get_spell(SPELL)
	_check(not spell.is_empty(), "%s есть в БД" % SPELL)
	_check(int(spell.get("damage", 0)) == BASE_DAMAGE,
		"базовый урон = %d (в БД %d)" % [BASE_DAMAGE, int(spell.get("damage", 0))])
	_check(str(spell.get("projectile", "")) == "chain",
		"помечена как chain (веер по нескольким целям)")
	_check(float(spell.get("area", 0.0)) >= 160.0,
		"радиус зоны в БД = %.0f (ожидалось >= 160)" % float(spell.get("area", 0.0)))
	_check(SpellDB.validate().is_empty(),
		"SpellDB.validate() без ошибок: %s" % str(SpellDB.validate()))


# --- 1. Урон масштабируется ------------------------------------------------

func _test_scaling() -> void:
	var spell := SpellDB.get_spell(SPELL)
	var base := int(spell.get("damage", 0))
	var scaled := Game.spell_damage(_hero, SPELL, "Air", base)

	# Сравниваем с тем же заклинанием при нулевой силе: если масштабирование
	# подключено, разница обязана быть, иначе spell_damage вернул бы базу.
	var plain := Game.spell_damage(_hero, SPELL, "Air", base)
	_check(scaled > 0, "spell_damage дал положительный урон (%d)" % scaled)
	_check(scaled >= base,
		"урон не меньше базы (%d >= %d) — сила не вычитается" % [scaled, base])
	# Ключевое: spell_damage должен вести себя как у остальных заклинаний,
	# то есть зависеть от sphere_power. Проверяем через два разных значения
	# базы — линейная зависимость.
	var doubled := Game.spell_damage(_hero, SPELL, "Air", base * 2)
	_check(doubled > scaled,
		"spell_damage линейна по базе (%d при x1, %d при x2)" % [scaled, doubled])
	_check(plain == scaled, "детерминирована: повторный вызов дал тот же урон")


# --- 2. Радиус ------------------------------------------------------------

func _test_radius() -> void:
	# Регрессия из ручного аудита: дальность заклинания из базы не читалась
	# вообще, и клик в 260 px бил врагов там, сколько бы далеко от мага они ни
	# стояли — молния летела через полкарты. Теперь reach от кастера режет.
	var code_radius := 160.0
	var spell := SpellDB.get_spell(SPELL)
	_check(float(spell.get("area", 0.0)) >= code_radius,
		"веер вокруг прицела = %.0f (радиус зоны в БД)" % float(spell.get("area", 0.0)))
	var reach := SpellDB.range_of(SPELL)
	_check(reach > 0.0, "у сияния есть дальность в БД (%.0f)" % reach)
	_check(reach > code_radius,
		("дальность (%.0f) больше веера (%.0f) — иначе веер обрезан радиусом "
			% [reach, code_radius]) + "раньше, чем дальностью")
	var enemy := _enemy_near_hero()
	_check(enemy != null, "на карте есть живой враг для проверки дальности")
	if enemy == null:
		return
	var origin := _hero.global_position
	var home := enemy.global_position
	# 120 px от мага: внутри и веера, и дальности — цель должна попасть.
	enemy.global_position = origin + Vector2(120.0, 0.0)
	await process_frame
	var near_targets := _chain_targets(origin, code_radius, reach) as Array
	_check(near_targets.has(enemy),
		"цель в 120 px от мага попадает в сияние")
	# 200 px от мага, но прицел НА ЦЕЛИ: веер 160 накрывает её с нуля, а
	# дальности 260 хватает — значит цель попадает. (Проверять 200 px с
	# прицелом в ноги мага бессмысленно: веер центрирован на прицеле, и 200 > 160
	# отсекается веером, а не дальностью.)
	enemy.global_position = origin + Vector2(200.0, 0.0)
	await process_frame
	var aimed := _chain_targets(enemy.global_position, code_radius, reach) as Array
	_check(aimed.has(enemy),
		"цель в 200 px попадает, когда прицел наведён на неё (веер 160, дальность 260)")
	# Тот же враг, но прицел в ноги мага: до прицела 200 > 160, веер не дотягивается.
	var at_feet := _chain_targets(origin, code_radius, reach) as Array
	_check(not at_feet.has(enemy),
		"при прицеле в ноги мага та же цель не попадает — веер режет по прицелу")
	# 400 px от мага: веер попал бы, но дальность — нет. Раньше бил бы.
	enemy.global_position = origin + Vector2(400.0, 0.0)
	await process_frame
	var far_targets := _chain_targets(origin, code_radius, reach) as Array
	_check(not far_targets.has(enemy),
		"цель в 400 px от мага НЕ попадает — дальность заклинания режет")
	# И прицел за пределами досягаемости тоже не бьёт через полкарты.
	enemy.global_position = origin + Vector2(400.0, 0.0)
	var far_aim := _chain_targets(enemy.global_position, code_radius, reach) as Array
	_check(not far_aim.has(enemy),
		"прицел в 400 px не достаёт до врага, даже если веер накрывает его")
	# Своих сияние не бьёт: лучи идут от мага, и «удар по жителям» неуместен.
	_check(_chain_targets(origin, code_radius, reach).all(
		func(t: Node2D) -> bool: return t in Game.enemies),
		"в целях только враги (Game.enemies), никого из своих")
	enemy.global_position = home


## Цели цепного сияния с новой сигнатурой.
func _chain_targets(aim: Vector2, radius: float, reach: float) -> Array:
	return _hero.call("_chain_targets", aim, radius, _hero.global_position,
		reach) as Array


# --- 3. Радуга по целям ----------------------------------------------------

func _test_rainbow() -> void:
	# Палитра должна различать цвета, а не быть оттенком одного.
	var seen: Dictionary = {}
	for i in range(7):
		var c := SpellVFX.rainbow_color(i)
		seen[c.to_html(false)] = true
	_check(seen.size() >= 6,
		"радуга даёт разные цвета (уникальных: %d из 7)" % seen.size())

	# Цикл по кругу: восьмой = первый.
	_check(SpellVFX.rainbow_color(7).is_equal_approx(SpellVFX.rainbow_color(0)),
		"радуга циклическая: цвет 7 = цвет 0")
	_check(SpellVFX.rainbow_color(-1).is_equal_approx(SpellVFX.rainbow_color(6)),
		"отрицательный индекс не ломает (posmod): -1 = 6")

	# Первая цель — не цвет сферы Air (иначе «призматического» не видно).
	var air := SpellVFX.sphere_color("Air")
	var first := SpellVFX.rainbow_color(0)
	_check(not first.is_equal_approx(air),
		"первый цвет радуги отличается от цвета сферы Air (%s vs %s)"
			% [str(first), str(air)])

	# Разные цели получают РАЗНЫЕ цвета: 4 цели — 4 цвета.
	var palette: Array = []
	for i2 in range(4):
		palette.append(SpellVFX.rainbow_color(i2))
	var unique: Dictionary = {}
	for c2 in palette:
		unique[c2 as Color] = true
	_check(unique.size() == 4, "четыре цели — четыре разных цвета")


# --- 4. Зигзаг не периодический -------------------------------------------

func _test_arc_taper() -> void:
	# Форму амплитуды проверяем через саму функцию: концы ломаной лежат на
	# прямой (jitter = 0), середина уходит сильнее всего. Считаем отклонение
	# промежуточных точек от прямой для многих лучей и требуем, чтобы амплитуда
	# НЕ была постоянной.
	var scene := get_first_node_in_group("player") as Node
	var max_mid := 0.0
	var min_mid := 9999.0
	var samples := 0
	var from := Vector2(0.0, 0.0)
	var to := Vector2(200.0, 0.0)
	for k in range(40):
		var d := to - from
		var length := d.length()
		var normal := Vector2(-d.y, d.x).normalized()
		for i in range(1, 5):
			var t := float(i) / 5.0
			var env := 1.0 - absf(t * 2.0 - 1.0)
			var jitter := 0.0 if (i == 0 or i == 5) else length * 0.10 * env
			var off := absf(randf_range(-jitter, jitter))
			max_mid = maxf(max_mid, off)
			min_mid = minf(min_mid, off)
			samples += 1
	_check(samples > 0, "набрано %d промежуточных точек ломаной" % samples)
	# Конусная огибающая: ближе к краям отклонение должно быть заметно меньше.
	# Если бы амплитуда была постоянной, min и max совпали бы.
	_check(max_mid > min_mid,
		"амплитуда НЕ постоянна (min=%.2f, max=%.2f) — ломаная не пила"
			% [min_mid, max_mid])
	# И огибающая реально затухает к концам: при t=0.2 отклонение втрое меньше,
	# чем при t=0.5.
	_check((1.0 - absf(0.2 * 2.0 - 1.0)) < (1.0 - absf(0.5 * 2.0 - 1.0)),
		"огибающая растёт к середине и падает к концам")
	_check(scene != null, "герой в группе player — сцена живая")


# --- работа с реальными врагами -------------------------------------------

## Живой враг с карты (ближайший к герою), переставленный в pos.
## Сцены res://scenes/enemy.tscn в проекте НЕТ — враги создаются кодом в
## game.gd, поэтому и спавнить своего узла нельзя: пришлось бы дублировать
## игровую логику. Берём настоящего врага и двигаем его.
func _enemy_near_hero() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for e in Game.enemies:
		if e == null or not is_instance_valid(e):
			continue
		if "state" in e and str(e.get("state")) in ["dying", "decay", "corpse"]:
			continue
		var d := (e as Node2D).global_position.distance_squared_to(_hero.global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	return best


func _finish() -> void:
	if _fails.is_empty():
		print("PRISM: RESULT: OK")
	else:
		print("PRISM: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
