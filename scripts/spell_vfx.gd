class_name SpellVFX
extends Node
## Процедурные визуальные эффекты заклинаний: ТОЛЬКО шейдеры и генерируемые
## частицы. Готовые кадры из assets/projecticles/* в рантайме не используются.
##
## Важно: Shader компилируется один раз на сферу и кэшируется. Раньше в
## make_projectile создавались новые Image/Shader/ShaderMaterial на КАЖДЫЙ
## каст — шейдер компилировался заново каждый выстрел.
##
## Сферы: Fire plasma, Water гексакристалл, Air молния, Earth трещины,
##        Astral звёздное поле.

const SPHERE_COLORS := {
	"Fire": Color(1.0, 0.4, 0.1),
	"Water": Color(0.2, 0.6, 1.0),
	"Air": Color(0.8, 0.9, 1.0),
	"Earth": Color(0.6, 0.4, 0.2),
	"Astral": Color(0.7, 0.3, 0.9),
}

# --- Кэш (компиляция шейдера дорогая, создаётся один раз) ---
static var _shader_cache: Dictionary = {}
static var _wall_shader_cache: Dictionary = {}
static var _ground_shader_cache: Dictionary = {}
static var _aux_shader_cache: Dictionary = {}
static var _white_tex: ImageTexture = null
static var _spark_tex: Dictionary = {}


static func white_texture() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


static func spark_texture(color: Color) -> ImageTexture:
	var key := color.to_html(false)
	if _spark_tex.has(key):
		return _spark_tex[key]
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	_spark_tex[key] = tex
	return tex


## Шейдер снаряда для сферы (компилируется один раз).
static func projectile_shader(sphere: String) -> Shader:
	if _shader_cache.has(sphere):
		var cached: Shader = _shader_cache[sphere]
		return cached
	var sh := Shader.new()
	sh.code = _shader_code_for(sphere)
	_shader_cache[sphere] = sh
	return sh


static func _shader_code_for(sphere: String) -> String:
	match sphere:
		"Fire": return _fire_shader()
		"Water": return _ice_shader()
		"Air": return _lightning_shader()
		"Earth": return _stone_shader()
		_: return _astral_shader()


static func _sphere_color(sphere: String) -> Color:
	return SPHERE_COLORS.get(sphere, Color.WHITE)


## Цвета ЗАЩИТ — отдельная таблица.
## Глобальные SPHERE_COLORS не трогаем: там огонь оранжевый (1.0, 0.4, 0.1),
## и такой он правильно выглядит на снарядах и стенах. Игрок попросил, чтобы
## защиты читались как: огонь — красный, вода — синий, молния — светло-голубой,
## земля — светло-коричневый.
const RESIST_COLORS := {
	"Fire": Color(1.0, 0.18, 0.12),     # красный
	"Water": Color(0.15, 0.5, 1.0),    # синий
	"Air": Color(0.72, 0.93, 1.0),      # светло-голубой
	"Earth": Color(0.72, 0.55, 0.35),   # светло-коричневый
	"Astral": Color(0.85, 0.6, 1.0),    # на всякий случай
}

## Форма значка защиты. Второй канал кроме цвета: примерно 10 % мужчин не
## различат красный и зелёный, а коричневый и оранжевый близки и на земле.
## 0 = огонь (шипы вверх), 1 = вода (капля), 2 = молния (зигзаг), 3 = земля (блок).
const RESIST_SHAPES := {
	"Fire": 0, "Water": 1, "Air": 2, "Earth": 3, "Astral": 4,
}


## Цвет защиты по сфере (для значка над головой).
static func resist_color(sphere: String) -> Color:
	return RESIST_COLORS.get(sphere, Color.WHITE)


## Номер формы значка защиты по сфере.
static func resist_shape(sphere: String) -> int:
	return int(RESIST_SHAPES.get(sphere, 0))

## Публичный доступ к цвету сферы: им пользуются аuras и зоны, которые
## подкрашиваются по стихии (сопротивление огню — оранжевое, холоду — голубое).
static func sphere_color(sphere: String) -> Color:
	return _sphere_color(sphere)


## Вспомогательный шейдер по ключу (ring/glow/wall) — тоже компилируется один раз.
static func aux_shader(key: String, code: String) -> Shader:
	if _aux_shader_cache.has(key):
		var cached: Shader = _aux_shader_cache[key]
		return cached
	var sh := Shader.new()
	sh.code = code
	_aux_shader_cache[key] = sh
	return sh


static func _scene() -> Node:
	return Engine.get_main_loop().current_scene as Node


# --- Снаряд ---------------------------------------------------------------

## Создать спрайт снаряда заклинания. Материал свой (свой time), шейдер общий.
static func make_projectile(spell_name: String) -> Sprite2D:
	var sphere := SpellDB.sphere_of(spell_name)
	var sprite := Sprite2D.new()
	sprite.z_index = 5
	sprite.texture = white_texture()
	var mat := ShaderMaterial.new()
	mat.shader = projectile_shader(sphere)
	mat.set_shader_parameter("color", _sphere_color(sphere))
	mat.set_shader_parameter("time", 0.0)
	sprite.material = mat
	sprite.scale = Vector2(2.0, 2.0)
	return sprite


## Обновить время в шейдере (каждый кадр).
static func update_shader_time(sprite: Sprite2D, _delta: float, elapsed: float) -> void:
	if sprite != null and sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter("time", elapsed)


# --- Каст -----------------------------------------------------------------

