extends SceneTree
## Сторож целостности кадров зданий после чистки арта Аллодов (29.10).
##
## Раньше здесь проверялся отсев битых фаз анимации у Аллодовских зданий
## (train/inn/blacksmith/tower/castle/mill): у части из них вторая фаза была
## заглушкой, и крыша на ней исчезала. Арт Аллодов удалён целиком (ids 1..179),
## а все наши здания — цельный спрайт 3×3 без фаз (whole_image=1, phases=1).
##
## Поэтому тест проверяет обратное: у оставшихся зданий НЕТ лишних кадров и
## фаз, а единственный кадр (`house-001.png`) реально грузится. Если когда-то
## появится анимированное здание, тест честно упадёт и напомнит, что отсев фаз
## (scripts/structure_node.gd) надо вернуть к жизни.
##
## Запуск: godot --headless --path . --script res://tests/structure_anim_smoke.gd

var _fails: Array[String] = []
var _checked := 0

func _init() -> void:
	var ids: Array = StructureDB.ids()
	_check(ids.size() > 0, "здания в structure_db: %d" % ids.size())
	for id in ids:
		var rec: Dictionary = StructureDB.get_by_id(int(id))
		var folder := str(rec.get("folder", ""))
		if folder == "":
			continue
		var phases := int(rec.get("phases", 1))
		_check(phases == 1, "%s (id %d): фаз 1 (у нас %d)" % [folder, int(id), phases])
		_check(int(rec.get("whole_image", 0)) == 1,
			"%s (id %d): цельный спрайт (whole_image=1)" % [folder, int(id)])
		var base := "res://assets/structures/%s/house-001.png" % folder
		_check(ResourceLoader.exists(base),
			"%s (id %d): house-001.png грузится" % [folder, int(id)])
		var extra := 0
		for frame in range(2, 6):
			var p := "res://assets/structures/%s/house-%03d.png" % [folder, frame]
			if ResourceLoader.exists(p):
				extra += 1
		_check(extra == 0, "%s (id %d): лишних кадров нет (%d)" % [folder, int(id), extra])
	_report()

func _check(cond: bool, label: String) -> void:
	_checked += 1
	if cond:
		print("OK   ", label)
	else:
		print("FAIL ", label)
		_fails.append(label)

func _report() -> void:
	print("---")
	if _fails.is_empty():
		print("RESULT: OK structure_anim_smoke (проверок: %d)" % _checked)
		quit(0)
	else:
		print("RESULT: FAIL structure_anim_smoke (провалено: %d)" % _fails.size())
		quit(1)
