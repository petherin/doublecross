extends RefCounted
## The game's spy look: fonts, paper colours, and helpers for drawing case-file
## props (paper, rubber stamps, paperclips, tape, coffee rings, redactions,
## polaroids). Fonts are bundled in assets/fonts (see the licence files there).

const INK := Color("1d1a16")
const RED_INK := Color("b3141f")
const GREEN_INK := Color("1f7a3a")
const PAPER := Color("ece3cb")
const PAPER_DARK := Color("d9cdaa")
const MANILA := Color("c4a265")
const MANILA_DARK := Color("a8854c")
const HIGHLIGHT := Color(1.0, 0.86, 0.15, 0.55)

static var _fonts := {}


static func _font(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[path]


## Military stencil, for headings.
static func stencil() -> Font:
	return _font("res://assets/fonts/BlackOpsOne-Regular.ttf")


## Worn, inky typewriter, for flavour text.
static func typewriter() -> Font:
	return _font("res://assets/fonts/SpecialElite-Regular.ttf")


## Clean typewriter, for readable text and buttons.
static func mono() -> Font:
	return _font("res://assets/fonts/CourierPrime-Regular.ttf")


static func mono_bold() -> Font:
	return _font("res://assets/fonts/CourierPrime-Bold.ttf")


## Theme for things printed on paper: dark ink, typewriter type, highlighter hovers.
static func paper_theme() -> Theme:
	var t := Theme.new()
	t.default_font = mono()
	t.default_font_size = 24
	for kind in ["Label", "Button", "LineEdit", "CheckButton", "RichTextLabel"]:
		t.set_color("font_color", kind, INK)
	t.set_font("font", "Button", mono_bold())
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", RED_INK)
	t.set_color("font_hover_pressed_color", "Button", RED_INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.35))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", mono())
	t.set_font("bold_font", "RichTextLabel", mono_bold())
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(6)
	var hover := StyleBoxFlat.new()
	hover.bg_color = HIGHLIGHT
	hover.set_content_margin_all(6)
	hover.skew = Vector2(-0.08, 0)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0, 0, 0, 0)
	pressed.border_color = RED_INK
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(22)
	pressed.set_content_margin_all(6)
	for kind in ["Button", "CheckButton"]:
		t.set_stylebox("normal", kind, empty)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("pressed", kind, pressed)
		t.set_stylebox("hover_pressed", kind, pressed)
		t.set_stylebox("disabled", kind, empty)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", empty)
	t.set_stylebox("hover_pressed", "CheckButton", hover)
	# Typed-on-a-line text fields.
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.25)
	field.border_color = INK
	field.border_width_bottom = 2
	field.set_content_margin_all(6)
	var field_focus := field.duplicate()
	field_focus.bg_color = Color(1, 0.95, 0.6, 0.35)
	field_focus.border_color = RED_INK
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.35))
	t.set_color("caret_color", "LineEdit", RED_INK)
	t.set_font("font", "LineEdit", mono_bold())
	# Sliders drawn in ink.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.5)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = RED_INK
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t


# ------------------------------------------------------------------ drawing props

## A sheet of paper with a soft shadow, a slightly darker edge and a fold.
static func draw_paper(ci: CanvasItem, r: Rect2, col := PAPER, angle := 0.0) -> void:
	var c := r.get_center()
	ci.draw_set_transform(c + Vector2(6, 9), angle, Vector2.ONE)
	ci.draw_rect(Rect2(-r.size / 2, r.size), Color(0, 0, 0, 0.35))
	ci.draw_set_transform(c, angle, Vector2.ONE)
	ci.draw_rect(Rect2(-r.size / 2, r.size), col.darkened(0.12))
	ci.draw_rect(Rect2(-r.size / 2 + Vector2(2, 2), r.size - Vector2(4, 4)), col)
	# Faint ruled lines and paper grain.
	var y := -r.size.y / 2 + 70
	while y < r.size.y / 2 - 30:
		ci.draw_line(Vector2(-r.size.x / 2 + 20, y), Vector2(r.size.x / 2 - 20, y), Color(0.2, 0.35, 0.6, 0.06), 1.0)
		y += 34
	for i in 40:
		var p := Vector2(fmod(i * 97.3, r.size.x) - r.size.x / 2, fmod(i * 53.7, r.size.y) - r.size.y / 2)
		ci.draw_circle(p, 1.0 + (i % 3), Color(0.4, 0.3, 0.15, 0.05))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## An inked rubber stamp: bordered text, rotated, with worn gaps in the ink.