## Вспышка при начале каста (кольцо, растущее наружу).
static func cast_flash(pos: Vector2, sphere: String) -> void:
	var scene := _scene()
	if scene == null:
		return
	# Свет на касте: без него вспышка просто яркая картинка, а не источник.
	# Узел создаётся в сцене, чтобы попасть в y-сортировку вместе с эффектом.
	var holder := Node2D.new()
	holder.position = pos
	scene.add_child(holder)
	SpellLighting.burst_light(holder, _sphere_color(sphere), 58.0, 0.4)
	var color := _sphere_color(sphere)
	var flash := Sprite2D.new()
	flash.z_index = 10
	flash.texture = white_texture()
	var mat := ShaderMaterial.new()
	mat.shader = projectile_shader(sphere)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("time", 0.0)
	flash.material = mat
	flash.position = pos
	flash.scale = Vector2.ZERO
	flash.modulate.a = 0.8
	scene.add_child(flash)
	var tw := scene.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(4.0, 4.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(flash.queue_free)


## Телеграф подготовки заклинания: кольцо, сжимающееся к моменту каста.
## Показывается cast_time секунд — игрок видит, когда заклинание сорвётся.
static func cast_telegraph(pos: Vector2, sphere: String, cast_time: float) -> void:
	var scene := _scene()
	if scene == null:
		return
	var ring := Sprite2D.new()
	ring.z_index = 9
	ring.texture = white_texture()
	var mat := ShaderMaterial.new()
	mat.shader = aux_shader("ring", _ring_shader())
	mat.set_shader_parameter("color", _sphere_color(sphere))
	ring.material = mat
	ring.position = pos
	ring.scale = Vector2(6.0, 6.0)
	ring.modulate.a = 0.7
	scene.add_child(ring)
	var tw := scene.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.2, 1.2), cast_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ring, "modulate:a", 0.95, cast_time)
	tw.chain().tween_callback(ring.queue_free)


## Аура вокруг юнита: бафф (тёплая) или дебафф (фиолетовая).
## Одноразовый всплеск на 0.45 с. Долгие эффекты (щит, Protection_from_*, Haste)
## держатся минутами, поэтому для них нужен SpellAura — см. spawn_aura().
static func aura_ring(unit: Node2D, sphere: String, kind: String) -> void:
	if not is_instance_valid(unit):
		return
	var scene := _scene()
	if scene == null:
		return
	var color := _sphere_color(sphere)
	if kind == "debuff":
		color = Color(0.75, 0.25, 0.95)
	elif kind == "heal":
		color = Color(0.4, 1.0, 0.5)
	var count := 10
	for i in range(count):
		var p := Sprite2D.new()
		p.z_index = 7
		p.texture = spark_texture(color)
		p.position = unit.global_position
		p.modulate.a = 0.9
		scene.add_child(p)
		var angle := TAU * i / count
		var target := unit.global_position + Vector2(cos(angle), sin(angle)) * 34.0
		var tw := scene.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", target, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, 0.5)
		tw.chain().tween_callback(p.queue_free)


# --- Попадание ------------------------------------------------------------

## Взрыв при попадании: ядро + разлетающиеся искры.
static func impact_burst(pos: Vector2, sphere: String, is_aoe: bool) -> void:
	var scene := _scene()
	if scene != null:
		var light_holder := Node2D.new()
		light_holder.position = pos
		scene.add_child(light_holder)
		SpellLighting.burst_light(light_holder, _sphere_color(sphere),
			90.0 if is_aoe else 52.0, 0.45)
		# ВТОРОЙ СЛОЙ: частицы дают то, чего не может статичный шейдер —
		# стохастичную детализацию и историю движения.
		if is_aoe:
			SpellParticles.aoe_debris(scene, pos, _sphere_color(sphere))
		else:
			SpellParticles.impact_sparks(scene, pos, _sphere_color(sphere))
	if scene == null:
		return
	var color := _sphere_color(sphere)
	var count := 14 if is_aoe else 7
	for i in range(count):
		var p := Sprite2D.new()
		p.z_index = 8
		p.texture = spark_texture(color)
		p.position = pos
		p.modulate.a = 0.9
		scene.add_child(p)
		var angle := TAU * i / count + randf_range(-0.3, 0.3)
		var dist := randf_range(30.0, 70.0) if is_aoe else randf_range(14.0, 36.0)
		var target := pos + Vector2(cos(angle), sin(angle)) * dist
		var tw := scene.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", target, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(p, "modulate:a", 0.0, 0.3)
		tw.tween_property(p, "scale", Vector2(0.3, 0.3), 0.3)
		tw.chain().tween_callback(p.queue_free)


## Свет (Astral, self): мягкое свечение вокруг героя.
static func spawn_light(pos: Vector2, life: float) -> void:
	var scene := _scene()
	if scene == null:
		return
	var glow := Sprite2D.new()
	glow.z_index = 2
	glow.texture = white_texture()
	var mat := ShaderMaterial.new()
	mat.shader = aux_shader("glow", _glow_shader())
	mat.set_shader_parameter("color", Color(1.0, 0.95, 0.7))
	mat.set_shader_parameter("time", 0.0)
	glow.material = mat
	glow.position = pos
	glow.scale = Vector2(7.0, 7.0)
	glow.modulate.a = 0.35
	scene.add_child(glow)
	var tw := scene.create_tween()
	tw.tween_property(glow, "modulate:a", 0.18, life * 0.5)
	tw.tween_property(glow, "modulate:a", 0.35, life * 0.5)
	tw.tween_callback(glow.queue_free)


## Молния между двумя точками (призматическое сияние, цепные заклинания).
## Раньше для «многоцелевого» заклинания был только одиночный снаряд, поэтому
## рисовать веер было нечем.
## Радуга для призматического сияния: каждой цели — свой цвет.
## Раньше все лучи красились в цвет СФЕРЫ (Air — светло-голубой), то есть
## «призматическое» сияние выглядело как несколько одинаковых голубых молний.
const RAINBOW := [
	Color(1.0, 0.22, 0.22),   # красный
	Color(1.0, 0.62, 0.15),   # оранжевый
	Color(1.0, 0.95, 0.25),   # жёлтый
	Color(0.35, 0.95, 0.35),  # зелёный
	Color(0.25, 0.7, 1.0),    # голубой
	Color(0.55, 0.4, 1.0),    # синий
	Color(0.95, 0.4, 0.95),   # фиолетовый
]


