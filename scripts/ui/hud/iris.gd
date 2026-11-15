extends Control
## Iris wipe for changing rooms: the screen closes to black around a point,
## then opens again from the new spot, like an old film cut.

const CLOSE_TIME := 0.12
const OPEN_TIME := 0.32

var _centre := Vector2.ZERO
var _radius := 0.0
var _max_radius := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Snaps closed around `centre` (this control's coordinates), then opens.
func play(centre: Vector2) -> void:
	if Settings.reduced_motion:
		return  # a plain cut
	_centre = centre
	_max_radius = size.length()
	var tw := create_tween()
	_radius = _max_radius * 0.35
	tw.tween_property(self, "_radius", 0.0, CLOSE_TIME).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "_radius", _max_radius, OPEN_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _radius >= _max_radius - 1.0:
		return
	# A black ring from the iris edge out past the screen corners.
	var outer := _max_radius + 40.0
	var width := outer - _radius
	draw_arc(_centre, _radius + width / 2.0, 0.0, TAU, 96, Color.BLACK, width, true)
