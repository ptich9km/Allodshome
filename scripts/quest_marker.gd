extends Node2D
class_name QuestMarker
## Marker above the town head (22.10).
##
## "!" - the head has offers or work to accept; "?" - the player has a
## finished quest of this town to hand in. This is the MMO convention: the
## exclamation mark says "take a quest", the question mark "come back and
## report".
##
## Frames - assets/ui/quest/marks/<name>-NNN.png (4 frames, ai art from
## mai-image-2.6-flash, cut by tests/extract_quest_art.py; the paths live in
## QuestIcons). Without frames the marker draws a coloured diamond: the head
## must be visible even before the art exists.
##
## Position - above the NPC sprite: the height comes from the set's sel_box
## (the same box that is the click hitbox), so the marker never sinks into the
## head of tall or short sprites.

const SPEC := {
	"available": {"frames": 4, "color": Color(1.0, 0.82, 0.25)},
	"ready": {"frames": 4, "color": Color(0.55, 0.9, 0.4)},
}
const FRAME_TIME := 0.16
const BOB_AMP := 2.0
const BOB_SPEED := 2.0

var kind: String = ""            # "available" | "ready" | "" (hidden)
var frames: Array = []           # Texture2D frames of the current kind
var bounce_px: float = 0.0       # reference flight height (sprite pixels)

var _sprite: Sprite2D = null
var _fallback: Polygon2D = null
var _t := 0.0
var _frame := 0
var _accum := 0.0

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Frames"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_apply()

## Show a marker kind. Empty kind - hide.
func set_kind(new_kind: String) -> void:
	if new_kind == kind:
		return
	kind = new_kind
	if is_inside_tree():
		_apply()

## Flight height above the NPC's feet: sprite top plus a margin.
func set_height_px(h: float) -> void:
	bounce_px = h
	position = Vector2(0, -h)

func _apply() -> void:
	visible = kind != ""
	if not visible:
		return
	frames = _load_frames(kind)
	_frame = 0
	_accum = 0.0
	_t = 0.0
	if not frames.is_empty():
		_sprite.texture = frames[0]
		_sprite.visible = true
		if _fallback != null:
			_fallback.queue_free()
			_fallback = null
	else:
		_sprite.visible = false
		_make_fallback()

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	position.y = -bounce_px + sin(_t * BOB_SPEED) * BOB_AMP
	if frames.size() <= 1:
		return
	_accum += delta
	if _accum < FRAME_TIME:
		return
	_accum = 0.0
	_frame = (_frame + 1) % frames.size()
	_sprite.texture = frames[_frame]

func _load_frames(variant: String) -> Array:
	var out: Array = []
	var count := int((SPEC.get(variant, {}) as Dictionary).get("frames", 0))
	for i in range(count):
		var tex = QuestIcons.mark_frame(variant, i)
		if tex == null:
			return []
		out.append(tex)
	return out


## Fallback diamond: there is no art yet, but a head with a quest must be seen.
func _make_fallback() -> void:
	if _fallback != null and is_instance_valid(_fallback):
		return
	_fallback = Polygon2D.new()
	_fallback.name = "Fallback"
	_fallback.polygon = PackedVector2Array([
		Vector2(0, -6), Vector2(5, 0), Vector2(0, 6), Vector2(-5, 0)])
	_fallback.color = color_of(kind)
	add_child(_fallback)
	move_child(_fallback, 0)

## Does this kind have drawn frames (art test and panel preview).
static func has_art(variant: String) -> bool:
	return QuestIcons.has_mark_art(variant)

## Fallback diamond colour of a kind (UiTheme palette, not per-panel numbers).
static func color_of(variant: String) -> Color:
	return SPEC.get(variant, {}).get("color", Color.WHITE)
