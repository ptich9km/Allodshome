extends SceneTree
## Headless-проверка «МЕТРИК ФИГУРЫ»: рамка юнита считается по непрозрачному
## содержимому кадра, а не по холсту.
##
## Повод (жалоба игрока 27.10): «персонаж бьётся в 3 шагах от монстра, и магия
## огня, которая должна быть у головы, у живота». Причины, обе арифметические:
##  1. Кадры у всех наборов — холст 64×64, а фигура внутри ~20×54. Всё, что
##     считалось «от высоты» (`UnitAnim.visual_height`), брало ХОЛСТ: ауры и
##     точка каста уезжали на ~10 px, а «центр корпуса» попадал в живот.
##  2. В `units_db.json` нет `sel_box`, и `UnitDB.sel_box()` отдаёт заглушку
##     96×96. Проверка «это дефолт» срабатывала только при w>=128, а у нас
##     w=h=64 — поэтому КАЖДЫЙ юнит носил бокс 96×96, смещённый на +56 px
##     вправо. `Game.units_range` мерил расстояние между такими боксами, и
##     бой начинался «в трёх шагах».
##
## Проверяет:
##  1. рамка фигуры меньше холста и стоит на основании (ноги ≈ 0);
##  2. высота «фигуры» < высоты холста;
##  3. хит-бокс = тело, а не 96×96: уже клетки, по центру, не зависит от кадра удара;
##  4. дистанция боя: соседняя клетка — рядом, две-три — далеко;
##  5. длина удара по оружию (палица < меч < посох < копьё);
##  6. аура огня действительно у головы, земля — у ног.
##
## Запуск:
##   godot --headless --path . --script res://tests/unit_figure_metrics_smoke.gd

const SET := "hero/war_men"
const TILE := 32

var _fails: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
	print("FIGURE: %s %s" % ["ok  " if ok else "FAIL", what])


func _run() -> void:
	_test_rect()
	_test_body_vs_attack()
	_test_distance()
	_test_reach()
	_test_aura_rows()
	_finish()


func _make_unit(set_name: String) -> Node2D:
	var root := Node2D.new()
	var anim := UnitAnim.new()
	anim.name = "UnitAnim"
	root.add_child(anim)
	anim.setup(set_name)
	return root


# --- 1-2. Рамка фигуры ----------------------------------------------------

func _test_rect() -> void:
	var u := _make_unit(SET)
	var fig := Game.unit_local_rect(u)
	var sprite: Sprite2D = u.get_node("UnitAnim/Sprite") as Sprite2D
	_check(fig.size.x > 4.0 and fig.size.y > 20.0,
		"рамка фигуры непустая: %.0f×%.0f px" % [fig.size.x, fig.size.y])
	_check(sprite != null and sprite.texture != null, "кадр загружен")
	if sprite == null or sprite.texture == null:
		u.queue_free()
		return
	var canvas := float(sprite.texture.get_height())
	_check(fig.size.y < canvas,
		"фигура ниже холста: %.0f < %.0f (холст ≠ фигура)" % [fig.size.y, canvas])
	_check(fig.size.x < canvas * 0.7,
		"фигура уже холста: %.0f < %.0f" % [fig.size.x, canvas * 0.7])
	_check(absf(fig.end.y) <= 8.0,
		"ноги у основания юнита (низ рамки %.1f)" % fig.end.y)
	_check(fig.position.y < -canvas * 0.5,
		"макушка выше середины холста (%.1f)" % fig.position.y)
	var h := Game.unit_visual_height(u)
	_check(absf(h - fig.size.y) < 0.5,
		"unit_visual_height = высота фигуры (%.1f), а не холста (%.0f)" % [h, canvas])
	u.queue_free()


# --- 3. Хит-бокс = тело, кадр удара не раздувает ---------------------------

func _test_body_vs_attack() -> void:
	var u := _make_unit(SET)
	u.global_position = Vector2(100, 100)
	var body := Game.unit_hit_rect(u)
	_check(body.size.x > 4.0 and body.size.x < TILE,
		"бокс уже клетки: %.0f px (было 96)" % body.size.x)
	_check(body.size.y > 20.0 and body.size.y < 70.0,
		"высота бокса — фигура: %.0f px" % body.size.y)
	_check(absf(body.get_center().x - u.global_position.x) < 6.0,
		"бокс по центру тела (смещение %.1f)" % (body.get_center().x - u.global_position.x))
	var anim: UnitAnim = u.get_node("UnitAnim") as UnitAnim
	anim.play(UnitAnim.Anim.ATTACK)
	anim.advance(0.02)
	var during := Game.unit_hit_rect(u)
	_check(during.size.is_equal_approx(body.size),
		"кадр удара не раздувает бокс (%.1f×%.1f против %.1f×%.1f)"
			% [during.size.x, during.size.y, body.size.x, body.size.y])
	u.queue_free()


