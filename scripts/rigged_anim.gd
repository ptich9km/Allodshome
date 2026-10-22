class_name RiggedAnim
extends UnitAnimBase
## Анимированный юнит из 2D-РИГА (cutout / paper-doll) вместо спрайт-листов.
##
## ЗАЧЕМ. Спрайт-листы требуют от ИИ-генератора рисовать циклы ходьбы и смерти
## для каждого из 8 направлений. Замеры проекта это прямо показывают: seedream
## на запрос «6 фаз ходьбы» выдаёт широкий присед в 2 клетках из 6, а сетку
## листа выбирает сам (просили 8x6 — получил 8x3). Риг снимает ровно эту
## проблему: от ИИ нужна ОДНА стоящая поза на ракурс, а ходьбу, атаку, смерть
## и распад мы считаем вращением костей. Новое состояние анимации стоит ноль
## новых картинок.
##
## КОНТРАКТ. Класс намеренно повторяет публичную поверхность `UnitAnim`
## (9 членов, сторож — tests/anim_contract_smoke.gd): игровой код создаёт юниты
## кодом и общается с анимацией ПО ИНТЕРФЕЙСУ, а не по классу — `game.gd`
## ищет узел по имени "UnitAnim" и дёргает методы через `has_method`.
## Поэтому риг может стоять рядом со спрайт-листами и включаться поштучно.
##
## СХЕМА rig.json (всё в одном файле, версии нет — набор арта меняется целиком):
##   {
##     "desc": "...",
##     "height": 112,                       # рост фигуры в px, для шкалы HP
##     "map": {"0":"north","4":"south",...},# октанта(после snap) -> имя вида
##     "views": {
##       "east": {"parts":"res://assets/units/rig/x/parts/",
##                 "bones":{"L_torso":38,"L_uarm":24,"L_thigh":28},
##                 "far_tint":"8080d9c9", "near_tint":"ffffffff",
##                 "faces":"east",           # в какую сторону нарисован арт
##                 "height":112}
##     },
##     "clips": {"idle": {"length":2.4,"loop":true,
##                        "rot":{"Torso":[[0.0,0.0],[1.2,3.0],[2.4,0.0]]},
##                        "pos":{"Hip":[[0.0,0,0],[1.2,0,-1],[2.4,0,0]]}}}
##   }
##
## ЧТО ЗДЕСЬ НЕТ И ПОЧЕМУ.
## - `Skeleton2D`/`Bone2D` НЕ используются. В Godot 4.7 Skeleton2D деформирует
##   только `Polygon2D` (свойство `skeleton` + веса `add_bone`); `Sprite2D`,
##   подвешенный на `Bone2D`, работает ровно как в иерархии `Node2D`. Для ~12
##   ЖЁСТКИХ частей разница = одно свойство `rest`, а цена = риск наступить на
##   сломанный API и потерять совместимость с headless-пайплайном. Кость здесь —
##   голый `Node2D`, спрайт-часть — его ребёнок.
## - Кости не требуют автора в редакторе: docs прямо пишут, что rest pose
##   «from the code, you need to iterate over the bones».
## - `AnimationPlayer` собирается ИЗ СРИПТА (`Animation.add_track`,
##   `AnimationLibrary.add_animation`, `add_animation_library("")`) — runtime-API.
## - Клипы НЕ крутятся собственным временем AnimationPlayer: он стоит на паузе,
##   а время двигает `advance()` той же дельтой, что и у UnitAnim. Иначе в
##   headless у AnimationPlayer не набирается дельта и риг невозможно проверить.
##
## КОНВЕНЦИЯ ПИВОТА (обязательна для арта, иначе риг разъедется):
## сустав части лежит в ТОЧНОМ пиксельном центре её текстуры; обе стороны
## холста ЧЁТНЫЕ. Часть паддингуется прозрачностью до этого состояния. Тогда
## `Sprite2D.centered = true` с нулевым offset кладёт начало кости ровно на
## сустав, и вращение не требует позиционной арифметики.
##
## ДАЛЬНЯЯ КОНЕЧНОСТЬ. Текстура дальней руки/ноги та же, что у ближней, только
## затемнена через `modulate`. `flip_h` на дальней конечности НЕ делается
## никогда: зеркалит асимметричный свет и читается неверно; противофаза
## приходит из вращения костей в клипе.
##
## ЗЕРКАЛО. `scale.x = -1` в Godot 4 НЕ декомпозируется: матрица переносит
## отрицательный X на ось Y и разворачивает её на 180°, после чего `rotation`,
## `position` и `skew` разъезжаются. Поэтому отражается ТОЛЬКО корень (Hip),
## а локальные углы частей после отражения не читаются и не пишутся.

