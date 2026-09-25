class_name SpellVFX
extends Node
## Процедурные визуальные эффекты заклинаний (гибрид: шейдеры + частицы + tween).
## Используется Projectile, Player, Enemy для отрисовки магии.

## Цвета сфер
const SPHERE_COLORS := {
	"Fire": Color(1.0, 0.4, 0.1),
	"Water": Color(0.2, 0.6, 1.0),
	"Air": Color(0.8, 0.9, 1.0),
	"Earth": Color(0.6, 0.4, 0.2),
	"Astral": Color(0.7, 0.3, 0.9),
}

## Создать снаряд с процедурным шейдером
static func make_projectile(spell_name: String) -> Sprite2D:
	var sphere := SpellDB.sphere_of(spell_name)
	var sprite := Sprite2D.new()
	sprite.z_index = 5

	# Базовая текстура (1 пиксель, растянутая шейдером)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(img)

	# Шейдер по типу снаряда
	var shader := Shader.new()
	match spell_name:
		"Fire_Arrow", "Fire_Ball":
			shader.code = _fire_shader()
		"Ice_Missile":
			shader.code = _ice_shader()
		"Lightning", "Prismatic_Spray":
			shader.code = _lightning_shader()
		"Stone_Missile", "Diamond_Dust":
			shader.code = _stone_shader()
		_:
			shader.code = _generic_shader(SPHERE_COLORS.get(sphere, Color.WHITE))

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("color", SPHERE_COLORS.get(sphere, Color.WHITE))
	mat.set_shader_parameter("time", 0.0)
	sprite.material = mat
	sprite.scale = Vector2(2.0, 2.0)
	return sprite

## Обновить время в шейдере (вызывать каждый кадр)
static func update_shader_time(sprite: Sprite2D, delta: float, elapsed: float) -> void:
	if sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter("time", elapsed)

## Вспышка при касте заклинания
static func cast_flash(pos: Vector2, sphere: String) -> void:
	var color: Color = SPHERE_COLORS.get(sphere, Color.WHITE)
	var flash := Sprite2D.new()
	flash.z_index = 10
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	flash.texture = ImageTexture.create_from_image(img)
	flash.position = pos
	flash.scale = Vector2.ZERO
	flash.modulate.a = 0.8

	# Добавляем в текущую сцену
	var scene: Node = Engine.get_main_loop().current_scene as Node
	if scene:
		scene.add_child(flash)
		var tw: Tween = scene.create_tween()
		tw.set_parallel(true)
		tw.tween_property(flash, "scale", Vector2(4.0, 4.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(flash, "modulate:a", 0.0, 0.2)
		tw.chain().tween_callback(flash.queue_free)

## Взрыв при попадании
static func impact_burst(pos: Vector2, sphere: String, is_aoe: bool) -> void:
	var color: Color = SPHERE_COLORS.get(sphere, Color.WHITE)
	var count := 12 if is_aoe else 6

	# Частицы через Sprite2D (простые квадратики)
	for i in range(count):
		var p := Sprite2D.new()
		p.z_index = 8
		var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
		img.fill(color)
		p.texture = ImageTexture.create_from_image(img)
		p.position = pos
		p.modulate.a = 0.9

		var scene: Node = Engine.get_main_loop().current_scene as Node
		if scene:
			scene.add_child(p)
			var angle: float = TAU * i / count + randf_range(-0.3, 0.3)
			var dist: float = randf_range(20.0, 50.0) if is_aoe else randf_range(10.0, 30.0)
			var target := pos + Vector2(cos(angle), sin(angle)) * dist
			var tw: Tween = scene.create_tween()
			tw.set_parallel(true)
			tw.tween_property(p, "position", target, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(p, "modulate:a", 0.0, 0.3)
			tw.tween_property(p, "scale", Vector2(0.3, 0.3), 0.3)
			tw.chain().tween_callback(p.queue_free)

## Попадание по щиту (вспышка на щите)
static func shield_hit(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var original := unit.modulate
	unit.modulate = Color(0.5, 0.7, 1.0, 1.0)
	await Engine.get_main_loop().create_timer(0.12).timeout
	if is_instance_valid(unit):
		unit.modulate = original

## Вспышка получения урона
static func hit_flash(unit: Node2D) -> void:
	if not is_instance_valid(unit):
		return
	var original := unit.modulate
	unit.modulate = Color(1.0, 0.3, 0.3, 1.0)
	await Engine.get_main_loop().create_timer(0.1).timeout
	if is_instance_valid(unit):
		unit.modulate = original

# === Шейдеры ===

static func _fire_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Пульсация радиуса
	float r = 0.3 + 0.1 * sin(time * 8.0);
	// Огненное свечение: ядро белое, края оранжевые
	float glow = smoothstep(r, r * 0.3, d);
	float edge = smoothstep(r, r * 0.7, d);
	vec3 col = mix(color.rgb, vec3(1.0, 0.9, 0.6), glow * 0.8);
	// Искажение через шум (простое)
	float n = sin(uv.x * 12.0 + time * 5.0) * cos(uv.y * 10.0 + time * 3.0);
	col += vec3(0.2, 0.1, 0.0) * n * edge;
	COLOR = vec4(col, edge * 0.9);
}"""

static func _ice_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Ледяной кристалл: шестиугольная форма
	float angle = atan(uv.y, uv.x);
	float hex = cos(angle * 3.0 + time * 2.0) * 0.15 + 0.35;
	float glow = smoothstep(hex, hex * 0.5, d);
	// Блики
	float sparkle = pow(max(0.0, sin(uv.x * 20.0 + time * 4.0) * sin(uv.y * 18.0 + time * 3.0)), 8.0);
	vec3 col = mix(color.rgb * 0.6, vec3(0.9, 0.95, 1.0), sparkle * 0.5);
	COLOR = vec4(col, glow * 0.85);
}"""

static func _lightning_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Молния: яркое ядро + ветвление
	float core = smoothstep(0.4, 0.05, d);
	// Ветвления через шум
	float branch = sin(uv.x * 30.0 + time * 10.0) * cos(uv.y * 25.0 - time * 8.0);
	branch = smoothstep(0.3, 0.8, abs(branch));
	float glow = core + branch * 0.3;
	vec3 col = mix(color.rgb, vec3(1.0), core * 0.7);
	COLOR = vec4(col, glow * 0.9);
}"""

static func _stone_shader() -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.6, 0.4, 0.2, 1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	// Камень: тёмное ядро + трещины
	float rock = smoothstep(0.4, 0.1, d);
	float crack = sin(uv.x * 15.0 + time * 2.0) * sin(uv.y * 12.0 - time);
	crack = smoothstep(0.7, 0.9, abs(crack));
	vec3 col = color.rgb * (0.7 + crack * 0.3);
	// Тень снизу
	col *= mix(0.5, 1.0, smoothstep(-0.3, 0.1, uv.y));
	COLOR = vec4(col, rock * 0.95);
}"""

static func _generic_shader(col: Color) -> String:
	return """shader_type canvas_item;
uniform vec4 color : source_color = vec4(1.0);
uniform float time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv);
	float glow = smoothstep(0.45, 0.1, d);
	float pulse = 0.8 + 0.2 * sin(time * 6.0);
	COLOR = vec4(color.rgb * pulse, glow * 0.8);
}"""
