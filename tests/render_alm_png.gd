extends SceneTree
## Render .alm map to PNG for visual inspection.
## Usage: godot --headless --path <proj> --script res://tests/render_alm_png.gd
## Optional 1st arg: path to .alm (defaults to generated map).

const TILE := 32
const DEFAULT_MAP := "res://assets/maps/gen/gen_smart_01.alm"
const OUT := "res://assets/maps/gen/gen_smart_01.png"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := DEFAULT_MAP
	if args.size() > 0:
		path = args[0]
	var out := OUT
	if args.size() > 1:
		out = args[1]
	_render(path, out)
	quit(0)

func _render(path: String, out: String) -> void:
	var m: Dictionary = AlmLoader.load_map(path)
	if m.is_empty():
		print("ERROR: load_map " + path)
		return
	var w: int = int(m["width"])
	var h: int = int(m["height"])
	var tiles: PackedInt32Array = m["tiles"]
	var img := Image.create_empty(w * TILE, h * TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var missing := 0
	for y in range(h):
		for x in range(w):
			var tile: int = tiles[y * w + x]
			var raw_f: int = AlmLoader.tile_file(tile)
			var file_n: int = (raw_f >> 4) + 1
			var variant: int = raw_f & 0xF
			var row: int = AlmLoader.tile_frame(tile)
			var bmp := "res://assets/terrain/tile%d-%02d.bmp" % [file_n, variant]
			if not ResourceLoader.exists(bmp):
				missing += 1
				continue
			var tex: Texture2D = load(bmp)
			var src: Image = tex.get_image()
			src.convert(Image.FORMAT_RGBA8)
			var nrows: int = src.get_height() / TILE
			if row >= nrows:
				missing += 1
				continue
			img.blit_rect(src, Rect2i(0, row * TILE, TILE, TILE),
					Vector2i(x * TILE, y * TILE))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)
	print("render %dx%d -> %s (err=%d, missing_tiles=%d)" % [w, h, out, err, missing])
