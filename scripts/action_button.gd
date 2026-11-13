extends Control
## Round on-screen action button that reads touches directly, so it works
## while the other thumb is holding the joystick (multi-touch).

signal pressed

const Icons = preload("res://scripts/icons.gd")

var label := "ACTION"
var accent := Color("5ab0ff")
var radius := 64.0
var enabled := true:
	set(v):
		enabled = v
		queue_redraw()

var _touch := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(radius * 2, radius * 2)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed and _touch == -1 and local.distance_to(size / 2) <= radius:
			_touch = event.index
			queue_redraw()
			if enabled:
				pressed.emit()
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			queue_redraw()


func _draw() -> void:
	var c := size / 2
	var down := _touch != -1 and enabled
	var a := 1.0 if enabled else 0.3
	draw_circle(c, radius, Color(accent, (0.45 if down else 0.18) * a))
	draw_arc(c, radius, 0, TAU, 48, Color(accent, 0.9 * a), 3.0, true)
	Icons.magnifier(self, c - Vector2(0, 10), radius * 0.8, Color(1, 1, 1, a))
	var font := ThemeDB.fallback_font
	var fs := 16
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w / 2, radius * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
