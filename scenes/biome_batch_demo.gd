extends Node2D

# Демонстрация системы батчинга биомов
# Создаёт тестовую карту 4x4 батча с разными биомами

const BiomeBatch = preload("res://scripts/biome_batch.gd")
const BiomeBatchManager = preload("res://scripts/biome_batch_manager.gd")

var batch_manager: BiomeBatchManager

func _ready():
    batch_manager = BiomeBatchManager.new()
    add_child(batch_manager)
    
    # Создаём тестовую сетку батчей 4x4
    create_test_map()

func create_test_map():
    """Создать тестовую карту из батчей."""
    var grid_size = 4
    var batch_pixel_size = 512  # 16 тайлов * 32px
    
    for by in range(grid_size):
        for bx in range(grid_size):
            # Определяем биом по позиции (простой паттерн)
            var biome = get_biome_for_position(bx, by, grid_size)
            
            # Создаём батч
            var batch = batch_manager.create_batch(biome, Vector2(bx * batch_pixel_size, by * batch_pixel_size))
            batch.batch_width = 16
            batch.batch_height = 16
            add_child(batch)
            
            # Определяем соседей
            var left = get_biome_for_position(bx - 1, by, grid_size) if bx > 0 else -1
            var right = get_biome_for_position(bx + 1, by, grid_size) if bx < grid_size - 1 else -1
            var top = get_biome_for_position(bx, by - 1, grid_size) if by > 0 else -1
            var bottom = get_biome_for_position(bx, by + 1, grid_size) if by < grid_size - 1 else -1
            
            batch.update_neighbors(left, right, top, bottom)

func get_biome_for_position(x: int, y: int, grid_size: int) -> int:
    """Определить биом по позиции (тестовый паттерн)."""
    # Простой паттерн: трава сверху-слева, песок снизу-справа
    var center = grid_size / 2.0
    var dist = sqrt(pow(x - center, 2) + pow(y - center, 2))
    
    if dist < center * 0.5:
        return 0  # Grass
    elif dist < center * 0.8:
        return 5  # Sand
    else:
        return 4  # Soil
