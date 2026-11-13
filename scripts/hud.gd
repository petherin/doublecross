extends CanvasLayer
## On-screen HUD: inventory, room name, minimap, leave button, joystick,
## search button, pop-up messages, room-change fade and the end screen.

signal leave_requested
signal search_pressed
signal rematch_requested
signal trap_chosen(kind: String)
signal attack_pressed
signal fire_pressed

const World = preload("res://scripts/world.gd")
const Joystick = preload("res://scripts/joystick.gd")
const ActionButton = preload("res://scripts/action_button.gd")
const Icons = preload("res://scripts/icons.gd")
const Ui = preload("res://scripts/ui.gd")

var world: World
var joystick: Joystick
var search_button: ActionButton
var trap_button: ActionButton
var attack_button: ActionButton
var fire_button: ActionButton
var _status: Control
var _clock_mine := 0.0
var _clock_rival := -1.0
var _hp := 3
var _max_hp := 3
var _darts := 3
var _trap_options := {}       # kind -> ActionButton
var _trap_menu_open := false
var _trap_menu_timer := 0.0
var _flash: ColorRect
var _gadgets: Array = []
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
var _bar: ColorRect
var _leave: Button
var _has_case := false


func setup(p_world: World, who: String, accent: Color) -> void:
	world = p_world
	_accent = accent

	# Everything on this layer is scaled up on small screens (phones).
	scale = Vector2.ONE * Ui.scale()

	joystick = Joystick.new()
	add_child(joystick)

	search_button = ActionButton.new()
	search_button.label = "SEARCH"
	search_button.accent = accent
	search_button.radius = 70.0
	search_button.pressed.connect(func(): search_pressed.emit())
	add_child(search_button)

	attack_button = ActionButton.new()
	attack_button.label = "ATTACK"
	attack_button.icon = "COSH"
	attack_button.accent = Color("ff7a1a")
	attack_button.radius = 58.0
	attack_button.pressed.connect(func(): attack_pressed.emit())
	add_child(attack_button)

	fire_button = ActionButton.new()
	fire_button.label = "FIRE"
	fire_button.icon = "DART"
	fire_button.accent = Color("ff7a1a")
	fire_button.radius = 48.0
	fire_button.pressed.connect(func(): fire_pressed.emit())
	add_child(fire_button)

	_status = Control.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.draw.connect(_draw_status)
	add_child(_status)

	trap_button = ActionButton.new()
	trap_button.label = "TRAP"
	trap_button.icon = "BOMB"
	trap_button.accent = accent
	trap_button.radius = 50.0
	trap_button.pressed.connect(_toggle_trap_menu)
	add_child(trap_button)
	for kind in ["BOMB", "SPRING", "WIRE"]:
		var b := ActionButton.new()
		b.label = kind
		b.icon = kind
		b.accent = Color("ffd23f")
		b.radius = 44.0
		b.visible = false
		b.pressed.connect(func():
			_close_trap_menu()
			trap_chosen.emit(kind))
		add_child(b)
		_trap_options[kind] = b

	_bar = ColorRect.new()
	_bar.color = Color(0, 0, 0, 0.55)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	var who_label := _label(who, 20, accent)
	who_label.position = Vector2(16, 16)
	add_child(who_label)

	_inventory = Control.new()
	_inventory.position = Vector2(196, 6)
	_inventory.size = Vector2(420, 48)
	_inventory.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory.draw.connect(_draw_inventory)
	add_child(_inventory)

	_room_label = _label("", 28, Color.WHITE)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_room_label)

	_leave = Button.new()
	_leave.text = "LEAVE"
	_leave.size = Vector2(96, 40)
	_leave.add_theme_font_size_override("font_size", 18)
	_leave.pressed.connect(func(): leave_requested.emit())
	add_child(_leave)

	_minimap = Control.new()
	_minimap.size = Vector2(56, 56)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap)
	add_child(_minimap)

	_toast = _label("", 26, Color.WHITE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	add_child(_toast)

	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	get_viewport().size_changed.connect(_layout)
	_layout()


func _place(b: Control, centre: Vector2) -> void:
	b.position = centre - b.size / 2.0


## Clock, health and darts (top-left) and the rival's clock (top-right).
func set_status(mine: float, rival: float, hp: int, max_hp: int, darts: int) -> void:
	if absf(mine - _clock_mine) < 0.05 and absf(rival - _clock_rival) < 0.05 and hp == _hp and darts == _darts:
		return
	_clock_mine = mine
	_clock_rival = rival
	_hp = hp
	_max_hp = max_hp
	_darts = darts
	fire_button.label = "FIRE ×%d" % darts
	fire_button.queue_redraw()
	_status.queue_redraw()


static func _fmt(t: float) -> String:
	var s := int(ceil(maxf(t, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


func _draw_status() -> void:
	var font := ThemeDB.fallback_font
	var low := _clock_mine < 30.0
	var blink := low and int(Time.get_ticks_msec() / 300) % 2 == 0
	var col := Color("ff5a5f") if low else Color.WHITE
	var bg := Rect2(8, 4, 250, 38)
	_status.draw_rect(bg, Color(0, 0, 0, 0.45))
	# Stopwatch icon
	var c := Vector2(28, 23)
	_status.draw_arc(c, 11, 0, TAU, 24, col, 2.5, true)
	_status.draw_line(c, c + Vector2(0, -7), col, 2.0)
	_status.draw_line(c, c + Vector2(5, 2), col, 2.0)
	_status.draw_rect(Rect2(c.x - 3, c.y - 16, 6, 3), col)
	_status.draw_string(font, Vector2(46, 32), _fmt(_clock_mine), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(col, 0.35) if blink else col)
	# Health pips
	for i in _max_hp:
		var p := Vector2(132 + i * 22, 23)
		_status.draw_circle(p, 8, Color(0, 0, 0, 0.5))
		_status.draw_circle(p, 6.5, _accent if i < _hp else Color(1, 1, 1, 0.15))
	# Darts left
	Icons.draw(_status, "DART", Vector2(210, 23), 22.0, _darts > 0)
	_status.draw_string(font, Vector2(224, 31), "%d" % _darts, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	if _clock_rival >= 0.0:
		var txt := "RIVAL  %s" % _fmt(_clock_rival)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_status.draw_rect(Rect2(_status.size.x - w - 28, 4, w + 20, 38), Color(0, 0, 0, 0.45))
		_status.draw_string(font, Vector2(_status.size.x - w - 18, 31), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.75))


## Size of this layer in its own (scaled) units.
func _area() -> Vector2:
	return Ui.view_size(self) / scale.x


## Positions everything relative to the screen edges, so it fits any shape.
func _layout() -> void:
	var L := _area()
	_bar.size = Vector2(L.x, 60)
	joystick.position = Vector2(0, 60)
	joystick.size = Vector2(L.x * 0.5, L.y - 60)
	joystick.queue_redraw()
	# Right-hand action cluster (positions are button centres).
	_place(search_button, Vector2(L.x - 105, L.y - 105))
	_place(attack_button, Vector2(L.x - 95, L.y - 268))
	_place(fire_button, Vector2(L.x - 228, L.y - 222))
	_place(trap_button, Vector2(L.x - 250, L.y - 78))
	# Trap options fan out to the left of the TRAP button.
	var spots := [Vector2(L.x - 380, L.y - 72), Vector2(L.x - 392, L.y - 178), Vector2(L.x - 345, L.y - 280)]
	var kinds := ["BOMB", "SPRING", "WIRE"]
	for i in kinds.size():
		_place(_trap_options[kinds[i]], spots[i])
	_status.position = Vector2(0, 60)
	_status.size = Vector2(L.x, 44)
	_flash.size = L
	_leave.position = Vector2(L.x - 110, 10)
	_minimap.position = Vector2(L.x - 190, 12)
	_room_label.position = Vector2(620, 10)
	_room_label.size = Vector2(maxf(0.0, L.x - 620 - 200), 40)
	_room_label.visible = _room_label.size.x > 160
	_toast.size = Vector2(minf(800.0, L.x - 40), 70)
	_toast.position = Vector2((L.x - _toast.size.x) / 2, L.y - 160)
	_fade.size = L
	if _end:
		_end.size = L


func show_room(room: Vector2i, animate: bool) -> void:
	_room = room
	_room_label.text = world.rooms[room]["name"].to_upper()
	_room_label.add_theme_color_override("font_color", (world.rooms[room]["tint"] as Color).lightened(0.4))
	_minimap.queue_redraw()
	if animate:
		_fade.color.a = 0.7
		create_tween().tween_property(_fade, "color:a", 0.0, 0.25)


func set_inventory(items: Array, has_case: bool, gadgets: Array = []) -> void:
	_held = items.duplicate()
	_has_case = has_case
	_gadgets = gadgets.duplicate()
	_inventory.queue_redraw()


## Which traps can be set right here (furniture traps / a doorway tripwire).
func set_trap_options(furniture: bool, door: bool) -> void:
	trap_button.enabled = furniture or door
	_trap_options["BOMB"].enabled = furniture
	_trap_options["SPRING"].enabled = furniture
	_trap_options["WIRE"].enabled = door
	if _trap_menu_open:
		_trap_menu_timer -= get_process_delta_time()
		if _trap_menu_timer <= 0.0 or not trap_button.enabled:
			_close_trap_menu()


func _toggle_trap_menu() -> void:
	if _trap_menu_open:
		_close_trap_menu()
		return
	_trap_menu_open = true
	_trap_menu_timer = 4.0
	for k in _trap_options:
		_trap_options[k].visible = true


func _close_trap_menu() -> void:
	_trap_menu_open = false
	for k in _trap_options:
		_trap_options[k].visible = false


## A quick coloured flash over the whole screen (when you get caught).
func flash(col: Color) -> void:
	_flash.color = Color(col, 0.45)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.5)


func toast(msg: String, col := Color.WHITE, seconds := 2.5) -> void:
	_toast.text = msg
	_toast.add_theme_color_override("font_color", col)
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func show_end(winner: int, my_id: int, winner_name: String, reason: String, can_rematch: bool) -> void:
	var won := winner == my_id
	search_button.visible = false
	trap_button.visible = false
	attack_button.visible = false
	fire_button.visible = false
	_close_trap_menu()
	joystick.visible = false
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	var L := _area()
	_end = Control.new()
	_end.size = L
	add_child(_end)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.7, 0.4)

	var title_text := "MISSION ACCOMPLISHED" if won else "DOUBLE-CROSSED!"
	var sub_text := "You escaped with the intel. Drinks are on you." if won else "%s got out with the intel. Awkward." % winner_name
	if reason == "time":
		if winner == 0:
			title_text = "TIME'S UP"
			sub_text = "Nobody got out. The base goes into lockdown."
		elif won:
			title_text = "LAST AGENT STANDING"
			sub_text = "Your rival's clock ran out. A win's a win."
		else:
			title_text = "OUT OF TIME"
			sub_text = "Your clock ran out. %s wins by default." % winner_name
	var title := _label(title_text, 72, Color("5dff8a") if won else Color("ff5a5f"))
	title.position = Vector2(0, L.y / 2 - 150)
	title.size = Vector2(L.x, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end.add_child(title)
	var sub := _label(sub_text, 28, Color(1, 1, 1, 0.85))
	sub.position = Vector2(0, L.y / 2 - 50)
	sub.size = Vector2(L.x, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.position = Vector2(L.x / 2 - 300, L.y / 2 + 50)
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
	# Tool belt: smaller gadget icons.
	var x0 := 24 + slots.size() * 50 + 4
	_inventory.draw_line(Vector2(x0 - 25, 6), Vector2(x0 - 25, 42), Color(1, 1, 1, 0.2), 1.0)
	for i in World.GADGETS.size():
		var g: String = World.GADGETS[i]
		var c := Vector2(x0 + i * 38, 24)
		var have := _gadgets.has(g)
		_inventory.draw_circle(c, 16, Color(1, 1, 1, 0.12 if have else 0.04))
		if have:
			_inventory.draw_arc(c, 16, 0, TAU, 28, Color("ffd23f", 0.9), 2.0, true)
		Icons.draw(_inventory, g, c, 24.0, have)


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
