extends Node2D
class_name Projectile
## Снаряд заклинания. Визуал полностью процедурный (SpellVFX), готовые кадры
## из assets/projectiles/* не используются.
##
## Раньше: скорость была фиксированной 200 px/с, поле range игнорировалось,
## числа урона рисовались дважды (здесь и в enemy.gd) и показывали сырое
## значение, а вызов alm_map.damage_area был пустой заглушкой.

var start_pos: Vector2
var target_pos: Vector2
var damage: int = 10
var speed: float = 200.0
var projectile_owner: Node2D
var spell_name: String = ""
var spell_area: float = 0.0

var _sprite: Sprite2D
var _trail: Array = []
var _elapsed := 0.0
var _trail_timer := 0.0


func _ready() -> void:
	global_position = start_pos
	_sprite = SpellVFX.make_projectile(spell_name)
	add_child(_sprite)
	z_index = 5
	# Разворачиваем спрайт по направлению полёта (снаряд круглый, но ядро
	# вытянутое — без этого Fire_Ball летит «боком»).
	if _sprite != null:
		_sprite.rotation = (target_pos - start_pos).angle()


func _process(delta: float) -> void:
	_elapsed += delta
	SpellVFX.update_shader_time(_sprite, delta, _elapsed)

	# Если кастер или сцена исчезли (смена карты/перезапуск) — снаряд уходит
	var owner_alive := projectile_owner == null or is_instance_valid(projectile_owner)
	if not owner_alive:
		queue_free()
		return

	var to_target := target_pos - global_position
	var dist := to_target.length()
	if dist <= maxf(4.0, speed * delta):
		global_position = target_pos
		explode()
		return
	global_position += to_target / dist * speed * delta
	if _sprite != null:
		_sprite.rotation = to_target.angle()

	_trail_timer += delta
	if _trail_timer >= 0.03:
		_trail_timer = 0.0
		_spawn_trail_particle()

	for i in range(_trail.size() - 1, -1, -1):
		var p: Sprite2D = _trail[i]
		if not is_instance_valid(p):
			_trail.remove_at(i)
			continue
		p.modulate.a -= delta * 3.0
		if p.modulate.a <= 0.0:
			p.queue_free()
			_trail.remove_at(i)


func _spawn_trail_particle() -> void:
	var sphere := SpellDB.sphere_of(spell_name)
	var color: Color = SpellVFX.SPHERE_COLORS.get(sphere, Color.WHITE)
	var p := Sprite2D.new()
	p.z_index = 4
	p.texture = SpellVFX.spark_texture(color)
	p.position = global_position
	p.modulate.a = 0.6
	p.scale = Vector2(0.8, 0.8)
	# След — ребёнок снаряда, чтобы не оставаться в сцене после queue_free
	add_child(p)
	_trail.append(p)


func explode() -> void:
	var sphere := SpellDB.sphere_of(spell_name)
	var is_aoe := spell_area > 0.0
	var radius := spell_area if is_aoe else 30.0

	SpellVFX.impact_burst(global_position, sphere, is_aoe)
	SoundDB.play(513)

	# Числа урона и вспышка рисуются в Game.deal_damage — здесь молча,
	# чтобы они не дублировались (раньше рисовались и тут, и в enemy.gd).
	if is_aoe:
		for enemy in Game.enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) <= radius:
				Game.deal_damage(enemy, damage, "magic", sphere, projectile_owner)
	else:
		# Одиночная цель: сначала конкретный снаряд, иначе любой в радиусе
		for enemy in Game.enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) <= radius:
				Game.deal_damage(enemy, damage, "magic", sphere, projectile_owner)
				break

	# Атрибуты заклинания (яды/замедления) — наводятся взрывом на ВРАГОВ в
	# радиусе. Вампиризм/баффы сюда не попадают: они вешаются на кастера.
	var spell := SpellDB.get_spell(spell_name)
	if not spell.is_empty():
		StatusEffects.apply_hostile_area(global_position, radius, spell, projectile_owner)

	Game.camera_trauma(0.3 if is_aoe else 0.15)
	queue_free()
