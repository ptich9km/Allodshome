class_name StructureNode
extends Node2D
## Здание из .alm (структура). Собирает сетку тайлов fw×fh из кадров
## house-001..N (папка из StructureDB), добавляет тень houseb и анимацию фаз.
##
## Раскладка кадров: файл хранит блоки — база (первые fw*fh кадров) и при
## Phases>1 дополнительные блоки-фазы по той же сетке. Номер кадра тайла:
##   frame = block * (fw*fh) + (fw*ly + lx) + 1
## Число блоков = реальное число кадров / сетку (автоопределение).

const TILE := 32  # размер тайла структуры

var folder := ""          # папка спрайтов ("mill1", "church")
var fw := 1               # тайлов по X
var th := 1               # корпус по Y (стоит на этих рядах)
var fh := 1               # всего рядов по Y
var sel_box := Rect2i(0, 0, 96, 96)  # хитбокс выделения [x1,y1,w,h]
var shadow_y := 0         # сдвиг тени по Y из реестра
var use_anim := true      # проигрывать анимацию фаз, если есть
var max_blocks := 0       # ограничение числа блоков (0 = без ограничений)

var _blocks := 1          # число блоков кадров (база + фазы)
var _valid_blocks: Array = [0]  # блоки, пригодные для анимации (0 = база)
var _tiles: Array = []    # Sprite2D по тайлам (индекс = ly*fw+lx)
var _shadow_tiles: Array = []  # тени houseb по тайлам
var _phase := 0           # текущий блок анимации
var _timer := 0.0
var _times: Array = []    # длительности кадров-фаз (секунды)
var _active := false      # есть анимация

func _ready() -> void:
	if _tiles.is_empty():
		_build()

## Собрать спрайты. Может перестроить при смене данных.
func build() -> void:
	for s in _tiles:
		s.queue_free()
	for s in _shadow_tiles:
		s.queue_free()
	_tiles.clear()
	_shadow_tiles.clear()
	_phase = 0
	_build()

func _build() -> void:
	# Определить число блоков по реальным кадрам в папке
	var grid := fw * fh
	var dir := DirAccess.open("res://assets/structures/%s" % folder)
	var max_frame := 0
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.begins_with("house-") and fn.ends_with(".png"):
				var num := int(fn.trim_prefix("house-").trim_suffix(".png"))
				max_frame = maxi(max_frame, num)
			fn = dir.get_next()
		dir.list_dir_end()
	if max_frame <= 0 and grid > 0:
		return  # папки нет — не рисуем
	# Полных блоков: floor. Неполный хвост (church 50 при grid 20, bridge3 36 при 24)
	# — частичная анимация — показываем только базу (без лишних фаз).
	_blocks = maxi(1, int(max_frame) / maxi(grid, 1))
	if max_frame % grid != 0:
		_blocks = 1  # частичная анимация: статичная база
	# Ограничение по DB phases (чтобы не показывать лишние кадры, например у колодцев)
	if max_blocks > 0:
		_blocks = mini(_blocks, max_blocks)
	_phase = 0
	_active = use_anim and _blocks > 1

	# Отсев «мусорных» фаз: заглушка-пустышка (битый конверт) заменяет реальный
	# тайл фазы, и здание мигает дырками — выглядит как разрушенное.
	# Сравниваем КАЖДЫЙ тайл фазы с соответствующим тайлом базового блока, а не
	# абсолютные байты: легитимный «пустой» тайл (небо, угол) одинаково мал в обоих
	# блоках, а заглушка — в разы меньше базы. Абсолютный порог неприменим: пустые
	# тайлы есть и в здоровых анимациях (castle house-047 = 83 б, mill1 house-034),
	# и порог «меньше 160 байт» погасил бы 20 зданий, включая все лавки друидов.
	# Раньше проверялся только ПЕРВЫЙ тайл фазы, из-за чего битые пропускались:
	# у train1 house-013 = 190 б (порог проходит), а house-014 = 118 б и
	# house-015 = 83 б — крыша исчезала на второй фазе.
	#
	# Отбрасывается ТОЛЬКО битая фаза, а не вся анимация: у mill2 из 6 фаз бита
	# одна (house-030 = 83 б против базовых 325 б), и мельница должна крутиться.
	_valid_blocks = [0]
	if _active:
		for b in range(1, _blocks):
			if not _is_phase_broken(b, grid):
				_valid_blocks.append(b)
		_active = use_anim and _valid_blocks.size() > 1

	# Тайлы (все блоки берём из первого блока: блок 0 — база)
	for ly in range(fh):
		for lx in range(fw):
			var idx := _tiles.size()
			var s := Sprite2D.new()
			s.name = "Tile%d" % idx
			s.position = Vector2(lx * TILE, ly * TILE)
			add_child(s)
			_tiles.append(s)
	# Тень: отдельным слоем под зданием (houseb-NNN), сдвиг вниз.
	# Узел здания стоит верхом на клетке (y-fh+th); корпус — клетки y..y+th-1.
	# Тень-ромб кладём так, чтобы её верх был на уровне земли (нижняя кромка корпуса).
	var shadow_off := float(fh - th) * TILE
	for ly in range(fh):
		for lx in range(fw):
			var s := Sprite2D.new()
			s.name = "Shadow%d" % _shadow_tiles.size()
			s.position = Vector2(lx * TILE, ly * TILE + shadow_off)
			s.z_index = -2
			s.modulate = Color(1, 1, 1, 0.4)   # полупрозрачная тень (не «второе здание»)
			add_child(s)
			_shadow_tiles.append(s)
	_apply_frame()

