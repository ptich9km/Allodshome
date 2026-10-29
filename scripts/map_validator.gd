class_name MapValidator
extends RefCounted
## Проверка пользовательской карты перед запуском (кнопка «Проверить»).
##
## Ловит то, что игра переживёт молча, но игрок увидит как поломку:
## нет спавна, спавн в воде, портал в никуда, здание за границей или поверх
## другого, неизвестный type_id (например, снесённые Аллодовские 1..179),
## НПЦ из несуществующего набора.
##
## Возврат: [{level: "error"|"warn", text: String, cell: Vector2i}].
## Уровень "error" — карта неиграбельна; "warn" — можно, но лучше поправить.

const CHAIN := {"start": "mid", "mid": "hard"}


static func validate(map: CustomMap, alm_path: String, zone: String) -> Array:
	var out: Array = []
	if map == null or map.map_width <= 0 or map.map_height <= 0:
		out.append(_err("Карта пустая: нет размеров.", Vector2i(-1, -1)))
		return out

	if not StartSetup.ZONES.has(zone):
		out.append(_warn("Неизвестная зона «%s» — старт будет из start." % zone, Vector2i(-1, -1)))
	if alm_path == "":
		out.append(_err("Карта ещё не сохранена в .alm — играть нечего.", Vector2i(-1, -1)))

	_check_spawn(map, out)
	_check_structures(map, out)
	_check_npcs(map, out)
	_check_portals(map, zone, out)
	return out


static func _check_spawn(map: CustomMap, out: Array) -> void:
	var cell := map.spawn_cell
	if cell.x < 0:
		out.append(_err("Нет точки спавна героя (инструмент «Спавн героя»).", Vector2i(-1, -1)))
		return
	if not _inside(map, cell):
		out.append(_err("Спавн за границей карты: %s." % str(cell), cell))
		return
	var t := map.tile_id_at(cell)
	if t == 1 or t == 2:
		out.append(_err("Спавн на непроходимой клетке (%s)." % CustomMap.TYPE_NAMES[t], cell))
	elif t >= 7:
		out.append(_warn("Спавн стоит на клетке с пропом/зданием.", cell))


static func _check_structures(map: CustomMap, out: Array) -> void:
	var rects: Array = []
	for i in range(map.structures.size()):
		var rec: Dictionary = map.structures[i]
		var tid := int(rec.get("type_id", 0))
		var def := StructureDB.get_by_id(tid)
		if def.is_empty():
			out.append(_err("Неизвестное здание type_id=%d (арт удалён или карта старая)." % tid,
				Vector2i(int(rec.get("x", 0)), int(rec.get("y", 0)))))
			continue
		var rect := map.structure_rect(rec)
		if rect.position.x < 0 or rect.position.y < 0 \
				or rect.end.x > map.map_width or rect.end.y > map.map_height:
			out.append(_err("Здание «%s» выходит за границу карты." % def.get("desc", tid),
				Vector2i(rect.position.x, rect.position.y)))
			continue
		for j in range(rects.size()):
			if (rects[j] as Rect2i).intersects(rect):
				out.append(_err("Здание «%s» пересекается с другим." % def.get("desc", tid),
					Vector2i(rect.position.x, rect.position.y)))
				break
		rects.append(rect)
		# Ставим на воду/горы — предупреждение, а не ошибка: игрок может хотеть
		# «парящий» замок, но обычно это промах кистью.
		var t := map.tile_id_at(Vector2i(rect.position.x, rect.end.y - 1))
		if t == 1 or t == 2:
			out.append(_warn("Здание «%s» стоит на %s." % [
				def.get("desc", tid), CustomMap.TYPE_NAMES[t]],
				Vector2i(rect.position.x, rect.end.y - 1)))


static func _check_npcs(map: CustomMap, out: Array) -> void:
	for raw in map.npcs:
		var rec: Dictionary = raw
		var cell := Vector2i(int(rec.get("x", -1)), int(rec.get("y", -1)))
		var set_name := str(rec.get("set", ""))
		if not UnitDB.has(set_name):
			out.append(_err("НПЦ набора «%s» нет в units_db." % set_name, cell))
			continue
		if not _inside(map, cell):
			out.append(_err("НПЦ «%s» за границей карты." % set_name, cell))
			continue
		if map.tile_id_at(cell) == 1 or map.tile_id_at(cell) == 2:
			out.append(_warn("НПЦ «%s» стоит на непроходимой клетке." % set_name, cell))


static func _check_portals(map: CustomMap, zone: String, out: Array) -> void:
	var wm: GDScript = load("res://scripts/world/world_map.gd")
	for raw in map.portals:
		var rec: Dictionary = raw
		var cell := Vector2i(int(rec.get("x", -1)), int(rec.get("y", -1)))
		if not _inside(map, cell):
			out.append(_err("Портал за границей карты: %s." % str(cell), cell))
			continue
		var to := str(rec.get("to", ""))
		if to == "":
			if not CHAIN.has(zone):
				out.append(_err("Портал «по цепочке» из зоны %s ведёт в никуда (тупик)." % zone, cell))
		elif not wm.has(to):
			out.append(_err("Портал ведёт в несуществующий сектор «%s»." % to, cell))
		if cell == map.spawn_cell:
			out.append(_warn("Портал стоит на клетке спавна — герой сразу спросит переход.", cell))


static func _inside(map: CustomMap, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map.map_width and cell.y < map.map_height


static func _err(text: String, cell: Vector2i) -> Dictionary:
	return {"level": "error", "text": text, "cell": cell}


static func _warn(text: String, cell: Vector2i) -> Dictionary:
	return {"level": "warn", "text": text, "cell": cell}
