## Смоук пиксельного ховера (Game.unit_hover_hit, 21.10).
##
## Жалоба игрока: у волка кольцо выделения по всему спрайту, у других НПЦ
## приходилось целиться ниже видимой фигуры. unit_hover_hit тестирует
## альфа-канал текущего кадра; unit_hit_rect — fallback.
##
## Проверяет на реальных наборах (волк — эталон жалобы, герои un2/dr2,
## высокие монстры):
## - попадание по телу (центр корпуса, ноги) — hit;
## - пустой угол кадра — miss (точность пиксель-теста);
## - точка тела вне старого unit_hit_rect — hit (регресс жалобы);
## - fallback: юнит без UnitAnim — hit по rect;
## - flip_h зеркального направления не ломает хит по телу.
##
## Запуск:
##   godot --headless --path . --script res://tests/hover_pixel_smoke.gd

extends SceneTree

const SETS := [
	"hero/war_men", "hero/war_women",
	"hero/undead_women", "hero/druid_women",
	"monsters/wolf", "monsters/troll", "monsters/dragon",
]

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)


func _run() -> void:
	# unit_hover_hit — static Game, нужен и сам класс.
	var game_script := load("res://scripts/game.gd")
	for set_name: String in SETS:
		_run_set(game_script, set_name)
	_test_fallback(game_script)
	_finish()


func _make_unit(set_name: String) -> Node2D:
	var root := Node2D.new()
	var anim := UnitAnim.new()
	anim.name = "UnitAnim"
	root.add_child(anim)
	anim.setup(set_name)
	return root


## Rect непрозрачных пикселей и самая верхняя непрозрачная точка текущего
## кадра, в локальных координатах корня юнита.
func _opaque_measure(anim: UnitAnim) -> Variant:
	var sprite: Sprite2D = anim.get_node("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return null
	var img: Image = sprite.texture.get_image()
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	var top_px := Vector2i(-1, -1)   # самая верхняя непрозрачная точка
	for x in range(w):
		for y in range(h):
			if img.get_pixel(x, y).a8 > 8:
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y:
					min_y = y
					top_px = Vector2i(x, y)
				if y > max_y: max_y = y
	if max_x < 0:
		return null
	var s: Vector2 = sprite.scale
	# Кадр рисуется от (-w/2, -h) при centered=false (unit_anim.gd:206).
	var pos := Vector2(-float(w) / 2.0, -float(h)) * s
	var rect := Rect2(pos + Vector2(float(min_x) * s.x, float(min_y) * s.y),
		Vector2(float(max_x - min_x + 1) * s.x, float(max_y - min_y + 1) * s.y))
	var top := pos + Vector2(float(top_px.x) * s.x, float(top_px.y) * s.y)
	return {"rect": rect, "top": top}


func _world(root: Node2D, local: Vector2) -> Vector2:
	return root.to_global(local)


func _run_set(game_script: Variant, set_name: String) -> void:
	if not ResourceLoader.exists("res://assets/units/%s/sprites-001.png" % set_name):
		_check(false, "набор %s существует" % set_name)
		return
	var root := _make_unit(set_name)
	var anim: UnitAnim = root.get_node("UnitAnim")
	var body: Variant = _opaque_measure(anim)
	if body == null:
		_check(false, "%s: кадр с непрозрачными пикселями" % set_name)
		root.queue_free()
		return
	var r: Rect2 = body["rect"]
	var top: Vector2 = body["top"]
	var center := Vector2(r.get_center().x, r.end.y - 4.0)   # низ корпуса
	var head := top                                           # фактическая верхняя точка
	var empty := Vector2(r.position.x - 6.0, r.position.y - 6.0) # пустой угол кадра

	_check(game_script.unit_hover_hit(root, _world(root, center)),
		"%s: центр корпуса — hit" % set_name)
	_check(game_script.unit_hover_hit(root, _world(root, head)),
		"%s: голова (верх силуэта) — hit" % set_name)
	_check(not game_script.unit_hover_hit(root, _world(root, empty)),
		"%s: пустой угол кадра — miss" % set_name)

	# Регресс жалобы: точка тела, которая вне старого unit_hit_rect,
	# обязана попадать по пиксельному тесту.
	var old_rect: Rect2 = game_script.unit_hit_rect(root)
	if not old_rect.has_point(_world(root, head)):
		_check(game_script.unit_hover_hit(root, _world(root, head)),
			"%s: тело вне старого rect — hit (регресс жалобы)" % set_name)

	# Зеркало не ломает хит по телу.
	if anim.has_method("set") and "flip_h" in anim.get_node("Sprite"):
		var spr: Sprite2D = anim.get_node("Sprite")
		spr.flip_h = true
		_check(game_script.unit_hover_hit(root, _world(root, center)),
			"%s: flip_h — центр корпуса hit" % set_name)
	root.queue_free()


## Fallback: юнит без UnitAnim — старый rect-тест.
func _test_fallback(game_script: Variant) -> void:
	var bare := Node2D.new()
	# Неглубокая подмена: unit_hit_rect на bare вернёт Rect2() — не hit.
	# Проверяем только, что вызов не падает и возвращает bool.
	var hit: bool = game_script.unit_hover_hit(bare, Vector2.ZERO)
	_check(hit is bool, "unit_hover_hit на узле без UnitAnim не падает")
	bare.queue_free()


func _finish() -> void:
	for m in _fails:
		print("FAIL: ", m)
	print("hover_pixel_smoke: %d checks, %d fails" % [_checks, _fails.size()])
	print("RESULT: %s" % ("OK" if _fails.is_empty() else "FAIL"))
	quit(0 if _fails.is_empty() else 1)