## Поля `set_name`, `dir`, `anim`, `anim_idx`, `target_dir`, `speed_scale`,
## `FULL_DIRS` и `enum Anim` унаследованы от UnitAnimBase.

const RIG_ROOT := "res://assets/units/rig/"

## Соответствие блоков UnitAnim.Anim на имена клипов в rig.json.
const CLIP_FOR: Dictionary = {
	0: "idle",    # Anim.IDLE
	1: "walk",    # Anim.MOVE
	2: "attack",  # Anim.ATTACK
	3: "dying",   # Anim.DYING
	4: "decay",   # Anim.DECAY
}

# --- внутреннее ---

var _hip: Node2D = null
var _bones: Dictionary = {}     # имя кости -> Node2D
var _anim: AnimationPlayer = null
var _clips: Dictionary = {}     # имя клипа -> {length, loop, rot, pos}
var _views: Dictionary = {}     # имя ракурса -> {...}
var _map: Dictionary = {}       # октанта -> имя ракурса
var _figure_height := 0.0
var _mirror := false
var _loaded := false
var _missing_parts: Array[String] = []
var _clip_time := 0.0          # время внутри клипа; двигает advance(), не сам AnimationPlayer
var _frozen := false           # труп заморожен: одноразовый клип не перезапускается
var _rot_acc := 0.0
var _hyst_dir := -1           # угол, который сейчас подтверждается гистерезисом
var _hyst_steps := 0
var _scale := 1.0
## Суффикс имён частей для текущего ракурса. Пусто = пилот (thigh.png);
## "south" = атласный риг (thigh_south.png). Задаётся полем "suffix" в views.
var _part_suffix := ""
const ROT_STEP_TIME := 0.05
## Шагов подряд, которые новый угол должен продержаться, прежде чем юнит
## начнёт доворачиваться. Без этого зеркало щёлкает на границе октантов.
const HYSTERESIS_STEPS := 2
var view_name := ""            # какой ракурс рига показан сейчас


# --- контракт UnitAnim ---

## Настроить риг по набору. Молча выходит, если для набора нет rig.json: риг
## непригоден, вызывающий код остаётся на спрайт-листах. `is_loaded()` честно
## сообщает результат — молча сломанный риг хуже его отсутствия.
func setup(name: String) -> void:
	set_name = name
	_loaded = false
	_missing_parts.clear()
	_clips.clear()
	_views.clear()
	_map.clear()
	_figure_height = 0.0
	_clear_skeleton()
	var path := RIG_ROOT + name.replace("/", "_") + "/rig.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("RiggedAnim: не разобран rig.json для `%s`" % name)
		return
	var root: Dictionary = parsed
	_views = root.get("views", {})
	_clips = root.get("clips", {})
	_map = root.get("map", {})
	_figure_height = float(root.get("height", 0.0))
	if _views.is_empty():
		return
	_build_view(_view_for(dir))
	# Масштаб юнита — тот же источник, что у спрайт-листов (UnitDB.tile_size),
	# иначе тролль на риге окажется ростом с героя.
	_scale = float(maxi(1, UnitDB.tile_size(name)))
	_loaded = true


func play(anim_kind: int, reset: bool = false) -> void:
	if anim == anim_kind and not reset and not _clip_finished(anim_kind):
		return
	if anim != anim_kind:
		_frozen = false   # сменили блок — труп перестаёт быть замороженным
	anim = anim_kind
	anim_idx = 0
	_clip_time = 0.0
	var clip := str(CLIP_FOR.get(anim_kind, ""))
	if _anim != null and _clips.has(clip):
		_anim.play(clip)
		_anim.pause()
		_anim.seek(0.0, true)


