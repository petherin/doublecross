extends CanvasLayer
## On-screen HUD: inventory, room name, minimap, leave button, joystick,
## search button, pop-up messages, room-change fade and the end screen.

signal leave_requested
signal search_pressed
signal rematch_requested
signal briefing_done
signal crawl_pressed
signal trap_chosen(kind: String)
signal attack_pressed
signal fire_pressed

const World = preload("res://scripts/core/world.gd")
const Joystick = preload("res://scripts/ui/joystick.gd")
const ActionButton = preload("res://scripts/ui/action_button.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Style = preload("res://scripts/ui/style.gd")
const Ui = preload("res://scripts/ui/ui.gd")
const DuctView = preload("res://scripts/ui/hud/duct_view.gd")
const Briefing = preload("res://scripts/ui/hud/briefing.gd")
const Debrief = preload("res://scripts/ui/hud/debrief.gd")

var world: World
var joystick: Joystick
var search_button: ActionButton
var trap_button: ActionButton
var attack_button: ActionButton
var crawl_button: ActionButton
var fire_button: ActionButton
var _known_vents: Array = []
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
var _tape: PanelContainer
var _toast_full := ""
var _toast_chars := 0.0
var _toast_tween: Tween
var _end: Debrief
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

	crawl_button = ActionButton.new()
	crawl_button.label = "CRAWL"
	crawl_button.icon = "VENT"
	crawl_button.accent = Color("ffd23f")
	crawl_button.radius = 52.0
	crawl_button.visible = false
	crawl_button.pressed.connect(func(): crawl_pressed.emit())
	add_child(crawl_button)

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

	_room_label = _label("", 26, Color.WHITE)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_label.add_theme_font_override("font", Style.stencil())
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.05, 0.05, 0.06, 0.9)
	plate.border_color = Color(1, 1, 1, 0.3)
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(4)
	plate.content_margin_left = 16
	plate.content_margin_right = 16
	_room_label.add_theme_stylebox_override("normal", plate)
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

	# Messages are typed out onto a strip of ticker tape.
	_tape = PanelContainer.new()
	var tape_style := StyleBoxFlat.new()
	tape_style.bg_color = Style.PAPER
	tape_style.border_color = Style.PAPER_DARK
	tape_style.border_width_top = 2
	tape_style.border_width_bottom = 2
	tape_style.shadow_color = Color(0, 0, 0, 0.5)
	tape_style.shadow_size = 6
	tape_style.shadow_offset = Vector2(3, 4)
	tape_style.content_margin_left = 22
	tape_style.content_margin_right = 22
	tape_style.content_margin_top = 8
	tape_style.content_margin_bottom = 8
	_tape.add_theme_stylebox_override("panel", tape_style)
	_tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tape.rotation = -0.012
	_tape.modulate.a = 0.0
	add_child(_tape)
	_toast = _label("", 22, Style.INK)
	_toast.add_theme_font_override("font", Style.mono_bold())
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tape.add_child(_toast)

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
	var clock_col := Color(col, 0.35) if blink else col
	_status.draw_string(font, Vector2(46, 32), _fmt(_clock_mine), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, clock_col)
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
		_status.draw_string(
				font, Vector2(_status.size.x - w - 18, 31), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.75))


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
	_place(crawl_button, Vector2(L.x - 238, L.y - 352))
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
	_fit_room_label()
	_fade.size = L
	if _end:
		_end.size = L


func show_room(room: Vector2i, animate: bool) -> void:
	_room = room
	_room_label.text = world.rooms[room]["name"].to_upper()
	_fit_room_label()
	_room_label.add_theme_color_override("font_color", (world.rooms[room]["tint"] as Color).lightened(0.45))
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


## Shows the CRAWL button while standing at a vent.
func set_crawl(on: bool) -> void:
	if crawl_button.visible != on:
		crawl_button.visible = on
		if on:
			crawl_button.scale = Vector2(0.6, 0.6)
			create_tween().tween_property(crawl_button, "scale", Vector2.ONE, 0.15)


func set_known_vents(pairs: Array) -> void:
	_known_vents = pairs.duplicate()
	_minimap.queue_redraw()