# --- 4. Дистанция боя ------------------------------------------------------

func _test_distance() -> void:
	var a := _make_unit(SET)
	var b := _make_unit(SET)
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(TILE, 0)          # соседняя клетка
	var near := Game.units_range(a, b)
	b.global_position = Vector2(TILE * 2, 0)      # через клетку
	var far := Game.units_range(a, b)
	b.global_position = Vector2(TILE * 3, 0)      # «три шага» из жалобы
	var far3 := Game.units_range(a, b)
	_check(near < 16.0, "соседняя клетка — тела рядом (зазор %.0f px)" % near)
	_check(far > near + 20.0, "через клетку — заметно дальше (%.0f)" % far)
	_check(far3 > 40.0, "три клетки — вне боя (%.0f; старый бокс 96 давал 0)" % far3)
	a.queue_free()
	b.queue_free()


# --- 5. Длина удара по оружию ----------------------------------------------

func _test_reach() -> void:
	var club := float(Game.REACH_BY_WEAPON.get("club", -1.0))
	var sword := float(Game.REACH_BY_WEAPON.get("sword", -1.0))
	var staff := float(Game.REACH_BY_WEAPON.get("staff", -1.0))
	var pike := float(Game.REACH_BY_WEAPON.get("pike", -1.0))
	_check(club > 0.0 and club < sword, "палица короче меча (%.0f < %.0f)" % [club, sword])
	_check(sword < staff, "посох длиннее меча (%.0f < %.0f)" % [sword, staff])
	_check(staff < pike, "копьё длиннее посоха (%.0f < %.0f)" % [staff, pike])
	_check(pike <= 24.0, "копьё не бьёт через две клетки (%.0f px)" % pike)
	_check(Game.REACH_DEFAULT > 0.0, "у монстров есть типовая длина удара")


# --- 6. Ауры по фигуре -----------------------------------------------------

func _test_aura_rows() -> void:
	var u := _make_unit(SET)
	get_root().add_child(u)
	u.global_position = Vector2.ZERO
	# Как в игре: узел анимации поднят на высоту рельефа (у героя ~25 px).
	var anim_node: Node2D = u.get_node("UnitAnim") as Node2D
	anim_node.position = Vector2(0, -20.0)
	var fig := Game.unit_local_rect(u)
	var h := fig.size.y
	var fire := SpellAura.attach(u, "resist", "Fire", "resist")
	var earth := SpellAura.attach(u, "resist", "Earth", "resist")
	_check(fire != null and earth != null, "ауры огня и земли созданы")
	if fire != null:
		# Обруч обязан подняться вместе с фигурой, а не стоять на земле.
		var shift_ok := absf(fire._sprite.position.y - (fire._base_offset - 20.0)) < 1.0
		_check(shift_ok, "обруч поднят вместе с фигурой (рельеф учитывается)")
		var up := -fire._base_offset                     # высота над ногами фигуры
		_check(up > h * 0.78,
			"огонь у ГОЛОВЫ: %.1f из %.1f px фигуры (было у живота)" % [up, h])
		var px := SpellVFX.sprite_px(fire._sprite)
		_check(px.y <= 24.0, "обруч тонкий: высота %.0f px" % px.y)
	if earth != null:
		var up2 := -earth._base_offset
		_check(up2 < h * 0.30, "земля у НОГ: %.1f из %.1f px" % [up2, h])
		# Обруч не должен свисать ПОД ноги: жалоба игрока 27.10.
		var bottom := up2 - SpellVFX.sprite_px(earth._sprite).y * 0.5
		_check(bottom >= 0.0,
			"обруч земли не уходит под ноги (низ %.1f px от подошв)" % bottom)
	u.queue_free()


func _finish() -> void:
	if _fails.is_empty():
		print("FIGURE: RESULT: OK")
	else:
		print("FIGURE: RESULT: FAIL (%d): %s" % [_fails.size(), str(_fails)])
	quit(0 if _fails.is_empty() else 1)
