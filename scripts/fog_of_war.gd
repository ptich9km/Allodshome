extends Node2D
class_name FogOfWar
## Туман войны на карте героя (RTS-стиль, пакет 19.10).
##
## Три состояния на клетку:
##   0 - неисследовано (почти чёрное),
##   1 - исследовано, вне зрения (приглушено),
##   2 - видно сейчас.
##
## Почему маска на клетках, а не источник света: карта - это байт на клетку;
## пересчёт только при смене клетки героем, обновляется ТОЛЬКО изменённый
## регион (спайки при каждом шаге давали «подергивания» на картах 192×192).
## Вне видимости юниты скрываются (enemy/npc.gd), что вместе с чанками
## террейна разгружает CPU - шаг к картам большего размера.
##
## LOS («видна ли клетка за деревом») в v1 нет: открывается по радиусу.

signal updated

const STATE_BLACK := 0
const STATE_EXPLORED := 1
const STATE_VISIBLE := 2

const RADIUS_CELLS := 14   # радиус видимости, клеток
const EDGE_CELLS := 2      # приглушённое кольцо за радиусом

## Цвета мини-карты (RGBA8 1px/клетку; visible = прозрачный).
const MINI_BLACK := Color(0.02, 0.02, 0.03, 0.95)
const MINI_EXPLORED := Color(0.0, 0.0, 0.0, 0.55)
const MINI_VISIBLE := Color(0.0, 0.0, 0.0, 0.0)

var enabled: bool = false
var map_node: Node2D = null
var width := 0
var height := 0
var mask := PackedByteArray()    # byte на клетку: STATE_*
## Слой для миникарты (ui.gd): цвет по состоянию, обновляется точечно.
var mini_img: Image = null

var _layer: Sprite2D = null
var _img: Image = null           # FORMAT_RF, значение = размытое состояние/2
var _tex: ImageTexture = null
var _last_cell := Vector2i(-1, -1)
var _visible := {}   # клетки текущего диска видимости (Vector2i -> true)

const FOG_SHADER := """shader_type canvas_item;
uniform sampler2D u_mask : filter_linear, repeat_disable;
uniform vec3 u_black : source_color = vec3(0.04, 0.04, 0.07);
void fragment() {
	float v = texture(u_mask, UV).r;
	float d = mix(0.97, 0.45, smoothstep(0.22, 0.42, v));
	d = mix(d, 0.0, smoothstep(0.55, 0.75, v));
	COLOR = vec4(u_black, d);
}"""

func _ready() -> void:
	add_to_group("fog")
	z_index = 99
	enabled = GameConfig.geti("debug", "fog_of_war") != 0
	Game.fog = self
	_setup()
	tree_exiting.connect(_on_exiting)

func _on_exiting() -> void:
	if Game.fog == self:
		Game.fog = null

## Привязка к карте. Вызывается из _ready и заново, если карта сменилась
## (переход через портал пересобирает карту).
func _setup() -> void:
	map_node = get_tree().get_first_node_in_group("alm_map")
	var w := 0
	var h := 0
	if map_node != null:
		w = int(map_node.get("map_width"))
		h = int(map_node.get("map_height"))
	if w <= 0 or h <= 0:
		width = 0
		height = 0
		mask = PackedByteArray()
		mini_img = null
		if _layer != null:
			_layer.visible = false
		return
	width = w
	height = h
	_last_cell = Vector2i(-1, -1)
	mask.resize(width * height)
	mask.fill(STATE_BLACK if enabled else STATE_VISIBLE)
	_build_layer()
	_refresh_full()
	if enabled:
		_rebuild_visible_set()
	# Маска из сейва (19.10): применяется один раз при сборке карты.
	if enabled and Game.pending_fog_rle != "":
		if apply_rle(Game.pending_fog_rle):
			Game.pending_fog_rle = ""
	else:
		Game.pending_fog_rle = ""

