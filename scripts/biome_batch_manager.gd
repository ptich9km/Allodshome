class_name BiomeBatchManager
extends Node

# Менеджер батчинга тайлов по биомам
# Группирует тайлы одного биома для эффективного рендера с шейдером

const TILE_SIZE = 32
const BATCH_SIZE = 16  # Тайлов в одном батче (16x16 = 512x512 px)

# Типы биомов
enum BiomeType {
    GRASS = 0,
    SOIL = 4,
    SAND = 5,
    MUD = 6,
    WATER = 2,
    MOUNTAIN = 1
}

# Пути к текстурам биомов
const BIOME_TEXTURES = {
    BiomeType.GRASS: "res://assets/terrain/biomes/grass/",
    BiomeType.SOIL: "res://assets/terrain/biomes/soil/",
    BiomeType.SAND: "res://assets/terrain/biomes/sand/",
    BiomeType.MUD: "res://assets/terrain/biomes/mud/",
    BiomeType.WATER: "res://assets/terrain/biomes/water/",
    BiomeType.MOUNTAIN: "res://assets/terrain/biomes/mountain/",
}

# Кэш загруженных текстур
var _texture_cache = {}

# Активные батчи
var _active_batches = {}

func _ready():
    # Предзагружаем текстуры
    _preload_textures()

func _preload_textures():
    """Предзагрузка текстур всех биомов."""
    for biome_type in BIOME_TEXTURES:
        var path = BIOME_TEXTURES[biome_type]
        var textures = []
        
        for i in range(1, 7):  # 6 вариантов на биом
            var tex_path = f"{path}biome_{i:02d}.png"
            if ResourceLoader.exists(tex_path):
                textures.append(load(tex_path))
        
        if textures.size() > 0:
            _texture_cache[biome_type] = textures
            print(f"Loaded {textures.size()} textures for biome {biome_type}")

func get_texture(biome_type: int, variant: int = 0) -> Texture2D:
    """Получить текстуру биома по типу и варианту."""
    if biome_type in _texture_cache:
        var textures = _texture_cache[biome_type]
        if textures.size() > 0:
            return textures[variant % textures.size()]
    return null

func create_batch(biome_type: int, position: Vector2, size: Vector2) -> BiomeBatch:
    """Создать батч для указанного биома."""
    var batch = BiomeBatch.new()
    batch.biome_type = biome_type
    batch.position = position
    batch.size = size
    batch.texture = get_texture(biome_type, 0)
    
    # Создаём материал с шейдером
    var mat = ShaderMaterial.new()
    mat.shader = load("res://shaders/biome_batch.shader")
    mat.set_shader_parameter("biome_texture", batch.texture)
    mat.set_shader_parameter("biome_type", float(biome_type))
    
    batch.material = mat
    
    _active_batches[batch.get_id()] = batch
    return batch

func update_batch(batch: BiomeBatch, neighbors: Dictionary):
    """Обновить параметры батча на основе соседних биомов."""
    if batch.material:
        batch.material.set_shader_parameter("has_left_neighbor", neighbors.get("left", false))
        batch.material.set_shader_parameter("has_right_neighbor", neighbors.get("right", false))
        batch.material.set_shader_parameter("has_top_neighbor", neighbors.get("top", false))
        batch.material.set_shader_parameter("has_bottom_neighbor", neighbors.get("bottom", false))

func clear_batches():
    """Очистить все батчи."""
    for batch in _active_batches.values():
        batch.queue_free()
    _active_batches.clear()
