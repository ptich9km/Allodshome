class_name UnitAnim
extends Node2D
## Анимированный юнит (герой/НПЦ/монстр) из наборов assets/units.
##
## Раскладка кадров (по карте пользователя, набор unarmed 129 кадров):
## блоки идут подряд: idle(9) → move(50) → attack(35) → dying(20) → decay(15);
## внутри блока — направление-мажор: frame = block_start + file_dir*phases + phase.
##
## В файле нарисованы ФАЙЛОВЫЕ направления (dirs = 5 у героя): 0=вниз, 1=вниз-влево,
## 2=влево, 3=влево-вверх, 4=вверх. Правая половина — зеркало левой:
## мировые направления 5,6,7 (вправо-вверх/вправо/вниз-вправо) показывают файловые
## 3,2,1 с flip_h=true. Наборы с dirs=8 (swordsman, монстры) — полные 8 направлений.

## Раскладка кадров:
## - 5 направлений (unarmed): направление-мажор, блоки idle→move→attack→dying→decay,
##   правые направления = зеркало левых (flip_h).
## - 8 направлений (swordsman и др.): фаза-мажор, кадр = block + phase*8 + dir;
##   движение 8 фаз, атака 7, смерть 4 (по units.txt).

enum Anim { IDLE, MOVE, ATTACK, DYING, DECAY }

const FULL_DIRS := 8

var set_name := ""            # "heroes/swordsman", "monsters/orc", ...
var prefix := "sprites"       # префикс кадра в папке (sprites | swordsman | ...)
var frames: Array = []        # Texture2D кадры sprites-001..N
var dir := 0                  # текущее МИРОВОЕ направление 0-7
var anim: int = Anim.IDLE
var anim_idx := 0             # номер фазы в текущем блоке
var target_dir := -1             # направление, к которому доворачиваем (плавный поворот)
var _rot_acc := 0.0
const ROT_STEP_TIME := 0.05      # сек на шаг направления при повороте
var anim_time := 0.0
var speed_scale := 1.0        # множитель темпа (движение быстрее — шаги быстрее)
var _last_dir := 0

var _sprite: Sprite2D

## Настроить набор. Переиспользует спрайт (не плодит новых при экипировке).
func setup(name: String) -> void:
	set_name = name
	var db := UnitDB.get_set(name)
	prefix = UnitDB.frame_prefix(name)
	var folder := str(db.get("folder", name))
	var n: int = UnitDB.frame_count(name)
	if n < 1:
		n = 1
	frames.clear()
	for i in range(n):
		var tex: Variant = load(UnitDB.frame_path(folder, prefix, i + 1))
		if tex != null:
			frames.append(tex)

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.centered = false
		add_child(_sprite)
	else:
		_sprite.flip_h = false
	# Масштаб крупных юнитов (TileSize: тролль/огр/катапульта 2x, дракон 3x)
	var ts: int = UnitDB.tile_size(name)
	_sprite.scale = Vector2.ONE * float(ts)
	_apply_frame()

## Число нарисованных направлений в файле (5 или 8).
func _file_dirs() -> int:
	return UnitDB.dirs(set_name)

## Мировое направление (0-7) -> файловый индекс направления (0..dirs-1) + зеркало.
func _file_dir_of(world_dir: int) -> Array:
	var d := _file_dirs()
	if d >= FULL_DIRS:
		return [world_dir, false]
	# 5 направлений: правая половина (5,6,7) = зеркало (3,2,1)
	if world_dir <= 4:
		return [world_dir, false]
	return [FULL_DIRS - world_dir, true]

## Направление по вектору скорости/взгляда (world coords).
func set_direction_vec(dir_vec: Vector2) -> void:
	if dir_vec.length_squared() < 0.001:
		return
	var ang := rad_to_deg(dir_vec.angle())  # -180..180, 0 = вправо
	# карта: 0 = юг (вниз экрана = 90deg в Godot), против часовой
	var d := int(round((ang - 90.0) / 45.0)) % FULL_DIRS
	if d < 0:
		d += FULL_DIRS
	# Плавный поворот: к цельному направлению крутимся через промежуточные
	if d != target_dir:
		target_dir = d

func _process(delta: float) -> void:
	if target_dir >= 0 and target_dir != dir:
		_advance_rotation(delta)

