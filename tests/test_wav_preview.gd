extends SceneTree
## Диагностика: найти wav, у которых превью/плейбэк падает (ffp != 8 при QOA).
## Перебираем все res://assets/audio/sfx/**/*.wav, грузим AudioStreamWAV,
## вызываем instantiate_playback() как это делает превью-плагин инспектора.

func walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if f != "." and f != "..":
				walk(dir + "/" + f, out)
		elif f.ends_with(".wav"):
			out.append(dir + "/" + f)
		f = d.get_next()

func _init() -> void:
	var files: Array = []
	walk("res://assets/audio/sfx", files)
	files.sort()
	var bad: Array = []
	var qoa_count := 0
	var pcm_count := 0
	for p in files:
		var wav: AudioStreamWAV = load(p)
		if wav == null:
			bad.append([p, "load() == null"])
			continue
		if wav.format == AudioStreamWAV.FORMAT_QOA:
			qoa_count += 1
			var pb: AudioStreamPlayback = wav.instantiate_playback()
			if pb == null:
				bad.append([p, "QOA instantiate_playback() == null (ffp != 8)"])
		else:
			pcm_count += 1
	print("total:", files.size(), " qoa:", qoa_count, " pcm:", pcm_count)
	if bad.is_empty():
		print("NO BAD FILES — все превью ок")
	else:
		print("BAD FILES:", bad.size())
		for b in bad:
			print("  ", b[0], "—", b[1])
	quit(0)