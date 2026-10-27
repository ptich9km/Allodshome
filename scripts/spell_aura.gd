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
## Шаг между эффектами в столбике (используется редкими видами аур).
const STACK_STEP := 20.0

## Кольца защит стоят на РАЗНОЙ ВЫСОТЕ по школе — доля высоты ФИГУРЫ от ног:
## земля у ног, воздух у бёдер, вода у груди, огонь у головы. Так четыре защиты
## читаются сразу и не складываются в одно пятно. Доли считаются от реальной
## рамки фигуры (54 px), а не от холста кадра (64 px) — иначе «голова» огня
## оказывалась на животе.
const RESIST_ROW_FRAC := {"Earth": 0.20, "Air": 0.40, "Water": 0.64, "Fire": 0.88,
	"Astral": 0.64}
## Высота кольца, px: тонкий обруч, а не широкий пузырь. Половина высоты
## (9 px) — это и есть запас: центр нижнего ряда стоит на 0.20 высоты фигуры
## (~11 px), поэтому обруч земли не уходит под ноги.
const BREEZE_H := 18.0
## Отступ кольца от силуэта по ширине, px.
const BREEZE_PAD := 20.0
## Размер летающего щита, px (геральдический силуэт в шейдере aura_shield).
## 27.10: уменьшен на 25 % по просьбе игрока — 20×26 оказался крупным.
const SHIELD_PX := Vector2(15.0, 20.0)
## Высота орбиты щита — доля высоты фигуры от ног (центр корпуса).
const SHIELD_BODY_FRAC := 0.55
## Аура благословения над головой, px.
const BLESS_PX := Vector2(16.0, 16.0)
const BLESS_HEAD_GAP := 8.0
## Ветер ускорения: широкая низкая полоса у ног.
const HASTE_PX := Vector2(40.0, 12.0)
## Крест лечения над головой, px.
const HEAL_CROSS_PX := 22.0

var kind: String = "shield"   # shield | resist | haste
var sphere: String = "Astral"
var unit: Node2D = null
var effect_type: String = ""

var _sprite: Sprite2D = null
var _elapsed: float = 0.0
var _base_offset: float = 0.0


func configure(u: Node2D, aura_kind: String, sp: String, effect: String) -> void:
	unit = u
	kind = aura_kind
	sphere = sp
	effect_type = effect


func _ready() -> void:
	# Аура — часть мира, а не интерфейса: на тактической паузе она обязана
	# замереть вместе с юнитом (корень сцены стоит на PROCESS_MODE_ALWAYS,
	# поэтому INHERIT паузу не ловит).
	process_mode = PROCESS_MODE_PAUSABLE
	z_index = 8
	_sprite = Sprite2D.new()
	_sprite.texture = SpellVFX.white_texture()
	_sprite.material = _material()
	_apply_size()
	# Кольцо ветерка рисуется ПОЗАДИ юнита: вокруг тела оно должно читаться как
	# обруч, а не как полосы поперёк лица. Сзади всё, что упирается в силуэт,
	# само скрывается спрайтом, наружу выходят только струи по бокам.
	if kind == "resist":
		_sprite.show_behind_parent = true
	add_child(_sprite)
	# Ветер — у ног, щит — вокруг корпуса, защиты — кольцами на своей высоте.
	_base_offset = _kind_offset()
	_apply_offset()
	set_process(true)


## Куда ставить эффект по его виду.
## Щит — «маленький летающий щит» вокруг корпуса; защита — обруч на своей
## доле высоты ФИГУРЫ (земля внизу, огонь у головы); ускорение — у ног.
func _kind_offset() -> float:
	var fig := _figure_rect()
	var bottom := fig.end.y          # ноги фигуры (≈ 0, чуть выше основания)
	var h := maxf(8.0, fig.size.y)
	match kind:
		"haste":
			# Ветер у самых ног, но НЕ под землёй: центр на 10 px, высота 12 px.
			return -10.0
		"shield":
			return bottom - h * SHIELD_BODY_FRAC
		"resist":
			var frac := float(RESIST_ROW_FRAC.get(sphere, 0.62))
			return bottom - h * frac
		"bless":
			# Над макушкой: top отрицательный, поэтому «выше» = ещё минус.
			return fig.position.y - BLESS_HEAD_GAP
		_:
			return _head_offset()


func _material() -> ShaderMaterial:
	match kind:
		"haste":
			return SpellVFX.zone_material("aura_wind", Color(0.78, 1.0, 0.82, 1.0))
		"resist":
			# Цвет школы + ФОРМА ДВИЖЕНИЯ по школе (uniform school):
			# огонь — угольки вверх, вода — рябь, воздух — косые струи,
			# земля — пыль. Цвет один — это канал, недоступный дальтоникам.
			var mat := SpellVFX.zone_material("aura_breeze", SpellVFX.resist_color(sphere))
			mat.set_shader_parameter("school", SpellVFX.resist_school(sphere))
			return mat
		"bless":
			return SpellVFX.zone_material("aura_bless", Color(1.0, 0.86, 0.38, 1.0))
		_:
			return SpellVFX.zone_material("aura_shield", Color(0.72, 0.52, 1.0, 1.0))


## Ширина корпуса юнита в пикселях — по РАМКЕ ФИГУРЫ, а не по холсту кадра.
## Холст 64 px, фигура ~20 px: кольцо по холсту выходило вдвое шире персонажа.
func _body_width() -> float:
	var r := Game.unit_local_rect(unit)
	if r.size.x > 1.0:
		return r.size.x
	var w := _sprite_width()
	if w > 0.0:
		return w
	return maxf(24.0, _sprite_height() * 0.35)


