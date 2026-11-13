extends Control
## Title screen: host a game, join one found on the network (or by IP), or practise solo.

signal practice_requested
signal bot_requested(level: String)

var _status: Label
var _hosts_box: VBoxContainer
var _searching: Label
var _ip_edit: LineEdit
var _main_buttons: Control
var _cancel: Button
var _t := 0.0
var _content: Control
var _bot_level := "medium"
var _lift := 0.0

const Ui = preload("res://scripts/ui.gd")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	# All menu widgets live in a 1280x800 panel that is centred (and lifted
	# above the on-screen keyboard) in _process.
	_content = Control.new()
	_content.size = Ui.BASE
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	var title := Label.new()
	title.text = "DOUBLE CROSS"
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", Color("ff5a5f"))
	title.add_theme_color_override("font_shadow_color", Color("5ab0ff"))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 60)
	title.size = Vector2(1280, 110)
	_content.add_child(title)

	var sub := Label.new()
	sub.text = "Two agents. One secret base. Only one gets out."
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 175)
	sub.size = Vector2(1280, 40)
	_content.add_child(sub)

	# Left column: host / practice
	var left := VBoxContainer.new()
	left.position = Vector2(140, 250)
	left.size = Vector2(440, 300)
	left.add_theme_constant_override("separation", 18)
	_content.add_child(left)
	_main_buttons = left
	left.add_child(_big_button("HOST GAME", _on_host))
	left.add_child(_big_button("PLAY VS BOT", func(): bot_requested.emit(_bot_level)))
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for lv in ["easy", "medium", "hard"]:
		var b := Button.new()
		b.text = lv.to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = lv == _bot_level
		b.custom_minimum_size = Vector2(141, 50)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func(): _bot_level = lv)
		levels.add_child(b)
	left.add_child(levels)
	left.add_child(_big_button("PRACTICE SOLO", func(): practice_requested.emit()))

	# Right column: join
	var right := VBoxContainer.new()
	right.position = Vector2(700, 280)
	right.size = Vector2(440, 400)
	right.add_theme_constant_override("separation", 14)
	_content.add_child(right)
	var jl := Label.new()
	jl.text = "GAMES ON YOUR NETWORK"
	jl.add_theme_color_override("font_color", Color("5ab0ff"))
	right.add_child(jl)
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 10)
	right.add_child(_hosts_box)
	_searching = Label.new()
	_searching.text = "Searching…"
	_searching.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	right.add_child(_searching)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	right.add_child(spacer)
	var ml := Label.new()
	ml.text = "OR JOIN BY IP ADDRESS"
	ml.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	ml.add_theme_font_size_override("font_size", 20)
	right.add_child(ml)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	right.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.20"
	_ip_edit.custom_minimum_size = Vector2(300, 60)
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip_edit.text_submitted.connect(func(_t): _join(_ip_edit.text.strip_edges()))
	row.add_child(_ip_edit)
	var jb := Button.new()
	jb.text = "JOIN"
	jb.custom_minimum_size = Vector2(130, 60)
	jb.pressed.connect(func(): _join(_ip_edit.text.strip_edges()))
	row.add_child(jb)

	_status = Label.new()
	_status.position = Vector2(0, 645)
	_status.size = Vector2(1280, 80)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", Color("ffd23f"))
	_content.add_child(_status)

	_cancel = Button.new()
	_cancel.text = "CANCEL"
	_cancel.position = Vector2(560, 720)
	_cancel.size = Vector2(160, 56)
	_cancel.visible = false
	_cancel.pressed.connect(func():
		Net.end_session("")
		_set_waiting(false)
		set_status(""))
	_content.add_child(_cancel)

	Net.hosts_changed.connect(_refresh_hosts)
	Net.joined_host.connect(func(): set_status("Connected! Briefing incoming…"))
	Net.join_failed.connect(func():
		_set_waiting(false)
		set_status("Couldn't reach that game. Check you're on the same Wi-Fi."))
	Net.start_listening()
	_refresh_hosts()


func set_status(msg: String) -> void:
	_status.text = msg


func _process(delta: float) -> void:
	_t += delta
	var vp := Ui.view_size(self)
	var k := minf(vp.x / Ui.BASE.x, vp.y / Ui.BASE.y)
	_content.scale = Vector2(k, k)
	# Lift the menu so the IP box stays visible above the on-screen keyboard.
	var target := 0.0
	var kb := 0.0
	if _ip_edit.has_focus() and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		kb = float(DisplayServer.virtual_keyboard_get_height())
	if kb > 0.0:
		var screen_to_view := vp.y / float(DisplayServer.window_get_size().y)
		var kb_top := vp.y - kb * screen_to_view
		var field_bottom := (_ip_edit.get_global_rect().end.y + _lift) + 20.0
		target = maxf(0.0, field_bottom - kb_top)
	_lift = lerpf(_lift, target, minf(1.0, delta * 12.0))
	_content.position = ((vp - Ui.BASE * k) / 2.0).floor() - Vector2(0, _lift)
	queue_redraw()


func _draw() -> void:
	# Animated radar-grid backdrop
	draw_rect(Rect2(Vector2.ZERO, size), Color("070a0f"))
	var off := fmod(_t * 20.0, 64.0)
	for x in range(-64, int(size.x) + 64, 64):
		draw_line(Vector2(x + off, 0), Vector2(x + off, size.y), Color(0.35, 0.69, 1.0, 0.06), 1.0)
	for y in range(-64, int(size.y) + 64, 64):
		draw_line(Vector2(0, y + off), Vector2(size.x, y + off), Color(0.35, 0.69, 1.0, 0.06), 1.0)
	var sweep := fmod(_t * 0.6, 1.0) * (size.x + 120.0) - 60.0
	draw_rect(Rect2(sweep, 0, 60, size.y), Color(1.0, 0.35, 0.37, 0.05))


func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		set_status("Couldn't start hosting (error %d)." % err)
		return
	_set_waiting(true)
	set_status("Waiting for a rival agent…\nThey can join from their tablet, or type your address: %s" % Net.local_ip())


func _join(ip: String) -> void:
	if ip == "":
		set_status("Type the host's IP address first.")
		return
	if Net.join(ip) != OK:
		set_status("That doesn't look like a valid address.")
		return
	_set_waiting(true)
	set_status("Connecting to %s…" % ip)


func _set_waiting(on: bool) -> void:
	_main_buttons.modulate.a = 0.35 if on else 1.0
	for b in _main_buttons.get_children():
		if b is Button:
			(b as Button).disabled = on
	_cancel.visible = on


func _refresh_hosts() -> void:
	for c in _hosts_box.get_children():
		c.queue_free()
	for ip in Net.discovered.keys():
		var b := Button.new()
		b.text = "%s  (%s)" % [Net.discovered[ip]["name"], ip]
		b.custom_minimum_size = Vector2(440, 60)
		b.pressed.connect(_join.bind(ip))
		_hosts_box.add_child(b)
	_searching.visible = Net.discovered.is_empty()


func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(440, 88)
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(cb)
	return b


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("141b26")
	normal.border_color = Color("5ab0ff")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate()
	hover.bg_color = Color("1d2838")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("ff5a5f")
	pressed.border_color = Color("ff5a5f")
	var disabled := normal.duplicate()
	disabled.border_color = Color("333")
	for kind in ["Button"]:
		t.set_stylebox("normal", kind, normal)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("pressed", kind, pressed)
		t.set_stylebox("disabled", kind, disabled)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
	var edit := normal.duplicate()
	edit.bg_color = Color("0c1118")
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit)
	return t
