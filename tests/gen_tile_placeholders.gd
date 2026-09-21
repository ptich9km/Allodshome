extends SceneTree
## Генератор placeholder-тайлов для tile5 (почва), tile6 (песок), tile7 (грязь).
## Создаёт отдельные PNG 32×32 для каждого variant/row как tile1-4.

const TILE_DIR := "res://assets/terrain/tiles/"

var _configs := {
	5: {"name": "soil",  "base": Color(0.45, 0.30, 0.15)},
	6: {"name": "sand",  "base": Color(0.85, 0.80, 0.50)},
	7: {"name": "mud",   "base": Color(0.30, 0.22, 0.12)},
}

func _init() -> void:
	for file_n in _configs:
		var cfg: Dictionary = _configs[file_n]
		_generate_tiles(file_n, cfg["name"], cfg["base"])
	quit(0)

func _generate_tiles(file_n: int, name: String, base: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = file_n * 1000
	var count := 0
	for variant in range(16):
		for row in range(14):
			var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			var shift := Color(
				rng.randf_range(-0.06, 0.06),
				rng.randf_range(-0.06, 0.06),
				rng.randf_range(-0.06, 0.06))
			var c := base + shift
			for py in range(32):
				var grad := 1.0 - float(py) / 32.0 * 0.12
				var row_c := c * grad
				for px in range(32):
					var noise := rng.randf_range(-0.02, 0.02)
					img.set_pixel(px, py, row_c + Color(noise, noise, noise))
			var path := TILE_DIR + "tile%d-%02d_%02d.png" % [file_n, variant, row]
			img.save_png(path)
			count += 1
	print("Created %d tiles for tile%d (%s)" % [count, file_n, name])
