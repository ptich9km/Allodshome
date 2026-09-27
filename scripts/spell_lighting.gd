class_name SpellLighting
extends RefCounted
## Свет для заклинаний: PointLight2D на каждый каст + процедурная текстура света.
##
## Зачем это нужно. До сих пор в сценах не было НИ ОДНОГО источника света:
## ни CanvasModulate, ни Light2D, ни WorldEnvironment. Картинка рисовалась
## «как есть», и это главная — не единственная — причина ощущения «1990-е».
## Правило из практики VFX: эффект должен ИЗЛУЧАТЬ и ОСВЕЩАТЬ МИР. Огонь
## освещает землю и юнитов в стене — иначе он читается как наклейка.
##
## Текстура света делается процедурно (GradientTexture2D FILL_RADIAL) — ни
## одного нового ассета, как и требует проект.
##
## ВАЖНО про производительность:
##  * каждый источник света ломает батчинг 2D у всех CanvasItem, которых он
##    касается, поэтому источников должно быть мало и они должны быть мелкими;
##  * `light_mask` разводит каналы: земля принимает свет, а HUD (Control)
##    светом не освещается в принципе;
##  * текстура света кэшируется статически: создавать GradientTexture2D на
##    каждый каст — лишняя работа в рантайме.

## Радиальный градиент: непрозрачный центр -> прозрачный край.
static var _light_tex: GradientTexture2D = null

const FILL_ALPHA := 0.16
const EDGE_ALPHA := 1.0

## Радиальная текстура света (создаётся один раз).
static func radial_texture() -> GradientTexture2D:
	if _light_tex != null:
		return _light_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_light_tex = GradientTexture2D.new()
	_light_tex.gradient = g
	_light_tex.fill = GradientTexture2D.FILL_RADIAL
	_light_tex.fill_from = Vector2(0.5, 0.5)
	_light_tex.fill_to = Vector2(1.0, 0.5)
	_light_tex.width = 128
	_light_tex.height = 128
	return _light_tex


## Создать источник света заклинания. node должен быть уже в дереве
## (иначе _ready() не отработает — см. грабли в godot-4-api-traps).
static func make_light(node: Node2D, color: Color, radius_px: float,
		life: float, peak_energy: float = 1.6) -> PointLight2D:
	if node == null or not is_instance_valid(node):
		return null
	var light := PointLight2D.new()
	light.texture = radial_texture()
	light.color = color
	light.energy = 0.0
	light.texture_scale = maxf(0.25, radius_px * 2.0 / 128.0)
	# Свет не должен ломать батчинг всего подряд: ограничиваем канал.
	light.range_item_cull_mask = 1
	light.shadow_enabled = false
	node.add_child(light)
	light.set_meta("peak_energy", peak_energy)
	light.set_meta("life_left", life)
	light.set_meta("rise", minf(0.18, life * 0.3))
	# Появление: быстрый подъём, затем плавное затухание.
	var tw := node.create_tween()
	tw.tween_property(light, "energy", peak_energy, light.get_meta("rise"))
	tw.tween_interval(maxf(0.05, life - light.get_meta("rise")))
	tw.tween_property(light, "energy", 0.0, light.get_meta("rise") + 0.12)
	tw.tween_callback(light.queue_free)
	return light


## Свет для удара по площади: шире и короче, чем у стены.
static func burst_light(node: Node2D, color: Color, radius_px: float,
		life: float = 0.35) -> PointLight2D:
	return make_light(node, color, radius_px, life, 2.2)


## Свет для снаряда: едет вместе с ним.
static func projectile_light(node: Node2D, color: Color) -> PointLight2D:
	return make_light(node, color, 46.0, 3.0, 1.1)