## Цвет радуги по индексу цели (с циклом по кругу).
static func rainbow_color(index: int) -> Color:
	if RAINBOW.is_empty():
		return Color.WHITE
	return RAINBOW[posmod(index, RAINBOW.size())]


## Молния между двумя точками. color_override — задать свой цвет (радуга);
## если не задан (alpha < 0), берётся цвет сферы.
static func chain_arc(from: Vector2, to: Vector2, sphere: String,
		color_override: Color = Color(-1.0, -1.0, -1.0, 0.0)) -> void:
	var scene := _scene()
	if scene == null:
		return
	var color := color_override if color_override.a >= 0.0 else _sphere_color(sphere)
	var d := to - from
	var length := d.length()
	if length < 1.0:
		return
	# Ломаная из 5 звеньев. Амплитуда РАСТЁТ к середине и падает к концам:
	# раньше у всех внутренних точек был одинаковый разброс, и зигзаг читался
	# как периодическая пила — глаз ловит повтор за ~200 мс. Конус даёт
	# «вспышку» в середине и чистые концы у излучателя и у цели.
	var points: Array[Vector2] = []
	var steps := 5
	var normal := Vector2(-d.y, d.x).normalized()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		# Треугольная огибающая: 0 на концах, 1 в середине.
		var env := 1.0 - absf(t * 2.0 - 1.0)
		var jitter := 0.0 if (i == 0 or i == steps) else length * 0.10 * env
		points.append(from + d * t + normal * randf_range(-jitter, jitter))
	# Слой свечения под основной разряд — иначе тонкая линия почти не видна.
	for pass_index in range(2):
		var line := Line2D.new()
		line.z_index = 9
		line.width = 14.0 if pass_index == 0 else 3.0
		line.default_color = color
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		if pass_index == 0:
			line.default_color = Color(color.r, color.g, color.b, 0.3)
		# В Godot 4 у Line2D нет метода add_points() — точки задаются свойством.
		line.points = points
		scene.add_child(line)
		var tw := scene.create_tween()
		tw.tween_interval(0.16 if pass_index == 0 else 0.1)
		tw.tween_property(line, "modulate:a", 0.0, 0.12)
		tw.tween_callback(line.queue_free)


## Короткий всплеск у НОГ: пыль/искры на земле в момент наложения баффа.
## Раньше на касте баффа рисовалось кольцо из искр вокруг юнита И одновременно
## появлялась постоянная аура — два эффекта в одной точке читались как «дёрнулось
## и наложилось». Теперь для баффов с постоянной аурой кольцо заменено пылью
## у земли: она подчёркивает, что эффект применился, и не спорит с аурой.
static func ground_dust(unit: Node2D) -> void:
	var scene := _scene()
	if scene == null or not is_instance_valid(unit):
		return
	var color := _sphere_color("Earth")
	for i in range(7):
		var p := Sprite2D.new()
		p.z_index = 3
		p.texture = spark_texture(color)
		p.position = unit.global_position
		p.modulate.a = 0.75
		scene.add_child(p)
		var angle := TAU * i / 7.0
		var target := unit.global_position + Vector2(cos(angle), sin(angle) * 0.4) * 30.0
		var tw := scene.create_tween()
		tw.set_parallel(true)
		tw.tween_property(p, "position", target, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, 0.5)
		tw.chain().tween_callback(p.queue_free)


## Стена огня/земли: узел с тикающим уроном и/или блокировкой клеток.
## Размер приходит в КЛЕТКАХ (6 × 2), а не в пикселях: раньше радиус урона,
## ширина спрайта и блок клеток задавались тремя разными числами и не совпадали.
static func spawn_wall(pos: Vector2, sphere: String, owner_unit: Node2D, life: float,
		mode: String = "damage", cells: Vector2i = SpellWall.DEFAULT_CELLS,
		damage: int = 0) -> SpellWall:
	var scene := _scene()
	if scene == null:
		return null
	var wall := SpellWall.new()
	wall.position = pos
	wall.set_mode(mode)
	# Стиль и наличие языков пламени — по сфере. В оригинале стены РАЗНЫЕ
	# (spells.txt): огонь непрерывно жжёт, земля — непроходимая преграда.
	# Огонь получает третий слой поверх юнитов, земля остаётся плоской.
	wall.flame = sphere == "Fire"
	wall.style = "wall_fire" if wall.flame else "wall_earth"
	scene.add_child(wall)
	wall.configure(damage, cells, sphere, owner_unit, life)
	return wall


## Зона заклинания общего типа: метель, ядовитое облако.
## Стиль выбирает отрисовку ("hail" — падающие осколки, "cloud" — туман),
## mode "damage" — тикает урон, "block" — непроходимая преграда.
static func spawn_zone(pos: Vector2, style: String, sphere: String, owner_unit: Node2D,
		life: float, cells: Vector2i, damage: int, tick_interval: float = 0.5) -> SpellZone:
	var scene := _scene()
	if scene == null:
		return null
	var zone := SpellZone.new()
	zone.position = pos
	zone.style = style
	zone.mode = "damage"
	zone.tick_interval = maxf(0.1, tick_interval)
	scene.add_child(zone)
	zone.configure(damage, cells, sphere, owner_unit, life)
	return zone


