@tool
extends Node2D

# Тестовая сцена для демонстрации биомных текстур
# Показывает переходы между биомами

@export var show_grid: bool = true
@export var tile_size: int = 32

var selector: RefCounted
var grass_textures: Array[Texture2D]
var sand_textures: Array[Texture2D]
var transition_textures: Dictionary

func _ready():
    # Загружаем селектор
    var BiomeTileSelectorClass = load("res://scripts/biome_tile_selector.gd")
    if BiomeTileSelectorClass:
        selector = BiomeTileSelectorClass.new()
    
    # Загружаем текстуры
    _load_textures()
    
    # Рисуем тестовую карту
    _draw_test_map()

func _load_textures():
    """Загрузить текстуры биомов."""
    if selector == null:
        return
    
    # Загружаем текстуры травы
    for i in range(6):
        var tex = selector.get_interior_texture(0, i)  # 0 = grass
        if tex:
            grass_textures.append(tex)
    
    # Загружаем текстуры песка
    for i in range(6):
        var tex = selector.get_interior_texture(5, i)  # 5 = sand
        if tex:
            sand_textures.append(tex)
    
    # Загружаем transition тайлы
    for direction in ["right", "left", "top", "bottom"]:
        for i in range(6):
            var tex = selector.get_transition_texture(0, 5, direction, i)
            if tex:
                var key = "%s_%d" % [direction, i]
                transition_textures[key] = tex
    
    print("Loaded %d grass, %d sand, %d transition textures" % [
        grass_textures.size(), sand_textures.size(), transition_textures.size()
    ])

func _draw_test_map():
    """Нарисовать тестовую карту с биомами и переходами."""
    if grass_textures.size() == 0 or sand_textures.size() == 0:
        print("No textures loaded!")
        return
    
    var map_width = 8
    var map_height = 8
    
    # Рисуем сетку биомов
    for y in range(map_height):
        for x in range(map_width):
            # Определяем биом по позиции
            var biome = _get_biome(x, y, map_width, map_height)
            
            # Выбираем текстуру
            var tex = _get_texture(biome, x, y)
            
            if tex:
                var sprite = Sprite2D.new()
                sprite.texture = tex
                sprite.position = Vector2(x * tile_size, y * tile_size)
                add_child(sprite)
    
    print("Test map drawn: %dx%d" % [map_width, map_height])

func _get_biome(x: int, y: int, width: int, height: int) -> int:
    """Определить биом по позиции (0=grass, 5=sand)."""
    # Простой паттерн: трава слева, песок справа
    if x < width / 2:
        return 0  # Grass
    else:
        return 5  # Sand

func _get_texture(biome: int, x: int, y: int) -> Texture2D:
    """Получить текстуру для клетки."""
    # Проверяем есть ли переход
    var neighbor_biome = _get_neighbor_biome(x, y)
    
    if neighbor_biome != biome:
        # Нужен transition тайл
        var direction = _get_direction(biome, neighbor_biome)
        var variant = (x + y) % 6  # Вариативность
        var key = "%s_%d" % [direction, variant]
        
        if key in transition_textures:
            return transition_textures[key]
    
    # Обычная текстура биома
    if biome == 0 and grass_textures.size() > 0:
        return grass_textures[(x + y) % grass_textures.size()]
    elif biome == 5 and sand_textures.size() > 0:
        return sand_textures[(x + y) % sand_textures.size()]
    
    return null

func _get_neighbor_biome(x: int, y: int) -> int:
    """Получить биом соседа справа (для демонстрации)."""
    # Упрощённо: всегда возвращаем противоположный биом
    if x < 4:
        return 5  # Sand
    else:
        return 0  # Grass

func _get_direction(from_biome: int, to_biome: int) -> String:
    """Определить направление перехода."""
    if from_biome == 0 and to_biome == 5:
        return "right"  # Grass -> Sand (справа)
    elif from_biome == 5 and to_biome == 0:
        return "left"  # Sand -> Grass (слева)
    return "right"
