## КОНТРАКТ анимированного юнита: всё, что риг обязан уметь вместо спрайт-листов.
##
## Зачем этот тест (10.10, фаза 0 перехода на 2D-риг):
## Юниты создаются КОДОМ (`UnitAnim.new()` в player/enemy/npc/mercenary),
## публичная поверхность — 9 членов, а `game.gd` обращается к ней через
## `get_node_or_null("UnitAnim")` + `has_method`, то есть по ИНТЕРФЕЙСУ, а не
## по классу. Именно на этом стоит миграция «спрайт-листы -> риг»: новый
## RiggedAnim встаёт рядом без единой правки в game.gd/spell_vfx/craft_vfx.
##
## Но до сих пор контракт НЕ сторожил ни один тест: `UnitAnim` упоминают лишь
## 5 тестов из ~60, и то косвенно. Сломанный контракт прошёл бы все тесты
## зелёными и упал бы в игре.
##
## Тест проверяет ДВА слоя:
##   1. наличие членов контракта (дёшево, ловит переименование);
##   2. что контракт РЕАЛЬНО работает на живом экземпляре (дорого, но это
##      единственная проверка, которая не пройдёт на сломанной схеме).
##
## Если появится `rigged_anim.gd`, тест подхватит его автоматически — список
## бэкендов расширяется сам, иначе новый риг стартовал бы без страховки.
## У каждого бэкенда СВОЙ набор: спрайт-листы не грузят риг и наоборот.
##
## Запуск:
##   godot --headless --path . --script res://tests/anim_contract_smoke.gd

extends SceneTree

## Члены, которые обязан иметь любой бэкенд анимации юнита.
## Формат: [имя, "method"|"var"].
const CONTRACT: Array = [
	["setup", "method"],
	["play", "method"],
	["advance", "method"],
	["freeze_last_frame", "method"],
	["set_direction_vec", "method"],
	["speed_scale", "var"],
	["sprite_height", "method"],
	["visual_height", "method"],
	["position", "var"],
]

## Бэкенды, которые тест обязан проверить. RiggedAnim подхватывается, если
## файл есть — жёсткой ссылки на класс нет намеренно: пока файла нет, такая
## ссылка была бы Parse Error и тест не запускался бы вовсе.
const BACKENDS: Array = [
	{"name": "UnitAnim", "path": "res://scripts/unit_anim.gd", "set": "humans/swordsman_"},
	{"name": "RiggedAnim", "path": "res://scripts/rigged_anim.gd", "set": "heroes/pilot"},
]

## Число мировых направлений (октант). Дублирует UnitAnim.FULL_DIRS, чтобы
## тест не зависел от загрузки бэкенда: проверка октант — это контракт.
const FULL_DIRS := 8

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)
	print(("  OK  " if ok else "  FAIL") + " " + msg)


func _has_member(obj: Object, member: String, kind: String) -> bool:
	# ВАЖНО (грабля §9.2): `has_method` на объекте Script видит только
	# СТАТИЧЕСКИЕ методы, поэтому проверять надо на экземпляре.
	if kind == "method":
		return obj.has_method(member)
	for p in obj.get_property_list():
		if str(p.get("name", "")) == member:
			return true
	return false


func _make_backend(backend: Dictionary) -> Object:
	var script: Variant = load(str(backend["path"]))
	if script == null:
		return null
	var obj: Object = script.new()
	if obj == null:
		return null
	obj.name = "UnitAnim"  # имя узла — часть контракта (game.gd ищет по нему)
	return obj


## Слой 1: у бэкенда есть все члены контракта.
func _test_members(label: String, obj: Object) -> void:
	for entry in CONTRACT:
		var member := str(entry[0])
		var kind := str(entry[1])
		_check(_has_member(obj, member, kind),
			"%s: контракт — есть %s `%s`" % [label, kind, member])


