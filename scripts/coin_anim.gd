class_name CoinAnim
extends Sprite2D
## Swaying gold coin on the ground (22.10): the same 4-frame sprite as the
## quest reward (QuestIcons.coin_frames), plus a small bob like a quest item.
## Falls back to the static frame and stands still while the art is missing.

const FRAME_TIME := QuestIcons.COIN_FRAME_TIME
const BOB_SPEED := 2.0
const BOB_AMP := 1.5

var _frames: Array = []
var _frame := 0
var _frame_t := 0.0
var _bob_t := 0.0
var _base_position := Vector2.ZERO


## Size in pixels the caller wants the coin on screen. The frame art is 32 px,
## so the scale keeps the same footprint as any other loot icon.
func setup(px: float) -> void:
	_frames = QuestIcons.coin_frames()
	if _frames.is_empty():
		texture = load(LootIcons.gold_icon())
	else:
		texture = _frames[0]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex := texture
	if tex != null:
		var side := float(maxi(1, maxi(tex.get_width(), tex.get_height())))
		var k := px / side
		scale = Vector2(k, k)


## World position as the loot layout lays it out; the bob moves around it.
func set_layout_position(p: Vector2) -> void:
	_base_position = p
	position = p


func _process(delta: float) -> void:
	_bob_t += delta
	position = _base_position + Vector2(0.0, sin(_bob_t * BOB_SPEED) * BOB_AMP)
	if _frames.size() <= 1:
		return
	_frame_t += delta
	if _frame_t < FRAME_TIME:
		return
	_frame_t = 0.0
	_frame = (_frame + 1) % _frames.size()
	texture = _frames[_frame]
