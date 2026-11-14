extends RefCounted
## Decorations on the back walls of a room: screens, maps, clocks, signs,
## posters and fuse boxes, drawn in code. Chosen per room from the world
## seed, so every device sees the same decor. `t` animates the screens.

const POSTERS := ["TRUST NO ONE", "WALLS HAVE EARS", "SHRED AFTER READING", "LOOK BUSY"]
const SIGNS := ["RESTRICTED", "AUTHORISED ONLY", "NO ENTRY", "DANGER: HIGH VOLTAGE"]


## Things hung on the back walls: screens, maps, clocks, vents, signs, posters.
## Chosen per room from the world seed, so both tablets see the same decor.
static func draw(ci: CanvasItem, xf: Transform2D, spans: Array, tint: Color, wall: int,
		seed_value: int, room: Vector2i, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, room, wall])
	var font := ThemeDB.fallback_font
	ci.draw_set_transform_matrix(xf)
	for sp in spans:
		var a: float = sp[0] + 95.0
		while a < sp[1] - 70.0:
			if rng.randf() < 0.6:
				var kind: String = ["monitor", "monitor", "map", "clock", "map", "sign", "poster", "fusebox"][rng.randi_range(0, 7)]
				var w := _decor(ci, kind, a, tint, rng.randi(), font, t)
				a += w + 50.0
			else:
				a += 120.0
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Draws one decoration centred at `a` along the wall; returns its width.
static func _decor(ci: CanvasItem, kind: String, a: float, tint: Color, seed_v: int, font: Font, t: float) -> float:
	match kind:
		"monitor":
			var r := Rect2(a - 38, -76, 76, 48)
			ci.draw_rect(r, Color("0a0d12"))
			ci.draw_rect(r, Color("3a4456"), false, 2.0)
			var sc := r.grow(-5)
			ci.draw_rect(sc, tint.darkened(0.82))
			if seed_v % 2 == 0:
				# Scrolling signal trace.
				var pts := PackedVector2Array()
				for i in 25:
					var x := sc.position.x + i * sc.size.x / 24.0
					pts.append(Vector2(x, sc.get_center().y + sin(i * 0.7 + t * 4.0 + seed_v) * 8.0 * sin(i * 0.23 + t)))
				ci.draw_polyline(pts, tint.lightened(0.4), 1.5, true)
			else:
				# Radar sweep with blips.
				var cc := sc.get_center()
				ci.draw_arc(cc, 15, 0, TAU, 24, Color(tint.lightened(0.3), 0.6), 1.0)
				ci.draw_arc(cc, 8, 0, TAU, 16, Color(tint.lightened(0.3), 0.4), 1.0)
				var ang := t * 2.0 + seed_v
				ci.draw_line(cc, cc + Vector2.from_angle(ang) * 15, tint.lightened(0.5), 1.5)
				for b in 3:
					var bp := cc + Vector2.from_angle(seed_v * 0.7 + b * 2.1) * (5 + b * 4)
					var fade := fposmod(ang - (seed_v * 0.7 + b * 2.1), TAU) / TAU
					ci.draw_circle(bp, 1.6, Color(1, 0.4, 0.4, 1.0 - fade))
			return 76.0
		"map":
			var r := Rect2(a - 62, -78, 124, 58)
			ci.draw_rect(r, Color("0d2236"))
			ci.draw_rect(r, Color("8a6a3a"), false, 3.0)
			for i in 5:
				var gx := r.position.x + i * r.size.x / 4.0
				ci.draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(1, 1, 1, 0.06), 1.0)
			var land := Color("2e6b57")
			for blob in [
					[-38, -58, 10], [-30, -50, 8], [-20, -40, 6], [-2, -60, 9], [4, -50, 8],
					[10, -40, 7], [30, -58, 11], [40, -50, 9], [44, -34, 6]]:
				ci.draw_circle(Vector2(a + blob[0], blob[1]), blob[2], land)
			for i in 3:
				var dot := Vector2(a - 40 + ((seed_v >> (i * 4)) % 80), -64 + ((seed_v >> (i * 3)) % 30))
				if int(t * 2.0 + i) % 2 == 0:
					ci.draw_circle(dot, 2.2, Color("ff4d4d"))
			return 124.0
		"clock":
			var cc := Vector2(a, -58)
			ci.draw_circle(cc, 18, Color("2b2f36"))
			ci.draw_circle(cc, 15, Color("e6e2d3"))
			for i in 12:
				var tick := Vector2.from_angle(i * TAU / 12.0)
				ci.draw_line(cc + tick * 12, cc + tick * 14, Color("2b2f36"), 1.0)
			var tm := Time.get_time_dict_from_system()
			var mins: float = tm["minute"] + tm["second"] / 60.0
			var hrs: float = (tm["hour"] % 12) + mins / 60.0
			ci.draw_line(cc, cc + Vector2.from_angle(hrs / 12.0 * TAU - PI / 2) * 8, Color("15151a"), 2.0)
			ci.draw_line(cc, cc + Vector2.from_angle(mins / 60.0 * TAU - PI / 2) * 12, Color("15151a"), 1.5)
			ci.draw_line(cc, cc + Vector2.from_angle(tm["second"] / 60.0 * TAU - PI / 2) * 13, Color("d32f2f"), 1.0)
			return 40.0
		"vent":
			var r := Rect2(a - 26, -44, 52, 32)
			ci.draw_rect(r, Color("0d1015"))
			ci.draw_rect(r, Color("4a5568"), false, 2.0)
			for i in 6:
				var y := r.position.y + 4 + i * 4.6
				ci.draw_line(Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), Color("3a4456"), 2.0)
			return 52.0
		"sign":
			var txt: String = SIGNS[seed_v % SIGNS.size()]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18
			var r := Rect2(a - w / 2, -70, w, 24)
			ci.draw_rect(r, Color("e0b10b"))
			ci.draw_rect(r.grow(-2), Color("15151a"), false, 1.5)
			ci.draw_string(font, Vector2(r.position.x + 9, r.end.y - 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("15151a"))
			return w
		"poster":
			var txt: String = POSTERS[seed_v % POSTERS.size()]
			var r := Rect2(a - 28, -84, 56, 70)
			ci.draw_rect(r, Color("e8dfc8"))
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color("b3262e"))
			# Spy silhouette: fedora and coat collar.
			var cc := Vector2(a, -50)
			ci.draw_circle(cc, 8, Color("15151a"))
			ci.draw_rect(Rect2(cc.x - 13, cc.y - 9, 26, 3), Color("15151a"))
			ci.draw_rect(Rect2(cc.x - 7, cc.y - 17, 14, 9), Color("15151a"))
			var base := PackedVector2Array([Vector2(-14, 22), Vector2(14, 22), Vector2(8, 6), Vector2(-8, 6)])
			base = Transform2D(0.0, cc) * base
			ci.draw_colored_polygon(base, Color("15151a"))
			var words := txt.split(" ")
			for i in mini(words.size(), 3):
				var ww := font.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
				ci.draw_string(font, Vector2(a - ww / 2, r.position.y + 10), "" if i > 0 else words[0],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
			var rest := " ".join(words.slice(1))
			var rw := font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			ci.draw_string(font, Vector2(a - rw / 2, r.end.y - 4), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("b3262e"))
			return 56.0
		"fusebox":
			var r := Rect2(a - 22, -70, 44, 54)
			ci.draw_rect(r, Color("4a5260"))
			ci.draw_rect(r, Color("2b3038"), false, 2.0)
			for i in 6:
				var on := int(t * 2.5 + i * 1.3 + seed_v) % 3 != 0
				var led := (Color("4dff9a") if i % 2 == 0 else Color("ff4d4d")) if on else Color("1c2026")
				ci.draw_circle(Vector2(r.position.x + 9 + (i % 3) * 13, r.position.y + 12 + (i / 3) * 10), 2.5, led)
			ci.draw_rect(Rect2(r.position.x + 8, r.end.y - 18, 28, 8), Color("e0b10b"))
			return 44.0
	return 60.0
