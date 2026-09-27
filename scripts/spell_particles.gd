class_name SpellParticles
extends RefCounted
## Второй слой эффекта: частицы (искры, угли, пыль, осколки).
##
## Зачем. Правило из практики VFX: эффект = ОСНОВНОЙ слой (сигнал для игрока) +
## ВТОРИЧНЫЙ (тематика: искры, угли, дым). Один спрайт с шейдером не даёт
## того, что дают частицы, — стохастичной высокочастотной детализации и
## ИСТОРИИ ДВИЖЕНИЯ. Ни то, ни другое принципиально невозможно получить из
## статичной математики шейдера.
##
## Всё процедурное: спрайт частицы рисуется шейдером, готовых кадров нет.
##
## ВАЖНО про физическую интерполяцию: Godot НЕ поддерживает интерполяцию для
## 2D-частиц, а в проекте включён physics/common/physics_interpolation. Без
## отключения интерполяции на узле частицы ступенчатые на экранах с высоким
## refresh. Поэтому ставим Mode = Disabled явно.

## Частица — один шрайдер на все вторичные слои, вид задаётся параметрами.
const PARTICLE_SHADER := """shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 color : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float hot : hint_range(0.0, 4.0) = 1.6;
uniform float size_px : hint_range(1.0, 24.0) = 6.0;

void fragment() {
\t// INSTANCE_CUSTOM.y — фаза жизни 0..1 (даёт сам Godot).
\tfloat life = INSTANCE_CUSTOM.y;
\tvec2 p = UV - vec2(0.5);
\t// Гаснем к концу жизни и слегка сжимаем: «искра угасает», а не исчезает.
\tfloat d = length(p) * 2.0;
\tfloat r = size_px / max(1.0, size_px * 0.0 + 1.0);
\tfloat shape = max(0.0, 1.0 - d);
\tfloat fade = (1.0 - life) * (1.0 - life);
\tfloat a = pow(shape, 2.2) * fade;
\tif (a < 0.01) {
\t\tdiscard;
\t}
\tvec3 col = mix(color.rgb, vec3(1.0, 0.92, 0.75), (1.0 - life) * 0.5);
\tCOLOR = vec4(col * a * hot, 1.0);
}"""

static var _shader: Shader = null


static func _particle_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PARTICLE_SHADER
	return _shader


static func _texture() -> Texture2D:
	return SpellVFX.white_texture()


## Базовый эмиттер. amount/lifetime/speed/gravity настраиваются вызывающим.
static func _make(parent: Node2D, amount: int, life: float, tex: Texture2D,
		color: Color, z: int, spread: float, speed: float, gravity: float,
		scale_min: float, scale_max: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 6.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = spread
	mat.initial_velocity_min = speed * 0.4
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, gravity, 0)
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	mat.color = color
	p.process_material = mat
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.6
	p.local_coords = false        # частицы живут в мире и не следуют за узлом
	p.visibility_rect = Rect2(-400, -400, 800, 800)
	# Свет не должен ломать батчинг у частиц: они аддитивные, свет им не нужен.
	p.light_mask = 0
	# ГЛАВНОЕ: 2D-частицы не поддерживают физическую интерполяцию.
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.z_index = z
	p.material = _canvas_material()
	return p


static func _canvas_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# Частицы не должны участвовать в освещении: они сами излучают.
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m


static func _attach_and_burst(parent: Node2D, p: GPUParticles2D, pos: Vector2) -> void:
	var holder := Node2D.new()
	holder.position = pos
	parent.add_child(holder)
	holder.add_child(p)
	p.emitting = true
	# Одноразовые частицы сами НЕ удаляются: они перестают излучать, но узел
	# остаётся в сцене навсегда. Без этого удаления каждый удар копил мёртвый
	# узел — на длинной игре это сотни висящих CanvasItem (в прогоне
	# runtime_errors_smoke вылезло 67 утеч RID типа CanvasItem).
	p.set_meta("self_free", true)
	_autofree(p, p.lifetime + 0.35)


## Удалить одноразовый эмиттер, когда он отработал.
static func _autofree(p: Node2D, delay: float) -> void:
	var tree := p.get_tree()
	if tree == null:
		return
	var t := tree.create_timer(delay)
	t.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Искры от попадания: короткий аддитивный веер вверх и в стороны.
static func impact_sparks(parent: Node2D, pos: Vector2, color: Color,
		amount: int = 14) -> GPUParticles2D:
	var p := _make(parent, amount, 0.45, _texture(), color, 9, 180.0, 130.0,
		280.0, 0.25, 0.6)
	_attach_and_burst(parent, p, pos)
	return p


## Угли/пыль от попадания по площади: шире, живут дольше, оседают.
static func aoe_debris(parent: Node2D, pos: Vector2, color: Color,
		radius: float = 60.0) -> GPUParticles2D:
	var p := _make(parent, 22, 0.9, _texture(), color, 9, 160.0, 90.0, 120.0,
		0.4, 1.0)
	var mat := p.process_material as ParticleProcessMaterial
	mat.emission_sphere_radius = maxf(4.0, radius * 0.5)
	_attach_and_burst(parent, p, pos)
	return p


## Хвост снаряда: частицы отбрасываются назад по движению.
static func projectile_trail(parent: Node2D, color: Color) -> GPUParticles2D:
	var p := _make(parent, 20, 0.4, _texture(), color, 9, 24.0, 26.0, -12.0,
		0.2, 0.5)
	p.explosiveness = 0.0            # не разовый, а постоянный поток
	p.one_shot = false
	p.z_index = 9
	parent.add_child(p)
	p.emitting = true
	return p


## Искры вдоль активной стены/зоны: «дымление» поверх краёв.
static func zone_embers(parent: Node2D, rect: Vector2, color: Color) -> GPUParticles2D:
	var p := _make(parent, 16, 1.2, _texture(), color, 12, 40.0, 34.0, -46.0,
		0.25, 0.55)
	var mat := p.process_material as ParticleProcessMaterial
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(rect.x * 0.5, rect.y * 0.5, 1.0)
	p.one_shot = false
	parent.add_child(p)
	p.emitting = true
	return p
