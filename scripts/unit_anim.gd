class_name UnitAnim
extends Node2D
## Анимированный юнит (герой/НПЦ/монстр) из наборов assets/units.
## Раскладка кадров: blocks по фазам (move, attack, dying, ...), внутри блока
## 8 кадров направлений: frame = block_start + phase*8 + direction.
##
## Направления 0-7: 0=юг(анфас), 1=юго-запад, 2=запад, 3=северо-запад,
## 4=север(спина), 5=северо-восток, 6=восток, 7=юго-восток (против часовой).

enum Anim { IDLE, MOVE, ATTACK, DYING }

const DIRS := 8

var set_name := ""            # "heroes/swordsman", "monsters/orc", ...
var prefix := "sprites"       # префикс кадра в папке (sprites | swordsman | ...)
var frames: Array = []        # Texture2D кадры sprites-001..N
var dir := 0                  # текущее направление 0-7
var anim: int = Anim.IDLE
var anim_idx := 0             # номер фазы в текущем блоке
var anim_time := 0.0
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
	_apply_frame()

## Направление по вектору скорости/взгляда (world coords).
func set_direction_vec(dir_vec: Vector2) -> void:
	if dir_vec.length_squared() < 0.001:
		return
	var ang := rad_to_deg(dir_vec.angle())  # -180..180, 0 = вправо
	# карта: 0 = юг (вниз экрана = 90deg в Godot), против часовой
	var d := int(round((ang - 90.0) / 45.0)) % DIRS
	if d < 0:
		d += DIRS
	dir = d

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

func _block_offset() -> int:
	var off := 0
	# IDLE показывает первый кадр движения (в блоке движения)
	var kind := Anim.MOVE if anim == Anim.IDLE else anim
	match kind:
		Anim.MOVE:
			off = 0
		Anim.ATTACK:
			off = UnitDB.move_phases(set_name) * DIRS
		Anim.DYING:
			off = (UnitDB.move_phases(set_name) + UnitDB.attack_phases(set_name)) * DIRS
	return off

func _apply_frame() -> void:
	if frames.is_empty() or _sprite == null:
		return
	# Раскладка направления-мажорная: в блоке подряд идут фазы одного направления:
	# frame = block_start + dir*phases_in_block + phase
	var kind := Anim.MOVE if anim == Anim.IDLE else anim
	var off := _block_offset()
	var phases: int = _phases_for(kind)
	if phases < 1:
		phases = 1
	var idx := off + dir * phases + anim_idx
	_last_dir = dir
	if idx >= frames.size():
		idx = off + dir * phases  # если блок не полный, берём первую фазу направления
		if idx >= frames.size():
			idx = off
	var tex: Texture2D = frames[idx]
	_sprite.texture = tex
	# Кадры обрезаны по содержимому: центрируем по X, низ спрайта = позиция узла
	_sprite.position = Vector2(-tex.get_width() / 2.0, -float(tex.get_height()))