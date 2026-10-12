## РЕНДЕР превью рига в PNG: глазами видно, чего не видно в тестах.
##
## Зачем: тест контракта проверяет интерфейс, а не КАРТИНКУ. Палочный риг с
## правильными пивотами всё равно может стоять вверх ногами, иметь дыру в
## тазобедренном шве или не отражаться при повороте — это ловится только
## взглядом. Поэтому рендерим ключевые позы в сетку.
##
## Требует графического бэкенда (не --headless: headless-рендер заглушен и
## Viewport отдаёт пустую текстуру).
##
## Запуск:
##   godot --path . --script res://tests/rig_render_preview.gd

extends SceneTree

const RIG_SET := "rig/hero_atlas"
const CELL := Vector2i(180, 220)
const COLS := 5

## Позы для превью: [клип, время, подпись].
const SHOTS: Array = [
	["idle", 0.0, "idle"],
	["walk", 0.0, "walk 0"],
	["walk", 0.2, "walk mid"],
	["attack", 0.18, "attack wind"],
	["attack", 0.34, "attack hit"],
	["dying", 0.5, "dying"],
	["dying", 1.2, "dead"],
	["decay", 0.8, "decay"],
	["idle", 0.6, "idle W (mirror)"],
	["idle", 0.6, "idle E"],
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rows := int(ceil(float(SHOTS.size()) / float(COLS)))
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x * COLS, CELL.y * rows)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	root.add_child(vp)

	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.16, 0.19)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)

	var rig := RiggedAnim.new()
	rig.name = "UnitAnim"
	rig.setup(RIG_SET)
	if not rig.is_loaded():
		print("[FAIL] риг не загрузился для `%s`" % RIG_SET)
		quit(1)
		return
	if not rig.missing_parts().is_empty():
		for m in rig.missing_parts():
			print("[FAIL] нет текстуры части: " + m)
		quit(1)
		return

	var label := Label.new()
	label.text = RIG_SET
	label.position = Vector2(6, 4)
	label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vp.add_child(label)

	var i := 0
	for shot in SHOTS:
		var col := i % COLS
		var row := int(i / COLS)
		var holder := Node2D.new()
		holder.position = Vector2(col * CELL.x, row * CELL.y)
		vp.add_child(holder)

		# Свежий риг на клетку: состояние клипа не должно течь между позами,
		# иначе превью показывало бы накопленный сдвиг, а не саму позу.
		var r := RiggedAnim.new()
		r.name = "UnitAnim"
		r.setup(RIG_SET)
		# Ноги клетки — «пол» в нижней трети.
		holder.add_child(r)
		r.position = Vector2(CELL.x * 0.5, CELL.y - 26)
		r.play(2 if str(shot[0]) == "attack" else (3 if str(shot[0]) == "dying" else (4 if str(shot[0]) == "decay" else 1 if str(shot[0]) == "walk" else 0)), true)
		r.advance(float(shot[1]))
		if i == SHOTS.size() - 2:
			# предпоследний кадр — проверка зеркала: восток, но показан влево
			r.set_direction_vec(Vector2.LEFT)
			for s in range(8):
				r._advance_rotation(0.06)
		elif i == SHOTS.size() - 1:
			r.set_direction_vec(Vector2.RIGHT)
			for s in range(8):
				r._advance_rotation(0.06)

		var cap := Label.new()
		cap.text = str(shot[2])
		cap.position = holder.position + Vector2(6, 6)
		vp.add_child(cap)
		i += 1

	await process_frame
	await process_frame
	await process_frame

	var img := vp.get_texture().get_image()
	var out := "res://rig_preview.png"
	var err := img.save_png(out)
	print("[render] %dx%d -> %s (err=%d)" % [img.get_width(), img.get_height(), out, err])
	quit(0 if err == OK else 1)