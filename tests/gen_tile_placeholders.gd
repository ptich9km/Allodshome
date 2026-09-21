extends SceneTree
## Генератор тайлов tile5 (почва), tile6 (песок), tile7 (грязь).
## Два формата:
##   - PNG 32×32: assets/terrain/tiles/tileN-VV_RR.png — палитра transition_editor
##   - BMP 32×448: assets/terrain/tileN-VV.bmp (14 рядов) — рендер AlmMap/CustomMap
## Текстуры — процедурный шум по базовому цвету, не плоская заливка.

const TILE_PNG_DIR := "res://assets/terrain/tiles/"
const TILE_BMP_DIR := "res://assets/terrain/"

var _configs := {
	5: {"name": "soil", "base": Color(0.42, 0.28, 0.14), "contrast": 0.14},
	6: {"name": "sand", "base": Color(0.82, 0.76, 0.48), "contrast": 0.10},
	7: {"name": "mud",  "base": Color(0.28, 0.21, 0.12), "contrast": 0.12},
}

func _init() -> void:
	for file_n in _configs:
		var cfg: Dictionary = _configs[file_n]
		_generate_file(int(file_n), cfg["name"], cfg["base"], cfg["contrast"])
	quit(0)

func _generate_file(file_n: int, tname: String, base: Color, contrast: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = file_n * 7919
	var png_count := 0
	var bmp_count := 0

	for variant in range(16):
		# --- BMP-полоса 14 рядов (32×448) ---
		var strip := Image.create_empty(32, 32 * 14, false, Image.FORMAT_RGB8)
		for row in range(14):
			var cell := _make_cell(rng, base, contrast, variant, row)
			strip.blit_rect(cell, Rect2i(0, 0, 32, 32), Vector2i(0, row * 32))
		var bmp_path := TILE_BMP_DIR + "tile%d-%02d.bmp" % [file_n, variant]
		_save_bmp(strip, bmp_path)
		bmp_count += 1

		# --- PNG-ячейки для палитры ---
		for row in range(14):
			var cell2 := _make_cell(rng, base, contrast, variant, row)
			var png_path := TILE_PNG_DIR + "tile%d-%02d_%02d.png" % [file_n, variant, row]
			cell2.convert(Image.FORMAT_RGBA8)
			cell2.save_png(png_path)
			png_count += 1

	print("tile%d (%s): %d BMP strips, %d PNG cells" % [file_n, tname, bmp_count, png_count])

## Ячейка 32×32: шум + лёгкая вертикальная градация (как у оригинальных тайлов).
func _make_cell(rng: RandomNumberGenerator, base: Color, contrast: float, variant: int, row: int) -> Image:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGB8)
	# Смещение тона по variant/row, чтобы тайлы отличались глазом
	var tone := Color(
		rng.randf_range(-contrast * 0.5, contrast * 0.5),
		rng.randf_range(-contrast * 0.5, contrast * 0.5),
		rng.randf_range(-contrast * 0.5, contrast * 0.5))
	var c0 := base + tone
	for py in range(32):
		var grad := 1.0 - float(py) / 32.0 * 0.10
		var row_c := c0 * grad
		for px in range(32):
			# Value-noise: два случайных «пикселя» + сглаживание
			var n := rng.randf_range(-contrast, contrast)
			var n2 := rng.randf_range(-contrast * 0.3, contrast * 0.3)
			var c := row_c + Color(n + n2, n + n2, n + n2)
			img.set_pixel(px, py, _clamp_col(c))
	return img

func _clamp_col(c: Color) -> Color:
	return Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0))

## Сохранить Image как несжатый 24-бит BMP (Godot 4 не умеет save_bmp).
func _save_bmp(img: Image, path: String) -> void:
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var row_size := w * 3
	var pad := (4 - (row_size % 4)) % 4
	var data_size := (row_size + pad) * h
	var file_size := 54 + data_size
	var buf := PackedByteArray()
	buf.resize(file_size)
	# Заголовок файла 'BM'
	buf[0] = 0x42
	buf[1] = 0x4D
	_u32(buf, 2, file_size)
	_u32(buf, 10, 54)          # offset до пикселей
	_u32(buf, 14, 40)          # размер DIB-заголовка
	_s32(buf, 18, w)
	_s32(buf, 22, h)           # положительная высота = bottom-up (Godot не ест top-down)
	_u16(buf, 26, 1)           # planes
	_u16(buf, 28, 24)          # bpp
	_u32(buf, 34, data_size)
	# Пиксели BGR, снизу вверх (классический bottom-up BMP)
	var o := 54
	for y in range(h - 1, -1, -1):
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			buf[o] = int(c.b * 255.0)
			buf[o + 1] = int(c.g * 255.0)
			buf[o + 2] = int(c.r * 255.0)
			o += 3
		for _p in range(pad):
			buf[o] = 0
			o += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(buf)
		f.close()

func _u32(b: PackedByteArray, off: int, v: int) -> void:
	b[off] = v & 0xFF
	b[off + 1] = (v >> 8) & 0xFF
	b[off + 2] = (v >> 16) & 0xFF
	b[off + 3] = (v >> 24) & 0xFF

func _s32(b: PackedByteArray, off: int, v: int) -> void:
	_u32(b, off, v & 0xFFFFFFFF)

func _u16(b: PackedByteArray, off: int, v: int) -> void:
	b[off] = v & 0xFF
	b[off + 1] = (v >> 8) & 0xFF
