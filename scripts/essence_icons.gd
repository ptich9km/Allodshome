class_name EssenceIcons
extends RefCounted
## Magic essence (22.10): the animated art of the crafting material the Master
## upgrade costs (CraftDB.ESSENCE_KEY). One source of truth for the frames.
##
## The art lives in assets/ui/essence/essence-000..003.png (AI sheet approved
## by the player -> tests/extract_essence_art.py). While the PNGs are missing
## every helper falls back to the item_db icon, so the drop, the craft cost row
## and the inventory keep showing something.

const DIR := "res://assets/ui/essence/"
const PREFIX := "essence"
const FRAMES := 4
## Frame step of the swaying fill (seconds), the same pace as the coin.
const FRAME_TIME := 0.22

static var _frames: Array = []
static var _loaded := false


static func frame_path(index: int) -> String:
	var path := "%s%s-%03d.png" % [DIR, PREFIX, index]
	return path if ResourceLoader.exists(path) else ""


static func frames() -> Array:
	if _loaded:
		return _frames
	_loaded = true
	var out: Array = []
	for i in range(FRAMES):
		var path := frame_path(i)
		if path == "":
			return []
		out.append(load(path))
	_frames = out
	return _frames


static func has_anim() -> bool:
	return frames().size() > 1


## Static icon of the essence: the first animation frame, otherwise the item icon.
static func icon() -> String:
	var path := frame_path(0)
	if path != "":
		return path
	return str(_item_icon())


static func _item_icon() -> String:
	var item := ItemDB.find(CraftDB.ESSENCE_KEY)
	return str(item.get("icon", ""))


## Texture of the icon for a Control that does not animate (cost rows, cards).
static func texture() -> Texture2D:
	var f := frames()
	if not f.is_empty():
		return f[0]
	var path := _item_icon()
	return load(path) if path != "" and ResourceLoader.exists(path) else null


## One animation tick shared by every essence icon on screen: returns the
## next frame index; the caller keeps the time accumulator.
static func tick_frame(delta: float, elapsed: float, frame: int) -> Dictionary:
	var f := frames()
	if f.size() <= 1:
		return {"frame": 0, "t": 0.0}
	elapsed += delta
	if elapsed < FRAME_TIME:
		return {"frame": frame, "t": elapsed}
	return {"frame": (frame + 1) % f.size(), "t": 0.0}