func _sprite_width() -> float:
	if not is_instance_valid(unit):
		return 0.0
	var anim: Node = unit.get_node_or_null("UnitAnim")
	if anim == null:
		return 0.0
	var sp := anim.get_node_or_null("Sprite") as Sprite2D
	if sp == null or sp.texture == null:
		return 0.0
	return sp.texture.get_width() * absf(sp.scale.x)


## Рамка ФИГУРЫ в координатах юнита (ноги ≈ 0, макушка — отрицательный y).
## Берётся по содержимому кадра, а не по холсту 64×64: фигура занимает ~54 px.
func _figure_rect() -> Rect2:
	var r := Game.unit_local_rect(unit)
	if r.size.y >= 8.0:
		return r
	var h := _sprite_height()
	return Rect2(Vector2(-12.0, -h), Vector2(24.0, h))


## Размер спрайта эффекта В ПИКСЕЛЯХ.
##
## Здесь была главная причина «однотипной точки, которая плавает»: масштаб
## задавался множителем 0.45…1.6 при текстуре 4×4 px, то есть аура выходила
## размером 2–6 пикселей. Считаем от текстуры — SpellVFX.fit_px().
func _size_px() -> Vector2:
	match kind:
		"haste":
			return Vector2(maxf(HASTE_PX.x, _body_width() * 1.15), HASTE_PX.y)
		"shield":
			return SHIELD_PX
		"resist":
			# Тонкий обруч вокруг тела: широкий, но низкий.
			return Vector2(_body_width() + BREEZE_PAD, BREEZE_H)
		"bless":
			return BLESS_PX
		_:
			return Vector2(20.0, 20.0)


func _apply_size() -> void:
	if _sprite == null:
		return
	var sz := _size_px()
	SpellVFX.fit_px(_sprite, sz.x, sz.y)


## Радиус орбиты летающего щита, px: чуть шире корпуса, чтобы щит не утопал в теле.
func _orbit_radius() -> float:
	return maxf(16.0, _body_width() * 0.9 + 8.0)


## Высота спрайта юнита в пикселях. Раньше бралась константа, и у гнома
## эффект висел в воздухе над головой, а у тролля уходил в землю.
func _sprite_height() -> float:
	return Game.unit_visual_height(unit)


func _head_offset() -> float:
	return -(_sprite_height() * HEAD_FACTOR + HEAD_MARGIN)


## Аура ушла — сдвигать больше нечего: кольца защит стоят по школе, а не по
## порядку наложения. Раньше здесь пересчитывался «столбик», и при снятии
## одной защиты остальные прыгали вниз.
func _exit_tree() -> void:
	pass


func _apply_offset() -> void:
	if _sprite == null:
		return
	_sprite.position = Vector2(0, _base_offset + _anim_offset())


## Смещение узла анимации относительно юнита: `_anim.position.y = -рельеф`.
## Фигура рисуется ОТ этого узла, а не от точки на земле. Без этой поправки
## ауры стояли на 20–25 px ниже персонажа — «под ногами» (жалоба 27.10).
func _anim_offset() -> float:
	if not is_instance_valid(unit):
		return 0.0
	var anim: Node2D = unit.get_node_or_null("UnitAnim") as Node2D
	if anim == null:
		return 0.0
	return anim.position.y


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

	# Щит ЛЕТАЕТ: облетает героя по эллипсу и слегка покачивается наклоном.
	# Раньше щит был статичной сеткой вокруг тела, а защиты — точкой, которая
	# качалась вверх-вниз. Покачивание убрано совсем (игрок: «точка плавает
	# туда-сюда»), движение осталось только у щита, где оно осмысленно.
	if kind == "shield" and _sprite != null:
		var ang := _elapsed * 1.5
		var rad := _orbit_radius()
		_sprite.position = Vector2(cos(ang) * rad,
			_base_offset + _anim_offset() + sin(ang) * rad * 0.30)
		_sprite.rotation = sin(ang * 1.2) * 0.22


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
		# Щит мага = броня (shield_armor); враги могут держать absorb-meta.
		return StatusEffects.shield_armor_time(unit) > 0.0 \
			or int(unit.get_meta("shield_strength", 0)) > 0 \
			and float(unit.get_meta("shield_time", 0.0)) > 0.0
	if kind == "resist":
		# Именно СВОЯ стихия: active_types() возвращает типы без сфер, поэтому
		# при четырёх защитах дал бы один «resist» и ни одна аура не исчезла бы
		# после истечения своей.
		return StatusEffects.has_effect(unit, "resist", sphere)
	if kind == "bless":
		return StatusEffects.has_effect(unit, "bless")
	if effect_type == "":
		return true
	return effect_type in StatusEffects.active_types(unit)


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
	SpellVFX.fit_px(s, HEAL_CROSS_PX, HEAL_CROSS_PX)
	var base_scale := s.scale
	# Над макушкой ФИГУРЫ в мировых координатах: точка на земле + подъём узла
	# анимации (рельеф) + верх рамки фигуры. Иначе крест висит под ногами.
	var shift := 0.0
	var anim: Node2D = u.get_node_or_null("UnitAnim") as Node2D
	if anim != null:
		shift = anim.position.y
	var top := shift + Game.unit_local_rect(u).position.y
	s.position = u.global_position + Vector2(0, top - 8.0)
	scene.add_child(s)
	var tw := SpellVFX.world_tween(scene)
	tw.set_parallel(true)
	tw.tween_property(s, "scale", base_scale * 1.3, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.9)
	tw.tween_callback(s.queue_free)
