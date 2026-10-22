extends SceneTree
## Smoke: тематический курсор (cursor_layer.gd).
## Запуск: godot --headless --path . --script res://tests/cursor_smoke.gd
## Проверяет: кадры normal/cast/buy/work грузятся, hotspot-мета валидна,
## переключение варианта cast > контекст (buy/work) > normal.
## Результат: RESULT: OK cursor_smoke (или FAIL с причиной).

func _init() -> void:
	var fails: Array[String] = []
	var script: GDScript = load("res://scripts/cursor_layer.gd")

	# 1. Узел создаётся, кадры загружены (спрайт создаёт _ready при живом рантайме).
	var cl: Variant = script.new()
	root.add_child(cl)
	cl._ensure_loaded()   # в headless-скрипте _ready не успевает до quit
	if not cl._have_any_frames():
		fails.append("кадры не загружены (_have_any_frames=false)")
	else:
		print("кадры загружены")

	# 2. Наборы кадров: все четыре варианта, по фиксированным именам нарезчика.
	for variant in ["normal", "cast", "buy", "work"]:
		var dir: String = "res://assets/ui/cursor/" + variant
		var count := 0
		for i in range(4):
			var path := "%s/cursor-%03d.png" % [dir, i]
			if load(path) == null:
				fails.append("не грузится " + path)
			else:
				count += 1
		if count == 0:
			fails.append("нет кадров в " + dir)
		else:
			print("%s: %d кадров" % [variant, count])
		# 3. Мета с hotspot.
		var meta_txt := FileAccess.get_file_as_string(dir + "/cursor_meta.json")
		if meta_txt == "":
			fails.append("нет cursor_meta.json в " + dir)
		else:
			var parsed: Variant = JSON.parse_string(meta_txt)
			if parsed is Dictionary and parsed.has("hotspot"):
				var hs: Array = parsed["hotspot"]
				if hs.size() != 2:
					fails.append("hotspot некорректен в " + dir)
			else:
				fails.append("cursor_meta.json не парсится в " + dir)

	# 4. Приоритет выбора: cast > контекст (buy/work) > normal.
	Game.cursor_context = "buy"
	var cv: String = cl._current_variant()
	if cv != "buy":
		fails.append("ожидал buy при cursor_context=buy, получено " + cv)
	Game.cursor_context = "work"
	cv = cl._current_variant()
	if cv != "work":
		fails.append("ожидал work при cursor_context=work, получено " + cv)
	Game.pending_spell = {"name": "test"}
	Game.cursor_context = "buy"
	cv = cl._current_variant()
	if cv != "cast":
		fails.append("ожидал cast при pending_spell+buy, получено " + cv)
	Game.pending_spell = {}
	Game.cursor_context = ""
	cv = cl._current_variant()
	if cv != "normal":
		fails.append("ожидал normal без контекста, получено " + cv)

	# 5. Аллодовские курсоры удалены (папка assets/cursors отсутствует).
	if DirAccess.open("res://assets/cursors") != null:
		fails.append("assets/cursors ещё существует — аллодовские курсоры не удалены")

	cl.free()
	if fails.is_empty():
		print("RESULT: OK cursor_smoke")
		quit(0)
	else:
		for f in fails:
			print("FAIL: " + f)
		print("RESULT: FAIL cursor_smoke")
		quit(1)
