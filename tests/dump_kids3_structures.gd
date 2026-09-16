extends SceneTree
## Печать структур Kids3.alm через родной парсер AlmLoader.

func _init() -> void:
	var map: Dictionary = AlmLoader.load_map("res://assets/maps/Kids3.alm")
	var structs: Array = map.get("structures", [])
	print("структур на карте:", structs.size())
	var types := {}
	for st in structs:
		var tid := int(st.get("type_id", 0))
		types[tid] = int(types.get(tid, 0)) + 1
	var keys: Array = types.keys()
	keys.sort()
	for t in keys:
		print("TypeID=%d x%d" % [t, types[t]])
	quit(0)