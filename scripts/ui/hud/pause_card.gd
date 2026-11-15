extends Control
## One-player games only: the "mission on hold" card shown while the game is
## paused. It keeps running while everything else is frozen, so its buttons
## (and the pause key) still work.

signal resumed
signal abandoned

const Style = preload("res://scripts/ui/style.gd")

var _dim: ColorRect
var _card: PanelContainer
var _resume: Button


func _init(area: Vector2) -> void:
	size = area
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.62)
	add_child(_dim)
	var card := PanelContainer.new()
	_card = card
	var sb := StyleBoxFlat.new()
	sb.bg_color = Style.PAPER
	sb.border_color = Style.PAPER_DARK
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(6, 10)
	sb.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", sb)
	card.rotation = -0.012
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	box.add_child(_text("MISSION ON HOLD", Style.stencil(), 44, Style.INK))
	box.add_child(_text("The clocks are stopped. Nobody moves until you do.", Style.typewriter(), 20, Style.INK))
	_resume = _button("[ RESUME ]")
	_resume.pressed.connect(func(): resumed.emit())
	box.add_child(_resume)
	var quit := _button("ABANDON MISSION")
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		quit.add_theme_color_override(c, Style.RED_INK)
	quit.pressed.connect(func(): abandoned.emit())
	box.add_child(quit)


## Shows or hides the card, centred in `area` (the HUD's size).
func show_card(on: bool, area: Vector2) -> void:
	visible = on
	if not on:
		return
	size = area
	_dim.size = area
	_card.reset_size()
	_card.position = (area - _card.size) / 2.0
	_resume.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		resumed.emit()


func _text(t: String, font: Font, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(380, 56)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_font_override("font", Style.mono_bold())
	b.add_theme_color_override("font_color", Style.INK)
	b.add_theme_color_override("font_hover_color", Style.INK)
	b.add_theme_color_override("font_focus_color", Style.INK)
	b.add_theme_color_override("font_pressed_color", Style.RED_INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Style.INK, 0.1 if state in ["hover", "focus"] else 0.0)
		sb.border_color = Color(Style.INK, 0.8)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(3)
		b.add_theme_stylebox_override(state, sb)
	return b
