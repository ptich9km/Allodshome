class_name SpellAura
extends Node2D
## Постоянный визуальный эффект на юните: щит, сопротивление стихии, ускорение.
##
## Раньше у этих эффектов был только одноразовый всплеск (`aura_ring` на 0.45 с):
## бафф с длительностью 20–90 секунд выглядел как вспышка в первый кадр и
## пропадал. Плюс он рисовался в `global_position` юнита, то есть У НОГ, хотя
## спрайты героев растут вверх от основания — эффект уезжал под ноги.
##
## Здесь аура живёт ровно столько, сколько длится эффект в status_effects,
## и висит НАД ГОЛОВОЙ: высота считается из реального размера спрайта юнита
## (`Game._unit_metrics` → tile_size из units_db.json), а не из константы.
##
## Само наличие эффекта проверяется по status_effects.active_has() — если
## игрок умер или баф снят, аура исчезает сама, без ручного снятия по таймеру.

const TILE := 32
## Насколько высоко поднимать эффект над основанием спрайта.
const HEAD_FACTOR := 0.86     # доля высоты спрайта
const HEAD_MARGIN := 12.0     # + px, чтобы не липло к макушке
## Вертикальный шаг между эффектами в столбике. Три наложенных баффа должны
## быть видны РАЗДЕЛЬНО, а не наложиться друг на друга в одной точке.
const STACK_STEP := 20.0

var kind: String = "shield"   # shield | resist | haste
var sphere: String = "Astral"
var unit: Node2D = null
var effect_type: String = ""

var _sprite: Sprite2D = null
var _elapsed: float = 0.0
var _base_offset: float = 0.0
var _stack_index: int = 0

## Порядок столбика снизу вверх: земля -> молния -> вода -> огонь.
## Огонь сверху: он самый контрастный, и четыре защиты сразу читаются как лестница.
## Щит в столбик НЕ входит (рисуется вокруг тела), ветер — у ног.
## Номер слота считается по уже висящим аурам той же стихии.
const RESIST_STACK_ORDER := {"Earth": 0, "Air": 1, "Water": 2, "Fire": 3}
const STACK_STEP_RESIST := 18.0


func configure(u: Node2D, aura_kind: String, sp: String, effect: String) -> void:
	unit = u
	kind = aura_kind
	sphere = sp
	effect_type = effect


func _ready() -> void:
	z_index = 8
	_sprite = Sprite2D.new()
	_sprite.texture = SpellVFX.white_texture()
	_sprite.material = _material()
	_sprite.scale = _scale()
	add_child(_sprite)
	# Ветер — у ног, щит — вокруг тела, остальное — над головой.
	_stack_index = _compute_stack_index()
	_base_offset = _kind_offset()
	_apply_offset()
	set_process(true)


## Куда ставить эффект по его виду.
## Щит рисуется ВОКРУГ героя (по центру силуэта), а не над головой: по
## описанию это «сетка вокруг персонажа», и так сразу видно, что он прикрыт.
## Сопротивление — в столбике над головой, ветер — у ног.
func _kind_offset() -> float:
	match kind:
		"haste":
			return -6.0
		"shield":
			return -_sprite_height() * 0.45
		_:
			return _head_offset()


## Номер слота в столбике: считаем, сколько «головных» аур уже висит ниже
## нашего по STACK_ORDER. Нужен, чтобы баффы не накладывались друг на друга.
## Щит в столбик не входит — он рисуется вокруг тела.
func _compute_stack_index() -> int:
	if kind != "resist":
		return 0
	return _rank_among(unit)


## Ранг среди висящих сопротивлений: сколько стихий стоят НИЖЕ нашей.
## Считать надо именно так: «сколько уже было ниже» давало 0 всем, когда
## накладывали сверху вниз (Fire -> Water -> Air -> Earth): каждый новый
## оказывался выше предыдущих, то есть снизу, и все четыре значка попадали
## в одну точку. Ранг же пересчитывается, когда состав стопки меняется.
func _rank_among(u: Node2D) -> int:
	if not is_instance_valid(u):
		return 0
	var mine := int(RESIST_STACK_ORDER.get(sphere, 0))
	var below := 0
	for child in u.get_children():
		if not (child is SpellAura):
			continue
		var other := child as SpellAura
		if other.kind != "resist" or other.sphere == sphere:
			continue
		if int(RESIST_STACK_ORDER.get(other.sphere, 0)) < mine:
			below += 1
	return below


## Пересчитать столбик на цели: слоты зависят от СОСТАВА висящих аур, поэтому
## при добавлении и удалении надо пересчитать их все, а не только новую.
static func restack(u: Node2D) -> void:
	if not is_instance_valid(u):
		return
	for child in u.get_children():
		if not (child is SpellAura):
			continue
		var a := child as SpellAura
		if a.kind != "resist":
			continue
		a.set_stack_index(a._rank_among(u))


## Задать слот столбика и сразу пересчитать смещение.
func set_stack_index(index: int) -> void:
	if _stack_index == index:
		return
	_stack_index = index
	_base_offset = _kind_offset()
	_apply_offset()


func _material() -> ShaderMaterial:
	match kind:
		"haste":
			return SpellVFX.zone_material("aura_wind", Color(0.78, 1.0, 0.82, 1.0))
		"resist":
			# Цвет и ФОРМА — по стихии (см. RESIST_COLORS / RESIST_SHAPES):
			# огонь красный и шипастый, вода синяя капля, молния светло-голубая
			# зигзаг, земля светло-коричневый блок.
			var mat := SpellVFX.zone_material("aura_up", SpellVFX.resist_color(sphere))
			mat.set_shader_parameter("shape", SpellVFX.resist_shape(sphere))
			return mat
		_:
			return SpellVFX.zone_material("aura_shield", Color(0.72, 0.52, 1.0, 1.0))