## Одноразовый клип, доигранный до конца?
##
## Нужно для повторного взмаха: игровой код держит состояние "attack" дольше
## одного замаха (удары гейтятся кулдауном) и зовёт play(ATTACK) каждый кадр,
## так что «anim уже равен ATTACK» больше не значит «уже играет». Без этой
## проверки клип навсегда замирал на последнем кадре — игрок видел один взмах,
## а дальше только звук и урон. У спрайт-листов такого дефекта нет: там advance()
## циклит фазы, поэтому взмах повторяется сам собой.
##
## ЗАМОРОЖЕННЫЙ блок не перезапускается: иначе play(DYING) в состоянии "dead"
## снова запустит падение и мёртвый будет шевелиться.
func _clip_finished(anim_kind: int) -> bool:
	if _frozen:
		return false
	var spec: Dictionary = _clips.get(str(CLIP_FOR.get(anim_kind, "")), {})
	var length := float(spec.get("length", 0.0))
	if bool(spec.get("loop", false)) or length <= 0.0:
		return false
	return _clip_time >= length - 0.0001


func advance(delta: float) -> bool:
	var clip: Dictionary = _clips.get(str(CLIP_FOR.get(anim, "")), {})
	if clip.is_empty():
		return true
	var length := float(clip.get("length", 0.0))
	if length <= 0.0:
		return true
	_clip_time += delta / maxf(speed_scale, 0.05)
	if bool(clip.get("loop", false)):
		_clip_time = fmod(_clip_time, length)
		_anim.seek(_clip_time, true)
		return false
	if _clip_time >= length:
		_clip_time = length
		_anim.seek(length, true)
		return true
	_anim.seek(_clip_time, true)
	return false


func freeze_last_frame(kind: int) -> void:
	anim = kind
	_frozen = true
	anim_idx = maxi(0, _clip_phases(kind) - 1)
	if _anim == null:
		return
	var clip: Dictionary = _clips.get(str(CLIP_FOR.get(kind, "")), {})
	if clip.is_empty():
		return
	var length := float(clip.get("length", 0.0))
	_clip_time = length
	_anim.seek(length, true)


func set_direction_vec(dir_vec: Vector2) -> void:
	var d := Game.unit_octant(dir_vec)
	if d < 0:
		return
	if d != target_dir:
		target_dir = d


func sprite_height() -> float:
	return _figure_height


func visual_height() -> float:
	return _figure_height * _scale


## Есть ли пригодный риг для набора — вызывающий код решает по нему, не
## создавая риг вслепую.
func is_loaded() -> bool:
	return _loaded


## Есть ли rig.json для набора. Статическая форма: нужна ДО создания рига,
## чтобы при смене экипировки знать, менять ли бэкенд вообще.
static func has_rig(set: String) -> bool:
	return FileAccess.file_exists(RIG_ROOT + set.replace("/", "_") + "/rig.json")


## Части, для которых не нашлось текстуры. Не пусто = риг неполон.
func missing_parts() -> Array[String]:
	return _missing_parts


## Масштаб юнита (1 = обычный, 2 = тролль). Ставится снаружи после setup().
func set_unit_scale(ts: int) -> void:
	_scale = float(maxi(1, ts))


func _process(delta: float) -> void:
	if target_dir >= 0 and target_dir != dir:
		_advance_rotation(delta)


