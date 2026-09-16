extends SceneTree
## Диагностика StructureDB: находит ли записи по ID и папке.

func _init() -> void:
	StructureDB.ensure_loaded()
	print("БД размер:", StructureDB._db.size())
	for tid in [1, 2, 15, 38, 53, 66, 67]:
		var rec := StructureDB.get_by_id(tid)
		print("id=%d -> folder=%s fw=%s th=%s fh=%s phases=%s sel=%s" % [
			tid, rec.get("folder"), rec.get("tile_width"), rec.get("tile_height"),
			rec.get("full_height"), rec.get("phases"), rec.get("sel")])
	var r15 := StructureDB.get_structure("well2")
	print("по папке well2:", r15.get("id"), r15.get("desc"))
	quit(0)