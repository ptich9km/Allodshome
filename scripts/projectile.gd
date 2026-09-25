extends Node2D
class_name Projectile

var start_pos: Vector2
var target_pos: Vector2
var damage: int = 10
var speed: float = 200.0
var projectile_owner: Node2D

## Магия: имя заклинания и радиус области удара.
var spell_name: String = ""
var spell_area: float = 0.0

var _sprite: Sprite2D
var _trail: Array = []  # след из маленьких спрайтов
var _elapsed := 0.0
var _trail_timer := 0.0

func _ready():
	global_position = start_pos
	look_at(target_pos)
	# Создаём снаряд через SpellVFX
	_sprite = SpellVFX.make_projectile(spell_name)
	add_child(_sprite)

func _process(delta):
	_elapsed += delta

	# Обновляем шейдер
	SpellVFX.update_shader_time(_sprite, delta, _elapsed)

	# Движение
	var direction := (target_pos - global_position).normalized()
	global_position += direction * speed * delta
	rotation = direction.angle()

	# След (маленькие квадратики с fade out)
	_trail_timer += delta
	if _trail_timer >= 0.03:
		_trail_timer = 0.0
		_spawn_trail_particle()

	# Обновляем след
	for i in range(_trail.size() - 1, -1, -1):
		var p: Sprite2D = _trail[i]
		p.modulate.a -= delta * 3.0
		if p.modulate.a <= 0:
			p.queue_free()
			_trail.remove_at(i)

	# Проверяем достижение цели
	if global_position.distance_to(target_pos) < 5.0:
		explode()

func _spawn_trail_particle():
	var sphere := SpellDB.sphere_of(spell_name)
	var color: Color = SpellVFX.SPHERE_COLORS.get(sphere, Color.WHITE)
	var p := Sprite2D.new()
	p.z_index = 4
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(color)
	p.texture = ImageTexture.create_from_image(img)
	p.position = global_position
	p.modulate.a = 0.6
	p.scale = Vector2(0.8, 0.8)
	get_parent().add_child(p)
	_trail.append(p)

func explode():
	var radius := spell_area if spell_area > 0.0 else 30.0
	var sphere := SpellDB.sphere_of(spell_name)

	# Визуальный взрыв
	SpellVFX.impact_burst(global_position, sphere, spell_area > 0.0)

	# Звук
	SoundDB.play(513)

	# Урон
	var targets: Array = []
	if spell_area > 0.0:
		for enemy in Game.enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) <= radius:
				targets.append(enemy)
		if not targets.is_empty():
			Game.deal_damage_area(targets, damage, "magic", sphere, projectile_owner)
		var map_node = get_tree().get_first_node_in_group("alm_map")
		if map_node and map_node.has_method("damage_area"):
			map_node.damage_area(global_position, radius, damage)
	else:
		for enemy in Game.enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) < radius:
				Game.deal_damage(enemy, damage, "magic", sphere, projectile_owner)
		var map_node = get_tree().get_first_node_in_group("alm_map")
		if map_node and map_node.has_method("damage_area"):
			map_node.damage_area(global_position, radius, damage)

	# Damage numbers
	for enemy in targets:
		if is_instance_valid(enemy):
			DamageNumber.show_at(enemy.global_position, damage, "damage")

	# Tряска камеры
	Game.camera_trauma(0.3 if spell_area > 0.0 else 0.15)

	queue_free()