## The cut-away of the agent crawling through a duct, shown for `seconds`.
func show_duct(crawl_sheet: Texture2D, seconds: float) -> void:
	add_child(DuctView.new(_area(), crawl_sheet, seconds))


## Sizes the room-name plate to the name, centred in the space in the top bar.
func _fit_room_label() -> void:
	var L := _area()
	var space := maxf(0.0, L.x - 620 - 200)
	var w := Style.stencil().get_string_size(_room_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 40
	_room_label.size = Vector2(minf(space, w), 42)
	_room_label.position = Vector2(620 + (space - _room_label.size.x) / 2.0, 9)
	_room_label.visible = space > 160


## A quick coloured flash over the whole screen (when you get caught).
func flash(col: Color) -> void:
	_flash.color = Color(col, 0.45)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.5)


func toast(msg: String, col := Color.WHITE, seconds := 2.5) -> void:
	# Warnings (yellow) are typed in red ink, everything else in black.
	var warn := col.r > 0.9 and col.g > 0.7 and col.b < 0.5
	_toast.add_theme_color_override("font_color", Style.RED_INK if warn else Style.INK)
	_toast_full = msg
	_toast_chars = 0.0
	_toast.text = ""
	if _toast_tween:
		_toast_tween.kill()
	_tape.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds + msg.length() / 70.0)
	_toast_tween.tween_property(_tape, "modulate:a", 0.0, 0.4)


func _process(delta: float) -> void:
	var L := _area()
	# Type the ticker tape out, and keep it centred above the controls.
	if _toast_chars < _toast_full.length():
		var before := int(_toast_chars)
		_toast_chars = minf(_toast_full.length(), _toast_chars + delta * 70.0)
		_toast.text = _toast_full.left(int(_toast_chars))
		if int(_toast_chars) / 4 != before / 4:
			Sound.play("type%d" % randi_range(1, 3), -16.0, false, 0.1)
	# Size the tape to the full text so it doesn't grow while typing.
	var f := Style.mono_bold()
	var widest := 0.0
	for line in _toast_full.split("\n"):
		widest = maxf(widest, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x)
	_toast.custom_minimum_size = Vector2(minf(widest + 4.0, L.x - 90.0), 0)
	_tape.size = Vector2.ZERO
	_tape.position = Vector2((L.x - _tape.size.x) / 2.0, L.y - 150.0 - _tape.size.y / 2.0)


## The case-file debrief at the end of the match.
func show_end(winner: int, my_id: int, winner_name: String, reason: String, can_rematch: bool) -> void:
	for b in [search_button, trap_button, attack_button, fire_button, crawl_button, joystick]:
		b.visible = false
	_close_trap_menu()
	if _toast_tween:
		_toast_tween.kill()
	_tape.modulate.a = 0.0
	_end = Debrief.new(_area(), winner == my_id, winner, winner_name, reason, can_rematch)
	_end.rematch_requested.connect(rematch_requested.emit)
	_end.leave_requested.connect(leave_requested.emit)
	add_child(_end)


## The mission briefing typed out at the start of a match, then it
## self-destructs. Any tap or key skips it.
func show_briefing(agent_name: String, rival_name: String, minutes: int) -> void:
	var b := Briefing.new(_area(), agent_name, rival_name, minutes)
	b.finished.connect(briefing_done.emit)
	add_child(b)


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
	# Vent shortcuts you've found: dashed yellow links.
	for pair in _known_vents:
		var ra: Vector2i = world.vents[pair[0]]["room"]
		var rb: Vector2i = world.vents[pair[1]]["room"]
		var ca := origin + Vector2((ra.x - ra.y) * a, (ra.x + ra.y) * a * 0.5 + a * 0.5)
		var cb := origin + Vector2((rb.x - rb.y) * a, (rb.x + rb.y) * a * 0.5 + a * 0.5)
		_minimap.draw_dashed_line(ca, cb, Color(1.0, 0.86, 0.15, 0.9), 1.5, 3.0)
		_minimap.draw_circle(ca, 2.0, Color(1.0, 0.86, 0.15))
		_minimap.draw_circle(cb, 2.0, Color(1.0, 0.86, 0.15))


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