## Слой 2: контракт реально работает на живом экземпляре.
## Без этого первый слой проверяет только наличие имён: переименование
## ловится, а поломанная логика — нет.
func _test_functional(label: String, obj: Object, test_set: String) -> void:
	var anim := obj as Node2D
	if anim == null:
		_check(false, "%s: бэкенд должен быть Node2D" % label)
		return

	if UnitDB.get_set(test_set).is_empty():
		_check(false, "%s: набора `%s` нет в units_db" % [label, test_set])
		return

	anim.setup(test_set)
	_check(str(obj.get("set_name")) == test_set,
		"%s: setup() запомнил набор (`%s`)" % [label, str(obj.get("set_name"))])

	# Узел обязан быть в дереве, иначе game.gd не найдёт "UnitAnim" по get_node.
	var holder := Node2D.new()
	holder.add_child(anim)
	_check(anim.get_parent() != null, "%s: узел добавлен в дерево" % label)

	# У анимированного юнита должна быть ненулевая высота — по ней game.gd и
	# spell_vfx позиционируют шкалу HP, ауры и кольцо выбора.
	var sh: float = float(obj.call("sprite_height"))
	var vh: float = float(obj.call("visual_height"))
	_check(sh > 0.0, "%s: sprite_height() > 0 (%.1f)" % [label, sh])
	_check(vh > 0.0, "%s: visual_height() > 0 (%.1f)" % [label, vh])

	# Направление. Проверяем НЕ `dir`, а `target_dir`: `set_direction_vec`
	# выставляет цель, а `dir` доворачивается в _process по аккумулятору
	# ROT_STEP_TIME. Первая версия проверки ждала мгновенной смены `dir`
	# и была фиктивно-зелёной по замыслу: за один headless-кадр аккумулятор
	# не набирает 0.05 с, и проверка прошла бы даже на сломанном маппинге.
	#
	# Реальный инвариант — соглашение о компасных октантах. ВАЖНО: у нас
	# индексация КОНТРИКЛОКОВАЯ: 0 = север (спина), 7 = северо-восток,
	# 6 = восток, 5 = юго-восток, 4 = юг, 3 = юго-запад, 2 = запад,
	# 1 = северо-запад.
	#
	# Вектор октанты i — это угол Godot (90 + i*45), то есть (cos a, sin a).
	# Первая версия теста строила вектор как (sin(i*45), cos(i*45)) — это
	# ОТРАЖЕНИЕ, и хелпер вместе с ожиданием posmod(-i) оставались взаимно
	# согласованы, то есть тест проверял, что код совпадает сам с собой, а не
	# что направления верны. Именно эта ошибка хелпера держала инвертированное
	# зеркало в RiggedAnim: игрок жаловался, что на ходу влево/вправо персонаж
	# идёт боком.
	var octant_ok := true
	var detail := ""
	for i in range(FULL_DIRS):
		var v := _octant_vector(i)
		obj.call("set_direction_vec", v)
		var want: int = i
		var got: int = int(obj.get("target_dir"))
		if got != want:
			octant_ok = false
			detail += " октанта[%d] -> %d (ждали %d);" % [i, got, want]
	_check(octant_ok, "%s: set_direction_vec раскладывает вектор по 8 октантам (0=север, против часовой)%s"
		% [label, "" if octant_ok else " — " + detail])

	# Плавный доворот обязан реально доводить dir до цели, иначе юнит
	# застревает в промежуточном ракурсе навсегда.
	# Дёргать `await process_frame` НЕЛЬЗЯ: в headless дельта кадра не
	# набирает ROT_STEP_TIME за разумное число итераций (та же грабля, что в
	# §12 про «замер по кадрам вместо замера по времени»). Поэтому шагаем
	# `_advance_rotation` явной дельтой — детерминированно и без гонки.
	obj.call("set_direction_vec", Vector2.RIGHT)
	if _has_member(obj, "_advance_rotation", "method"):
		var steps := 0
		while int(obj.get("target_dir")) >= 0 and steps < 32:
			obj.call("_advance_rotation", 0.06)
			steps += 1
		_check(int(obj.get("target_dir")) < 0,
			"%s: поворот доезжает до цели за %d шагов (target_dir сброшен)"
				% [label, steps])
	else:
		print("-- %s: нет _advance_rotation, шаг доворота не проверяем" % label)

	# Воспроизведение блока и одноразовость.
	obj.call("play", 0)  # Anim.IDLE
	var anim_after: int = int(obj.get("anim"))
	_check(anim_after == 0, "%s: play(IDLE) выставил anim=0 (получено %d)"
		% [label, anim_after])

	# advance() обязан вернуть true на ОДНОРАЗОВОМ блоке. Первая версия
	# проверяла это на IDLE и упала на риге — и это была ошибка проверки, а не
	# кода: у рига idle действительно зациклен по-настоящему (в спрайт-листах
	# тот же блок циклически перебирает кадры и «возвращает true»). Ждать
	# завершения от вечного цикла бессмысленно, ждать его надо от атаки.
	obj.call("play", 2)  # Anim.ATTACK — одноразовый блок
	var finished := false
	for i in range(600):
		if bool(obj.call("advance", 0.05)):
			finished = true
			break
	_check(finished, "%s: advance() вернул true на одноразовом блоке ATTACK" % label)

	# freeze_last_frame обязан оставить юнит на ПОСЛЕДНЕМ кадре блока: иначе
	# труп возвращается к началу и зацикливается вместо того, чтобы лежать.
	#
	# Номер последнего кадра у бэкендов разный и НИГДЕ не задан извне: у
	# спрайт-листов фазы берутся из units_db, у рига — из числа ключей клипа.
	# Первая версия проверки ожидала величину из units_db и была фиктивной для
	# рига (смешала два источника истины). Поэтому сравниваем не с числом, а
	# с ПОВЕДЕНИЕМ: freeze обязан дать индекс не меньше максимального, который
	# бэкенд показывал при обычном проигрывании того же блока.
	obj.call("play", 3)  # Anim.DYING
	var max_seen := 0
	for i in range(600):
		if bool(obj.call("advance", 0.05)):
			break
		max_seen = maxi(max_seen, int(obj.get("anim_idx")))
	obj.call("freeze_last_frame", 3)
	var frozen: int = int(obj.get("anim_idx"))
	_check(frozen >= max_seen,
		"%s: freeze_last_frame(DYING) не откатил назад (заморожен %d, в игре доходило до %d)"
			% [label, frozen, max_seen])

	# speed_scale — обычное поле, контракт требует его наличия и базовой 1.0.
	_check(is_equal_approx(float(obj.get("speed_scale")), 1.0),
		"%s: speed_scale по умолчанию 1.0" % label)

	holder.remove_child(anim)
	anim.free()
	holder.free()


