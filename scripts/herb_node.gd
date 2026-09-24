class_name HerbNode
extends Area2D

const REGROW_SECONDS := 180.0

var item_key := ""
var icon_path := ""
var cell := Vector2i(-1, -1)
var regrow_seconds := REGROW_SECONDS
var available := true

var _sprite: Sprite2D

func setup(key: String, path: String, grid_cell: Vector2i, relief: float) -> void:
	item_key = key
	icon_path = path
	cell = grid_cell
	position = Vector2(grid_cell.x * 32 + 16, grid_cell.y * 32 + 16 - relief)
	monitoring = false
	monitorable = false
	_sprite = Sprite2D.new()
	_sprite.name = "HerbSprite"
	_sprite.texture = load(path) as Texture2D
	_sprite.centered = true
	add_child(_sprite)
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

func _ready() -> void:
	add_to_group("herb_resource")

func is_available() -> bool:
	return available

func contains_point(world_position: Vector2) -> bool:
	return available and global_position.distance_to(world_position) <= 28.0

func harvest() -> bool:
	if not available:
		return false
	available = false
	if is_instance_valid(_sprite):
		_sprite.visible = false
	var timer := get_tree().create_timer(regrow_seconds)
	timer.timeout.connect(_restore)
	return true

func _restore() -> void:
	if not is_inside_tree():
		return
	available = true
	if is_instance_valid(_sprite):
		_sprite.visible = true