## Высота спрайта юнита в пикселях. Раньше бралась константа, и у гнома
## эффект висел в воздухе над головой, а у тролля уходил в землю.
func _sprite_height() -> float:
	return Game.unit_visual_height(unit)


func _head_offset() -> float:
	var step := STACK_STEP_RESIST if kind == "resist" else STACK_STEP
	return -(_sprite_height() * HEAD_FACTOR + HEAD_MARGIN + float(_stack_index) * step)


## Аура ушла (истекло сопротивление или сняли бафф) — оставшиеся в столбике
## обязаны сдвинуться, иначе внизу останется пустое место.
func _exit_tree() -> void:
	if unit != null and is_instance_valid(unit) and kind == "resist":
		restack(unit)


func _apply_offset() -> void:
	if _sprite == null:
		return
	_sprite.position = Vector2(0, _base_offset)


func _scale() -> Vector2:
	# Щит — шире силуэта, чтобы сетка его окружала. Сопротивление — значок над
	# головой, ветер — широкая полоса у ног.
	match kind:
		"haste":
			return Vector2(1.6, 0.34)
		"resist":
			return Vector2(0.45, 0.45)
		"shield":
			return Vector2(1.6, 1.6)
		_:
			return Vector2(0.78, 0.78)


func _process(delta: float) -> void:
	if not is_instance_valid(unit):
		queue_free()
		return
	# Следуем за юнитом, даже если он телепортировался или его сдвинул отброс.
	global_position = unit.global_position
	_elapsed += delta
	if _sprite != null and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("time", _elapsed)

	# Эффект закончился (баф снят, юнит умер) — аура исчезает сама.
	if not _effect_still_active():
		queue_free()
		return

	# Сопротивление и щит слегка покачиваются, чтобы было видно, что это эффект.
	if kind != "haste" and _sprite != null:
		_sprite.position.y = _base_offset + sin(_elapsed * 2.4) * 3.0


## Эффект закончился (баф снят, юнит умер) — аура исчезает сама.
## Источник правды РАЗНЫЙ для разных эффектов, и это неочевидно:
##   сопротивление и ускорение лежат в status_effects (active_types);
##   щит — НЕ в статусах, а в отдельном meta силы/времени, который тикает
##   Game.tick_shields. Поэтому универсальная проверка по active_types() для
##   щита всегда возвращала «щита нет», и аура щита удаляла себя в тот же кадр.
func _effect_still_active() -> bool:
	if not is_instance_valid(unit):
		return false
	if kind == "shield":
		return int(unit.get_meta("shield_strength", 0)) > 0 \
			and float(unit.get_meta("shield_time", 0.0)) > 0.0
	if kind == "resist":
		# Именно СВОЯ стихия: active_types() возвращает типы без сфер, поэтому
		# при четырёх защитах дал бы один «resist» и ни одна аура не исчезла бы
		# после истечения своей.
		return StatusEffects.has_effect(unit, "resist", sphere)
	if effect_type == "":
		return true
	return effect_type in StatusEffects.active_types(unit)


## Высота эффекта над основанием спрайта — для статических всплесков.
static func _head_offset_for(u: Node2D) -> float:
	return Game.unit_visual_height(u) * HEAD_FACTOR + HEAD_MARGIN


## Создать ауру на юните (или обновить существующую того же вида).
static func attach(u: Node2D, aura_kind: String, sp: String, effect_type: String) -> SpellAura:
	if not is_instance_valid(u):
		return null
	# Дедуп по ключу «вид + сфера». Раньше ключом был только вид, и все четыре
	# Protection_from_* делили одну ауру: накладываешь огонь, потом воду — вода
	# затирала огонь, и на экране оставался ОДИН значок вместо четырёх.
	# Щит и ветер sphere-независимы, для них ключ тот же.
	for child in u.get_children():
		if not (child is SpellAura):
			continue
		var old_aura := child as SpellAura
		if old_aura.kind != aura_kind:
			continue
		if aura_kind == "resist" and old_aura.sphere != sp:
			continue
		old_aura.effect_type = effect_type
		return old_aura
	var aura := SpellAura.new()
	# Конфигурация ДО add_child: _ready() выполняется внутри add_child, и если
	# задать kind после, высота и вид считались бы для дефолтного "shield" —
	# ветер ускорения уезжал над головой вместе с щитом.
	aura.configure(u, aura_kind, sp, effect_type)
	u.add_child(aura)
	# Состав столбика изменился — пересчитать слоты у всех, иначе новая аура
	# встанет на чужое место.
	restack(u)
	return aura


## Красный крест лечения над головой — короткий всплеск, не постоянный.
static func heal_cross(u: Node2D) -> void:
	if not is_instance_valid(u):
		return
	var scene: Node = Engine.get_main_loop().current_scene as Node
	if scene == null:
		return
	var s := Sprite2D.new()
	s.z_index = 8
	s.texture = SpellVFX.white_texture()
	s.material = SpellVFX.zone_material("heal_cross", Color(1.0, 0.32, 0.32, 1.0))
	s.scale = Vector2(0.55, 0.55)
	s.position = u.global_position + Vector2(0, -_head_offset_for(u))
	scene.add_child(s)
	var tw := scene.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector2(0.72, 0.72), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.9)
	tw.tween_callback(s.queue_free)
