extends Control
## The end-of-match case file: dims the game, shows the outcome on a paper
## card, slams a rubber stamp onto it, and offers a rematch or a way out.

signal rematch_requested
signal leave_requested

const Style = preload("res://scripts/ui/style.gd")

## When the stamp starts to fall, and how long it takes to land.
const STAMP_AT := 0.55
const STAMP_FALL := 0.16

var _dim: ColorRect
var _card: Control
var _stamp: Control
var _stamp_text := ""
var _stamp_col := Color.WHITE
var _sub_text := ""
var _t := 0.0
var _landed := false


## `winner` is a peer id, or 0 if nobody won; `reason` is "escape" or "time".
func _init(area: Vector2, won: bool, winner: int, winner_name: String, reason: String, can_rematch: bool) -> void:
	size = area
	_describe(won, winner, winner_name, reason)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.size = area
	add_child(_dim)

	_card = Control.new()
	_card.size = Vector2(760, 440)
	_card.position = (area - _card.size) / 2.0 + Vector2(0, -20)
	_card.theme = Style.paper_theme()
	_card.draw.connect(_draw_card)
	add_child(_card)

	_stamp = Control.new()
	_stamp.size = _card.size
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp.draw.connect(_draw_stamp)
	_card.add_child(_stamp)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.position = Vector2(40, 372)
	row.size = Vector2(680, 56)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(row)
	if can_rematch:
		row.add_child(_button("[ REMATCH ]", rematch_requested.emit))
	else:
		var wait := Label.new()
		wait.text = "Awaiting orders from the host…"
		wait.add_theme_font_override("font", Style.typewriter())
		wait.add_theme_font_size_override("font_size", 21)
		row.add_child(wait)
	row.add_child(_button("[ BACK TO HQ ]", leave_requested.emit))


func _ready() -> void:
	create_tween().tween_property(_dim, "color:a", 0.65, 0.4)


func _process(delta: float) -> void:
	_t += delta
	_stamp.queue_redraw()


func _describe(won: bool, winner: int, winner_name: String, reason: String) -> void:
	_stamp_text = "MISSION ACCOMPLISHED" if won else "DOUBLE-CROSSED"
	_sub_text = "Escaped with the intel. Drinks are on you."
	if not won:
		_sub_text = "%s got out with the intel. Awkward." % winner_name
	if reason == "time":
		if winner == 0:
			_stamp_text = "TIME EXPIRED"
			_sub_text = "Nobody got out. The base goes into lockdown."
		elif won:
			_stamp_text = "LAST AGENT STANDING"
			_sub_text = "Your rival's clock ran out. A win's a win."
		else:
			_stamp_text = "OUT OF TIME"
			_sub_text = "Your clock ran out. %s wins by default." % winner_name
	_stamp_col = Style.GREEN_INK if won else Style.RED_INK


func _draw_card() -> void:
	var c := _card
	Style.draw_paper(c, Rect2(Vector2.ZERO, c.size), Style.PAPER, -0.01)
	c.draw_string(Style.stencil(), Vector2(40, 70), "CASE FILE", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Style.INK)
	c.draw_string(Style.mono_bold(), Vector2(44, 104), "OPERATION DOUBLE CROSS  //  DEBRIEF",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Style.RED_INK)
	c.draw_line(Vector2(40, 120), Vector2(720, 120), Style.INK, 2.0)
	c.draw_string(Style.mono_bold(), Vector2(44, 168), "OUTCOME:", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Style.INK)
	c.draw_string(Style.typewriter(), Vector2(44, 204), _sub_text, HORIZONTAL_ALIGNMENT_LEFT, 680, 23, Style.INK)
	Style.draw_redacted(c, Vector2(44, 248), "REMARKS:", [160, 90, 130])
	Style.draw_paperclip(c, Vector2(700, 6), 1.6, 70.0)


## The rubber stamp slams down a moment after the card appears.
func _draw_stamp() -> void:
	var k := clampf((_t - STAMP_AT) / STAMP_FALL, 0.0, 1.0)
	if k <= 0.0:
		return
	if not _landed and k >= 1.0:
		_landed = true
		Sound.play("stamp", 2.0, false, 0.02)
		Settings.buzz(60)
		var shake := create_tween()
		var rest := _card.position
		for i in 4:
			shake.tween_property(_card, "position", rest + Vector2(randf_range(-7, 7), randf_range(-5, 5)), 0.03)
		shake.tween_property(_card, "position", rest, 0.04)
	Style.draw_stamp(_stamp, _stamp_text, Vector2(380, 300), -0.08, _stamp_col, 40,
			0.9 * k, Style.PAPER, lerpf(2.6, 1.0, k))


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(on_press)
	return b
