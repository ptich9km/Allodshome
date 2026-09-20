extends Node2D
class_name Projectile

var start_pos: Vector2
var target_pos: Vector2
var damage: int = 10
var speed: float = 200.0
var projectile_owner: Node2D  # Переименовали чтобы не конфликтовало с owner из Node

## Магия: имя заклинания (для анимации снаряда) и радиус области удара.
var spell_name: String = ""
var spell_area: float = 0.0

var _sprite: Sprite2D
var _frames: Array = []
var _frame := 0
var _timer := 0.0

func _ready():
	global_position = start_pos
	look_at(target_pos)
	# Ищем спрайт: в сцене уже есть (Sprite), переиспользуем
	_sprite = get_node_or_null("Sprite") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		add_child(_sprite)

func _process(delta):
	if _sprite != null and _frames.size() > 1:
		_timer += delta
		if _timer >= 0.05:
			_timer = 0.0
			_frame = (_frame + 1) % _frames.size()
			_sprite.texture = _frames[_frame]

	var direction = (target_pos - global_position).normalized()
	global_position += direction * speed * delta

	# Проверяем достижение цели
	if global_position.distance_to(target_pos) < 5.0:
		explode()

## Анимация снаряда из assets/projectiles/<папка>/sprites-NNN.png (SpellDB).
func set_spell_anim(name: String) -> void:
	var folder := SpellDB.projectile_folder(name)
	if folder == "":
		return
	var dir := DirAccess.open("res://assets/projectiles/%s" % folder)
	var paths: Array = []
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.begins_with("sprites-") and fn.ends_with(".png"):
				paths.append(fn)
			fn = dir.get_next()
		dir.list_dir_end()
	paths.sort()
	var nframes := SpellDB.projectile_frames(name)
	for i in range(nframes):
		var base := "sprites-%03d.png" % i
		if not paths.has(base):
			continue
		var tex: Variant = load("res://assets/projectiles/%s/%s" % [folder, base])
		if tex != null:
			_frames.append(tex)
	if _frames.is_empty():
		# fallback: любой кадр из папки
		for p in paths:
			var tex: Variant = load("res://assets/projectiles/%s/%s" % [folder, p])
			if tex != null:
				_frames.append(tex)
			if _frames.size() >= 1:
				break
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
		# центрируем снаряд (спрайты нарисованы по центру)
		var tex: Texture2D = _frames[0]
		_sprite.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height() / 2.0)
		# масштаб: снаряды 12-128px, типичный урон виден хорошо
		_sprite.scale = Vector2.ONE * 0.5 if tex.get_width() > 48 else Vector2.ONE

func explode():
	var radius := spell_area if spell_area > 0.0 else 30.0
	# При касте звук заклинания уже проигран (player._play_spell_sound).
	# На попадании — универсальный взрыв (513 = magic\explosion.wav).
	SoundDB.play(513)
	var sphere := SpellDB.sphere_of(spell_name)
	var targets: Array = []
	if spell_area > 0.0:
		# Областное заклинание: урон всем целям в радиусе области
		for enemy in Game.enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) <= radius:
				targets.append(enemy)
		if not targets.is_empty():
			Game.deal_damage_area(targets, damage, "magic", sphere, projectile_owner)
		# Разрушаемые объекты карты в радиусе (карта применяет свой урон сама)
		var map_node = get_tree().get_first_node_in_group("alm_map")
		if map_node and map_node.has_method("damage_area"):
			map_node.damage_area(global_position, radius, damage)
	else:
		# Одиночный снаряд: урон ближайшей цели (30 px — как раньше)
		for enemy in Game.enemies:
			if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) < radius:
				Game.deal_damage(enemy, damage, "magic", sphere, projectile_owner)
		var map_node = get_tree().get_first_node_in_group("alm_map")
		if map_node and map_node.has_method("damage_area"):
			map_node.damage_area(global_position, radius, damage)
	queue_free()