class_name BiomeTileSelector
extends RefCounted

# Селектор тайлов биомов на основе biome_transition_db.json
# Заменяет старую систему transition_db + tile_from_spec

const DB_PATH = "res://assets/maps/biome_transition_db.json"

var _db: Dictionary = {}
var _texture_cache: Dictionary = {}

func _init():
    _load_db()

func _load_db():
    """Загрузить базу переходов."""
    var f = FileAccess.open(DB_PATH, FileAccess.READ)
    if f == null:
        push_warning("BiomeTileSelector: не открыть " + DB_PATH)
        return
    
    var json = JSON.parse_string(f.get_as_text())
    f.close()
    
    if json is Dictionary:
        _db = json
        var interior = _db.get("interior", {})
        print("BiomeTileSelector: загружено %d interior биомов: %s" % [interior.size(), str(interior.keys())])
        print("BiomeTileSelector: загружено %d transitions" % _db.get("transitions", {}).size())

func get_interior_texture(biome_type: int, variant: int = 0) -> Texture2D:
    """Получить текстуру интерьера биома."""
    var interior = _db.get("interior", {})
    var key = str(biome_type)
    
    if key in interior:
        var textures = interior[key].get("textures", [])
        if textures.size() > 0:
            var tex_path = textures[variant % textures.size()]
            return _load_texture(tex_path)
    
    return null

func get_transition_texture(biome_a: int, biome_b: int, direction: String, variant: int = 0) -> Texture2D:
    """Получить текстуру перехода между биомами."""
    var transitions = _db.get("transitions", {})
    var key = "%d:%d" % [biome_a, biome_b]
    
    if key in transitions:
        var dir_data = transitions[key].get(direction, null)
        
        if dir_data is String and dir_data.begins_with("@"):
            # Ссылка на противоположный переход
            return _resolve_reference(dir_data, variant)
        elif dir_data is Array:
            if dir_data.size() > 0:
                var tex_path = dir_data[variant % dir_data.size()]
                return _load_texture(tex_path)
    
    return null

func _resolve_reference(ref: String, variant: int) -> Texture2D:
    """Разрешить ссылку на противоположный переход (@0:5:left)."""
    var parts = ref.substr(1).split(":")  # ["0", "5", "left"]
    if parts.size() == 3:
        var biome_a = int(parts[0])
        var biome_b = int(parts[1])
        var direction = parts[2]
        return get_transition_texture(biome_a, biome_b, direction, variant)
    return null

func _load_texture(path: String) -> Texture2D:
    """Загрузить текстуру с кэшированием."""
    if path in _texture_cache:
        return _texture_cache[path]
    
    if ResourceLoader.exists(path):
        var tex = load(path)
        _texture_cache[path] = tex
        return tex
    
    push_warning("BiomeTileSelector: текстура не найдена " + path)
    return null

func has_biome(biome_type: int) -> bool:
    """Проверить есть ли биом в базе."""
    return str(biome_type) in _db.get("interior", {})

func get_biome_types() -> Array:
    """Получить список типов биомов в базе."""
    var types = []
    for key in _db.get("interior", {}).keys():
        types.append(int(key))
    return types
