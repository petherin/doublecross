extends CanvasLayer
## On-screen HUD: room name, minimap, leave button, joystick and room-change fade.

signal leave_requested

const World = preload("res://scripts/world.gd")
const Joystick = preload("res://scripts/joystick.gd")

var world: World
var joystick: Joystick
var _room_label: Label
var _who_label: Label
var _minimap: Control
var _fade: ColorRect
var _room := Vector2i.ZERO
var _accent := Color.WHITE


func setup(p_world: World, who: String, accent: Color) -> void:
	world = p_world
	_accent = accent

	joystick = Joystick.new()
	joystick.position = Vector2(0, 60)
	joystick.size = Vector2(640, 740)
	add_child(joystick)

	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.position = Vector2.ZERO
	bar.size = Vector2(1280, 60)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_who_label = _label(who, 22, accent)
	_who_label.position = Vector2(20, 14)
	add_child(_who_label)

	_room_label = _label("", 28, Color.WHITE)
	_room_label.position = Vector2(0, 10)
	_room_label.size = Vector2(1280, 40)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_room_label)

	var leave := Button.new()
	leave.text = "LEAVE"
	leave.position = Vector2(1170, 10)
	leave.size = Vector2(96, 40)
	leave.add_theme_font_size_override("font_size", 18)
	leave.pressed.connect(func(): leave_requested.emit())
	add_child(leave)

	_minimap = Control.new()
	_minimap.position = Vector2(1180, 80)
	_minimap.size = Vector2(86, 86)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap)
	add_child(_minimap)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = Vector2(1280, 800)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func show_room(room: Vector2i, animate: bool) -> void:
	_room = room
	_room_label.text = world.rooms[room]["name"].to_upper()
	_room_label.add_theme_color_override("font_color", (world.rooms[room]["tint"] as Color).lightened(0.4))
	_minimap.queue_redraw()
	if animate:
		_fade.color.a = 0.7
		create_tween().tween_property(_fade, "color:a", 0.0, 0.25)


func _draw_minimap() -> void:
	var cell := 26.0
	var pad := 4.0
	for y in World.ROWS:
		for x in World.COLS:
			var r := Rect2(x * (cell + pad), y * (cell + pad), cell, cell)
			var here := Vector2i(x, y) == _room
			_minimap.draw_rect(r, Color(_accent, 0.85) if here else Color(1, 1, 1, 0.12))
			_minimap.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