## Условие выбора бэкенда. Player решает по нему, риг ли брать — значит
## ошибка здесь тихо вернёт героя на спрайт-листы, и пилот «не работает»
## без единой ошибки в логе.
func _test_backend_selection() -> void:
	if not ResourceLoader.exists("res://scripts/rigged_anim.gd"):
		return
	_check(bool(RiggedAnim.has_rig("heroes/pilot")),
		"выбор бэкенда: у `heroes/pilot` риг есть")
	_check(not bool(RiggedAnim.has_rig("humans/swordsman_")),
		"выбор бэкенда: у `humans/swordsman_` рига нет (остаёмся на листах)")
	_check(not bool(RiggedAnim.has_rig("heroes/не_существует")),
		"выбор бэкенда: несуществующий набор не считается ригом")

	# Набор без рига обязан дать НЕ ЗАГРУЖЕННЫЙ риг, а не риг с пустым
	# скелетом: иначе юнит просто исчезнет вместо отката к листам.
	var r := RiggedAnim.new()
	r.setup("humans/swordsman_")
	_check(not r.is_loaded(), "выбор бэкенда: риг без своего rig.json не загружается")
	_check(float(r.call("visual_height")) == 0.0,
		"выбор бэкенда: незагруженный риг не выдаёт высоту (иначе шкала HP уедет)")
	r.free()


