## Замер: почему герой выглядит выше и худое NPC города.
##
## Сравниваем не холсты, а СИЛУЭТЫ (непрозрачные пиксели): высоту, ширину и
## отношение ширины к высоте. Холст 64x64 у обоих, но контент разный.
##
## Запуск:
##   godot --headless --path . --script res://tests/hero_size_probe.gd

extends SceneTree

const SETS := ["hero/war_men", "city_human_mage/t1", "city_human_warrior/t2"]


func _init() -> void:
	call_deferred("_run")


func _silhouette(tex: Texture2D) -> Dictionary:
	var img: Image = tex.get_image()
	if img == null:
		return {}
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	var count := 0
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.35:
				count += 1
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	if x1 < 0:
		return {}
	return {"w": w, "h": h, "x0": x0, "x1": x1, "y0": y0, "y1": y1,
		"cw": x1 - x0 + 1, "ch": y1 - y0 + 1, "px": count}


func _run() -> void:
	for set_name in SETS:
		var o: Dictionary = UnitDB.get_set(set_name)
		if o.is_empty():
			print("%s: НЕТ В БАЗЕ" % set_name)
			continue
		var folder := str(o.get("folder", set_name))
		var prefix := str(o.get("prefix", "sprites"))
		print("=== %s (folder=%s)" % [set_name, folder])
		print("    холст в базе: w=%d h=%d cx=%d cy=%d tile=%s" % [
			int(o.get("w", 0)), int(o.get("h", 0)), int(o.get("cx", -1)),
			int(o.get("cy", -1)), str(o.get("tile", "null"))])
		print("    UnitDB.tile_size=%d  блоков=%d" % [
			int(UnitDB.tile_size(set_name)), int(o.get("blocks", 1))])
		var frames := int(o.get("frames", 0))
		for i in range(1, mini(frames, 6) + 1):
			var path := UnitDB.frame_path(folder, prefix, i)
			if not ResourceLoader.exists(path):
				print("    кадр %d: НЕТ ФАЙЛА %s" % [i, path])
				continue
			var s := _silhouette(load(path))
			if s.is_empty():
				print("    кадр %d: пустой" % i)
				continue
			var ratio: float = float(s["cw"]) / float(s["ch"])
			print("    кадр %d: холст %dx%d, контент %dx%d (y %d..%d), ширина/высота=%.3f" % [
				i, int(s["w"]), int(s["h"]), int(s["cw"]), int(s["ch"]),
				int(s["y0"]), int(s["y1"]), ratio])
	quit(0)