func _build_layer() -> void:
	if _layer == null:
		_layer = Sprite2D.new()
		_layer.name = "FogLayer"
		_layer.centered = false
		add_child(_layer)
	var tile := 32
	if map_node != null:
		tile = int(map_node.get("tile_size"))
	_layer.position = Vector2.ZERO
	_layer.scale = Vector2(tile, tile)
	_layer.visible = enabled
	if _layer.material == null:
		var mat := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = FOG_SHADER
		mat.shader = shader
		_layer.material = mat

## Размытое состояние клетки: среднее состояний 3×3 (0/1/2 → 0..2, /2).
## Хранится в FORMAT_RF-текстуре; шейдер гладит порогами.
func _blurred_at(x: int, y: int) -> float:
	var sum := 0.0
	var cnt := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			sum += float(mask[ny * width + nx])
			cnt += 1
	if cnt == 0:
		return 0.0
	return sum / float(cnt) * 0.5

func _write_cell(x: int, y: int, v: float) -> void:
	_img.set_pixel(x, y, Color(v, 0.0, 0.0, 1.0))
	if mini_img != null:
		var s := int(round(v * 2.0))
		var col := MINI_VISIBLE if s >= STATE_VISIBLE \
			else (MINI_EXPLORED if s >= STATE_EXPLORED else MINI_BLACK)
		mini_img.set_pixel(x, y, col)

## Полная пересборка изображения (один раз на карту и после apply_rle).
func _refresh_full() -> void:
	if width <= 0 or height <= 0:
		return
	if _img == null or _img.get_width() != width or _img.get_height() != height:
		_img = Image.create(width, height, false, Image.FORMAT_RF)
	if mini_img == null or mini_img.get_width() != width:
		mini_img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			_write_cell(x, y, _blurred_at(x, y))
	_ensure_tex()
	updated.emit()

## Точечное обновление: сами клетки + их окрестность (блюр 3×3 по состояниям).
## Сотни set_pixel вместо десятков тысяч - без спайков при каждом шаге.
func _refresh_region(cells: Array) -> void:
	if _img == null or cells.is_empty():
		return
	var seen := {}
	for c_v in cells:
		var c: Vector2i = c_v
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := c.x + dx
				var ny := c.y + dy
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				var key := ny * width + nx
				if seen.has(key):
					continue
				seen[key] = true
				_write_cell(nx, ny, _blurred_at(nx, ny))
	_ensure_tex()
	updated.emit()

func _ensure_tex() -> void:
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
		# БЕЗ текстуры спрайт ничего не рисует - это была причина
		# «невидимого тумана» (19.10).
		_layer.texture = _tex
	else:
		_tex.update(_img)

## Открыть диск вокруг клетки: видимое r=RADIUS, приглушённое кольцо за ним.
## Клетки, ВЫШЕДШИЕ из радиуса, опускаются 2 -> 1: иначе весь пройденный
## путь навсегда оставался «видимым» (баг из проверки 19.10).
## Вызывается и тестами напрямую (без героя).
func reveal_around(cell: Vector2i) -> void:
	if width <= 0 or height <= 0:
		return
	var r2 := RADIUS_CELLS * RADIUS_CELLS
	var changed: Array = []
	var now_visible := {}
	for dy in range(-RADIUS_CELLS, RADIUS_CELLS + 1):
		var y := cell.y + dy
		if y < 0 or y >= height:
			continue
		for dx in range(-RADIUS_CELLS, RADIUS_CELLS + 1):
			var x := cell.x + dx
			if x < 0 or x >= width:
				continue
			if dx * dx + dy * dy > r2:
				continue
			var i := y * width + x
			now_visible[Vector2i(x, y)] = true
			if mask[i] < STATE_VISIBLE:
				mask[i] = STATE_VISIBLE
				changed.append(Vector2i(x, y))
	for c in _visible:
		if now_visible.has(c):
			continue
		var ci := (c as Vector2i).y * width + (c as Vector2i).x
		if mask[ci] == STATE_VISIBLE:
			mask[ci] = STATE_EXPLORED
			changed.append(c as Vector2i)
	_visible = now_visible
	# Приглушённое кольцо за радиусом (кромка разведанного).
	var e_span := RADIUS_CELLS + EDGE_CELLS
	var e2 := e_span * e_span
	for dy in range(-e_span, e_span + 1):
		var y2 := cell.y + dy
		if y2 < 0 or y2 >= height:
			continue
		for dx in range(-e_span, e_span + 1):
			var x2 := cell.x + dx
			if x2 < 0 or x2 >= width:
				continue
			var d2 := dx * dx + dy * dy
			if d2 <= r2 or d2 > e2:
				continue
			var i2 := y2 * width + x2
			if mask[i2] < STATE_EXPLORED:
				mask[i2] = STATE_EXPLORED
				changed.append(Vector2i(x2, y2))
	if not changed.is_empty():
		_refresh_region(changed)

