extends TextureRect
## Faint film grain over the whole screen: a tiled noise texture that jumps
## to a new offset every frame.

const Art = preload("res://scripts/render/art.gd")

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	texture = Art.grain()
	stretch_mode = TextureRect.STRETCH_TILE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.085
	_rng.randomize()


func _process(_delta: float) -> void:
	visible = not Settings.reduced_motion
	if not visible:
		return
	var vs := get_viewport().get_visible_rect().size
	size = vs + Vector2(256, 256)
	position = -Vector2(_rng.randi_range(0, 255), _rng.randi_range(0, 255))
