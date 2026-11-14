extends Control
## Floating virtual joystick: touch anywhere on the left half of the screen
## and drag. Also works with a mouse (touch emulation is on).

const MAX_DIST := 90.0

var output := Vector2.ZERO
var _touch := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed and _touch == -1 and Rect2(Vector2.ZERO, size).has_point(local):
			_touch = event.index
			_origin = local
			_knob = local
			output = Vector2.ZERO
			queue_redraw()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			output = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == _touch:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var off := (local - _origin).limit_length(MAX_DIST)
		_knob = _origin + off
		output = off / MAX_DIST
		queue_redraw()


func _draw() -> void:
	if _touch == -1:
		var hint := Vector2(160, size.y - 130)
		draw_circle(hint, MAX_DIST, Color(1, 1, 1, 0.05))
		draw_arc(hint, MAX_DIST, 0, TAU, 48, Color(1, 1, 1, 0.15), 2.0, true)
		draw_circle(hint, 34, Color(1, 1, 1, 0.12))
		return
	draw_circle(_origin, MAX_DIST, Color(1, 1, 1, 0.08))
	draw_arc(_origin, MAX_DIST, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0, true)
	draw_circle(_knob, 38, Color(1, 1, 1, 0.35))
