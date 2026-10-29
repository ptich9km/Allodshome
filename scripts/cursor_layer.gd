extends CanvasLayer
## Тематический анимированный курсор игры.
##
## Заменяет системную стрелку и аллодовские курсоры (assets/cursors/) везде:
## меню, выбор персонажа, карта, редактор, прицел заклинаний/свитков.
## Механика прежняя (перенос из ui.gd, 22.10): системный курсор скрывается
## прозрачной 1×1 текстурой, поверх мышью водится Sprite2D с кадрами.
##
## Четыре набора кадров (assets/ui/cursor/<вариант>/ + cursor_meta.json):
##   normal — обычный курсор (анимированная стрела-перо);
##   cast   — курсор-прицел (каст заклинания/свитка);
##   buy    — магазин (монета и кошелёк);
##   work   — мастерская (кузнечный молот).
##
## Приоритет выбора: cast (Game.pending_spell/pending_scroll непусты) ->
## контекст (Game.cursor_context: "buy"/"work", ставит ui.gd в open_shop/
## open_workshop, сбрасывает в _on_panel_closed) -> normal.
##
## Если кадры варианта не найдены — падаем на normal; если кадров нет вовсе,
## курсор НЕ прячет системный: игра остаётся работоспособной до появления
## ассетов. Горячая точка берётся из cursor_meta.json (px холста 32×32).

const FRAME_TIME := 0.08  # сек на кадр анимации
const CANVAS := 32        # размер холста кадра (совпадает с нарезчиком)

const DIR_NORMAL := "res://assets/ui/cursor/normal"
const DIR_CAST := "res://assets/ui/cursor/cast"
const DIR_BUY := "res://assets/ui/cursor/buy"
const DIR_WORK := "res://assets/ui/cursor/work"

var _frames: Dictionary = {}          # вариант -> Array[Texture2D]
var _hotspots: Dictionary = {}        # вариант -> Vector2
var _sprite: Sprite2D = null
var _invisible_tex: ImageTexture = null
var _t := 0.0
var _i := 0
## Пока открыт диалог (FileDialog/PopupPanel — отдельный Window), спрайт
## курсора в главном вьюпорте не виден: возвращаем системную стрелку.
## Стартовое значение — `true` («системный ещё виден»), чтобы первый же вызов
## `_apply_system_cursor(false)` в _ready реально его спрятал. С `false`
## срабатывала ранняя проверка «состояние уже такое» и курсора было ДВА.
var _system_cursor := true
var _cursor_applied := false
const CURSOR_SHAPES := [
	Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_IBEAM,
	Input.CURSOR_CROSS, Input.CURSOR_WAIT, Input.CURSOR_BUSY,
	Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP, Input.CURSOR_FORBIDDEN,
	Input.CURSOR_VSIZE, Input.CURSOR_HSIZE,
]

func _ready() -> void:
	name = "CursorLayer"
	layer = 100  # выше UI-слоёв: курсор не прячется под панелями
	_ensure_loaded()
	if not _have_any_frames():
		# Ассетов нет: системный курсор остаётся, узел ждёт (файлы добавит импорт).
		set_process(false)
		return
	_sprite = Sprite2D.new()
	_sprite.name = "CursorSprite"
	_sprite.texture = _first_frame()
	add_child(_sprite)
	# Прячем системный курсор во ВСЕХ формах: кнопки проекта ставят
	# CURSOR_POINTING_HAND, поля ввода — IBEAM, иначе системная рука/бал
	# будет видна рядом с нашим спрайтом.
	_invisible_tex = _make_invisible_tex()
	_apply_system_cursor(false)
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)
	_queue_refresh()

func _have_any_frames() -> bool:
	for v in _frames.values():
		if not (v as Array).is_empty():
			return true
	return false

func _ensure_loaded() -> void:
	## Загрузка кадров четырёх вариантов; идемпотентна (для повторного вызова
	## из smoke-теста, где _ready в headless-скрипте не успевает сработать).
	if not _frames.is_empty():
		return
	for variant in ["normal", "cast", "buy", "work"]:
		var res := _load_frames(_dir_for(variant))
		_frames[variant] = res[0]
		_hotspots[variant] = res[1]

func _dir_for(variant: String) -> String:
	match variant:
		"cast": return DIR_CAST
		"buy": return DIR_BUY
		"work": return DIR_WORK
		_: return DIR_NORMAL

