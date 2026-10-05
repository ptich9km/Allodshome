class_name MenuBackdrop
extends Node2D
## Живой фон главного меню: настоящая карта, плавно плывущая камера.
##
## Требование игрока было — «заставка из анимации игры, а не статичная картинка»
## (как X4 Foundations и Space Engineers). Здесь так и сделано: грузится реальный
## `.alm`, деревья качаются штатной анимацией `AlmObstacle`, а «камера» — это
## сглаженное движение самого узла.
##
## ## Почему БЕЗ Camera2D
##
## `Camera2D` трансформирует canvas слоя 0, а `Control` главного меню живёт
## на слое 0 — камера увлекла бы за собой интерфейс. Поэтому `Backdrop`
## двигается сам, а интерфейс вынесен в `CanvasLayer` (см. main_menu.gd).
##
## ## Почему НЕ трогаем `Game.*`
##
## `Game` — `class_name` со `static var`, и они переживают смену сцены.
## `game.gd:_quit_to_menu()` НЕ обнуляет `map_seed`/`pending_map_path`, поэтому
## при возврате в меню `AlmMap._resolve_map_path()` подхватил бы КАРТУ ИГРОКА
## вместо фона. Здесь статики глушатся на время создания карты и
## восстанавливаются: меню не имеет права менять состояние игры.
##
## ## Содержимое
##
## Только террейн и деревья — по решению игрока. Юниты не спавнятся намеренно:
## NPC требуют порядка добавления в дерево (ищут группу `alm_map` в `_ready`),
## монстры без цели замирают (`enemy.gd`), и у каждого монстра есть полоска HP,
## которая в меню читается как HUD.

## Предзапечённая карта. Генерировать в рантайме нельзя: `MapGenerator`
## пересобирает устаревший кэш в `user://maps` (там лежит gen_version 5 при
## GEN_VERSION 10), и меню стартовало бы с генерации 128x128 — то есть с
## паузы на старте игры.
const MAP_PATH := "res://assets/maps/menu/menu_backdrop.alm"

## Лучшее окно обзора выбрано замером, а не на глаз:
##   godot --headless --script res://tests/analyze_menu_backdrop.gd
## seed 7777, зона mid -> trees=15, биомов 4, воды 62 в окне 20x13.
## Первая версия анализатора выбрала (58, 114) — окно у самого нижнего края
## карты, где камера выходила за последнюю клетку. Теперь анализатор требует
## запас = половина окна + радиус дрейфа.
const DRIFT_ORIGIN := Vector2i(56, 35)

## Обход камеры. Пиксели, не клетки: узел смещается в мировых координатах.
##
## Скорость подобрана ДВАЖДЫ замером, и обе крайности игрок отверг:
##   * 4.5 px/с  — «никакой анимации нет» (первая попытка);
##   * 95 px/с  — «камера быстро движется» (вторая попытка).
## Сейчас ~23 px/с: медленный проход, который читается как живой мир, но не
## укатывает сцену. Замер идёт по заданному времени `_process(1.0)`, а не по
## кадрам: в headless 60 кадров — доли секунды, и замер по кадрам врал бы.
const DRIFT_RADIUS := Vector2(230.0, 130.0)
const DRIFT_SPEED := 0.10
## Окно обзора в клетках — столько влезает в экран при зуме 2.
const VIEW_CELLS := Vector2(20, 13)

var _map: AlmMap
var _anchor := Vector2.ZERO
var _phase := 0.0
var _started := false

## Статики Game, затлушенные на время создания карты.
var _saved_seed: int
var _saved_zone: String
var _saved_path: String


func _ready() -> void:
	# Меню живёт и при паузе, иначе фон замирает на экране загрузки.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_map()
	set_process(_started)


## Ставит карту, глуша статики Game на время её создания.
func _build_map() -> void:
	_saved_seed = Game.map_seed
	_saved_zone = Game.map_zone
	_saved_path = Game.pending_map_path
	Game.map_seed = 0
	Game.pending_map_path = ""
	Game.map_zone = "mid"

	_map = AlmMap.new()
	_map.name = "Map"
	_map.alm_path = MAP_PATH
	add_child(_map)

	# Возврат статик — сразу, а не «когда-нибудь»: если карта не загрузилась,
	# состояние игры всё равно должно остаться нетронутым.
	Game.map_seed = _saved_seed
	Game.map_zone = _saved_zone
	Game.pending_map_path = _saved_path

	if _map.map_width <= 0 or _map.map_height <= 0:
		push_warning("MenuBackdrop: фон не загрузился (%s)" % MAP_PATH)
		return

	# Карта рисуется от мирового (0,0). Чтобы в центре экрана оказался ЦЕНТР
	# измеренного окна, узел надо сдвинуть в минус от его координат.
	# Первая версия складывала плюсом, и камера смотрела на окно, смещённое
	# на (+10, +6.5) клетки от измеренного — то есть на неизвестный участок.
	var window_center := Vector2(DRIFT_ORIGIN) + Vector2(VIEW_CELLS) * 0.5
	var viewport_center := Vector2(1280, 800) * 0.5
	_anchor = viewport_center - window_center * float(_map.tile_size)
	position = _anchor
	_started = true


## Медленный обход по эллипсу. Скорость намеренно мала: это фон, а не демо.
func _process(delta: float) -> void:
	if not _started:
		return
	_phase += delta * DRIFT_SPEED
	position = _clamp_to_map(_anchor + Vector2(
		cos(_phase) * DRIFT_RADIUS.x,
		sin(_phase) * DRIFT_RADIUS.y))


## Не даём камере уехать за край карты.
##
## Обнаружено проверкой: окно обзора центрировано на клетке (68, 120.5), а
## дрейф по вертикали ±150 px — это ±4.7 клетки. Внизу камера выходила за
## нижний край 128-й клетки, и на экране было пустое место вместо земли.
## Клетка 0 карты рисуется в позиции узла, поэтому допустимый диапазон
## положения — это ровно [размер экрана − размер карты; 0].
func _clamp_to_map(target: Vector2) -> Vector2:
	if not is_instance_valid(_map):
		return target
	var ts := float(_map.tile_size)
	var map_px := Vector2(float(_map.map_width) * ts, float(_map.map_height) * ts)
	var vp := Vector2(1280, 800)
	var lo := vp - map_px
	return Vector2(
		clampf(target.x, minf(lo.x, 0.0), 0.0),
		clampf(target.y, minf(lo.y, 0.0), 0.0))


## Для теста: двигается ли фон и не замер ли он.
func drift_sample() -> Vector2:
	return position


func is_ready_backdrop() -> bool:
	return _started


## Деревья анимируются? Проверяется по живым узлам карты.
func animated_objects() -> int:
	if not is_instance_valid(_map):
		return 0
	var n := 0
	for child in _map.get_children():
		if child is AlmObstacle or child is PortalMarker:
			if child.is_processing():
				n += 1
	return n


func map_node() -> AlmMap:
	return _map