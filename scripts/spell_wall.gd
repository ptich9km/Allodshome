class_name SpellWall
extends Node2D
## Зона урона заклинаний-стен (Wall_of_Fire / Wall_of_Earth).
##
## Раньше стена была ColorRect 32×32 на 2 секунды: без урона, без блокировки
## пути и добавленная в get_tree().root (переживала смену сцены).
## Теперь это настоящая зона: тикает уроном, блокирует клетки на время жизни
## и всегда снимает блокировку при удалении.

const BLOCK_RADIUS := 1          # блокируется область радиусом в клетках
const TICK_INTERVAL := 0.5       # как часто наносится урон

var damage: int = 10
var area: float = 72.0
var width: float = 72.0
var sphere: String = "Fire"
var mode: String = "damage"      # damage — жжёт и проходима; block — стена
var damage_owner: Node2D = null
var life_left: float = 6.0

var _tick_accum: float = 0.0
var _blocked: Array = []


func configure(dmg: int, area_px: float, sp: String, owner_unit: Node2D, life: float) -> void:
	damage = dmg
	area = area_px
	width = area_px
	sphere = sp
	damage_owner = owner_unit
	life_left = life


## damage — только урон (стена огня), block — только непроходимость
## (стена земли). В оригинале они разные.
func set_mode(m: String) -> void:
	mode = m


func blocks_path() -> bool:
	return mode == "block"


func deals_damage() -> bool:
	return damage > 0 and mode != "block"


func _ready() -> void:
	z_index = 6
	var sprite := Sprite2D.new()
	sprite.texture = SpellVFX.white_texture()
	sprite.material = SpellVFX.wall_material(sphere)
	sprite.scale = Vector2(width / 32.0 * 1.6, 1.8)
	sprite.modulate.a = 0.85
	# Преграда выглядит плотнее горящей стены
	if blocks_path():
		sprite.modulate = Color(0.8, 0.75, 0.7, 0.95)
	add_child(sprite)
	var mat := sprite.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("time", 0.0)
	if blocks_path():
		_block_cells()
	set_process(true)


func _exit_tree() -> void:
	_unblock_cells()


func _process(delta: float) -> void:
	life_left -= delta
	var sprite := get_child(0) as Sprite2D
	if sprite != null and sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter("time", float(Time.get_ticks_msec()) * 0.001)
	# Последние 0.8 с стена гаснет
	if life_left < 0.8 and sprite != null:
		sprite.modulate.a = maxf(0.0, life_left / 0.8) * 0.85
	if life_left <= 0.0:
		queue_free()
		return
	if not deals_damage():
		return
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	_tick_accum -= TICK_INTERVAL
	_damage_units()


func _damage_units() -> void:
	# Обе точки (стена и юниты) уже лежат в Ground-плоскости, поэтому
	# рельеф вычитать нельзя — иначе зона уезжает на высоту холма.
	var center := global_position
	for enemy in Game.enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var d: float = enemy.global_position.distance_to(center)
		if d <= area:
			Game.deal_damage(enemy, damage, "magic", sphere, damage_owner)


func _block_cells() -> void:
	var map_node := get_tree().get_first_node_in_group("alm_map")
	if map_node == null or not map_node.has_method("set_nowalk_cell"):
		return
	var cell := _center_cell()
	if cell.x < 0:
		return
	for dy in range(-BLOCK_RADIUS, BLOCK_RADIUS + 1):
		for dx in range(-BLOCK_RADIUS, BLOCK_RADIUS + 1):
			var c := cell + Vector2i(dx, dy)
			map_node.call("set_nowalk_cell", c, true)
			_blocked.append(c)


func _unblock_cells() -> void:
	var map_node := get_tree().get_first_node_in_group("alm_map")
	if map_node == null or not map_node.has_method("set_nowalk_cell"):
		return
	for c in _blocked:
		map_node.call("set_nowalk_cell", c, false)
	_blocked.clear()


func _center_cell() -> Vector2i:
	var map_node := get_tree().get_first_node_in_group("alm_map")
	if map_node == null or not map_node.has_method("height_at_world"):
		return Vector2i(-1, -1)
	var ts := 32
	return Vector2i(int(global_position.x / ts), int(global_position.y / ts))