## Поворот рига: жалоба игрока «постоянно разворачивается спиной идёт».
## Жалоба имела ДВЕ причины, и обе проверяются здесь раздельно:
##   1. скелет пересобирался на каждом шаге поворота (мерцание);
##   2. зеркало щёлкало на границе октантов (дёрганье).
func _test_rig_turning() -> void:
	if not ResourceLoader.exists("res://scripts/rigged_anim.gd"):
		return
	var r := RiggedAnim.new()
	root.add_child(r)
	r.name = "UnitAnim"
	r.setup("heroes/pilot")
	if not r.is_loaded():
		_check(false, "поворот рига: пилотный риг не загрузился")
		r.queue_free()
		return

	# Вектор октанты берётся общим хелпером — см. _octant_vector.
	var vec: Callable = func(i: int) -> Vector2:
		return _octant_vector(i)

	# --- 1. Скелет НЕ пересобирается при повороте внутри одной ракурсной группы ---
	# Восточный октант (2) и юго-восточный (3) смотрят в одну сторону, значит
	# ракурс тот же. Если бы _build_view вызывался на каждом шаге, узел Hip
	# был бы ДРУГИМ экземпляром — это ловится по instance_id.
	r.set_direction_vec(vec.call(2))
	for i in range(6):
		r._advance_rotation(0.06)
	var hip_after_east: int = 0
	var hip_node: Node = r.get_node_or_null("Hip")
	if hip_node != null:
		hip_after_east = hip_node.get_instance_id()
	_check(hip_after_east != 0, "поворот рига: узел Hip найден после доворота на восток")

	r.set_direction_vec(vec.call(3))
	for i in range(6):
		r._advance_rotation(0.06)
	var hip_after_se: int = 0
	hip_node = r.get_node_or_null("Hip")
	if hip_node != null:
		hip_after_se = hip_node.get_instance_id()
	_check(hip_after_se == hip_after_east,
		"поворот рига: скелет НЕ пересобран при смене октанта внутри вида (восток->юго-восток)")

	# --- 2. Зеркало НЕ щёлкает на соседних октантах, смотрящих в одну сторону ---
	# 2 (восток) и 3 (юго-восток) оба вправо: mirror обязан остаться тем же.
	# Это ровно то «дёрганье», на которое жаловался игрок.
	var mirror_stable := true
	for probe in [2, 3, 2, 3, 2]:
		var before := _hip_scale_sign(r)
		r.set_direction_vec(vec.call(int(probe)))
		for i in range(8):
			r._advance_rotation(0.06)
		if _hip_scale_sign(r) != before:
			mirror_stable = false
	_check(mirror_stable,
		"поворот рига: зеркало стабильно на октантах, смотрящих в одну сторону")

	# --- 2b. Зеркало ОРИЕНТИРОВАНО, а не только стабильно ---
	# Арт пилота нарисован вправо (faces_east = 1). Октанта 6 = восток =>
	# без зеркала; октанта 2 = запад => зеркало. Проверка на стабильность
	# (2a) перепутанный знак ПРОПУСКАЛА: зеркало было стабильным, но инвертированным,
	# и игрок видел «на ходу влево/вправо персонаж идёт боком». Поэтому знак
	# проверяем явно, а не «лишь бы не дёргалось».
	r.set_direction_vec(vec.call(6))   # восток
	for i in range(20):
		r._advance_rotation(0.06)
	var east_sign := _hip_scale_sign(r)
	_check(int(r.dir) == 6 and is_equal_approx(east_sign, 1.0),
		"поворот рига: на востоке (октанта 6) арт НЕ отражён (dir=%d, scale.x=%.0f)"
			% [r.dir, east_sign])

	r.set_direction_vec(vec.call(2))   # запад
	for i in range(20):
		r._advance_rotation(0.06)
	var west_sign := _hip_scale_sign(r)
	_check(int(r.dir) == 2 and is_equal_approx(west_sign, -1.0),
		"поворот рига: на западе (октанта 2) арт ОТРАЖЁН (dir=%d, scale.x=%.0f)"
			% [r.dir, west_sign])

	# --- 3. Юг не дёргает зеркало ---
	# Жалоба игрока: «когда идёт вниз, иногда отворачивается в другую
	# сторону, хотя вектор один и точный». Причина: cos(270°) в плавающей
	# точке это -1.8e-16, а не 0. Условие >= 0 решало «смотрит на запад» и
	# включало зеркало ровно на октанте юга. При ходьбе вниз октанты 4<->5
	# чередуются, и персонаж щёлкал туда-сюда.
	# Обе октанты «вниз» — 4 (юг) и 5 (юго-восток) — обязаны давать ОДНО
	# зеркало, иначе на ровной ходьбе вниз будет дёргание.
	r.set_direction_vec(vec.call(6))   # восток — задаём известное состояние
	for i in range(20):
		r._advance_rotation(0.06)
	var south_sign := _hip_scale_sign(r)
	r.set_direction_vec(vec.call(4))   # ровно на юг
	for i in range(20):
		r._advance_rotation(0.06)
	var due_south_sign := _hip_scale_sign(r)
	_check(int(r.dir) == 4 and is_equal_approx(due_south_sign, south_sign),
		"поворот рига: на юге (октанта 4) зеркало не щёлкает (scale.x %.0f -> %.0f)"
			% [south_sign, due_south_sign])

	# Полный круг: 0..7. Зеркало обязано переключиться РОВНО ДВАЖДЫ (на
	# западной стороне и обратно). Больше двух — значит «полярные» октанты
	# север/юг дают ложные переключения.
	r.set_direction_vec(vec.call(0))
	for i in range(20):
		r._advance_rotation(0.06)
	var flips := 0
	var prev := _hip_scale_sign(r)
	for step in range(FULL_DIRS):
		r.set_direction_vec(vec.call(step))
		for i in range(20):
			r._advance_rotation(0.06)
		var now := _hip_scale_sign(r)
		if now != prev:
			flips += 1
			prev = now
	_check(flips == 2,
		"поворот рига: полный круг даёт ровно 2 переключения зеркала (получено %d)" % flips)

	# --- 4. Гистерезис: одиночный «дрож» направления не должен доворачивать юнита ---
	r.set_direction_vec(vec.call(2))
	for i in range(10):
		r._advance_rotation(0.06)
	var dir_before_jitter: int = r.dir
	r.set_direction_vec(vec.call(1))   # на один шаг дёрнулись вбок
	r._advance_rotation(0.06)
	r.set_direction_vec(vec.call(2))   # и вернулись
	for i in range(10):
		r._advance_rotation(0.06)
	_check(r.dir == dir_before_jitter,
		"поворот рига: одиночный дребезг направления не доворачивает юнита (было %d, стало %d)"
			% [dir_before_jitter, r.dir])

	# --- 4. Устойчивый поворот всё-таки доводит юнита ---
	r.set_direction_vec(vec.call(6))   # запад, держим
	for i in range(20):
		r._advance_rotation(0.06)
	_check(r.dir == 6, "поворот рига: устойчивое направление доезжает (dir=%d, ждали 6)" % r.dir)

	# --- 5. Одноразовый клип ПЕРЕЗАПУСКАЕТСЯ при повторном play() ---
	# Жалоба игрока: «когда атакует, то он первый раз делает взмах, и потом
	# просто звуки и видно как отнимается здоровье». Причина: игровой код держит
	# состояние "attack" дольше одного замаха (удары гейтятся кулдауном), и
	# play(ATTACK) вызывается каждый кадр. Первый раз клип запустился, дальше
	# play() выходил раньше по `anim == anim_kind`, и одноразовый клип навсегда
	# оставался на последнем кадре. У спрайт-листов такого нет: там advance()
	# циклит фазы, поэтому взмах повторялся сам собой.
	# Проверяем ПОВЕДЕНИЕМ: после доигрывания и повторного play(ATTACK) поза
	# обязана отличаться от замороженной последней.
	r.play(2)  # ATTACK
	while not r.advance(0.05):
		pass
	var arm := _bone_rotation(r, "ArmFront")
	var held := true
	for i in range(4):
		r.advance(0.05)
		held = is_equal_approx(_bone_rotation(r, "ArmFront"), arm)
	_check(held, "повтор атаки: доигранный клип держит последний кадр")

	r.play(2)  # повторный замах, БЕЗ reset
	# Проверять ПОЗУ здесь бессмысленно: клип замаха возвращается в начальную
	# позу на последнем ключе (ArmFront: -10° … -95° … 40° … -10°), поэтому
	# первый и последний кадр неразличимы и проверка «поза изменилась» прошла
	# бы и на сломанном коде. Поэтому сверяем сам факт рестарта — время клипа
	# вернулось в ноль — и то, что клип реально проигрывается: замах проходит
	# через крайнюю фазу, которой нет в конце.
	var time_after_restart: float = float(r.get("_clip_time"))
	_check(is_equal_approx(time_after_restart, 0.0),
		"повтор атаки: play(ATTACK) ПЕРЕЗАПУСКАЕТ доигранный одноразовый клип (время %.3f)"
			% time_after_restart)
	var windup := false
	for i in range(10):
		r.advance(0.05)
		if _bone_rotation(r, "ArmFront") < -1.0:
			windup = true
			break
	_check(windup, "повтор атаки: после рестарта клип реально проигрывает замах")

	# Замороженный труп перезапускаться НЕ должен: иначе play(DYING) в
	# состоянии "dead" снова запустит падение, и мёртвый будет шевелиться.
	r.freeze_last_frame(3)  # DYING
	var frozen_rot := _bone_rotation(r, "ArmFront")
	for i in range(6):
		r.play(3)
		r.advance(0.05)
	_check(is_equal_approx(_bone_rotation(r, "ArmFront"), frozen_rot),
		"повтор атаки: замороженный DYING не перезапускается повторным play(DYING)")

	r.queue_free()