func _advance_rotation(delta: float) -> void:
	if target_dir < 0:
		return
	_rot_acc += delta
	if _rot_acc < ROT_STEP_TIME:
		return
	_rot_acc = 0.0

	# Уже на месте — шагать некуда. Без этой проверки шаг всё равно делался бы
	# (diff == 0 попадает в ветку step = +1), юнит ПРОСКАКИВАЛ мимо цели и
	# уходил дальше: поворот никогда не сходился. В игре путь закрыт условием в
	# _process, но метод вызывается и напрямую из тестов.
	if target_dir == dir:
		target_dir = -1
		_hyst_dir = -1
		_hyst_steps = 0
		return

	# ГИСТЕРЕЗИС. Без него юнит «дёргается» на границе октантов: игрок ведёт
	# курсор вдоль вектора, октант скачет 2↔3, зеркало щёлкает, и персонаж
	# выглядит так, будто постоянно разворачивается. Требуем КАЖДЫЙ новый
	# угол подтвердить HYSTERESIS_STEPS шагами подряд, иначе поворот не начинаем.
	if target_dir != _hyst_dir:
		_hyst_dir = target_dir
		_hyst_steps = 0
		return
	_hyst_steps += 1
	if _hyst_steps < HYSTERESIS_STEPS:
		return

	var diff := wrapi(target_dir - dir, 0, FULL_DIRS)
	var step := 1 if diff <= int(FULL_DIRS / 2.0) else -1
	dir = wrapi(dir + step, 0, FULL_DIRS)

	# Скелет пересобирается ТОЛЬКО при смене ракурса. Первая версия дёргала
	# `_build_view` на каждом шаге поворота, то есть уничтожала и заново
	# создавала 15 узлов и AnimationPlayer 20 раз в секунду — это и было
	# главным источником «постоянно разворачивается». Внутри одной ракурсной
	# группы меняется только зеркало, а это дешёвый сдвиг scale.x.
	var next_view := _view_for(dir)
	if next_view != view_name:
		# Пересборка обязана вернуть и время клипа, иначе юнит переключит вид
		# «на середине шага» и дёрнется.
		_build_view(next_view)
		var clip := str(CLIP_FOR.get(anim, ""))
		if _anim != null and _clips.has(clip):
			_anim.play(clip)
			_anim.pause()
			_anim.seek(_clip_time, true)
	else:
		_apply_mirror()

	if dir == target_dir:
		target_dir = -1
		_hyst_dir = -1
		_hyst_steps = 0


# --- сборка скелета ---

func _clear_skeleton() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	_bones.clear()
	_hip = null
	_anim = null
	view_name = ""


func _bone(parent: Node2D, bone_name: String, pos: Vector2) -> Node2D:
	var b := Node2D.new()
	b.name = bone_name
	b.position = pos
	parent.add_child(b)
	_bones[bone_name] = b
	return b


func _part(bone: Node2D, tex: String, tone: Color, dir_path: String) -> void:
	var s := Sprite2D.new()
	# Суффикс направления: "thigh" -> "thigh_south" (атласный риг) или
	# "thigh" -> "thigh" (пилот, suffix пустой).
	var base := tex if _part_suffix.is_empty() else tex + "_" + _part_suffix
	var full := dir_path + base + ".png"
	if ResourceLoader.exists(full):
		s.texture = load(full)
	else:
		_missing_parts.append(full)
	s.modulate = tone
	s.centered = true
	s.offset = Vector2.ZERO
	bone.add_child(s)


## Есть ли текстура части с учётом суффикса ракурса.
func _has_part(tex: String, dir_path: String) -> bool:
	var base := tex if _part_suffix.is_empty() else tex + "_" + _part_suffix
	return ResourceLoader.exists(dir_path + base + ".png")


func _disc(bone: Node2D, tex: String, tone: Color, dir_path: String) -> void:
	# Шарнирная «пробка» в точке вращения (0,0). Рисуется ПОВЕРХ конечности
	# (добавляется после _part) и закрывает клиновидный шов, который иначе
	# появляется при повороте. Это прямая цена paperdoll-анимации.
	_part(bone, tex, tone, dir_path)


