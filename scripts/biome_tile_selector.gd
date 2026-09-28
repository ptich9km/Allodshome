class_name BiomeTileSelector
extends RefCounted
## Selects procedural biome textures (PNG) for terrain types 4-6.
## Interior: {type}_{variant:02d}.png
## Transitions: {typeA}_{typeB}_{direction}_{variant:02d}.png
## Missing pairs fall back to BMP tiles (handled by caller).

const BIOME_DIR := "res://assets/terrain/biomes"
const NUM_VARIANTS := 6

## Map terrain type -> directory name
const TYPE_DIR := {
	0: "grass", 1: "mountain", 2: "water", 3: "road",
	4: "soil", 5: "sand", 6: "mud",
}

## Map terrain type -> friendly name for paths
const TYPE_NAME := {
	0: "grass", 1: "mountain", 2: "water", 3: "road",
	4: "soil", 5: "sand", 6: "mud",
}

## Direction name mapping: generator direction -> texture direction
## N=from_north (tile above differs) -> texture "top" (north edge of THIS tile)
const DIR_MAP := {
	"N": "top", "S": "bottom", "E": "right", "W": "left",
	"NE": "right", "NW": "left", "SE": "right", "SW": "left",
}

## Cached textures: interior[type] = [Texture2D x 6]
var _interior := {}
## Cached transitions: transitions["typeA_typeB_dir"] = [Texture2D x 6]
var _transitions := {}
## Set of types that have biome textures available
var _available_types := {}

func _init() -> void:
	_load_interior()
	_load_transitions()


func _load_interior() -> void:
	for t in TYPE_DIR:
		var dir_name: String = TYPE_DIR[t]
		var textures: Array = []
		for v in range(NUM_VARIANTS):
			var path := "%s/%s/%s_%02d.png" % [BIOME_DIR, dir_name, dir_name, v + 1]
			if ResourceLoader.exists(path):
				var tex: Texture2D = load(path)
				if tex:
					textures.append(tex)
		if textures.size() > 0:
			_interior[t] = textures
			_available_types[t] = true


func _load_transitions() -> void:
	var dir := DirAccess.open(BIOME_DIR)
	if dir == null:
		return
	var trans_dir := DirAccess.open(BIOME_DIR + "/transitions")
	if trans_dir == null:
		return
	trans_dir.list_dir_begin()
	var fname := trans_dir.get_next()
	while fname != "":
		if fname.ends_with(".png") and not fname.ends_with(".import"):
			# Parse: grass_sand_bottom_01.png -> typeA=grass, typeB=sand, dir=bottom, v=01
			var parts := fname.replace(".png", "").split("_")
			if parts.size() >= 4:
				var direction: String = parts[parts.size() - 2]  # bottom/left/right/top
				var variant_str: String = parts[parts.size() - 1]  # 01-06
				var type_b: String = parts[parts.size() - 3]  # sand/soil/mud
				# typeA = everything before type_b and direction
				var type_a_parts := parts.slice(0, parts.size() - 3)
				var type_a: String = "_".join(type_a_parts)  # grass/mountain

				var ta := _name_to_type(type_a)
				var tb := _name_to_type(type_b)
				if ta >= 0 and tb >= 0:
					var variant := variant_str.to_int() - 1
					if variant >= 0 and variant < NUM_VARIANTS:
						var key := "%d_%d_%s" % [ta, tb, direction]
						if not _transitions.has(key):
							_transitions[key] = []
						var path := "%s/transitions/%s" % [BIOME_DIR, fname]
						if ResourceLoader.exists(path):
							var tex: Texture2D = load(path)
							if tex:
								while _transitions[key].size() <= variant:
									_transitions[key].append(null)
								_transitions[key][variant] = tex
		fname = trans_dir.get_next()
	trans_dir.list_dir_end()


func _name_to_type(n: String) -> int:
	for t in TYPE_NAME:
		if TYPE_NAME[t] == n:
			return t
	return -1


func has_type(t: int) -> bool:
	return _available_types.has(t)


func has_transition(ta: int, tb: int) -> bool:
	# Check both orderings
	return _transitions.has("%d_%d_top" % [ta, tb]) or _transitions.has("%d_%d_top" % [tb, ta])


## Get interior texture for terrain type. variant derived from position hash.
func get_interior(t: int, variant: int) -> Texture2D:
	if not _interior.has(t):
		return null
	var textures: Array = _interior[t]
	if textures.is_empty():
		return null
	return textures[variant % textures.size()]


## Get transition texture for two terrain types and direction.
## direction: "N", "S", "E", "W", "NE", "NW", "SE", "SW"
## The texture shows the edge of type A bordering type B.
func get_transition(ta: int, tb: int, direction: String, variant: int) -> Texture2D:
	var tex_dir: String = DIR_MAP.get(direction, "bottom")

	# Try ta->tb first, then tb->ta (reversed direction)
	var key := "%d_%d_%s" % [ta, tb, tex_dir]
	if _transitions.has(key):
		var textures: Array = _transitions[key]
		if not textures.is_empty():
			return textures[variant % textures.size()]

	# Try reversed: swap A/B and flip direction
	var rev_key := "%d_%d_%s" % [tb, ta, _flip_dir(tex_dir)]
	if _transitions.has(rev_key):
		var textures: Array = _transitions[rev_key]
		if not textures.is_empty():
			return textures[variant % textures.size()]

	return null


func _flip_dir(d: String) -> String:
	match d:
		"top": return "bottom"
		"bottom": return "top"
		"left": return "right"
		"right": return "left"
	return d
