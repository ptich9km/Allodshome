extends SceneTree

const TARGETS: Array[Vector2] = [
	Vector2(1849.566, 1491.975),
	Vector2(1795.624, 1524.036),
	Vector2(1779.0, 1546.0),
	Vector2(1734.0, 1531.0),
	Vector2(1775.0, 1490.0),
	Vector2(1730.0, 1495.0),
	Vector2(1696.0, 1520.0),
	Vector2(1810.0, 1470.0),
]

var _hits := 0

func _init() -> void:
	Game.hero_class = "warrior"
	Game.hero_gender = "male"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	Game.hero_stats = {"strength": 20, "dexterity": 20, "intelligence": 10, "vitality": 20, "spirit": 10, "luck": 5}
	Game.hero_start_book = ""
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player = game.get("player")
	var map_node = game.get("alm_map")
	print("SPAWN cell=", Vector2i(int(player.global_position.x) / 32, int(player.global_position.y) / 32), " orc=", Vector2i(4, 2))
	for idx in range(TARGETS.size()):
		game.handle_click(TARGETS[idx])
		for f in range(240):
			await process_frame
			if f % 60 == 0:
				var cell := Vector2i(int(player.global_position.x) / 32, int(player.global_position.y) / 32)
				if not map_node.call("is_walkable_world", player.global_position):
					_hits += 1
					print("HIT idx=%d f=%d cell=%s" % [idx, f, cell])
		print("seg%d end=%s state=%s hits=%d" % [idx, Vector2i(int(player.global_position.x) / 32, int(player.global_position.y) / 32), player.get("state"), _hits])
	print("TOTAL water-hits = ", _hits)
	quit(0)