func _build_view(view: String) -> void:
	_clear_skeleton()
	var spec: Dictionary = _views.get(view, {})
	if spec.is_empty():
		return
	view_name = view
	var dir_path: String = str(spec.get("parts", ""))
	_part_suffix = str(spec.get("suffix", ""))
	var far := _color(spec.get("far_tint"), Color(0.8, 0.8, 0.86))
	var near := _color(spec.get("near_tint"), Color.WHITE)
	var bones: Dictionary = spec.get("bones", {})
	var l_torso := float(bones.get("L_torso", 38.0))
	var l_uarm := float(bones.get("L_uarm", 24.0))
	var l_thigh := float(bones.get("L_thigh", 28.0))

	# Позиции суставов ОТ РЕАЛЬНЫХ РАЗМЕРОВ ТЕКСТУР, а не от долей L_torso.
	var torso_tex := _part_size("torso", dir_path)
	var arm_tex := _part_size("upper_arm", dir_path)
	var thigh_tex := _part_size("thigh", dir_path)
	# Реальная высота контента торса = половина canvas (контент в верхней половине)
	var torso_h := torso_tex.y * 0.5
	# Бёдра: на 1/4 ширины торса от центра
	var hip_x := torso_tex.x * 0.25
	# Плечо: у края торса, на 10% ниже макушки
	var sh_x := torso_tex.x * 0.40
	var sh_y := -torso_h + torso_h * 0.10

	var composite_arm := _has_part("upper_arm", dir_path)
	var composite_leg := _has_part("thigh", dir_path) and not _has_part("arm_far", dir_path)

	_hip = _bone(self, "Hip", Vector2.ZERO)

	# ДАЛЬНЯЯ НОГА — за торсом
	if composite_leg:
		var tb := _bone(_hip, "ThighBack", Vector2(-hip_x, 0))
		_part(tb, "thigh", far, dir_path)
		var sb := _bone(tb, "ShinBack", Vector2(0, l_thigh))
		_part(sb, "shin", far, dir_path)

	# ТОРС
	var torso := _bone(_hip, "Torso", Vector2.ZERO)

	# ДАЛЬНЯЯ РУКА — под торсом
	if composite_arm:
		var ab := _bone(torso, "ArmBack", Vector2(-sh_x, sh_y))
		_part(ab, "upper_arm", far, dir_path)
		var fb := _bone(ab, "ForearmBack", Vector2(0, l_uarm))
		_part(fb, "forearm", far, dir_path)

	# СТВОЛ
	_part(torso, "torso", near, dir_path)

	# БЛИЖНЯЯ РУКА — перед торсом
	var af := _bone(torso, "ArmFront", Vector2(sh_x, sh_y))
	if composite_arm:
		_part(af, "upper_arm", near, dir_path)
		var ff := _bone(af, "ForearmFront", Vector2(0, l_uarm))
		_part(ff, "forearm", near, dir_path)
	elif _has_part("arm_near", dir_path):
		_part(af, "arm_near", near, dir_path)

	# ГОЛОВА — на макушке торса (не от L_torso, а от реальной высоты)
	var head := _bone(torso, "Head", Vector2(0, -torso_h))
	_part(head, "head", near, dir_path)

	# БЛИЖНЯЯ НОГА — перед торсом
	var tf := _bone(_hip, "ThighFront", Vector2(hip_x, 0))
	_part(tf, "thigh", near, dir_path)
	var sf := _bone(tf, "ShinFront", Vector2(0, l_thigh))
	_part(sf, "shin", near, dir_path)

	_hip.scale.x = 1.0
	_apply_mirror()
	_build_anims()


## Размер текстуры части (пустой вектор, если нет).
func _part_size(tex: String, dir_path: String) -> Vector2:
	var base := tex if _part_suffix.is_empty() else tex + "_" + _part_suffix
	var path := dir_path + base + ".png"
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		return Vector2(t.get_width(), t.get_height())
	return Vector2.ZERO


## Порог «направление определено». Ближайшие к зеркалу октанты — север и юг:
## там горизонталь стремится к нулю, а cos(270°) в плавающей точке возвращает
## НЕ ноль, а -1.8e-16. Условие `>= 0` на таком числе решает «смотрит на запад»
## и включает зеркало, хотя юг — это прямо вниз и отражать нечего. При ходьбе
## вниз октанты 4<->5 чередуются, и персонаж дёргался в другую сторону.
## При |cos| < порога решение НЕ ПРИНИМАЕТСЯ: зеркало сохраняет прежнее, то
## есть юнит «скользит» текущим ракурсом. Диагонали дают |cos| = 0.707, так что
## порог 0.35 отделяет неопределённость от реального решения с запасом.
const MIRROR_EPS := 0.35


