extends RefCounted
## Little drawn icons for the items, used by the HUD.


static func draw(ci: CanvasItem, item: String, c: Vector2, s: float, lit := true) -> void:
	var k := func(col: Color) -> Color:
		return col if lit else Color(1, 1, 1, 0.16)
	match item:
		"PASSPORT":
			ci.draw_rect(Rect2(c + Vector2(-0.32, -0.42) * s, Vector2(0.64, 0.84) * s), k.call(Color("8b1e2d")))
			ci.draw_rect(Rect2(c + Vector2(-0.32, -0.42) * s, Vector2(0.08, 0.84) * s), k.call(Color("5e1420")))
			ci.draw_circle(c + Vector2(0.04, -0.06) * s, 0.15 * s, k.call(Color("e8c25a")))
			ci.draw_rect(Rect2(c + Vector2(-0.14, 0.2) * s, Vector2(0.36, 0.05) * s), k.call(Color("e8c25a")))
		"CASH":
			for i in 3:
				var o := Vector2(0, (1 - i) * 0.12) * s
				ci.draw_rect(Rect2(c + o + Vector2(-0.45, -0.2) * s, Vector2(0.9, 0.4) * s), k.call(Color("2f8f46").darkened(i * 0.1)))
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.32) * s, Vector2(0.9, 0.4) * s), k.call(Color("4fbf6a")))
			ci.draw_circle(c + Vector2(0, -0.12) * s, 0.12 * s, k.call(Color("2f8f46")))
			ci.draw_rect(Rect2(c + Vector2(-0.08, -0.36) * s, Vector2(0.16, 0.6) * s), k.call(Color("e6e2c8")))
		"MICROFILM":
			ci.draw_rect(Rect2(c + Vector2(0.0, 0.12) * s, Vector2(0.5, 0.2) * s), k.call(Color("5a4a2a")))
			ci.draw_circle(c + Vector2(-0.08, -0.04) * s, 0.38 * s, k.call(Color("3a3f48")))
			ci.draw_circle(c + Vector2(-0.08, -0.04) * s, 0.3 * s, k.call(Color("8a6a3a")))
			ci.draw_circle(c + Vector2(-0.08, -0.04) * s, 0.1 * s, k.call(Color("c7ccd6")))
			for i in 3:
				var a := i * TAU / 3.0
				ci.draw_circle(c + Vector2(-0.08, -0.04) * s + Vector2.from_angle(a) * 0.2 * s, 0.05 * s, k.call(Color("3a3f48")))
		"KEYCARD":
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.3) * s, Vector2(0.9, 0.6) * s), k.call(Color("eef1f5")))
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.18) * s, Vector2(0.9, 0.12) * s), k.call(Color("ff5a5f")))
			ci.draw_rect(Rect2(c + Vector2(-0.33, 0.04) * s, Vector2(0.2, 0.15) * s), k.call(Color("e8c25a")))
			ci.draw_rect(Rect2(c + Vector2(0.0, 0.08) * s, Vector2(0.32, 0.04) * s), k.call(Color("9aa3b0")))
		"BRIEFCASE":
			ci.draw_arc(c + Vector2(0, -0.26) * s, 0.14 * s, PI, TAU, 12, k.call(Color("3b2a1c")), 0.06 * s)
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.26) * s, Vector2(0.9, 0.58) * s), k.call(Color("7a5238")))
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.26) * s, Vector2(0.9, 0.08) * s), k.call(Color("946645")))
			ci.draw_rect(Rect2(c + Vector2(-0.3, -0.24) * s, Vector2(0.1, 0.12) * s), k.call(Color("e8c25a")))
			ci.draw_rect(Rect2(c + Vector2(0.2, -0.24) * s, Vector2(0.1, 0.12) * s), k.call(Color("e8c25a")))


## A magnifying glass, for the search button.
static func magnifier(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_arc(c + Vector2(-0.08, -0.08) * s, 0.24 * s, 0, TAU, 28, col, 0.08 * s, true)
	ci.draw_line(c + Vector2(0.1, 0.1) * s, c + Vector2(0.32, 0.32) * s, col, 0.11 * s, true)
