extends Control
## Full-screen cut-away of an agent crawling through an air duct. Fades in,
## plays for `seconds`, fades out and frees itself.

const Style = preload("res://scripts/ui/style.gd")

const FRAMES := 8
const CAPTION := "…crawling through the air ducts…"

var _sheet: Texture2D
var _seconds := 1.0
var _t := 0.0


func _init(area: Vector2, crawl_sheet: Texture2D, seconds: float) -> void:
	size = area
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_sheet = crawl_sheet
	_seconds = seconds


func _ready() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	tw.tween_interval(_seconds - 0.4)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.96))
	var h := 230.0
	var top := size.y / 2.0 - h / 2.0
	var scroll := _t * 240.0
	_draw_duct(top, h, scroll)
	_draw_agent(top, h)
	# Dust drifting by.
	for i in 24:
		var px := fposmod(i * 97.0 - scroll * (0.5 + (i % 3) * 0.3), size.x + 40.0)
		var py := top + fmod(i * 53.0, h)
		draw_circle(Vector2(px, py), 1.5, Color(1, 0.95, 0.8, 0.25))
	var font := Style.typewriter()
	var w := font.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(font, Vector2((size.x - w) / 2.0, top + h + 80), CAPTION,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.92, 0.88, 0.78))


## Sheet-metal walls, the inside lit by grilles drifting past.
func _draw_duct(top: float, h: float, scroll: float) -> void:
	draw_rect(Rect2(0, top, size.x, h), Color("15181d"))
	for band in [[top - 26.0, 26.0], [top + h, 26.0]]:
		draw_rect(Rect2(0, band[0], size.x, band[1]), Color("4a5260"))
		draw_rect(Rect2(0, band[0], size.x, 4), Color("6b7585"))
	var x := -fmod(scroll, 180.0)
	while x < size.x:
		draw_line(Vector2(x, top - 26), Vector2(x, top), Color("2b3038"), 2.0)
		draw_line(Vector2(x, top + h), Vector2(x, top + h + 26), Color("2b3038"), 2.0)
		draw_circle(Vector2(x + 10, top - 13), 2.5, Color("9aa3b0"))
		draw_circle(Vector2(x + 10, top + h + 13), 2.5, Color("9aa3b0"))
		x += 180.0
	x = -fmod(scroll, 520.0) + 120.0
	while x < size.x + 200.0:
		var shaft := PackedVector2Array([
			Vector2(x - 40, top), Vector2(x + 40, top), Vector2(x + 110, top + h), Vector2(x - 110, top + h),
		])
		draw_colored_polygon(shaft, Color(1.0, 0.92, 0.7, 0.07))
		for k in 4:
			var slat := Vector2(x - 34 + k * 22, top + 2)
			draw_line(slat, slat + Vector2(8, 0), Color(1.0, 0.95, 0.75, 0.6), 3.0)
		x += 520.0


func _draw_agent(top: float, h: float) -> void:
	if _sheet == null:
		return
	var fw := _sheet.get_width() / FRAMES
	var fh := _sheet.get_height()
	var f := int(_t * 11.0) % FRAMES
	var sc := 1.25
	var at := Vector2(size.x / 2.0 - fw * sc / 2.0 + sin(_t * 2.0) * 20.0, top + h - fh * sc + 6)
	draw_texture_rect_region(_sheet, Rect2(at, Vector2(fw, fh) * sc), Rect2(f * fw, 0, fw, fh))
