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
				var walkable: bool = map_node.call("is_walkable_world", player.global_position)
				var in_water := _is_water(map_node, cell)
				# Проверяем ОБА условия, а не только проходимость. Настоящий
				# баг: переходные тайлы (файлы 8..15) попадали в WalkTable
				# как файл 8..15, которого в таблице нет, цена падала на
				# DEFAULT=8, и берег становился ПРОХОДИМЫМ. Тогда
				# is_walkable_world возвращал true, и проверка только на
				# проходимость рапортовала 0 hits при сломанной игре.
				#
				# ОГРАНИЧЕНИЕ: эти клики заканчиваются на суше, поэтому
				# утверждение про тип клетки срабатывает редко и само по
				# себе регрессию не доказывает. Надёжный страж - проверка
				# "переходный тайл не меняет проходимость биома" в
				# transition_blend_smoke, она обходит ВСЕ клетки карты.
				if not walkable or in_water:
					_hits += 1
					print("HIT idx=%d f=%d cell=%s walkable=%s water=%s" % [idx, f, cell, walkable, in_water])
		print("seg%d end=%s state=%s hits=%d" % [idx, Vector2i(int(player.global_position.x) / 32, int(player.global_position.y) / 32), player.get("state"), _hits])
	print("TOTAL water-hits = ", _hits)
	quit(0)

## Тип клетки по данным карты: 2 = вода. Берём из hflags, а не из
## is_walkable_world, чтобы ловить именно «герой в клетке воды».
func _is_water(map_node, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_node.map_width or cell.y >= map_node.map_height:
		return false
	var i: int = cell.y * map_node.map_width + cell.x
	return AlmLoader.terrain_type(map_node._hflags[i]) == 2
