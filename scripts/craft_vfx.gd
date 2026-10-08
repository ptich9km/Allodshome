class_name CraftVFX
extends RefCounted

## Свечение уровня крафтовой вещи на иконке предмета.
##
## Три уровня: обычная (без эффекта), улучшенная (дыхание), мастерская
## (переливание). Текстура у всех трёх ОДНА — различаются только числа в базе
## и этот шейдер, ровно как задумано.
##
## ГДЕ ВИДНО. Только в интерфейсе. На оружии героя в мире эффект поставить
## не на что: UnitAnim держит ОДИН приватный Sprite2D (unit_anim.gd:37) и
## рисует плоский запечённый PNG, а экипировка лишь подменяет весь набор
## кадров (player.gd:691 _anim.setup(anim_set_name())). Оружие нарисован
## ВНУТРИ спрайта анимации, отдельного узла-оружия не существует, а материал
## на _sprite красил бы всего юнита вместе со щитом.
##
## ПОЧЕМУ ШЕЙДЕР САМОВЫРАЖАЕТСЯ, А НЕ БЕРЁТ СВЕЧЕНИЕ ОТ ДВИЖКА.
## game.gd:582-583 задаёт `env.background_canvas_max_layer = 0`, а все панели
## висят на CanvasLayer layer = 10. То есть Environment.glow и AgX до иконок
## НЕ доходят намеренно (это закреплено тестом lighting_smoke.gd:102, чтобы
## HUD не темнел). Поэтому шейдер выдаёт значения больше 1.0 сам - спасает
## hdr_2d=true (project.godot), который не ограничен нулевым слоем.
##
## ПРАВИЛА ШЕЙДЕРА, ЗАЛОЖЕННЫЕ СРАЗУ (2d-vfx-craft):
##   * маска берётся из АЛЬФЫ ТЕКСТУРЫ, а не из радиуса по UV - иначе свечение
##     вылезает за силуэт вещи и она перестаёт читаться как предмет;
##   * никакого sin/cos - у синуса одна частота, и глаз ловит периодичность
##     за ~200 мс и читает картинку как синтетическую. Только fBm + domain
##     warping по координате;
##   * яркость к центру силуэта, а не равномерная: равномерная яркость не имеет
##     фокуса и читается как плоская наклейка;
##   * blend_mix, а не blend_add: свечение должно ПОДСВЕЧИВАТЬ вещь, а не
##     заменять её силуэт собственной яркой кляксой.

const TIER_ORDINARY := 0
const TIER_IMPROVED := 1
const TIER_MASTER := 2

static var _shader_cache: Dictionary = {}


## Общий кусок GLSL для шейдеров уровней: hash -> value noise -> fBm ->
## domain warping. Живёт строкой, потому что в проекте нет ни одного файла
## .gdshader - все шейдеры это инлайновые константы с кэшем
## (см. spell_vfx.gd:_shader_cache).
static func _noise() -> String:
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

// Domain warping: вложенный fBm применяется к КООРДИНАТЕ, а не к значению.
// Превращает одну гладкую периодичную волну в самоперекрывающееся поле.
float warped(vec2 p) {
	vec2 q = vec2(fbm2(p), fbm2(p + vec2(5.2, 1.3)));
	vec2 r = vec2(fbm2(p + 3.0 * q + vec2(1.7, 9.2)),
	              fbm2(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm2(p + 2.0 * r);
}"""


## Улучшенная вещь: мягкое «дыхание» по альфе силуэта, с цветовым сдвигом.
static func _improved_code() -> String:
	return """shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform float strength : hint_range(0.0, 3.0) = 1.6;

""" + _noise() + """

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		discard;
	}
	// Маска - альфа ТЕКСТУРЫ. Свечение не выходит за силуэт вещи.
	float n = warped(UV * 3.1);
	float breath = 0.72 + 0.28 * n;
	// Яркость к центру силуэта: чем плотнее ткань, тем светлее.
	float mass = 1.0 - clamp(distance(tex.rgb, vec3(0.5)) * 1.4, 0.0, 1.0);
	vec3 col = tex.rgb * tint.rgb;
	col *= breath * (1.0 + strength * 0.5 * mass);
	COLOR = vec4(col, tex.a);
}"""


## Мастерская вещь: переливание оттенка + ядро. Оттенок сдвигается по fBm,
## поэтому цвета «плывут» не периодически, а неожиданно для глаза.
static func _master_code() -> String:
	return """shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 tint_a : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec4 tint_b : source_color = vec4(1.0, 0.65, 0.95, 1.0);
uniform vec4 tint_c : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform float strength : hint_range(0.0, 4.0) = 2.2;

""" + _noise() + """

vec3 palette(float t) {
	// Три фиксированных пятна вместо радуги: полный hue-цикл на маленькой
	// иконке читается как помехи, а не как «магия».
	vec3 c = mix(tint_a.rgb, tint_b.rgb, clamp(t * 2.0, 0.0, 1.0));
	return mix(c, tint_c.rgb, clamp(t * 2.0 - 1.0, 0.0, 1.0));
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		discard;
	}
	float n = warped(UV * 2.6);
	float shimmer = 0.6 + 0.4 * n;
	vec3 glow = palette(fract(n * 0.7 + TIME * 0.06));
	// Ядро: центр силуэта светлее края, иначе эффект плоский.
	float mass = 1.0 - clamp(distance(tex.rgb, vec3(0.5)) * 1.4, 0.0, 1.0);
	vec3 col = tex.rgb * mix(vec3(1.0), glow, 0.55) * shimmer;
	col *= 1.0 + strength * 0.45 * mass;
	COLOR = vec4(col, tex.a);
}"""


static func shader_for_tier(tier: int) -> Shader:
	var key := "tier%d" % clampi(tier, TIER_ORDINARY, TIER_MASTER)
	if _shader_cache.has(key):
		var cached: Shader = _shader_cache[key]
		return cached
	var sh := Shader.new()
	if tier == TIER_IMPROVED:
		sh.code = _improved_code()
	elif tier == TIER_MASTER:
		sh.code = _master_code()
	else:
		# Обычная вещь - обычный шейдер без эффектов, чтобы ветка кода
		# существовала и её можно было замерить тестом.
		sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, UV);\n}\n"
	_shader_cache[key] = sh
	return sh


## Материал для иконки предметта уровня tier, или null для обычной вещи.
## null - это не «ошибка», а обычный случай: материал просто не назначается.
static func tier_material(tier: int) -> ShaderMaterial:
	if tier <= TIER_ORDINARY:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader_for_tier(tier)
	return mat


## Навесить (или снять) эффект уровня на узел с иконкой.
static func apply_to_icon(icon: CanvasItem, tier: int) -> void:
	if icon == null or not is_instance_valid(icon):
		return
	icon.material = tier_material(tier)


## Уровень вещи по её качеству в базе. 0 для всего, что не крафтовая вещь.
## Читает префикс "Crafted", который задаёт gen_crafted_items.py.
static func tier_of_item(item: Dictionary) -> int:
	var q := str(item.get("quality", ""))
	if not q.begins_with("Crafted"):
		return TIER_ORDINARY
	if q.ends_with("Master"):
		return TIER_MASTER
	if q.ends_with("Fine"):
		return TIER_IMPROVED
	return TIER_ORDINARY