func _first_frame() -> Texture2D:
	for variant in ["normal", "cast", "buy", "work"]:
		var arr: Array = _frames[variant]
		if not arr.is_empty():
			return arr[0]
	return null

func _make_invisible_tex() -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

func _load_frames(dir_path: String) -> Array:
	## [кадры, hotspot]. Нарезчик всегда кладёт ровно 4 кадра с фиксированными
	## именами cursor-000..003, поэтому грузим по имени — без обхода каталога
	## (DirAccess по res:// ненадёжен в headless-режиме).
	var frames: Array = []
	var hotspot := CANVAS * 0.5 * Vector2.ONE
	for i in range(4):
		var tex: Variant = load("%s/cursor-%03d.png" % [dir_path, i])
		if tex != null:
			frames.append(tex)
	var meta_txt := FileAccess.get_file_as_string(dir_path + "/cursor_meta.json")
	if meta_txt != "":
		var parsed: Variant = JSON.parse_string(meta_txt)
		if parsed is Dictionary and parsed.has("hotspot"):
			var hs: Array = parsed["hotspot"]
			if hs.size() == 2:
				hotspot = Vector2(float(hs[0]), float(hs[1]))
	return [frames, hotspot]

## Текущий вариант курсора: cast > контекст (buy/work) > normal.
func _current_variant() -> String:
	if not Game.pending_spell.is_empty() or not Game.pending_scroll.is_empty():
		if not (_frames["cast"] as Array).is_empty():
			return "cast"
	var ctx: String = Game.cursor_context
	if (ctx == "buy" or ctx == "work") and not (_frames[ctx] as Array).is_empty():
		return ctx
	var normal: Array = _frames["normal"]
	if not normal.is_empty():
		return "normal"
	for variant in ["cast", "buy", "work"]:
		if not (_frames[variant] as Array).is_empty():
			return variant
	return ""

func _process(delta: float) -> void:
	if _sprite == null:
		return
	# Диалог (FileDialog/PopupPanel) — отдельный Window со своим вьюпортом,
	# наш спрайт туда не рисуется. Включаем системную стрелку на время диалога.
	if _extra_window_open():
		_apply_system_cursor(true)
		_sprite.visible = false
		return
	_apply_system_cursor(false)
	var variant := _current_variant()
	if variant == "":
		_sprite.visible = false
		return
	var frames: Array = _frames[variant]
	var hotspot: Vector2 = _hotspots[variant]
	_sprite.visible = true
	_sprite.global_position = get_viewport().get_mouse_position()
	_sprite.offset = CANVAS * 0.5 * Vector2.ONE - hotspot
	if _i >= frames.size():
		_i = 0
	_sprite.texture = frames[_i]
	_t += delta
	if _t >= FRAME_TIME:
		_t = 0.0
		_i = (_i + 1) % frames.size()


## Открыт ли поверх главного окна ещё один Window (диалог, попап, файловый
## выбор). В его вьюпорте наш CanvasLayer не действует — там нужен системный
## курсор, иначе он «исчезает» (жалоба игрока 29.10).
func _extra_window_open() -> bool:
	return _open_windows > 0


var _open_windows := 0
var _refresh_queued := false

## Пересчитать открытые дочерние окна. Вызывается по событиям дерева и
## `visibility_changed`, а не каждый кадр: обход всей сцены в _process стоил бы
## дорого на живой карте.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_open_windows.call_deferred()


func _refresh_open_windows() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	var main := get_viewport().get_window() if get_viewport() != null else null
	_open_windows = _count_visible_windows(get_tree().root, main)


func _count_visible_windows(node: Node, main: Window) -> int:
	var total := 0
	for c in node.get_children():
		if c is Window:
			var w := c as Window
			if w != main:
				if not w.visibility_changed.is_connected(_on_window_visibility):
					w.visibility_changed.connect(_on_window_visibility)
				if w.visible:
					total += 1
		total += _count_visible_windows(c, main)
	return total


func _on_window_visibility() -> void:
	_queue_refresh()


func _on_tree_changed(_n: Node = null) -> void:
	_queue_refresh()


## Переключить системный курсор: true — показать стрелку, false — спрятать
## (вместо него рисуется наш спрайт).
func _apply_system_cursor(on: bool) -> void:
	if _system_cursor == on:
		return
	_system_cursor = on
	_cursor_applied = true
	var tex: Texture2D = null if on else _invisible_tex
	for shape in CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(tex, shape, Vector2.ZERO)
