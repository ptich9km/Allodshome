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


## Стена огня/земли: узел с тикающим уроном и/или блокировкой клеток.
static func spawn_wall(pos: Vector2, sphere: String, owner_unit: Node2D, life: float,
		mode: String = "damage", width: float = 72.0, damage: int = 0) -> SpellWall:
	var scene := _scene()
	if scene == null:
		return null
	var wall := SpellWall.new()
	wall.position = pos
	wall.width = width
	wall.set_mode(mode)
	scene.add_child(wall)
	wall.configure(damage, width, sphere, owner_unit, life)
	return wall


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

static func _fire_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Плазменное ядро: горячий центр, рваный край через шум
	float n = sin(uv.x * 9.0 + time * 6.0) * cos(uv.y * 11.0 - time * 4.0);
	float r = 0.34 + 0.07 * sin(time * 9.0) + n * 0.05;
	float core = smoothstep(r, r * 0.25, d);
	float edge = smoothstep(r, r * 0.75, d);
	vec3 hot = mix(color.rgb, vec3(1.0, 0.92, 0.65), core);
	vec3 col = mix(hot, color.rgb * 0.7, edge);
	COLOR = vec4(col, edge * 0.92);
}"""


static func _ice_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Гексакристалл: шестигранная маска + холодный блеск по грани
	float a = atan(uv.y, uv.x);
	float hex = cos(a * 3.0 + time * 1.5) * 0.12 + 0.34;
	float body = smoothstep(hex, hex * 0.55, d);
	float facet = pow(max(0.0, cos(a * 3.0 + time * 0.8)), 6.0);
	float sparkle = pow(max(0.0, sin(uv.x * 18.0 + time * 3.0) * sin(uv.y * 16.0 - time * 2.0)), 10.0);
	vec3 col = mix(color.rgb * 0.55, vec3(0.9, 0.97, 1.0), facet * 0.5 + sparkle * 0.6);
	COLOR = vec4(col, body * 0.88);
}"""


static func _lightning_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Молния: яркое ядро + ветвление, которое быстро мерцает
	float core = smoothstep(0.36, 0.04, d);
	float branch = sin(uv.x * 26.0 + time * 14.0) * cos(uv.y * 21.0 - time * 11.0);
	branch = smoothstep(0.45, 0.9, abs(branch));
	float flicker = 0.75 + 0.25 * sin(time * 40.0);
	float glow = (core + branch * 0.35 * (1.0 - core)) * flicker;
	vec3 col = mix(color.rgb, vec3(1.0), core * 0.85);
	COLOR = vec4(col, clamp(glow, 0.0, 1.0) * 0.95);
}"""


static func _stone_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.6, 0.4, 0.2, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	float rock = smoothstep(0.42, 0.12, d);
	// Трещины расходятся от центра и медленно «дышат»
	float crack = sin((uv.x + uv.y) * 13.0 + time * 1.5) * sin((uv.x - uv.y) * 11.0 - time);
	crack = smoothstep(0.78, 0.95, abs(crack));
	vec3 col = color.rgb * (0.65 + crack * 0.5);
	col *= mix(0.55, 1.0, smoothstep(-0.3, 0.15, uv.y));
	COLOR = vec4(col, rock * 0.95);
}"""


static func _astral_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.7, 0.3, 0.9, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Туманность: два слоя шума + «звёзды» (резкие точки)
	float n1 = sin(uv.x * 7.0 + time * 0.9) * cos(uv.y * 6.0 - time * 0.7);
	float n2 = sin((uv.x + uv.y) * 11.0 - time * 1.3);
	float nebula = smoothstep(0.45, 0.05, d) * (0.5 + 0.5 * n1 * n2);
	float stars = pow(max(0.0, sin(uv.x * 40.0 + time * 3.0) * sin(uv.y * 36.0 - time * 2.0)), 18.0);
	vec3 col = color.rgb * (0.6 + nebula * 0.8) + vec3(stars * 0.9);
	COLOR = vec4(col, clamp(nebula + stars * 0.8, 0.0, 1.0) * 0.9);
}"""


static func _ring_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Тонкое кольцо с мягким краем — телеграф каста
	float ring = smoothstep(0.42, 0.34, d) * smoothstep(0.22, 0.32, d);
	COLOR = vec4(color.rgb, ring * 0.9);
}"""


static func _glow_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	float g = smoothstep(0.5, 0.0, d);
	float breathe = 0.85 + 0.15 * sin(time * 2.0);
	COLOR = vec4(color.rgb, g * 0.55 * breathe);
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
