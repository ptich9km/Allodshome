extends Area2D
class_name LootBag

@export var items: Array = []  # [{"name": "Gold", "amount": 5}, ...]

var sprite_node: Sprite2D
var label_node: Label

func _ready():
	sprite_node = get_node("Sprite")
	
	# Определяем размер по количеству предметов
	var size = "small"
	if items.size() >= 5:
		size = "large"
	elif items.size() >= 2:
		size = "medium"
	
	var tex_path = "res://assets/sprites/loot_%s.png" % size
	var tex = load(tex_path)
	if tex:
		sprite_node.texture = tex
	
	# Подбор по клику
	input_event.connect(_on_input_event)
	
	# Показываем количество предметов
	label_node = Label.new()
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.position = Vector2(0, -30)
	label_node.add_theme_font_size_override("font_size", 12)
	label_node.add_theme_color_override("font_color", Color.YELLOW)
	label_node.text = str(items.size())
	add_child(label_node)

func _on_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pick_up()

func pick_up():
	print("Подобрано: ", items.size(), " предметов")
	for item in items:
		print("  + ", item.get("name", "Unknown"), " x", item.get("amount", 1))
	queue_free()
