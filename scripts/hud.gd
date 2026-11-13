extends CanvasLayer
## On-screen HUD: inventory, room name, minimap, leave button, joystick,
## search button, pop-up messages, room-change fade and the end screen.

signal leave_requested
signal search_pressed
signal rematch_requested

const World = preload("res://scripts/world.gd")
const Joystick = preload("res://scripts/joystick.gd")
const ActionButton = preload("res://scripts/action_button.gd")
const Icons = preload("res://scripts/icons.gd")

var world: World
var joystick: Joystick
var search_button: ActionButton
var _room_label: Label
var _minimap: Control
var _inventory: Control
var _fade: ColorRect
var _toast: Label
var _toast_tween: Tween
var _end: Control
var _room := Vector2i.ZERO
var _accent := Color.WHITE
var _held: Array = []
var _has_case := false


func setup(p_world: World, who: String, accent: Color) -> void:
	world = p_world
	_accent = accent

	joystick = Joystick.new()
	joystick.position = Vector2(0, 60)
	joystick.size = Vector2(640, 740)
	add_child(joystick)

	search_button = ActionButton.new()
	search_button.label = "SEARCH"
	search_button.accent = accent
	search_button.radius = 70.0
	search_button.position = Vector2(1280 - 190, 800 - 190)
	search_button.pressed.connect(func(): search_pressed.emit())
	add_child(search_button)

	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.size = Vector2(1280, 60)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var who_label := _label(who, 20, accent)
	who_label.position = Vector2(16, 16)
	add_child(who_label)

	_inventory = Control.new()
	_inventory.position = Vector2(196, 6)
	_inventory.size = Vector2(260, 48)
	_inventory.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory.draw.connect(_draw_inventory)
	add_child(_inventory)

	_room_label = _label("", 28, Color.WHITE)
	_room_label.position = Vector2(440, 10)
	_room_label.size = Vector2(600, 40)
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
	_minimap.position = Vector2(1090, 12)
	_minimap.size = Vector2(56, 56)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap)
	add_child(_minimap)

	_toast = _label("", 26, Color.WHITE)
	_toast.position = Vector2(240, 650)
	_toast.size = Vector2(800, 60)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	add_child(_toast)

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


func set_inventory(items: Array, has_case: bool) -> void:
	_held = items.duplicate()
	_has_case = has_case
	_inventory.queue_redraw()


func toast(msg: String, col := Color.WHITE, seconds := 2.5) -> void:
	_toast.text = msg
	_toast.add_theme_color_override("font_color", col)
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func show_end(won: bool, winner_name: String, can_rematch: bool) -> void:
	search_button.visible = false
	joystick.visible = false
	_end = Control.new()
	_end.size = Vector2(1280, 800)
	add_child(_end)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.size = _end.size
	_end.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.7, 0.4)

	var title := _label("MISSION ACCOMPLISHED" if won else "DOUBLE-CROSSED!", 72, Color("5dff8a") if won else Color("ff5a5f"))
	title.position = Vector2(0, 250)
	title.size = Vector2(1280, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end.add_child(title)
	var sub := _label(
		"You escaped with the intel. Drinks are on you." if won
		else "%s got out with the intel. Awkward." % winner_name, 28, Color(1, 1, 1, 0.85))
	sub.position = Vector2(0, 350)
	sub.size = Vector2(1280, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.position = Vector2(640 - 300, 450)
	row.size = Vector2(600, 80)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_end.add_child(row)
	if can_rematch:
		row.add_child(_end_button("REMATCH", func(): rematch_requested.emit()))
	else:
		var wait := _label("Waiting for the host to call a rematch…", 22, Color(1, 1, 1, 0.6))
		wait.custom_minimum_size = Vector2(0, 70)
		wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(wait)
	row.add_child(_end_button("MENU", func(): leave_requested.emit()))


func _draw_inventory() -> void:
	var slots: Array = World.INTEL + [World.BRIEFCASE]
	for i in slots.size():
		var c := Vector2(24 + i * 50, 24)
		var item: String = slots[i]
		var have := _held.has(item) or (item == World.BRIEFCASE and _has_case)
		_inventory.draw_circle(c, 22, Color(1, 1, 1, 0.12 if have else 0.04))
		if have:
			_inventory.draw_arc(c, 22, 0, TAU, 32, Color(_accent, 0.9), 2.0, true)
		Icons.draw(_inventory, item, c, 30.0, have)
		if i == World.INTEL.size() - 1:
			_inventory.draw_line(Vector2(c.x + 25, 6), Vector2(c.x + 25, 42), Color(1, 1, 1, 0.2), 1.0)


func _draw_minimap() -> void:
	# Isometric mini-map matching the room view's orientation; the exit room is green.
	var a := 9.0
	var origin := Vector2(28, 8)
	for y in World.ROWS:
		for x in World.COLS:
			var c := origin + Vector2((x - y) * a, (x + y) * a * 0.5 + a * 0.5)
			var pts := PackedVector2Array([
				c + Vector2(0, -a * 0.5 + 1), c + Vector2(a - 1.5, 0), c + Vector2(0, a * 0.5 - 1), c + Vector2(-a + 1.5, 0)])
			var here := Vector2i(x, y) == _room
			var col := Color(_accent, 0.9) if here else Color(1, 1, 1, 0.15)
			if not here and Vector2i(x, y) == world.exit_room:
				col = Color("5dff8a", 0.55)
			_minimap.draw_colored_polygon(pts, col)


func _end_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 70)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	return b


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