## Отражение ракурса. Вынесено из _build_view: смена зеркала не должна
## пересобирать скелет, это дешёвый сдвиг scale.x на корне.
##
## Горизонталь октанты берётся как COS(90° + dir*45°), а НЕ как SIN(dir*45°).
## Октанты у нас контриклоковые от севера: 0=север 7=северо-восток 6=восток
## 5=юго-восток 4=юг 3=юго-запад 2=запад 1=северо-запад. Первая версия брала
## sin(dir*45°) и была ИНВЕРТИРОВАНА: октанта 2 (запад) считалась восточной и
## наоборот, поэтому на ходу влево/вправо персонаж отражался не тем боком и
## шёл боком — на это была жалоба игрока. Ось Y при scale.x = -1 не
## декомпозируется (см. шапку файла), поэтому отражается ТОЛЬКО корень.
func _apply_mirror() -> void:
	if _hip == null:
		return
	var spec: Dictionary = _views.get(view_name, {})
	var art_faces_east := int(spec.get("faces_east", 1))
	var h := cos(deg_to_rad(90.0 + float(dir) * 45.0))
	if absf(h) >= MIRROR_EPS:
		# Направление определено — запоминаем решение.
		_mirror = (h > 0.0) != (art_faces_east >= 0)
	# На север/юге решение не принимается: `_mirror` сохраняет прежнее, и
	# юнит «скользит» текущим ракурсом. Значение всё равно пишется — узел мог
	# быть только что пересоздан и по умолчанию стоит без отражения.
	_hip.scale.x = float(-1 if _mirror else 1)


func _color(v: Variant, fallback: Color) -> Color:
	var s := str(v)
	if s.length() < 6:
		return fallback
	if s.length() < 8:
		s += "ff"
	var c := Color.from_string(s, fallback)
	if c.a < 0.001:
		c.a = 1.0
	return c


## Ракурс для октанты. Диагонали схлопываются на ближайший кардинал
## (нарисовано 3 вида, мир просит 8) — ровно то, что делает LPC;
## устоявшегося ответа для рига в top-down нет.
func _view_for(octant: int) -> String:
	if _views.is_empty():
		return ""
	var cardinal := Game.snap_octant_to_cardinal(octant)
	var want := str(_map.get(str(cardinal), ""))
	if want.is_empty() or not _views.has(want):
		var first := str(_views.keys()[0])
		want = first
	return want


func _clip_phases(kind: int) -> int:
	var clip: Dictionary = _clips.get(str(CLIP_FOR.get(kind, "")), {})
	var rot: Dictionary = clip.get("rot", {})
	var n := 1
	for bone_name in rot:
		n = maxi(n, (rot[bone_name] as Array).size())
	return n


func _build_anims() -> void:
	_anim = AnimationPlayer.new()
	_anim.name = "Anim"
	add_child(_anim)
	var lib := AnimationLibrary.new()
	for clip_name in _clips:
		lib.add_animation(str(clip_name), _make_anim(str(clip_name), _clips[clip_name]))
	_anim.add_animation_library("", lib)


func _make_anim(_clip_name: String, spec: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = float(spec.get("length", 1.0))
	a.loop_mode = Animation.LOOP_LINEAR if bool(spec.get("loop", false)) else Animation.LOOP_NONE
	var rot: Dictionary = spec.get("rot", {})
	for bone_name in rot:
		var node: Node2D = _bones.get(bone_name, null)
		if node == null:
			continue
		var t := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(t, NodePath(str(get_path_to(node)) + ":rotation"))
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		for key in rot[bone_name]:
			a.track_insert_key(t, float(key[0]), deg_to_rad(float(key[1])))
	var pos: Dictionary = spec.get("pos", {})
	for bone_name in pos:
		var node: Node2D = _bones.get(bone_name, null)
		if node == null:
			continue
		var t2 := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(t2, NodePath(str(get_path_to(node)) + ":position"))
		a.track_set_interpolation_type(t2, Animation.INTERPOLATION_LINEAR)
		for key in pos[bone_name]:
			a.track_insert_key(t2, float(key[0]), Vector2(float(key[1]), float(key[2])))
	return a