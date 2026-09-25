extends SceneTree
## Проверка, что герой НЕ застревает на границе карты.
##
## Баг: `_move_checked` блокировал весь вектор движения целиком, если впереди
## непроходимая клетка (вода) или граница карты. У края карты таких клеток много,
## и герой «прилипал» к границе: не мог ни пройти, ни отойти, ни сдвинуться вдоль.
##
## Тест: для каждой проходимой клетки, у которой есть непроходимый сосед,
## герой ставится в неё и должен дойти до соседней проходимой клетки.
## Застрявшая клетка = hero не сдвинулся.
##
## Запуск: godot --headless --path . --script res://tests/fuzz_edge.gd

const TILE := 32
## Максимум физических кадров на одну попытку дойти до соседней клетки.
const FRAMES := 90

var _fails: Array[String] = []
var _checked := 0
var _stuck := 0

func _init() -> void:
	Game.hero_class = "warrior"
	Game.hero_name = "Тест"
	Game.hero_character_id = "mfighter"
	Game.hero_stats = {"body": 12, "agility": 11, "mind": 9, "spirit": 8,
		"blade": 30, "bludgeon": 15, "pike": 10,
		"fire": 5, "water": 5, "air": 5, "earth": 5, "astral": 5,
		"weapon": "sword", "shield": true, "armor": "heavy"}
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	for i in range(3):
		await process_frame
	var player = game.get("player")
	var am = game.get("alm_map")
	var w: int = int(am.get("map_width"))
	var h: int = int(am.get("map_height"))
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	# Собираем граничные клетки: проходимые, но с непроходимым соседом.
	var edge_cells: Array[Vector2i] = []
	for y in range(0, h):
		for x in range(0, w):
			if not _walk(am, x, y):
				continue
			var touches_blocked := false
			for d in dirs:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or not _walk(am, nx, ny):
					touches_blocked = true
					break
			if touches_blocked:
				edge_cells.append(Vector2i(x, y))
	print("EDGE_CELLS: %d" % edge_cells.size())
	if edge_cells.is_empty():
		print("RESULT: FAIL fuzz_edge — не найдено ни одной граничной клетки")
		quit(1)
		return

	# Шаг 2 — кратно уменьшаем число проверок, чтобы тест шёл секунды, а не минуты.
	var step: int = maxi(1, edge_cells.size() / 60)
	for i in range(0, edge_cells.size(), step):
		var cell: Vector2i = edge_cells[i]
		var from := Vector2(cell.x * TILE + 16, cell.y * TILE + 16)
		var to_cell := _neighbor_walkable(am, cell, dirs, w, h)
		if to_cell == Vector2i(-999, -999):
			continue  # изолированная клетка, вокруг некуда идти
		_checked += 1
		player.global_position = from
		player.reset_physics_interpolation()
		# Маршрут ставим напрямую, а не через handle_click: клик может попасть в NPC
		# или здание и не дойти до begin_path, а здесь проверяется именно перемещение.
		player.state = "move"
		player.begin_path([Vector2(to_cell.x * TILE + 16, to_cell.y * TILE + 16)])
		for f in range(FRAMES):
			await physics_frame
			if player.global_position.distance_to(from) > 8.0:
				break
		var moved: float = player.global_position.distance_to(from)
		if moved <= 8.0:
			_stuck += 1
			_fails.append("cell=%s (%s) не сдвинулся" % [cell, "изолированная" if to_cell == Vector2i(-999, -999) else "обычная"])
			print("STUCK cell=%s to=%s pos=%s state=%s" % [cell, to_cell, player.global_position, player.get("state")])

	# Граница карты: герой не должен выходить за пределы.
	var edge_x: int = w * TILE
	game.handle_click(Vector2(float(edge_x + 600.0), 2000.0))
	for f in range(400):
		await physics_frame
		var p: Vector2 = player.global_position
		if p.x > edge_x - 1.0 or p.x < 0.0 or p.y < 0.0 or p.y > h * TILE:
			_fails.append("вышел за границу карты: %s" % p)
			break
	print("BOUNDS_OK checked=%d stuck=%d fails=%d" % [_checked, _stuck, _fails.size()])
	print("---")
	if _fails.is_empty():
		print("RESULT: OK fuzz_edge (проверено граничных клеток: %d, застреваний: 0)" % _checked)
		quit(0)
	else:
		print("RESULT: FAIL fuzz_edge (застреваний: %d из %d)" % [_stuck, _checked])
		var shown: int = 0
		for f in _fails:
			print("  - ", f)
			shown += 1
			if shown >= 15:
				print("  ... и ещё %d" % (_fails.size() - shown))
				break
		quit(1)

func _walk(am, x: int, y: int) -> bool:
	return am.call("is_walkable_world", Vector2(x * TILE + 16, y * TILE + 16))

func _neighbor_walkable(am, cell: Vector2i, dirs: Array[Vector2i], w: int, h: int) -> Vector2i:
	for d in dirs:
		var nx: int = cell.x + d.x
		var ny: int = cell.y + d.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		if _walk(am, nx, ny):
			return Vector2i(nx, ny)
	return Vector2i(-999, -999)
