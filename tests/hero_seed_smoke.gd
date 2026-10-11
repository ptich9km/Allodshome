## Сторож геройского набора seedream (heroes/sw_seed) — пилот 10.10.
##
## Проверяет инварианты, которые нарезка обязана держать, иначе набор молча
## ломает анимацию в игре:
## - в базе ровно столько кадров, сколько лежит файлов, и все грузятся;
## - холст 64x64 (контракт ork_mage_a52), высота контента 52, низ на y=62;
## - блоки idle/move/attack не пересекаются и покрывают кадры без дыр;
## - в кадре не осталось пурпурного фона (seedream рисует его как '#FF00FF');
## - кадры не пустые и не превратились в прямоугольник (фигура не вырезана).
##
## Запуск:
##   godot --headless --path . --script res://tests/hero_seed_smoke.gd

extends SceneTree

const SET := "seed/sw_seed"
const CANVAS := 64
const CONTENT_H := 52
const FEET_Y := 62
const DIRS := 8
const IDLE_PHASES := 8
const MOVE_PHASES := 2
const ATTACK_PHASES := 2
const TOTAL := IDLE_PHASES + MOVE_PHASES * DIRS + ATTACK_PHASES * DIRS

var _checks := 0
var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)


func _run() -> void:
	var o: Dictionary = UnitDB.get_set(SET)
	_check(not o.is_empty(), "набор %s есть в units_db" % SET)
	if o.is_empty():
		_finish()
		return

	_check(int(o.get("frames", -1)) == TOTAL,
		"frames в базе = %d (ожидалось %d)" % [int(o.get("frames", -1)), TOTAL])
	_check(int(o.get("dirs", -1)) == DIRS, "dirs = 8, иначе зеркало не отработает")
	_check(int(o.get("idle_phases", -1)) == IDLE_PHASES, "idle_phases = 8")
	_check(int(o.get("move", -1)) == MOVE_PHASES, "move = 2")
	_check(int(o.get("attack", -1)) == ATTACK_PHASES, "attack = 2")
	_check(int(o.get("w", 0)) == CANVAS and int(o.get("h", 0)) == CANVAS,
		"холст в базе 64x64")
	_check(int(o.get("cy", 0)) == FEET_Y, "cy = 62 (точка земли)")

	var folder := str(o.get("folder", SET))
	var prefix := str(o.get("prefix", "sprites"))
	var n := UnitDB.frame_count(SET)
	_check(n == TOTAL, "файлов на диске = %d (ожидалось %d)" % [n, TOTAL])

	for i in range(TOTAL):
		var path := UnitDB.frame_path(folder, prefix, i + 1)
		if not ResourceLoader.exists(path):
			_check(false, "нет текстуры %s" % path)
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			_check(false, "текстура не грузится %s" % path)
			continue
		var img := tex.get_image()
		if img == null:
			_check(false, "нет изображения %s" % path)
			continue
		_check(img.get_width() == CANVAS and img.get_height() == CANVAS,
			"кадр %d: холст %dx%d (ожидалось 64x64)" % [i + 1, img.get_width(), img.get_height()])

		var bb := _content_bbox(img)
		if bb == Rect2i():
			_check(false, "кадр %d пустой" % (i + 1))
			continue
		_check(bb.size.y == CONTENT_H,
			"кадр %d: высота контента %d (ожидалось %d)" % [i + 1, bb.size.y, CONTENT_H])
		_check(bb.position.y + bb.size.y - 1 == FEET_Y,
			"кадр %d: низ контента y=%d (ожидалось %d)"
			% [i + 1, bb.position.y + bb.size.y - 1, FEET_Y])
		_check(bb.size.x < bb.size.y,
			"кадр %d: ширина %d при высоте %d - похоже, что вырезан прямоугольник"
			% [i + 1, bb.size.x, bb.size.y])
		_check(bb.size.x >= 8,
			"кадр %d: ширина %d - фигура срезана" % [i + 1, bb.size.x])
		_check(_magenta_px(img) <= 4,
			"кадр %d: осталось пурпурных пикселей %d" % [i + 1, _magenta_px(img)])

	_test_block_layout()
	_finish()


## Блоки фаз не должны наезжать друг на друга: смещение считается как
## idle + move*dirs и idle + move*dirs + attack*dirs.
func _test_block_layout() -> void:
	var seen := {}
	for d in range(DIRS):
		var idle_idx := d
		_check(not seen.has(idle_idx), "кадр %d занят дважды" % idle_idx)
		seen[idle_idx] = true
		for p in range(MOVE_PHASES):
			var m := IDLE_PHASES + d * MOVE_PHASES + p
			_check(not seen.has(m), "ходьба налезает на другой блок: %d" % m)
			seen[m] = true
		for p in range(ATTACK_PHASES):
			var a := IDLE_PHASES + MOVE_PHASES * DIRS + d * ATTACK_PHASES + p
			_check(not seen.has(a), "атака налезает на другой блок: %d" % a)
			seen[a] = true
	_check(seen.size() == TOTAL,
		"блоки покрывают %d кадров из %d" % [seen.size(), TOTAL])


func _content_bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.15:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _magenta_px(img: Image) -> int:
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			if float(c.r) - float(c.g) > 0.17 and float(c.b) - float(c.g) > 0.15:
				n += 1
	return n


func _finish() -> void:
	if _fails.is_empty():
		print("RESULT: OK hero_seed_smoke (проверок: %d, провалов: 0)" % _checks)
	else:
		for f in _fails:
			print("  FAIL %s" % f)
		print("RESULT: FAIL hero_seed_smoke (проверок: %d, провалов: %d)"
			% [_checks, _fails.size()])
	quit(1 if _fails.size() > 0 else 0)