func state_at(cell: Vector2i) -> int:
	if not enabled or width <= 0:
		return STATE_VISIBLE
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return STATE_VISIBLE   # за границей карты ничего не прячем
	return mask[cell.y * width + cell.x]

func state_at_world(pos: Vector2) -> int:
	var tile := 32
	if map_node != null and is_instance_valid(map_node):
		tile = int(map_node.get("tile_size"))
	return state_at(Vector2i(int(pos.x) / tile, int(pos.y) / tile))

## Юнит вне видимой клетки не тикает и не рисуется (enemy.gd/npc.gd).
func blocks_process(pos: Vector2) -> bool:
	return state_at_world(pos) < STATE_VISIBLE

func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	# Карта могла пересобраться (портал) — проверяем по размеру.
	if map_node == null or not is_instance_valid(map_node) \
			or int(map_node.get("map_width")) != width:
		_setup()
		if width <= 0:
			return
	if Game.hero == null or not is_instance_valid(Game.hero):
		return
	var tile := int(map_node.get("tile_size"))
	var cell := Vector2i(
		int(Game.hero.global_position.x) / tile,
		int(Game.hero.global_position.y) / tile)
	if cell == _last_cell:
		return
	_last_cell = cell
	reveal_around(cell)

## Пересобрать множество видимых клеток (после _setup и apply_rle).
func _rebuild_visible_set() -> void:
	_visible.clear()
	for y in range(height):
		for x in range(width):
			if mask[y * width + x] == STATE_VISIBLE:
				_visible[Vector2i(x, y)] = true

## --- Сохранение маски (save_system.gd, payload.map.fog) -------------------

## Маска в компактную строку для сейва: RLE-пары (длина, значение) + base64.
## Пустая строка — туман выключен или карты нет, сейву нечего хранить.
func mask_rle() -> String:
	if not enabled or width <= 0:
		return ""
	return rle_encode(mask)

func apply_rle(data: String) -> bool:
	if data.is_empty() or width <= 0:
		return false
	var decoded := rle_decode(data, width * height)
	if decoded.size() != width * height:
		return false
	mask = decoded
	_refresh_full()
	_rebuild_visible_set()
	return true

static func rle_encode(m: PackedByteArray) -> String:
	var out := PackedByteArray()
	var i := 0
	while i < m.size():
		var v := m[i]
		var run := 1
		while i + run < m.size() and m[i + run] == v and run < 255:
			run += 1
		out.append(run)
		out.append(v)
		i += run
	return Marshalls.raw_to_base64(out)

static func rle_decode(data: String, expected: int) -> PackedByteArray:
	var out := PackedByteArray()
	var raw := Marshalls.base64_to_raw(data)
	if raw.is_empty():
		return out
	var i := 0
	while i + 1 < raw.size() and out.size() < expected:
		var run := raw[i]
		var v := raw[i + 1]
		for _k in range(run):
			if out.size() >= expected:
				break
			out.append(v)
		i += 2
	return out