## Падающий ледяной осколок метели.
static func hail_shard(pos: Vector2) -> void:
	var scene := _scene()
	if scene == null:
		return
	var s := Sprite2D.new()
	s.z_index = 9
	s.texture = spark_texture(Color(0.8, 0.92, 1.0))
	s.position = pos + Vector2(0, -26)
	s.scale = Vector2(1.6, 3.0)
	s.material = zone_material("shard", Color(0.85, 0.94, 1.0, 1.0))
	s.modulate.a = 0.95
	scene.add_child(s)
	var tw := scene.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "position", pos + Vector2(0, 8), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(s, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(s.queue_free)


## Материал зоны/осколка. Кэш берётся общий (aux_shader), иначе на каждый
## осколок компилировался бы новый Shader.
static func zone_material(style: String, color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	# render_mode подставляется по стилю: ауры над юнитом самосветящиеся
	# (unshaded + additive), наземные зоны смешиваются с землёй.
	mat.shader = aux_shader("zone_" + style, _zone_shader_with_mode(style))
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("time", 0.0)
	return mat


## Цвет огненной стены. Игрок попросил РОВНЫЙ красно-оранжевый: сфера Fire
## даёт (1.0, 0.4, 0.1), и на 6×2 поле с HDR это читалось как рыжая плёнка.
## Языки пламени держат один hue, а яркость даёт ядро, а не смена оттенка.
const FLAME_WALL_COLOR := Color(1.0, 0.30, 0.06)


## Материал языков пламени для огненной стены.
##
## Ключевое: слой рисуется ПОВЕРХ юнитов (решение игрока), поэтому он
## самосветящийся (unshaded + additive) и не должен быть плотной заливкой —
## заливка земли остаётся под юнитами и отвечает за границы опасной зоны.
##
## Ширина языков ЖЁСТКО ограничена прямоугольником зоны (по UV.x), а вверх они
## выходят за его пределы. Это важно для «визуал не врёт»: пламя не должно
## выглядеть так, будто горит больше клеток, чем реально бьёт. По вертикали
## выход над зоной допустим — огонь вверх растёт, опасная зона от этого не
## расширяется.
static func flame_wall_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = aux_shader("flame_wall", _flame_wall_shader())
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("time", 0.0)
	mat.set_shader_parameter("rise", 1.0)
	return mat


static func _flame_wall_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(1.0, 0.30, 0.06, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;
uniform float rise : hint_range(0.1, 4.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// 0 внизу (у земли), 1 вверху (кончик языка).
	float h = clamp((1.0 - UV.y) * rise, 0.0, 1.0);

	// Доменное искажение: иначе все языки одинаковой формы и глаз ловит
	// периодичность. Искажаем САМУ выборку шума, а не покрытие.
	vec2 q = vec2(UV.x * 9.0, UV.y * 2.2 - time * 1.15);
	float warp = fbm(q * 1.7 + vec2(0.0, -time * 0.45));
	q.x += (warp - 0.5) * 1.35;

	// Язык = вертикальная полоса шума, поднятая порогом. Порог растёт с
	// высотой: у земли языки широкие, кверху — тонкие и рваные.
	float n = fbm(q);
	float t = 1.0 - h;
	float body = smoothstep(0.62 - t * 0.30, 0.92 - t * 0.30, n);

	// Кончики: чем выше, тем меньше шанс догореть.
	float tips = smoothstep(0.30, 0.85, h);
	body *= 1.0 - smoothstep(0.55, 1.0, h) * 0.85;

	// У земли огонь плотнее — там горит, а не дымит.
	float base_glow = (1.0 - smoothstep(0.0, 0.22, h)) * 0.55;

	float m = clamp(body + base_glow, 0.0, 1.0);
	m *= 0.75 + 0.25 * tips;
	if (m < 0.03) {
		discard;
	}

	// Ядро светлее и HDR — значение выше 1.0, иначе с glow это плоское пятно.
	// Но 0 % и 100 % читаются как интерфейс, поэтому ядро не доводим до белого.
	vec3 col = mix(color.rgb * 1.15, color.rgb * 0.5 + vec3(0.85, 0.75, 0.45),
		body * 0.45);
	COLOR = vec4(col * m * 1.8, 1.0);
}"""


## Наземная зона заклинания. Один шейдер на стену/метель/облако.
##
## Ключевое отличие от прежнего: вся математика идёт в МИРОВЫХ координатах,
## а не в UV. Раньше один белый квад 4x4 растягивался до 192x64 и UV
## сжимались в 6 раз по горизонтали — отсюда «глюк на земле» и ощущение,
## что эффект «не в клетках». Мировая сетка даёт одинаковый масштаб зерна
## у 3x3 облака и 6x2 стены, и привязывает эффект к клеткам мира.
##
## nb — битовая маска соседей: 1=N 2=E 4=S 8=W 16=NE 32=SE 64=SW 128=NW.
## Контур рисуется ТОЛЬКО по сторонам, где соседа нет, поэтому 12 клеток
## читаются как один прямоугольник, а не как 12 квадратиков.
static func _ground_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;
uniform float tile_px = 32.0;
// Стиль: 0 = стена (огонь/камень), 1 = метель, 2 = ядовитое облако.
uniform int style : hint_range(0, 2) = 0;
uniform vec2 cells = vec2(6.0, 2.0);
uniform vec2 origin_cell = vec2(0.0, 0.0);
uniform int nb = 0;
// Фаза: 0 = телеграф (только контур), 1 = активна.
uniform float active = 0.0;
// 0..1 — растворение на затухании.
uniform float burn = 0.0;
// Заливка намеренно слабая: юниты в зоне должны оставаться видимыми.
uniform float fill_a : hint_range(0.0, 1.0) = 0.20;
uniform float edge_w : hint_range(1.0, 8.0) = 3.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

// Профиль контура. GLSL не поддерживает вложенные функции (это C), поэтому
// объявляем на верхнем уровне и передаём толщину параметром.
float edge(float d, float lw) {
	return 1.0 - smoothstep(lw * 0.4, lw, d);
}

// Шум в МИРОВЫХ координатах + domain warping: одна гладкая волна
// превращается в органическое самоперекрывающееся поле.
float field(vec2 w) {
	vec2 p = w / 42.0;
	vec2 q = vec2(fbm(p + vec2(0.0, time * 0.25)),
	              fbm(p + vec2(5.2, 1.3) - vec2(time * 0.2, 0.0)));
	vec2 r = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm(p + 2.5 * r);
}

void fragment() {
	vec2 w = world;
	vec2 cid = floor(w / tile_px);
	vec2 cuv = fract(w / tile_px);

	// Соседи: рисуем сторону, только если сосед вне зоны.
	bool n_out  = (nb &   1) == 0;
	bool e_out  = (nb &   2) == 0;
	bool s_out  = (nb &   4) == 0;
	bool w_out  = (nb &   8) == 0;

	float dN = cuv.y;
	float dS = 1.0 - cuv.y;
	float dW = cuv.x;
	float dE = 1.0 - cuv.x;

	float lw = edge_w / tile_px;   // толщина контура в долях клетки

	float border = 0.0;
	if (n_out) { border = max(border, edge(dN, lw)); }
	if (s_out) { border = max(border, edge(dS, lw)); }
	if (w_out) { border = max(border, edge(dW, lw)); }
	if (e_out) { border = max(border, edge(dE, lw)); }

	// Внешние углы скругляем, вогнутые оставляем прямыми (вогнутая
	// «зарубка» читается правильно, скруглённая выглядит кляксой).
	float r = 0.34;
	if (n_out && w_out && (nb & 128) != 0) { border *= 1.0 - smoothstep(0.0, r, length(vec2(dW, dN)) - r); }
	if (s_out && e_out && (nb &  32) != 0) { border *= 1.0 - smoothstep(0.0, r, length(vec2(dE, dS)) - r); }

	// Телеграф: заливка идёт вдоль длинной оси зоны, по клеткам, а не
	// по UV — так направление стены читается однозначно.
	float along = cells.x > 1.0 ? (cid.x - origin_cell.x) / (cells.x - 1.0) : 0.0;
	if (cells.y > cells.x) {
		along = cells.y > 1.0 ? (cid.y - origin_cell.y) / (cells.y - 1.0) : 0.0;
	}
	float wipe = clamp(along, 0.0, 1.0);

	float n = field(w);

	// Мягкий край: зона не должна быть прямоугольным «баннером».
	float inner = min(min(cuv.x, 1.0 - cuv.x), min(cuv.y, 1.0 - cuv.y));
	float soft = smoothstep(0.0, 0.12, inner);

	float alpha_fill = fill_a * soft * n * active * step(wipe, mix(-0.15, 1.25, active));
	float alpha_edge = border * (0.55 + 0.45 * sin(time * 5.0)) * (0.25 + 0.75 * active);

	// Растворение на затухании вместо линейного затухания modulate.a.
	float e = smoothstep(burn, burn + 0.18, n);
	float a = (alpha_fill * e + alpha_edge * (1.0 - burn)) * soft;
	if (a < 0.004) {
		discard;
	}

	// Ярче к центру (правило «это излучает свет»), но НЕ чисто белый:
	// 0% и 100% принадлежат интерфейсу, а не эффекту.
	vec3 col = mix(color.rgb * 0.65, color.rgb, n);
	col = mix(col, rim_color.rgb, border * 0.6);
	COLOR = vec4(col, a);
}"""

## Материал наземной зоны. Один шейдер на все стили (стиль — uniform int),
## потому что зон три, а логика у них одна.
static func ground_material(sphere: String, style: String) -> ShaderMaterial:
	if _ground_shader_cache.is_empty():
		var sh := Shader.new()
		sh.code = _ground_shader()
		_ground_shader_cache["ground"] = sh
	var mat := ShaderMaterial.new()
	var cached: Shader = _ground_shader_cache["ground"]
	mat.shader = cached
	mat.set_shader_parameter("color", _sphere_color(sphere))
	mat.set_shader_parameter("rim_color", _sphere_color(sphere).lerp(Color(1, 1, 1), 0.55))
	mat.set_shader_parameter("time", 0.0)
	mat.set_shader_parameter("active", 0.0)
	mat.set_shader_parameter("burn", 0.0)
	return mat


static func wall_material(sphere: String) -> ShaderMaterial:
	if not _wall_shader_cache.has(sphere):
		var sh := Shader.new()
		sh.code = _wall_shader()
		_wall_shader_cache[sphere] = sh
	var mat := ShaderMaterial.new()
	var cached: Shader = _wall_shader_cache[sphere]
	mat.shader = cached
	mat.set_shader_parameter("color", _sphere_color(sphere))
	mat.set_shader_parameter("time", 0.0)
	return mat


# --- Вспышки на юните -----------------------------------------------------

## Попадание по щиту: голубая вспышка. Раньше не вызывалась ни разу.
static func shield_hit(unit: Node2D) -> void:
	_flash_unit(unit, Color(0.5, 0.7, 1.0, 1.0), 0.12)


## Вспышка получения урона.
static func hit_flash(unit: Node2D) -> void:
	_flash_unit(unit, Color(1.0, 0.3, 0.3, 1.0), 0.1)


## Невидимого юнита видно полупрозрачным (для отладки и попаданий).
static func invisible_tint(unit: Node2D, alpha: float) -> void:
	if is_instance_valid(unit):
		unit.modulate.a = clampf(alpha, 0.15, 1.0)


static func _flash_unit(unit: Node2D, color: Color, seconds: float) -> void:
	if not is_instance_valid(unit):
		return
	var anim := unit.get_node_or_null("UnitAnim")
	if anim == null:
		return
	var original: Color = anim.modulate
	anim.modulate = color
	var tree := unit.get_tree()
	if tree == null:
		return
	await tree.create_timer(seconds, true, false, true).timeout
	if is_instance_valid(anim):
		anim.modulate = original


# === Шейдеры ===

static func _noise_prelude() -> String:
	return """float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}

"""
## Огонь. Раньше: sin(uv.x*9 + t*6) * cos(uv.y*11 - t*4) — периодичная
## сетка, которая и читалась как «1990-е». Теперь: warped-шум, вертикальный
## подъём, яркое ядро со значением ВЫШЕ 1.0 (нужно для bloom при hdr_2d).
static func _fire_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}



void fragment() {
	vec2 uv = UV;
	float d = length(uv - vec2(0.5)) * 2.0;
	if (d > 1.0) { discard; }
	vec2 p = vec2(uv.x * 3.0, uv.y * 2.2 - time * 0.9);
	float n = warped(p, time);
	float flame = pow(max(0.0, n * 1.35 - 0.18), 1.5);
	float body = core(d) * (0.45 + 0.85 * flame);
	// Тёмный ободок -> цвет сферы -> горячее ядро. НЕ чисто белый:
	// 0% и 100% в эффектах читаются как интерфейс, а не как магия.
	vec3 col = mix(color.rgb * 0.45, color.rgb, flame);
	col = mix(col, vec3(1.0, 0.86, 0.55), core(d) * 0.55);
	// Ядро выводим за 1.0 — hdr_2d превращает это в свечение.
	COLOR = vec4(col * body * 1.7, 1.0);
}"""


## Лёд: гребневая текстура даёт острые грани, которых не даёт fbm.
static func _ice_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}



void fragment() {
	vec2 uv = UV;
	float d = length(uv - vec2(0.5)) * 2.0;
	if (d > 1.0) { discard; }
	vec2 p = uv * 4.0 + vec2(time * 0.2, -time * 0.35);
	float cr = ridged(p) * ridged(p * 1.7 + 3.3);
	float facet = pow(clamp(cr, 0.0, 1.0), 2.2);
	float body = core(d) * (0.3 + 1.1 * facet);
	vec3 col = mix(color.rgb * 0.5, color.rgb, facet);
	col = mix(col, vec3(0.85, 0.95, 1.0), core(d) * 0.6);
	COLOR = vec4(col * body * 1.5, 1.0);
}"""


## Молния: ветви из ridged-шума + тонкий горячий канал. Высокий контраст,
## узкая полоса — иначе выглядит как светящееся пятно, а не разряд.
static func _lightning_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}



void fragment() {
	vec2 uv = UV;
	float d = length(uv - vec2(0.5)) * 2.0;
	if (d > 1.0) { discard; }
	vec2 p = vec2(uv.x * 3.0, uv.y * 1.2);
	float br = ridged(p * 2.0 + vec2(0.0, time * 1.4));
	float branch = pow(clamp(br, 0.0, 1.0), 6.0);
	float channel = pow(max(0.0, 1.0 - abs(uv.x - 0.5) * 3.2), 3.0);
	float flicker = 0.72 + 0.28 * fbm2(vec2(time * 6.0, 0.0));
	float body = (branch * 0.9 + channel * 0.8) * flicker * core(d);
	vec3 col = mix(color.rgb * 0.6, color.rgb, channel);
	col = mix(col, vec3(0.95, 0.98, 1.0), channel * 0.7);
	COLOR = vec4(col * body * 2.0, 1.0);
}"""


## Камень: трещины. Ridged-шум с порогом даёт тонкие ветвящиеся трещины,
## которых не даёт fbm (у него слишком мягкие границы).
static func _stone_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(0.6, 0.4, 0.2, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}



void fragment() {
	vec2 uv = UV;
	float d = length(uv - vec2(0.5)) * 2.0;
	if (d > 1.0) { discard; }
	float cr = ridged(uv * 3.4 + vec2(time * 0.08, 0.0));
	float crack = pow(clamp(cr, 0.0, 1.0), 5.0);
	float dust = warped(uv * 2.6 + 4.4, time * 0.5);
	float body = core(d) * (0.25 + 1.3 * crack + 0.35 * dust);
	vec3 col = mix(color.rgb * 0.4, color.rgb, crack);
	col = mix(col, vec3(1.0, 0.88, 0.7), crack * 0.5);
	COLOR = vec4(col * body * 1.4, 1.0);
}"""


## Астрал: туманность из warped-шума + настоящие звёзды из хеша.
static func _astral_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(0.7, 0.3, 0.9, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}



void fragment() {
	vec2 uv = UV;
	float d = length(uv - vec2(0.5)) * 2.0;
	if (d > 1.0) { discard; }
	float neb = warped(uv * 2.2 + 9.1, time * 0.35);
	// Звёзды: хеш по ячейкам, яркие и редкие.
	vec2 gp = uv * 14.0;
	vec2 gi = floor(gp);
	float h = hash21(gi);
	float star = pow(max(0.0, 1.0 - length(fract(gp) - 0.5) * 2.0), 12.0)
		* step(0.86, h) * (0.6 + 0.4 * sin(time * 3.0 + h * 30.0));
	float body = core(d) * (0.3 + 1.0 * neb) + star * 1.4;
	vec3 col = mix(color.rgb * 0.4, color.rgb, neb);
	col = mix(col, vec3(0.95, 0.85, 1.0), star);
	COLOR = vec4(col * body * 1.5, 1.0);
}"""


## Кольцо ауры: мягкий ободок с шумовым разрывом, ярче к центру кольца.
static func _ring_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}



void fragment() {
	vec2 uv = UV;
	float d = length(uv - vec2(0.5)) * 2.0;
	if (d > 1.0) { discard; }
	float wob = (fbm2(uv * 3.0 + time * 0.6) - 0.5) * 0.10;
	float r = d + wob;
	float ring = 1.0 - smoothstep(0.0, 0.20, abs(r - 0.74));
	float halo = core(d) * 0.22;
	float body = (ring + halo) * (0.7 + 0.3 * warped(uv * 2.0, time));
	vec3 col = mix(color.rgb * 0.55, color.rgb, ring);
	col = mix(col, vec3(1.0, 0.95, 0.8), ring * 0.5);
	COLOR = vec4(col * body * 1.6, 1.0);
}"""


## Свечение: радиальное с ярким ядром и HDR-запасом. Без значения выше 1.0
## это просто «яркая картинка», а не свечение — glow нужен hdr_2d.
static func _glow_shader() -> String:
	return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + 11.3;
		a *= 0.5;
	}
	return v;
}

