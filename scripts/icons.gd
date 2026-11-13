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

		"WIRE CUTTERS":
			ci.draw_line(c + Vector2(-0.35, -0.35) * s, c + Vector2(0.15, 0.15) * s, k.call(Color("c7ccd6")), 0.1 * s)
			ci.draw_line(c + Vector2(0.35, -0.35) * s, c + Vector2(-0.15, 0.15) * s, k.call(Color("c7ccd6")), 0.1 * s)
			ci.draw_line(c + Vector2(0.15, 0.15) * s, c + Vector2(0.38, 0.42) * s, k.call(Color("ff5a5f")), 0.14 * s)
			ci.draw_line(c + Vector2(-0.15, 0.15) * s, c + Vector2(-0.38, 0.42) * s, k.call(Color("ff5a5f")), 0.14 * s)
			ci.draw_circle(c, 0.07 * s, k.call(Color("50575f")))
		"EXTINGUISHER":
			ci.draw_rect(Rect2(c + Vector2(-0.16, -0.25) * s, Vector2(0.32, 0.68) * s), k.call(Color("d32f2f")))
			ci.draw_circle(c + Vector2(0, -0.25) * s, 0.16 * s, k.call(Color("d32f2f")))
			ci.draw_rect(Rect2(c + Vector2(-0.06, -0.48) * s, Vector2(0.12, 0.1) * s), k.call(Color("2b2f36")))
			ci.draw_line(c + Vector2(0.05, -0.44) * s, c + Vector2(0.35, -0.3) * s, k.call(Color("2b2f36")), 0.07 * s)
			ci.draw_rect(Rect2(c + Vector2(-0.16, 0.0) * s, Vector2(0.32, 0.1) * s), k.call(Color("eef1f5")))
		"TOOLKIT":
			ci.draw_line(c + Vector2(-0.3, 0.32) * s, c + Vector2(0.2, -0.18) * s, k.call(Color("9aa3b0")), 0.11 * s)
			ci.draw_arc(c + Vector2(0.24, -0.24) * s, 0.14 * s, -0.6, 4.2, 12, k.call(Color("9aa3b0")), 0.08 * s)
			ci.draw_line(c + Vector2(0.3, 0.3) * s, c + Vector2(-0.18, -0.18) * s, k.call(Color("e8c25a")), 0.09 * s)
			ci.draw_rect(Rect2(c + Vector2(0.2, 0.2) * s, Vector2(0.16, 0.16) * s), k.call(Color("3b2a1c")))
		"BOMB":
			ci.draw_circle(c + Vector2(-0.05, 0.08) * s, 0.32 * s, k.call(Color("15151a")))
			ci.draw_circle(c + Vector2(-0.16, -0.02) * s, 0.08 * s, k.call(Color(1, 1, 1, 0.35)))
			ci.draw_rect(Rect2(c + Vector2(0.06, -0.3) * s, Vector2(0.14, 0.12) * s), k.call(Color("2b2b33")))
			ci.draw_line(c + Vector2(0.13, -0.3) * s, c + Vector2(0.3, -0.42) * s, k.call(Color("c9a46a")), 0.05 * s)
			ci.draw_circle(c + Vector2(0.32, -0.44) * s, 0.08 * s, k.call(Color("ffd23f")))
		"SPRING":
			var pts := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				pts.append(c + Vector2((0.28 if i % 2 == 0 else -0.28), 0.36 - t * 0.66) * s)
			ci.draw_polyline(pts, k.call(Color("c7ccd6")), 0.07 * s, true)
			ci.draw_rect(Rect2(c + Vector2(-0.38, 0.36) * s, Vector2(0.76, 0.1) * s), k.call(Color("50575f")))
			ci.draw_rect(Rect2(c + Vector2(-0.3, -0.4) * s, Vector2(0.6, 0.1) * s), k.call(Color("ff5a5f")))
		"WIRE":
			ci.draw_rect(Rect2(c + Vector2(-0.44, -0.3) * s, Vector2(0.1, 0.6) * s), k.call(Color("e0b10b")))
			ci.draw_rect(Rect2(c + Vector2(0.34, -0.3) * s, Vector2(0.1, 0.6) * s), k.call(Color("e0b10b")))
			ci.draw_line(c + Vector2(-0.34, 0.12) * s, c + Vector2(0.34, 0.16) * s, k.call(Color("eef1f5")), 0.04 * s)
			ci.draw_circle(c + Vector2(0.0, 0.14) * s, 0.06 * s, k.call(Color("ff5a5f")))

		"COSH":
			ci.draw_line(c + Vector2(-0.3, 0.32) * s, c + Vector2(0.22, -0.2) * s, k.call(Color("7a5238")), 0.13 * s, true)
			ci.draw_circle(c + Vector2(0.26, -0.24) * s, 0.14 * s, k.call(Color("3b2a1c")))
			ci.draw_line(c + Vector2(-0.36, 0.38) * s, c + Vector2(-0.22, 0.24) * s, k.call(Color("15151a")), 0.15 * s)
		"DART":
			ci.draw_line(c + Vector2(-0.36, 0.2) * s, c + Vector2(0.3, -0.16) * s, k.call(Color("c7ccd6")), 0.06 * s, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.42, -0.23) * s, c + Vector2(0.26, -0.2) * s, c + Vector2(0.31, -0.1) * s]), k.call(Color("eef1f5")))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.36, 0.2) * s, c + Vector2(-0.44, 0.06) * s, c + Vector2(-0.22, 0.12) * s]), k.call(Color("ff5a5f")))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.36, 0.2) * s, c + Vector2(-0.3, 0.34) * s, c + Vector2(-0.2, 0.16) * s]), k.call(Color("ff5a5f")))


## A magnifying glass, for the search button.
static func magnifier(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_arc(c + Vector2(-0.08, -0.08) * s, 0.24 * s, 0, TAU, 28, col, 0.08 * s, true)
	ci.draw_line(c + Vector2(0.1, 0.1) * s, c + Vector2(0.32, 0.32) * s, col, 0.11 * s, true)