## Один шаг поворота к target_dir (кратчайшая дуга по 8 направлениям).
func _advance_rotation(delta: float) -> void:
	if target_dir < 0:
		return
	_rot_acc += delta
	if _rot_acc < ROT_STEP_TIME:
		return
	_rot_acc = 0.0
	var diff := wrapi(target_dir - dir, 0, FULL_DIRS)
	var step := 1 if diff <= FULL_DIRS / 2 else -1
	dir = wrapi(dir + step, 0, FULL_DIRS)
	_apply_frame()
	if dir == target_dir:
		target_dir = -1

func play(anim_kind: int, reset: bool = false) -> void:
	if anim == anim_kind and not reset:
		return
	anim = anim_kind
	anim_idx = 0
	anim_time = 0.0
	_apply_frame()

## Продвинуть анимацию, вернуть true когда блок завершён (для одноразовых анимаций).
func advance(delta: float) -> bool:
	var phases: int = _phases_for(anim)
	if phases <= 1:
		return true
	var times: Array = _times_for(anim)
	var t: float = 0.12
	if anim_idx < times.size():
		t = times[anim_idx]
	t /= maxf(speed_scale, 0.05)
	anim_time += delta
	if anim_time < t:
		return false
	anim_time = 0.0
	anim_idx += 1
	if anim_idx >= phases:
		anim_idx = 0
		_apply_frame()
		return true
	_apply_frame()
	return false

func _phases_for(kind: int) -> int:
	match kind:
		Anim.MOVE:
			return UnitDB.move_phases(set_name)
		Anim.ATTACK:
			return UnitDB.attack_phases(set_name)
		Anim.DYING:
			return UnitDB.dying_phases(set_name)
		Anim.DECAY:
			return UnitDB.decay_phases(set_name)
	return 1

func _times_for(kind: int) -> Array:
	match kind:
		Anim.MOVE:
			return UnitDB.block_times(set_name, "move_t", _phases_for(kind))
		Anim.ATTACK:
			return UnitDB.block_times(set_name, "attack_t", _phases_for(kind))
		Anim.DYING:
			return UnitDB.block_times(set_name, "dying_t", _phases_for(kind))
	return []

## Смещение блока анимации в кадрах (0-based), с учётом предыдущих блоков.
func _block_offset() -> int:
	var d := _file_dirs()
	var off := 0
	var kind := Anim.MOVE if anim == Anim.IDLE else anim
	# idle-блок (если есть) идёт первым
	off = UnitDB.idle_phases(set_name)
	match kind:
		Anim.MOVE:
			return off
		Anim.ATTACK:
			return off + UnitDB.move_phases(set_name) * d
		Anim.DYING:
			return off + (UnitDB.move_phases(set_name) + UnitDB.attack_phases(set_name)) * d
		Anim.DECAY:
			return off + (UnitDB.move_phases(set_name) + UnitDB.attack_phases(set_name) \
				+ UnitDB.dying_phases(set_name)) * d
	return off

func _apply_frame() -> void:
	if frames.is_empty() or _sprite == null:
		return
	var kind := Anim.MOVE if anim == Anim.IDLE else anim
	var idx := _frame_index(kind)
	_last_dir = dir
	if idx < 0 or idx >= frames.size():
		return  # блока нет в наборе (неполные/другие раскладки) — не падаем
	var tex: Texture2D = frames[idx]
	_sprite.texture = tex
	# Кадры обрезаны по содержимому: центрируем по X, низ спрайта = позиция узла
	_sprite.position = Vector2(-tex.get_width() / 2.0, -float(tex.get_height()))

## Индекс кадра: направление-мажор. frame = block_start + file_dir*phases + phase.
## Для dirs=5 (unarmed) правые направления (5,6,7) = зеркало левых (3,2,1) flip_h.
## Для dirs=8 (оружие, меч) все 8 направлений нарисованы — зеркало не нужно.
func _frame_index(kind: int) -> int:
	var fd := _file_dir_of(dir)
	var file_dir: int = fd[0]
	var flipped: bool = fd[1]
	_sprite.flip_h = flipped
	if anim == Anim.IDLE:
		# Стойка: у оружия (8 напр) — отдельные кадры 001-008 (idle-блок в начале).
		# У unarmed (5 напр) — первый кадр ходьбы направления (подтверждено).
		if _file_dirs() >= FULL_DIRS:
			return dir
		return _block_offset()
	var phases: int = _phases_for(kind)
	if phases < 1:
		phases = 1
	return _block_offset() + file_dir * phases + anim_idx