float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + 5.7;
		a *= 0.5;
	}
	return v;
}

// Domain warping: вложенный fbm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в органическое самоперекрывающееся
// поле. Это главное отличие от прежних шейдеров на голых sin/cos: синус
// идеально периодичен, глаз ловит это за ~200 мс и читает картинку как
// синтетическую (эффект из демосцены, а не «магия»).
float warped(vec2 p, float t) {
	vec2 q = vec2(fbm2(p + vec2(0.0, t * 0.25)),
	              fbm2(p + vec2(5.2, 1.3) - vec2(t * 0.2, 0.0)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.2 * r);
}

// Профиль круга: 1 в центре, 0 у края. Эффект ДОЛЖЕН быть ярче к центру —
// равномерная яркость не имеет фокуса и читается как плоская наклейка.
float core(float d) {
	return pow(max(0.0, 1.0 - d), 1.6);
}



void fragment() {
	vec2 uv = UV;
	float d = length(uv - vec2(0.5)) * 2.0;
	if (d > 1.0) { discard; }
	float n = warped(uv * 2.4, time * 0.5);
	float body = pow(max(0.0, 1.0 - d), 2.4) * (0.55 + 0.75 * n);
	vec3 col = mix(color.rgb * 0.6, color.rgb, n);
	COLOR = vec4(col * body * 2.2, 1.0);
}"""


static func _wall_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV;
	// Языки пламени/камни: вертикальный градиент + шум, края рваные
	float rise = fract(uv.y * 2.0 - time * 1.4);
	float n = sin(uv.x * 14.0 + time * 3.0) * cos(uv.y * 9.0 - time * 2.0);
	float body = smoothstep(0.0, 0.35, uv.y) * smoothstep(1.0, 0.55, uv.y);
	float edge = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	float a = body * edge * (0.55 + 0.45 * rise) * (0.75 + 0.25 * n);
	vec3 col = mix(color.rgb, vec3(1.0, 0.95, 0.7), rise * 0.5);
	COLOR = vec4(col, a * 0.85);
}"""


## Шейдеры зон заклинания. Стиль выбирается строкой, потому что зон три, а
## логика у них одна (прямоугольник + необязательная блокировка клеток).
## Код шейдера с подставленным render_mode.
static func _zone_shader_with_mode(style: String) -> String:
	var mode := _zone_render_mode(style)
	if mode.is_empty():
		return _zone_shader(style)
	return mode + _zone_shader(style)

## Render mode по стилю зоны.
## Ауры над юнитом (щит, сопротивление, ветер, крест) и огненные осколки
## рисуются как САМОСВЕЧЕНИЕ: unshaded + additive. Раньше у них не было
## render_mode вообще, то есть они считались освещаемыми — а источников света
## в сцене почти нет, и ambient гасил их на ~12 %, а на светлой траве щит с
## альфой 0.22 пропадал совсем.
## Наземные зоны (стена/метель/облако) остаются blend_mix: они лежат на земле
## и должны смешиваться с ней, а не выжигать.
static func _zone_render_mode(style: String) -> String:
	match style:
		"aura_shield", "aura_up", "aura_wind", "heal_cross", "shard":
			return "render_mode blend_add, unshaded;\n"
		_:
			return ""


static func _zone_shader(style: String) -> String:
	match style:
		"hail":
			return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.85, 0.94, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Метель: снежная крупа, полосы сносит ветром по диагонали.
	vec2 uv = UV;
	float w = uv.x * 6.0 - time * 1.6;
	float h = uv.y * 4.0 + time * 2.2;
	float flakes = sin(w * 6.2831) * sin(h * 6.2831);
	flakes = smoothstep(0.35, 0.95, flakes);
	// Холодное свечение у земли, прозрачное к верху.
	float ground = smoothstep(1.0, 0.35, uv.y);
	float a = flakes * (0.35 + 0.65 * ground);
	COLOR = vec4(color.rgb, a * 0.55);
}"""
		"shard":
			return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.85, 0.94, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Осколок: вытянутый по вертикали кристалл с острыми краями.
	vec2 uv = UV;
	vec2 p = uv * 2.0 - 1.0;
	p.x *= 2.6;
	float body = 1.0 - smoothstep(0.25, 1.0, abs(p.x));
	float tip = 1.0 - smoothstep(0.6, 1.0, abs(p.y));
	float facet = 0.6 + 0.4 * sin(p.x * 8.0 + time * 6.0);
	float a = body * tip * facet;
	COLOR = vec4(color.rgb, a * 0.9);
}"""
		"cloud":
			return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.55, 0.85, 0.42, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Ядовитое облако: два слоя клубящегося шума, клубы ползут вверх.
	vec2 uv = UV;
	float n1 = sin(uv.x * 7.0 + time * 1.1) * cos(uv.y * 5.0 - time * 0.9);
	float n2 = sin(uv.x * 11.0 - time * 1.7) * cos(uv.y * 9.0 + time * 1.3);
	float f = 0.5 + 0.25 * n1 + 0.25 * n2;
	// Мягкий круглый край, чтобы облако не было прямоугольным баннером.
	vec2 d = uv - 0.5;
	float round = 1.0 - smoothstep(0.32, 0.5, length(d));
	float a = smoothstep(0.35, 0.9, f) * round;
	COLOR = vec4(color.rgb, a * 0.6);
}"""
		"aura_shield":
			return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.72, 0.52, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Щит: едва заметная сетка вокруг персонажа. Должна читаться как защита,
	// а не как светящийся шар — поэтому линии тонкие и полупрозрачные.
	vec2 uv = UV;
	vec2 p = uv * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// Гексагональная сетка из двух наборов диагоналей.
		float a1 = abs(fract((p.x * 3.0 + p.y * 3.0) * 2.0) - 0.5);
		float a2 = abs(fract((p.x * 3.0 - p.y * 3.0) * 2.0) - 0.5);
		float grid = smoothstep(0.34, 0.5, max(a1, a2));
		float pulse = 0.78 + 0.22 * sin(time * 2.2);
		// Ободок — основной носитель информации: по нему видно границу щита.
		float shell = smoothstep(0.68, 1.0, r);
		float alpha = (grid * 0.55 + shell * 0.9) * pulse;
		// Ядро ободка выводим за 1.0 — hdr_2d превращает это в свечение.
		vec3 col = mix(color.rgb, vec3(0.92, 0.85, 1.0), shell * 0.7);
		COLOR = vec4(col * (1.0 + shell * 1.2), alpha);
	}
}"""
		"aura_up":
			return """shader_type canvas_item;
render_mode blend_add, unshaded;
uniform vec4 color : source_color = vec4(1.0, 0.18, 0.12, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;
// Форма значка: 0 огонь, 1 вода, 2 молния, 3 земля, 4 астрал.
uniform int shape : hint_range(0, 4) = 0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float m = 0.0;
	if (shape == 0) {
		// ОГОНЬ: три шипа вверх, средний выше, края рваные.
		float t = clamp((p.y + 0.5) * 2.0, 0.0, 1.0);
		float w = (1.0 - t) * 0.42;
		float tip = abs(p.x);
		float sp = 0.0;
		sp = max(sp, 1.0 - smoothstep(0.0, w, tip - p.y * 0.18));
		sp = max(sp, 1.0 - smoothstep(0.0, w * 0.8, tip + p.x * 0.35));
		sp = max(sp, 1.0 - smoothstep(0.0, w * 0.7, tip - p.x * 0.30));
		m = clamp(sp, 0.0, 1.0) * smoothstep(-0.48, -0.34, p.y);
	} else if (shape == 1) {
		// ВОДА: капля — острая сверху, круглая снизу.
		float d = length(vec2(p.x, max(0.0, p.y) * 1.25));
		float body = 1.0 - smoothstep(0.20, 0.28, d);
		float tip = 1.0 - smoothstep(0.0, 0.40, length(vec2(p.x * 0.55, (p.y + 0.16) * 1.6))
			+ max(0.0, p.y) * 1.4);
		m = max(body, tip) * 0.9;
	} else if (shape == 2) {
		// МОЛНИЯ: зигзаг вверх-вниз, самый яркий из четырёх.
		float zig = abs(p.x) - (0.06 + 0.16 * abs(fract(p.y * 1.6 + 0.25) - 0.5) * 2.0);
		m = 1.0 - smoothstep(0.0, 0.075, zig);
		m *= smoothstep(-0.46, -0.30, p.y) * smoothstep(0.46, 0.30, p.y);
	} else if (shape == 3) {
		// ЗЕМЛЯ: сплошной блок с каменной крошкой по контуру.
		vec2 q = abs(p);
		float box = step(q.x, 0.26) * step(q.y, 0.24);
		float grain = 0.72 + 0.28 * vnoise(p * 14.0 + vec2(time * 0.25, 0.0));
		m = box * grain;
		float edge = (1.0 - step(q.x, 0.30)) * step(0.22, q.y) * step(q.y, 0.28)
			+ (1.0 - step(q.y, 0.28)) * step(0.22, q.x) * step(q.x, 0.30);
		m = max(m, edge * 0.9);
	} else {
		float d = length(p);
		m = pow(max(0.0, 1.0 - d * 1.6), 2.0);
	}
	if (m < 0.02) {
		discard;
	}
	float pulse = 0.80 + 0.20 * sin(time * 3.0);
	// Ядро светлее, но НЕ чисто белый: 0 % и 100 % читаются как интерфейс.
	vec3 col = mix(color.rgb, color.rgb * 0.45 + vec3(0.55), m * 0.5);
	COLOR = vec4(col * m * pulse * 1.6, 1.0);
}"""
		"aura_wind":
			return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.75, 1.0, 0.8, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Ускорение: полосы ветра струятся мимо ног слева направо.
	vec2 uv = UV;
	float lane = floor(uv.y * 3.0);
	float speed = 1.6 + lane * 0.35;
	float streak = fract(uv.x * 2.0 - time * speed + lane * 0.37);
	float line = smoothstep(0.0, 0.12, streak) * smoothstep(0.42, 0.16, streak);
	// Гаснем по краям, чтобы полосы не обрезались квадратом.
	float edge = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	float a = line * edge * 0.55;
	COLOR = vec4(color.rgb, a);
}"""
		"heal_cross":
			return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Лечение: красный крест, медленно вращается и пульсирует.
	vec2 p = UV - vec2(0.5, 0.5);
	float s = sin(time * 1.4);
	float c = cos(time * 1.4);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	float bar_h = step(abs(p.x), 0.10) * step(abs(p.y), 0.34);
	float bar_v = step(abs(p.y), 0.10) * step(abs(p.x), 0.34);
	float cross = clamp(bar_h + bar_v, 0.0, 1.0);
	float pulse = 0.75 + 0.25 * sin(time * 5.0);
	COLOR = vec4(color.rgb, cross * pulse * 0.95);
}"""
		_:
			return _wall_shader()