## Угол кости по имени. Полный путь — Hip/Torso/<кость>: Torso лежит под Hip,
## а не под корнем, и первая версия искала "Torso/..." — промахивалась и
## МОЛЧА возвращала 0.0, из-за чего проверка «поза удержалась» проходила
## вхолостую. Теперь промах — ошибка теста, а не тихий ноль.
func _bone_rotation(r: Object, bone_name: String) -> float:
	for path in ["Hip/Torso/" + bone_name, "Hip/" + bone_name, bone_name]:
		var b: Node = r.get_node_or_null(path)
		if b != null:
			return (b as Node2D).rotation
	_check(false, "тест: кость `%s` не найдена — проверка ниже была бы вхолостую"
		% bone_name)
	return 0.0


func _hip_scale_sign(r: Object) -> float:
	var hip: Node = r.get_node_or_null("Hip")
	if hip == null:
		return 0.0
	return signf(float((hip as Node2D).scale.x))


## ЕДИНСТВЕННЫЙ хелпер «октанта -> вектор». Вынесен отдельно, потому что его
## пришлось писать заново: инверсия оси здесь молча инвертировала зеркало рига
## (жалоба игрока: «ходит влево или вправо, постоянно разворачивается спиной»).
## Вектор октанты i — это угол Godot (90 + i*45): 0=север, 6=восток, 4=юг,
## 2=запад. Godot-угол считается от +x против часовой, поэтому вектор = (cos, sin).
func _octant_vector(i: int) -> Vector2:
	var a := deg_to_rad(90.0 + float(i) * 45.0)
	return Vector2(cos(a), sin(a))


func _run() -> void:
	var tested := 0
	for backend in BACKENDS:
		var label := str(backend["name"])
		var path := str(backend["path"])
		if not ResourceLoader.exists(path):
			print("-- %s отсутствует (%s), пропущен" % [label, path])
			continue
		tested += 1
		print("-- проверка бэкенда: %s" % label)
		var obj: Object = _make_backend(backend)
		if obj == null:
			_check(false, "%s: не удалось создать экземпляр" % label)
			continue
		_test_members(label, obj)
		await _test_functional(label, obj, str(backend["set"]))

	_check(tested > 0, "проверен хотя бы один бэкенд анимации")
	_test_backend_selection()
	_test_rig_turning()
	_report()


func _report() -> void:
	print("\n==== ИТОГ ====")
	if _fails.is_empty():
		print("RESULT: OK anim_contract_smoke (проверок: %d, провалов: 0)" % _checks)
	else:
		print("RESULT: FAIL anim_contract_smoke (проверок: %d, провалов: %d)"
			% [_checks, _fails.size()])
		for f in _fails:
			print("  FAIL " + f)
	quit(0 if _fails.is_empty() else 1)