## Размер файла кадра house-NNN в байтах (-1, если файла нет).
func _house_size(frame: int) -> int:
	var f := FileAccess.open("res://assets/structures/%s/house-%03d.png" % [folder, frame], FileAccess.READ)
	if f == null:
		return -1
	var sz := f.get_length()
	f.close()
	return sz

## Порог «тайл фазы — заглушка»: меньше 30% размера того же тайла базового блока.
## Подобран по всем зданиям с анимацией, на глаз проверен по кадрам:
##   битые   0.034..0.255 — blacksmith1/2, train1/2/3, inn1/2, tower_m, mill2
##   здоровые 0.380..0.969 — mill1 (house-028 = 131 б, реальный тайл), mill3,
##                           castle, все druid*, tower1/2
const BROKEN_PHASE_RATIO := 0.30

## Фаза b — битая, если хоть один её тайл в разы меньше базового (заглушка).
func _is_phase_broken(block: int, grid: int) -> bool:
	for i in range(grid):
		var base_size := _house_size(i + 1)
		var phase_size := _house_size(block * grid + i + 1)
		# Отсутствующий кадр — это не «битый», это недокачанный набор: молча
		# оставляем как есть, _apply_frame() подставит базовый тайл.
		if base_size <= 0 or phase_size < 0:
			continue
		if base_size > 0 and float(phase_size) / float(base_size) < BROKEN_PHASE_RATIO:
			return true
	return false

## Применить текущую фазу ко всем тайлам.
## _phase — индекс в _valid_blocks, а НЕ номер блока: битые фазы вычеркнуты,
## и анимация идёт только по пригодным (у mill2 пропускается фаза 3).
func _apply_frame() -> void:
	var grid := fw * fh
	var block: int = _current_block()
	for i in range(_tiles.size()):
		var frame := block * grid + i + 1
		var tex: Variant = load("res://assets/structures/%s/house-%03d.png" % [folder, frame])
		if tex == null:
			tex = load("res://assets/structures/%s/house-%03d.png" % [folder, i + 1])
		if tex != null:
			(_tiles[i] as Sprite2D).texture = tex
	for i in range(_shadow_tiles.size()):
		var s := _shadow_tiles[i] as Sprite2D
		var tex: Variant = load("res://assets/structures/%s/houseb-%03d.png" % [folder, i + 1])
		if tex != null:
			s.texture = tex
			s.visible = true
		else:
			s.visible = false

## Номер блока для текущего индекса фазы.
func _current_block() -> int:
	if _valid_blocks.is_empty():
		return 0
	return int(_valid_blocks[_phase % _valid_blocks.size()])

func _process(delta: float) -> void:
	if not _active or _times.is_empty():
		return
	_timer += delta
	if _timer >= _times[_phase % _times.size()]:
		_timer = 0.0
		_phase = (_phase + 1) % _valid_blocks.size()
		_apply_frame()

## Установить расписание фаз (секунды на фазу) из StructureDB.
func set_anim_times(times: Array) -> void:
	_times = times
	if _times.is_empty() and _blocks > 1:
		_times = []
		for i in range(_blocks):
			_times.append(0.15)