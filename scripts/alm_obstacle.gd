class_name AlmObstacle
extends Node2D
## НЕПОДВИЖНЫЙ объект карты-препятствие (.alm obstacle): дерево/камень/статуя.
## Отрисовка и анимация как в Allods16: спрайт с якорем (cx,cy), поднимается
## на высоту рельефа под собой, кадры (sprites-001..00N) листаются по таймеру.

var folder := ""            # имя папки спрайтов: "pine1", "maple2/dead"
var frame_count := 1
var reg_w := 128            # размер из реестра (для нормировки якоря)
var reg_h := 128
var cx := 64.0              # якорь в пикселях реестра
var cy := 80.0

var _frame := 0
var _timer := 0.0
var _sprite: Sprite2D
var _tex_w := 32
var _tex_h := 32
var _frames_dir := ""       # каталог кадров

const FRAME_TIME := 0.5     # секунд на кадр (как у ObjectDB.DEFAULT_FRAME_TIME)

func setup(obs_folder: String, n_frames: int, w: int, h: int, a_cx: int, a_cy: int) -> void:
	folder = obs_folder
	frame_count = maxi(n_frames, 1)
	reg_w = maxi(w, 1)
	reg_h = maxi(h, 1)
	cx = float(a_cx)
	cy = float(a_cy)
	_frames_dir = "res://assets/map-objects/%s" % folder
	# Реально существующие кадры: папка может иметь меньше кадров, чем phases
	var dir := DirAccess.open(_frames_dir)
	var max_frames := 0
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.begins_with("sprites-") and fn.ends_with(".png"):
				var num := int(fn.trim_prefix("sprites-").trim_suffix(".png"))
				max_frames = maxi(max_frames, num)
			fn = dir.get_next()
		dir.list_dir_end()
	if max_frames > 0:
		frame_count = mini(frame_count, max_frames)
	else:
		# Папки нет совсем (например fire-варианты не извлечены) — не рисовать
		frame_count = 0
	_apply_frame()

func _apply_frame() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.centered = false
		add_child(_sprite)
	if frame_count <= 0:
		visible = false
		return
	var idx: int = _frame % frame_count
	var tex: Variant = load("%s/sprites-%03d.png" % [_frames_dir, idx + 1])
	if tex == null:
		visible = false
		return
	visible = true
	_sprite.texture = tex
	_tex_w = tex.get_width()
	_tex_h = tex.get_height()

## Позиция: центр клетки + якорь (доля от реестрового размера) как в Allods16.
func place_at(cell: Vector2i, tile: int, relief: float) -> void:
	var x := cell.x * tile + tile / 2.0
	var y := cell.y * tile + tile / 2.0 - relief
	position = Vector2(
		x - cx / float(reg_w) * float(_tex_w),
		y - cy / float(reg_h) * float(_tex_h))

func _process(delta: float) -> void:
	if frame_count <= 1:
		return
	_timer += delta
	if _timer >= FRAME_TIME:
		_timer = 0.0
		_frame = (_frame + 1) % frame_count
		_apply_frame()