static func draw_stamp(
		ci: CanvasItem, text: String, centre: Vector2, angle: float, col: Color, size: int,
		alpha := 0.85, gap_col := PAPER, scale := 1.0) -> void:
	var f := stencil()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := float(size)
	ci.draw_set_transform(centre, angle, Vector2(scale, scale))
	var box := Rect2(-w / 2 - 16, -h * 0.75, w + 32, h * 1.25)
	ci.draw_rect(box, Color(col, alpha), false, maxf(3.0, size / 12.0))
	ci.draw_rect(box.grow(-maxf(6.0, size / 8.0)), Color(col, alpha * 0.6), false, maxf(1.5, size / 30.0))
	ci.draw_string(f, Vector2(-w / 2, h * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, alpha))
	# Worn patches where the stamp didn't take.
	for i in 26:
		var p := Vector2(fmod(i * 71.7, box.size.x) + box.position.x, fmod(i * 37.3, box.size.y) + box.position.y)
		ci.draw_circle(p, 1.0 + (i % 4) * 0.9, Color(gap_col, 0.75))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_paperclip(ci: CanvasItem, at: Vector2, angle := 0.0, length := 70.0) -> void:
	ci.draw_set_transform(at, angle, Vector2.ONE)
	var col := Color("b8bec7")
	var pts := PackedVector2Array()
	# A paperclip is a long rounded loop inside another.
	for seg in [[0.0, length, 9.0], [6.0, length - 12.0, 5.0]]:
		var a: float = seg[0]
		var b: float = seg[1]
		var r: float = seg[2]
		pts.clear()
		pts.append(Vector2(a, -r))
		pts.append(Vector2(b, -r))
		for i in 9:
			pts.append(Vector2(b, 0) + Vector2.from_angle(-PI / 2 + i * PI / 8.0) * r)
		pts.append(Vector2(a, r))
		ci.draw_polyline(pts, Color(0, 0, 0, 0.3), 4.0, true)
		ci.draw_polyline(pts, col, 2.5, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_tape(ci: CanvasItem, at: Vector2, angle := 0.0, size := Vector2(80, 26)) -> void:
	ci.draw_set_transform(at, angle, Vector2.ONE)
	ci.draw_rect(Rect2(-size / 2, size), Color(0.95, 0.9, 0.72, 0.6))
	for i in 5:
		var notch := Vector2(-size.x / 2, -size.y / 2 + i * size.y / 4)
		ci.draw_line(notch, notch + Vector2(-2, 3), Color(0.95, 0.9, 0.72, 0.6), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_coffee_ring(ci: CanvasItem, at: Vector2, r := 46.0) -> void:
	ci.draw_arc(at, r, 0.2, TAU - 0.5, 48, Color(0.45, 0.28, 0.12, 0.22), 5.0, true)
	ci.draw_arc(at + Vector2(3, 2), r - 4, 1.0, TAU - 0.2, 48, Color(0.45, 0.28, 0.12, 0.12), 3.0, true)
	ci.draw_circle(at + Vector2(r * 0.9, r * 0.6), 4.0, Color(0.45, 0.28, 0.12, 0.15))


## A typed line with some words blacked out.
static func draw_redacted(ci: CanvasItem, at: Vector2, label: String, bars: Array, size := 18) -> void:
	var f := mono()
	ci.draw_string(f, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(INK, 0.85))
	var x := at.x + f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8
	for w in bars:
		ci.draw_rect(Rect2(x, at.y - size * 0.8, w, size * 0.95), INK)
		x += w + 10


## A polaroid photo; `draw_photo` paints the picture into the given rect.
static func draw_polaroid(ci: CanvasItem, centre: Vector2, angle: float, caption: String, draw_photo: Callable) -> void:
	var size := Vector2(170, 200)
	ci.draw_set_transform(centre + Vector2(5, 8), angle, Vector2.ONE)
	ci.draw_rect(Rect2(-size / 2, size), Color(0, 0, 0, 0.35))
	ci.draw_set_transform(centre, angle, Vector2.ONE)
	ci.draw_rect(Rect2(-size / 2, size), Color("f5f2ea"))
	var photo := Rect2(-size.x / 2 + 10, -size.y / 2 + 10, size.x - 20, size.x - 20)
	ci.draw_rect(photo, Color("20262f"))
	draw_photo.call(ci, photo)
	var f := typewriter()
	var w := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	ci.draw_string(f, Vector2(-w / 2, size.y / 2 - 14), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
