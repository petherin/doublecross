extends Control
## Title screen, styled as a classified case file open on a desk: host a game,
## join one found on the network (or by IP), play the bot or practise solo.

signal practice_requested
signal bot_requested(level: String)

const Ui = preload("res://scripts/ui/ui.gd")
const Style = preload("res://scripts/ui/style.gd")
const Art = preload("res://scripts/render/art.gd")

const TAGLINE := "Two agents. One secret base. Only one gets out."
var _status: Label
var _hosts_box: VBoxContainer
var _searching: Label
var _ip_edit: LineEdit
var _find_row: HBoxContainer
var _ip_row: HBoxContainer
var _name_edit: LineEdit
var _main_buttons: Control
var _cancel: Button
var _content: Control
var _art: Control
var _overlay: Control
var _bot_level := "medium"
var _t := 0.0
var _lift := 0.0
# Typewriter effect for the status line and the tagline.
var _status_full := ""
var _status_chars := 0.0
var _tag_chars := 0.0
# Polaroid photos of the agents, cut from the Blender sprite sheets.
var _photos := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Style.paper_theme()
	_bot_level = Settings.bot_level
	# Everything lives in a 1280x800 panel, centred (and lifted above the
	# on-screen keyboard) in _process.
	_content = Control.new()
	_content.size = Ui.BASE
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_art = Control.new()
	_art.size = Ui.BASE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_dossier)
	_content.add_child(_art)
	_load_photos()

	# ---- Right page: mission orders.
	var name_row := HBoxContainer.new()
	name_row.position = Vector2(700, 168)
	name_row.add_theme_constant_override("separation", 10)
	_content.add_child(name_row)
	name_row.add_child(_label("AGENT CODENAME:", Style.mono_bold(), 20))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "NIGHTJAR"
	_name_edit.text = Settings.player_name
	_name_edit.max_length = 14
	_name_edit.custom_minimum_size = Vector2(230, 42)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.text_changed.connect(func(t):
		Settings.player_name = t.strip_edges()
		Settings.save())
	name_row.add_child(_name_edit)

	var orders := VBoxContainer.new()
	orders.position = Vector2(690, 222)
	orders.add_theme_constant_override("separation", 2)
	_content.add_child(orders)
	_main_buttons = orders
	orders.add_child(_order_button("HOST A MISSION", _on_host))
	orders.add_child(_order_button("TAKE ON THE BOT", func(): bot_requested.emit(_bot_level)))
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 6)
	var lpad := Control.new()
	lpad.custom_minimum_size = Vector2(36, 0)
	levels.add_child(lpad)
	var group := ButtonGroup.new()
	for lv in ["easy", "medium", "hard"]:
		var b := Button.new()
		b.text = lv.to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = lv == _bot_level
		b.custom_minimum_size = Vector2(118, 40)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func():
			_bot_level = lv
			Settings.bot_level = lv
			Settings.save())
		levels.add_child(b)
	orders.add_child(levels)
	orders.add_child(_order_button("SOLO TRAINING", func(): practice_requested.emit()))

	var signals := VBoxContainer.new()
	signals.position = Vector2(700, 470)
	signals.size = Vector2(450, 0)
	signals.add_theme_constant_override("separation", 6)
	_content.add_child(signals)
	var sl := _label("INTERCEPTED TRANSMISSIONS", Style.mono_bold(), 18)
	sl.add_theme_color_override("font_color", Style.RED_INK)
	signals.add_child(sl)
	_hosts_box = VBoxContainer.new()
	signals.add_child(_hosts_box)
	_searching = _label("Looking for hosts", Style.typewriter(), 19)
	_searching.add_theme_color_override("font_color", Color(Style.INK, 0.6))
	signals.add_child(_searching)

	# Finding a host: hosts on the same Wi-Fi turn up in the list above by
	# themselves; FIND HOST rescans at once. Typing an IP is the last resort.
	_find_row = HBoxContainer.new()
	_find_row.add_theme_constant_override("separation", 18)
	signals.add_child(_find_row)
	_find_row.add_child(_small_button("FIND HOST", func():
		Net.scan()
		set_status("Scanning the Wi-Fi for hosts…")))
	_find_row.add_child(_small_button("TYPE IP", func(): _show_ip_row(true)))

	_ip_row = HBoxContainer.new()
	_ip_row.add_theme_constant_override("separation", 8)
	_ip_row.visible = false
	signals.add_child(_ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.20"
	_ip_edit.text = Settings.last_ip
	_ip_edit.custom_minimum_size = Vector2(220, 40)
	_ip_edit.add_theme_font_size_override("font_size", 20)
	# The URL keyboard always has a dot key (the number pad often doesn't).
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_ip_edit.text_submitted.connect(func(_t): _join(_ip_edit.text.strip_edges()))
	_ip_row.add_child(_ip_edit)
	_ip_row.add_child(_small_button("JOIN ▸", func(): _join(_ip_edit.text.strip_edges())))
	_ip_row.add_child(_small_button("✕", func(): _show_ip_row(false)))

	_status = Label.new()
	_status.custom_minimum_size = Vector2(450, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_font_override("font", Style.typewriter())
	_status.add_theme_font_size_override("font_size", 19)
	_status.add_theme_color_override("font_color", Style.RED_INK)
	signals.add_child(_status)

	_cancel = Button.new()
	_cancel.text = "✕ ABORT"
	_cancel.position = Vector2(1040, 700)
	_cancel.add_theme_font_size_override("font_size", 22)
	_cancel.visible = false
	_cancel.pressed.connect(func():
		Net.end_session("")
		_set_waiting(false)
		set_status(""))
	_content.add_child(_cancel)

	# ---- Index tabs poking out of the bottom of the folder.
	_content.add_child(_tab_button("HOW TO PLAY", Vector2(120, 744), _show_help))
	_content.add_child(_tab_button("SETTINGS", Vector2(330, 744), _show_settings))

	# Every button types a key when pressed.
	_hook_clicks(self)

	Net.hosts_changed.connect(_refresh_hosts)
	Net.joined_host.connect(func(): set_status("Contact established. Briefing incoming…"))
	Net.join_failed.connect(func():
		_set_waiting(false)
		set_status("No answer. Check both devices are on the same Wi-Fi."))
	Net.start_listening()
	_refresh_hosts()


# ------------------------------------------------------------------ widgets

func _small_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_size_override("font_size", 21)
	b.pressed.connect(on_press)
	return b


func _show_ip_row(on: bool) -> void:
	_ip_row.visible = on
	_find_row.visible = not on
	if on:
		_ip_edit.grab_focus()
	else:
		_ip_edit.release_focus()


func _label(text: String, font: Font, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 40)
	return l


## A typed order with a tick-box: highlighted when hovered.
func _order_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "☐  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 56)
	b.add_theme_font_size_override("font_size", 31)
	b.pressed.connect(cb)
	return b


func _tab_button(text: String, at: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = at
	b.size = Vector2(190, 44)
	b.add_theme_font_size_override("font_size", 19)
	var tab := StyleBoxFlat.new()
	tab.bg_color = Style.MANILA_DARK
	tab.corner_radius_bottom_left = 8
	tab.corner_radius_bottom_right = 8
	tab.shadow_color = Color(0, 0, 0, 0.4)
	tab.shadow_size = 4
	tab.set_content_margin_all(6)
	var tab_hover := tab.duplicate()
	tab_hover.bg_color = Style.MANILA
	for s in ["normal", "focus"]:
		b.add_theme_stylebox_override(s, tab)
	for s in ["hover", "pressed"]:
		b.add_theme_stylebox_override(s, tab_hover)
	b.pressed.connect(cb)
	return b


func _hook_clicks(n: Node) -> void:
	for c in n.get_children():
		if c is BaseButton and not c.has_meta("click"):
			c.set_meta("click", true)
			(c as BaseButton).pressed.connect(func(): Sound.play("type%d" % randi_range(1, 3), -2.0, false, 0.05))
		_hook_clicks(c)


# ------------------------------------------------------------------ the case file art

func _load_photos() -> void:
	var path := "res://assets/sprites/agents.json"
	if not FileAccess.file_exists(path):
		return
	var m = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not m is Dictionary or not m.has("frames_per_direction"):
		return
	var fsize: float = m["frame"]
	# Facing the camera: direction 1, first idle frame.
	var fid: int = 1 * int(m["frames_per_direction"]) + int(m["anims"]["idle"]["start"])
	for sheet in m["sheets"]:
		if not ResourceLoader.exists(m["sheets"][sheet]):
			continue
		# Packed frames are trimmed: rebuild the full frame box around the trim.
		var r: Array = m["rects"][sheet][fid]
		var box := Rect2(r[0] - r[4], r[1] - r[5], fsize, fsize)
		_photos[sheet] = [load(m["sheets"][sheet]), box, Rect2(r[0], r[1], r[2], r[3])]


func _photo(ci: CanvasItem, r: Rect2, who: String) -> void:
	# Interrogation-room backdrop, then a head-and-shoulders crop of the agent.
	ci.draw_rect(r, Color("2b3442"))
	for i in 5:
		var y := r.position.y + r.size.y * (0.2 + i * 0.15)
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.08), 1.0)
	if _photos.has(who):
		var tex: Texture2D = _photos[who][0]
		var reg: Rect2 = _photos[who][1]
		var drawn: Rect2 = _photos[who][2]
		var crop := Rect2(reg.position + Vector2(reg.size.x * 0.22, reg.size.y * 0.02), reg.size * Vector2(0.56, 0.56))
		# Only the frame's own pixels: map the visible part of the crop onto the photo.
		var vis := crop.intersection(drawn)
		if vis.has_area():
			var k := r.size / crop.size
			var dest := Rect2(r.position + (vis.position - crop.position) * k, vis.size * k)
			ci.draw_texture_rect_region(tex, dest, vis)
	ci.draw_rect(r, Color(1.0, 0.9, 0.7, 0.08))


func _draw_dossier() -> void:
	var a := _art
	# Back cover of the folder, and its tab.
	a.draw_rect(Rect2(66, 66, 1160, 700), Color(0, 0, 0, 0.45))
	a.draw_rect(Rect2(90, 24, 270, 52), Style.MANILA_DARK)
	a.draw_string(Style.mono_bold(), Vector2(110, 52), "FILE Nº 84-DX", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Style.INK)
	a.draw_rect(Rect2(60, 60, 1160, 700), Style.MANILA)
	a.draw_rect(Rect2(60, 60, 1160, 700), Style.MANILA_DARK, false, 3.0)
	a.draw_line(Vector2(640, 62), Vector2(640, 758), Color(0, 0, 0, 0.25), 4.0)
	# Two pages.
	Style.draw_paper(a, Rect2(88, 86, 540, 652), Style.PAPER, -0.015)
	Style.draw_paper(a, Rect2(660, 92, 530, 646), Style.PAPER, 0.01)

	# Left page: classification line, title, tagline.
	a.draw_string(Style.mono_bold(), Vector2(118, 136), "CLASSIFIED  //  OPERATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Style.RED_INK)
	a.draw_string(Style.stencil(), Vector2(112, 238), "DOUBLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 104, Style.INK)
	a.draw_string(Style.stencil(), Vector2(112, 346), "CROSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 122, Style.RED_INK)
	var shown := TAGLINE.left(int(_tag_chars))
	a.draw_string(Style.typewriter(), Vector2(118, 392), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Style.INK)
	if _tag_chars < TAGLINE.length() or int(_t * 2.0) % 2 == 0:
		var cw := Style.typewriter().get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		a.draw_rect(Rect2(120 + cw, 374, 11, 22), Color(Style.INK, 0.8))

	# Polaroids of the two subjects, taped in.
	Style.draw_polaroid(a, Vector2(212, 545), -0.09, "SUBJECT: CRIMSON", func(ci, r): _photo(ci, r, "crimson"))
	Style.draw_polaroid(a, Vector2(420, 552), 0.07, "SUBJECT: COBALT", func(ci, r): _photo(ci, r, "cobalt"))
	Style.draw_tape(a, Vector2(200, 445), -0.3)
	Style.draw_tape(a, Vector2(440, 452), 0.25)
	Style.draw_paperclip(a, Vector2(1160, 104), 1.62, 80.0)
	Style.draw_redacted(a, Vector2(124, 690), "LAST SEEN:", [120, 70, 90])
	Style.draw_coffee_ring(a, Vector2(560, 680), 44.0)

	# The TOP SECRET stamp, slightly crooked across the title.
	Style.draw_stamp(a, "TOP SECRET", Vector2(470, 160), -0.2, Style.RED_INK, 42)

	# Right page: heading and rules.
	a.draw_string(Style.stencil(), Vector2(694, 146), "MISSION ORDERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Style.INK)
	a.draw_line(Vector2(694, 156), Vector2(1150, 156), Style.INK, 2.0)
	for x in range(696, 1150, 14):
		a.draw_line(Vector2(x, 455), Vector2(x + 7, 455), Color(Style.INK, 0.5), 1.5)
	Style.draw_stamp(a, "EYES ONLY", Vector2(1080, 720), 0.12, Color("1f4f9a"), 22, 0.7)
	a.draw_string(Style.mono_bold(), Vector2(910, 758), "BUILD v" + Net.version, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Style.INK, 0.55))


func _draw() -> void:
	# The desk: dark wood under a warm lamp, with deep shadows at the edges.
	var vp := Ui.view_size(self)
	var wood := Art.wood_tex()
	draw_texture_rect(wood, Rect2(Vector2.ZERO, vp), true, Color(0.9, 0.85, 0.8))
	var soft := Art.soft()
	var flick := 0.95 + 0.05 * sin(_t * 7.0) * sin(_t * 2.3)
	draw_texture_rect(soft, Rect2(Vector2(-vp.x * 0.2, -vp.y * 0.5), vp * 1.3), false, Color(1.0, 0.8, 0.5, 0.35 * flick))
	draw_texture_rect(Art.vignette(), Rect2(Vector2.ZERO, vp), false, Color(1, 1, 1, 0.9))


# ------------------------------------------------------------------ overlays (memos)

## A typed memo on a sheet of paper, over the dimmed desk. Returns its VBox.
func _open_overlay(title_text: String, width := 760.0) -> VBoxContainer:
	_close_overlay()
	Sound.play("paper", -4.0)
	_overlay = Control.new()
	add_child(_overlay)
	_overlay.position = Vector2.ZERO
	_overlay.size = Ui.view_size(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Style.PAPER
	sb.border_color = Style.PAPER_DARK
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(6, 10)
	sb.set_content_margin_all(26)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := _label("MEMORANDUM", Style.stencil(), 40)
	head.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var stamp := Control.new()
	stamp.custom_minimum_size = Vector2(210, 60)
	stamp.draw.connect(func(): Style.draw_stamp(stamp, "EYES ONLY", Vector2(105, 30), -0.1, Style.RED_INK, 26))
	head.add_child(stamp)
	var subj := _label("SUBJECT: " + title_text, Style.mono_bold(), 22)
	box.add_child(subj)
	var rule := ColorRect.new()
	rule.color = Style.INK
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)
	return box


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _done_button(box: VBoxContainer) -> void:
	var done := Button.new()
	done.text = "[ FILE IT ]"
	done.add_theme_font_size_override("font_size", 26)
	done.custom_minimum_size = Vector2(0, 56)
	done.pressed.connect(func():
		Settings.save()
		Sound.play("stamp", -6.0)
		_close_overlay())
	box.add_child(done)
	_hook_clicks(box)


func _show_settings() -> void:
	var box := _open_overlay("FIELD EQUIPMENT SETTINGS", 660.0)
	box.add_child(_slider_row("Music", Settings.music_volume, func(v):
		Settings.music_volume = v
		Settings.changed.emit()))
	box.add_child(_slider_row("Sound effects", Settings.sfx_volume, func(v):
		Settings.sfx_volume = v
		Settings.changed.emit()
		Sound.play("type1", -2.0, false, 0.0)))
	var vib := CheckButton.new()
	vib.text = "Vibrate when hit"
	vib.button_pressed = Settings.vibration
	vib.toggled.connect(func(on): Settings.vibration = on)
	box.add_child(vib)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _label("Clock per agent", Style.mono(), 22)
	l.custom_minimum_size = Vector2(210, 40)
	row.add_child(l)
	var group := ButtonGroup.new()
	for m in [4, 6, 8, 10]:
		var b := Button.new()
		b.text = "%d MIN" % m
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = m == Settings.clock_minutes
		b.custom_minimum_size = Vector2(92, 46)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func(): Settings.clock_minutes = m)
		row.add_child(b)
	box.add_child(row)
	var note := _label("In a two-player game the host's clock setting is used.", Style.typewriter(), 18)
	note.add_theme_color_override("font_color", Color(Style.INK, 0.6))
	box.add_child(note)
	_done_button(box)


func _slider_row(label_text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := _label(label_text, Style.mono(), 22)
	l.custom_minimum_size = Vector2(210, 40)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(320, 40)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.drag_ended.connect(func(_c): on_change.call(sl.value))
	sl.value_changed.connect(func(v):
		# Keyboard/gamepad changes apply at once; drags apply on release.
		if not sl.has_focus():
			on_change.call(v))
	row.add_child(sl)
	return row


func _show_help() -> void:
	var box := _open_overlay("FIELD MANUAL", 920.0)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = false
	text.scroll_active = true
	text.custom_minimum_size = Vector2(856, 430)
	text.add_theme_font_size_override("normal_font_size", 19)
	text.add_theme_font_size_override("bold_font_size", 19)
	text.add_theme_font_size_override("italics_font_size", 19)
	text.add_theme_font_override("italics_font", Style.typewriter())
	text.text = """[b][color=#b3141f]1. THE MISSION.[/color][/b] Recover the [b]PASSPORT, CASH, MICROFILM[/b] and [b]KEYCARD[/b] hidden in the furniture, then walk out of the [b]EXIT[/b] before your clock runs out. First one out wins.

[b][color=#b3141f]2. SEARCHING.[/color][/b] Stand next to furniture and press [b]SEARCH[/b]. Without the [b]BRIEFCASE[/b] you can carry only one item, so you'll swap and leave the other behind.

[b][color=#b3141f]3. TRAPS.[/color][/b] Press [b]TRAP[/b] to hide a [b]BOMB[/b] or [b]SPRING[/b] in furniture, or string a [b]TRIPWIRE[/b] across a doorway. Getting caught knocks you out, scatters your intel and costs 20 seconds. Only you can see your own traps, but they still work on you.

[b][color=#b3141f]4. GADGETS.[/color][/b] The [b]EXTINGUISHER[/b] beats bombs, the [b]TOOLKIT[/b] beats springs and the [b]WIRE CUTTERS[/b] beat tripwires. Each is used up when it saves you.

[b][color=#b3141f]5. FIGHTING.[/color][/b] [b]ATTACK[/b] swings your cosh, [b]FIRE[/b] shoots a dart. Three hits take an agent out: they drop their intel, lose 30 seconds and wake up back at the start.

[b][color=#b3141f]6. KEYBOARD.[/color][/b] WASD/arrows move · E search · 1/2/3 traps · F cosh · G dart

[i]This manual will not self-destruct. Please return it to the file.[/i]"""
	box.add_child(text)
	_done_button(box)


# ------------------------------------------------------------------ behaviour

func set_status(msg: String) -> void:
	_status_full = msg
	_status_chars = 0.0
	_status.text = ""


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

	# Typewriter effects (with the odd key clack).
	if _tag_chars < TAGLINE.length():
		var before := int(_tag_chars)
		_tag_chars = minf(TAGLINE.length(), _tag_chars + delta * 26.0)
		if int(_tag_chars) != before and TAGLINE[before] != " " and before % 2 == 0:
			Sound.play("type%d" % randi_range(1, 3), -10.0, false, 0.08)
	if _status_chars < _status_full.length():
		var before := int(_status_chars)
		_status_chars = minf(_status_full.length(), _status_chars + delta * 45.0)
		_status.text = _status_full.left(int(_status_chars)) + "▌"
		if int(_status_chars) != before and before % 3 == 0:
			Sound.play("type%d" % randi_range(1, 3), -12.0, false, 0.08)
	elif _status_full != "":
		_status.text = _status_full + ("▌" if int(_t * 2.0) % 2 == 0 else "")
	_searching.text = "Looking for hosts" + ".".repeat(int(_t * 2.0) % 4)
	_art.queue_redraw()
	queue_redraw()


func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		set_status("Couldn't open a channel (error %d)." % err)
		return
	_set_waiting(true)
	set_status("Waiting for a rival… They'll see you under FIND HOST. (IP %s)" % Net.local_ip())


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
	set_status("Dialling %s…" % ip)


func _set_waiting(on: bool) -> void:
	_main_buttons.modulate.a = 0.35 if on else 1.0
	for b in _main_buttons.get_children():
		if b is Button:
			(b as Button).disabled = on
	_cancel.visible = on
	_find_row.visible = not on
	_ip_row.visible = false
	_ip_edit.release_focus()


func _refresh_hosts() -> void:
	for c in _hosts_box.get_children():
		c.queue_free()
	# Room for two on the page (there's only ever one rival anyway).
	for ip in Net.discovered.keys().slice(0, 2):
		var b := Button.new()
		var their: String = Net.discovered[ip].get("version", "?")
		var host_name: String = Net.discovered[ip]["name"]
		b.text = "▸ JOIN AGENT %s" % host_name
		if their != Net.version:
			# Different app version: can't play together.
			b.text = "✕ %s: needs v%s" % [host_name, their]
			b.disabled = true
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(440, 40)
		b.add_theme_font_size_override("font_size", 21)
		b.pressed.connect(_join.bind(ip))
		_hosts_box.add_child(b)
		_hook_clicks(_hosts_box)
	_searching.visible = Net.discovered.is_empty()
