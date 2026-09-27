class_name BiomeBatch
extends Node2D

# Батч тайлов одного биома
# Рендерится как один спрайт с шейдером для blending на границах

var biome_type: int = 0
var texture: Texture2D
var material: ShaderMaterial

# Размеры батча в тайлах
var batch_width: int = 16
var batch_height: int = 16

# Позиция в мире
var world_position: Vector2 = Vector2.ZERO

# Соседние биомы (для blending)
var left_neighbor: int = -1
var right_neighbor: int = -1
var top_neighbor: int = -1
var bottom_neighbor: int = -1

var _sprite: Sprite2D
var _id: String

func _ready():
    _setup_sprite()

func _setup_sprite():
    """Создать спрайт для батча."""
    _sprite = Sprite2D.new()
    _sprite.texture = texture
    _sprite.material = material
    _sprite.centered = false
    
    # Устанавливаем размер (batch_size * TILE_SIZE)
    var size = Vector2(batch_width * 32, batch_height * 32)
    _sprite.scale = size / texture.get_size() if texture else Vector2.ONE
    
    add_child(_sprite)

func get_id() -> String:
    """Уникальный ID батча."""
    if _id.is_empty():
        _id = f"batch_{biome_type}_{world_position.x}_{world_position.y}"
    return _id

func update_neighbors(left: int, right: int, top: int, bottom: int):
    """Обновить информацию о соседних биомах."""
    left_neighbor = left
    right_neighbor = right
    top_neighbor = top
    bottom_neighbor = bottom
    
    if material:
        material.set_shader_parameter("left_biome", float(left))
        material.set_shader_parameter("right_biome", float(right))
        material.set_shader_parameter("top_biome", float(top))
        material.set_shader_parameter("bottom_biome", float(bottom))

func set_texture(tex: Texture2D):
    """Установить текстуру биома."""
    texture = tex
    if _sprite:
        _sprite.texture = tex
