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
var _overlay: Control
var _lift := 0.0

const Ui = preload("res://scripts/ui.gd")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_bot_level = Settings.bot_level
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
		b.pressed.connect(func():
			_bot_level = lv
			Settings.bot_level = lv
			Settings.save())
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
	_ip_edit.text = Settings.last_ip
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

	# Small buttons along the bottom.
	var help := Button.new()
	help.text = "HOW TO PLAY"
	help.position = Vector2(140, 730)
	help.size = Vector2(210, 50)
	help.add_theme_font_size_override("font_size", 20)
	help.pressed.connect(_show_help)
	_content.add_child(help)
	var settings := Button.new()
	settings.text = "SETTINGS"
	settings.position = Vector2(370, 730)
	settings.size = Vector2(170, 50)
	settings.add_theme_font_size_override("font_size", 20)
	settings.pressed.connect(_show_settings)
	_content.add_child(settings)

	# Every button in the menu clicks.
	_hook_clicks(self)

	Net.hosts_changed.connect(_refresh_hosts)
	Net.joined_host.connect(func(): set_status("Connected! Briefing incoming…"))
	Net.join_failed.connect(func():
		_set_waiting(false)
		set_status("Couldn't reach that game. Check you're on the same Wi-Fi."))
	Net.start_listening()
	_refresh_hosts()


func _hook_clicks(n: Node) -> void:
	for c in n.get_children():
		if c is BaseButton and not c.has_meta("click"):
			c.set_meta("click", true)
			(c as BaseButton).pressed.connect(func(): Sound.play("click", -4.0, false, 0.0))
		_hook_clicks(c)


## A dimmed full-screen panel with a centred card; returns the card's VBox.
func _open_overlay(title_text: String, width := 760.0) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	add_child(_overlay)
	_overlay.position = Vector2.ZERO
	_overlay.size = Ui.view_size(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0f1621")
	sb.border_color = Color("5ab0ff")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Color("ff5a5f"))
	box.add_child(t)
	return box


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _done_button(box: VBoxContainer) -> void:
	var done := Button.new()
	done.text = "DONE"
	done.custom_minimum_size = Vector2(0, 64)
	done.pressed.connect(func():
		Settings.save()
		_close_overlay())
	box.add_child(done)
	_hook_clicks(box)


func _show_settings() -> void:
	var box := _open_overlay("SETTINGS", 640.0)
	box.add_child(_slider_row("Music", Settings.music_volume, func(v):
		Settings.music_volume = v
		Settings.changed.emit()))
	box.add_child(_slider_row("Sound effects", Settings.sfx_volume, func(v):
		Settings.sfx_volume = v
		Settings.changed.emit()
		Sound.play("click", -4.0, false, 0.0)))
	var vib := CheckButton.new()
	vib.text = "Vibrate when hit"
	vib.button_pressed = Settings.vibration
	vib.toggled.connect(func(on): Settings.vibration = on)
	box.add_child(vib)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = "Clock per agent"
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var group := ButtonGroup.new()
	for m in [4, 6, 8, 10]:
		var b := Button.new()
		b.text = "%d min" % m
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m == Settings.clock_minutes
		b.custom_minimum_size = Vector2(90, 50)
		b.pressed.connect(func(): Settings.clock_minutes = m)
		row.add_child(b)
	box.add_child(row)
	var note := Label.new()
	note.text = "In a two-player game the host's clock setting is used."
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	box.add_child(note)
	_done_button(box)


func _slider_row(label_text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(320, 40)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.drag_ended.connect(func(_c): on_change.call(sl.value))
	sl.value_changed.connect(func(v): if not sl.has_focus(): on_change.call(v))
	row.add_child(sl)
	return row


func _show_help() -> void:
	var box := _open_overlay("HOW TO PLAY", 900.0)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(840, 0)
	text.add_theme_font_size_override("normal_font_size", 21)
	text.add_theme_font_size_override("bold_font_size", 21)
	text.text = """[b][color=#5ab0ff]The mission[/color][/b]  Find the [b]PASSPORT, CASH, MICROFILM[/b] and [b]KEYCARD[/b] hidden in the furniture, then walk out of the glowing [color=#5dff8a][b]EXIT[/b][/color] before your clock runs out. First one out wins.

[b][color=#5ab0ff]Searching[/color][/b]  Stand next to furniture and tap [b]SEARCH[/b]. Without the [b]BRIEFCASE[/b] you can only carry one item, so you'll swap and leave the other behind.

[b][color=#5ab0ff]Traps[/color][/b]  Tap [b]TRAP[/b] to hide a [b]BOMB[/b] or [b]SPRING[/b] in furniture, or string a [b]TRIPWIRE[/b] across a doorway. Getting caught knocks you out, scatters your intel and costs 20 seconds. Only you can see your own traps, but they still work on you!

[b][color=#5ab0ff]Gadgets[/color][/b]  The [b]EXTINGUISHER[/b] beats bombs, the [b]TOOLKIT[/b] beats springs and the [b]WIRE CUTTERS[/b] beat tripwires. Each one is used up when it saves you.

[b][color=#5ab0ff]Fighting[/color][/b]  [b]ATTACK[/b] swings your cosh, [b]FIRE[/b] shoots a dart. Three hits take an agent out: they drop their intel, lose 30 seconds and wake up back at the start.

[b][color=#5ab0ff]Keyboard[/color][/b]  WASD/arrows move · E search · 1/2/3 traps · F cosh · G dart"""
	box.add_child(text)
	_done_button(box)


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
	if _overlay:
		_overlay.size = vp
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
	Settings.last_ip = ip
	Settings.save()
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
