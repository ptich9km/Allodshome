extends Node2D

# Тестовая сцена для демонстрации плавного смешивания биомов

@onready var sprite_a = $SpriteA
@onready var sprite_b = $SpriteB
@onready var blend_sprite = $BlendSprite

# Загружаем текстуры
var grass_textures = []
var sand_textures = []

func _ready():
    # Загружаем текстуры травы и песка
    for i in range(1, 7):
        var grass_path = f"res://assets/terrain/biomes/grass/grass_{i:02d}.png"
        var sand_path = f"res://assets/terrain/biomes/sand/sand_{i:02d}.png"
        
        if ResourceLoader.exists(grass_path):
            grass_textures.append(load(grass_path))
        if ResourceLoader.exists(sand_path):
            sand_textures.append(load(sand_path))
    
    print(f"Loaded {grass_textures.size()} grass textures")
    print(f"Loaded {sand_textures.size()} sand textures")
    
    # Настраиваем тестовые спрайты
    setup_test_sprites()

func setup_test_sprites():
    if grass_textures.size() > 0:
        sprite_a.texture = grass_textures[0]
        sprite_a.scale = Vector2(8, 8)  # Увеличиваем для наглядности
    
    if sand_textures.size() > 0:
        sprite_b.texture = sand_textures[0]
        sprite_b.scale = Vector2(8, 8)
        sprite_b.position = Vector2(300, 0)
    
    # Настраиваем спрайт со смешиванием
    if grass_textures.size() > 0 and sand_textures.size() > 0:
        var mat = ShaderMaterial.new()
        mat.shader = load("res://shaders/biome_blend.shader")
        mat.set_shader_parameter("tex_a", grass_textures[0])
        mat.set_shader_parameter("tex_b", sand_textures[0])
        mat.set_shader_parameter("blend_width", 0.3)
        mat.set_shader_parameter("noise_scale", 3.0)
        
        blend_sprite.material = mat
        blend_sprite.texture = grass_textures[0]  # Базовая текстура
        blend_sprite.scale = Vector2(8, 8)
        blend_sprite.position = Vector2(0, 300)
