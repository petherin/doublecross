extends Control
## The mission briefing typed out at the start of a match, which then
## self-destructs in a puff of smoke. Any tap or key skips it.

signal finished

const Style = preload("res://scripts/ui/style.gd")

const CHARS_PER_SECOND := 55.0
## How long the finished page stays up before it goes up in smoke.
const READ_TIME := 1.4

var _lines: Array = []
var _sheet: Control
var _t := 0.0
var _done := false


func _init(area: Vector2, agent_name: String, rival_name: String, minutes: int) -> void:
	size = area
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.size = area
	add_child(dim)
	_sheet = Control.new()
	_sheet.size = Vector2(minf(860.0, area.x - 60.0), 400)
	_sheet.position = (area - _sheet.size) / 2.0
	_sheet.draw.connect(_draw_sheet)
	add_child(_sheet)
	_lines = [
		["OPERATION DOUBLE CROSS", Style.stencil(), 40, Style.INK],
		["TO: " + agent_name, Style.mono_bold(), 22, Style.INK],
		["Recover the PASSPORT, CASH, MICROFILM and KEYCARD,", Style.mono(), 22, Style.INK],
		["then get to the EXIT. You have %d minutes." % minutes, Style.mono(), 22, Style.INK],
		["Beware: %s is already inside. Trust no one." % rival_name, Style.mono_bold(), 22, Style.RED_INK],
		["This message will self-destruct in 3… 2… 1…", Style.typewriter(), 22, Style.INK],
	]


func _ready() -> void:
	Sound.play("paper", -2.0)


func _process(delta: float) -> void:
	var before := _chars()
	_t += delta
	if _chars() < _total_chars() and _chars() / 3 != before / 3:
		Sound.play("type%d" % randi_range(1, 3), -9.0, false, 0.08)
	if _t > _typing_time() + READ_TIME:
		_self_destruct()
	_sheet.queue_redraw()


func _input(event: InputEvent) -> void:
	if _done:
		return
	if (event is InputEventScreenTouch or event is InputEventKey) and event.pressed:
		_t = maxf(_t, _typing_time() + READ_TIME)
		_self_destruct()
		get_viewport().set_input_as_handled()


func _chars() -> int:
	return int(_t * CHARS_PER_SECOND)


func _total_chars() -> int:
	var total := 0
	for l in _lines:
		total += (l[0] as String).length()
	return total


func _typing_time() -> float:
	return float(_total_chars()) / CHARS_PER_SECOND


func _self_destruct() -> void:
	if _done:
		return
	_done = true
	Sound.play("poof", -2.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)
	finished.emit()


func _draw_sheet() -> void:
	var smoke := clampf((_t - (_typing_time() + READ_TIME)) / 0.6, 0.0, 1.0)
	Style.draw_paper(_sheet, Rect2(Vector2.ZERO, _sheet.size), Style.PAPER, 0.008)
	var left := _chars()
	var y := 70.0
	for l in _lines:
		var text: String = l[0]
		_sheet.draw_string(l[1], Vector2(40, y), text.left(maxi(0, left)),
				HORIZONTAL_ALIGNMENT_LEFT, _sheet.size.x - 80, l[2], l[3])
		left -= text.length()
		y += 46.0 if l[2] > 30 else 52.0
	Style.draw_stamp(_sheet, "TOP SECRET", Vector2(_sheet.size.x - 150, 52), 0.12, Style.RED_INK, 26)
	if smoke > 0.0:
		for i in 18:
			var a := i * 2.4
			var p := _sheet.size / 2.0 + Vector2(cos(a), sin(a)) * (40.0 + 220.0 * smoke) * Vector2(1.6, 0.8)
			_sheet.draw_circle(p, 40.0 + 60.0 * smoke, Color(0.3, 0.3, 0.3, 0.6 * (1.0 - smoke)))
