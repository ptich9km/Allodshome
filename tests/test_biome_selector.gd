extends SceneTree

# Тест BiomeTileSelector

func _init():
    print("=== Тест BiomeTileSelector ===")
    
    var selector = load("res://scripts/biome_tile_selector.gd").new()
    
    # Проверяем загрузку DB
    print("\nДоступные биомы:")
    for biome_type in selector.get_biome_types():
        print("  Биом %d: %s" % [biome_type, "OK" if selector.has_biome(biome_type) else "MISSING"])
    
    # Проверяем загрузку текстур интерьера
    print("\nТекстуры интерьера:")
    for biome_type in selector.get_biome_types():
        var tex = selector.get_interior_texture(biome_type, 0)
        print("  Биом %d: %s" % [biome_type, "OK" if tex else "NULL"])
    
    # Проверяем загрузку transition тайлов
    print("\nTransition тайлы (трава->песок):")
    for direction in ["right", "left", "top", "bottom"]:
        var tex = selector.get_transition_texture(0, 5, direction, 0)
        print("  %s: %s" % [direction, "OK" if tex else "NULL"])
    
    print("\n=== Тест завершён ===")
    quit(0)
