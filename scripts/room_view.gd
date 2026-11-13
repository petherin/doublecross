extends Node2D
## Draws the room the local agent is standing in: walls, floor, doors and furniture.
## Everything is drawn in code for now; real art can replace each piece later.

const World = preload("res://scripts/world.gd")

var world: World
var room := Vector2i.ZERO:
	set(v):
		room = v
		queue_redraw()

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var R := World.ROOM
	var data: Dictionary = world.rooms[room]
	var tint: Color = data["tint"]
	var outer := R.grow(World.WALL)

	# Wall slab with bevel
	draw_rect(outer.grow(6), Color("0b0e13"))
	draw_rect(outer, Color("2a3240"))
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, 8)), Color("3a4456"))
	draw_rect(Rect2(outer.position.x, outer.end.y - 8, outer.size.x, 8), Color("1c222c"))
	# Rivets along the walls
	for x in range(int(outer.position.x) + 30, int(outer.end.x), 70):
		draw_circle(Vector2(x, outer.position.y + 20), 2.5, Color("4a5568"))
		draw_circle(Vector2(x, outer.end.y - 20), 2.5, Color("4a5568"))

	# Floor: dark metal plates with a subtle grid
	draw_rect(R, Color("161b22"))
	var step := 80
	for x in range(int(R.position.x), int(R.end.x), step):
		for y in range(int(R.position.y), int(R.end.y), step):
			var checker := (int((x - R.position.x) / step) + int((y - R.position.y) / step)) % 2
			if checker == 0:
				draw_rect(Rect2(x, y, step, step), Color(1, 1, 1, 0.018))
	for x in range(int(R.position.x), int(R.end.x) + 1, step):
		draw_line(Vector2(x, R.position.y), Vector2(x, R.end.y), Color(1, 1, 1, 0.045), 1.0)
	for y in range(int(R.position.y), int(R.end.y) + 1, step):
		draw_line(Vector2(R.position.x, y), Vector2(R.end.x, y), Color(1, 1, 1, 0.045), 1.0)
	# Coloured light spill from the ceiling strips
	for i in 6:
		var a := 0.05 - i * 0.008
		draw_rect(Rect2(R.position.x, R.position.y, R.size.x, 18 + i * 14), Color(tint, a))
	# Inner wall edge glow
	draw_rect(R, Color(tint, 0.55), false, 2.0)
	# Ceiling light strips on the top wall
	var pulse := 0.75 + 0.25 * sin(_t * 2.0)
	for sx in [R.position.x + 60, R.end.x - 360]:
		draw_rect(Rect2(sx, outer.position.y + 14, 300, 6), Color(tint, 0.9 * pulse))
		draw_rect(Rect2(sx - 4, outer.position.y + 10, 308, 14), Color(tint, 0.15 * pulse))

	# Doors
	for dir in [World.Dir.UP, World.Dir.DOWN, World.Dir.LEFT, World.Dir.RIGHT]:
		if world.has_door(room, dir):
			_draw_door(dir, tint)

	# Furniture (shadows first so they sit under everything)
	var items: Array = world.furniture(room)
	for f in items:
		draw_rect(Rect2((f["rect"] as Rect2).position + Vector2(6, 8), (f["rect"] as Rect2).size), Color(0, 0, 0, 0.35))
	for f in items:
		_draw_furniture(f, tint)


func _draw_door(dir: int, tint: Color) -> void:
	var R := World.ROOM
	var c := R.get_center()
	var h := World.DOOR_HALF
	var w := World.WALL
	var gap: Rect2
	var post_a: Rect2
	var post_b: Rect2
	var horizontal := dir == World.Dir.UP or dir == World.Dir.DOWN
	match dir:
		World.Dir.UP: gap = Rect2(c.x - h, R.position.y - w, h * 2, w)
		World.Dir.DOWN: gap = Rect2(c.x - h, R.end.y, h * 2, w)
		World.Dir.LEFT: gap = Rect2(R.position.x - w, c.y - h, w, h * 2)
		_: gap = Rect2(R.end.x, c.y - h, w, h * 2)
	draw_rect(gap, Color("0e1217"))
	# Open blast door panels slid into the wall
	if horizontal:
		post_a = Rect2(gap.position.x - 14, gap.position.y, 14, gap.size.y)
		post_b = Rect2(gap.end.x, gap.position.y, 14, gap.size.y)
	else:
		post_a = Rect2(gap.position.x, gap.position.y - 14, gap.size.x, 14)
		post_b = Rect2(gap.position.x, gap.end.y, gap.size.x, 14)
	for post in [post_a, post_b]:
		_hazard(post)
	# Threshold light
	var lamp := Color("5dff8a") if int(_t * 2.0) % 2 == 0 else Color("3bbf62")
	var lamp_pos := post_a.get_center()
	draw_circle(lamp_pos, 5.0, lamp)
	draw_circle(lamp_pos, 9.0, Color(lamp, 0.25))
	# Floor arrow pointing out of the room
	var arrow_dir := Vector2(World.DIR_VEC[dir])
	var base := gap.get_center() - arrow_dir * (w * 0.5 + 26)
	var side := Vector2(-arrow_dir.y, arrow_dir.x)
	draw_colored_polygon(PackedVector2Array([
		base + arrow_dir * 14, base - arrow_dir * 6 + side * 12, base - arrow_dir * 6 - side * 12,
	]), Color(tint, 0.35))


func _hazard(r: Rect2) -> void:
	draw_rect(r, Color("e0b10b"))
	var n := 6
	var horizontal := r.size.x > r.size.y
	for i in n:
		if i % 2 == 0:
			continue
		if horizontal:
			var seg := r.size.x / n
			draw_rect(Rect2(r.position.x + i * seg, r.position.y, seg, r.size.y), Color("1a1a1a"))
		else:
			var seg := r.size.y / n
			draw_rect(Rect2(r.position.x, r.position.y + i * seg, r.size.x, seg), Color("1a1a1a"))


func _draw_furniture(f: Dictionary, tint: Color) -> void:
	var r: Rect2 = f["rect"]
	var d: int = f["detail"]
	var vertical := r.size.y > r.size.x
	var inner := r.grow(-5)
	match f["type"]:
		"desk":
			_box(r, Color("3c4656"), Color("4f5d72"))
			var mon := Rect2(r.get_center() - Vector2(22, 14), Vector2(44, 28))
			draw_rect(mon, Color("0b0f14"))
			draw_rect(mon.grow(-3), Color(tint, 0.55 + 0.2 * sin(_t * 3.0 + d)))
			draw_rect(Rect2(inner.position, Vector2(18, 10)), Color("d8d2c0"))
		"console":
			_box(r, Color("22303c"), Color("2f4252"))
			var screen := Rect2(inner.position, Vector2(inner.size.x * 0.4, inner.size.y)) if not vertical else Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.4))
			draw_rect(screen, Color("05080b"))
			for i in 5:
				var yy := screen.position.y + 5 + i * (screen.size.y - 10) / 5.0
				var ww := screen.size.x * (0.3 + 0.6 * fposmod(sin(d + i * 1.7 + _t), 1.0))
				draw_line(Vector2(screen.position.x + 4, yy), Vector2(screen.position.x + 4 + ww * 0.85, yy), Color("4dff9a", 0.8), 2.0)
			var colors := [Color("ff4d4d"), Color("ffd84d"), Color("4dff9a"), Color("4dc4ff")]
			for i in 8:
				var bx := inner.position.x + inner.size.x * (0.48 + 0.065 * i) if not vertical else inner.position.x + 6 + (i % 3) * 12
				var by := inner.get_center().y + (6 if i % 2 == 0 else -6) if not vertical else inner.position.y + inner.size.y * (0.48 + 0.065 * i)
				var on := int(_t * 3.0 + i + d) % 4 != 0
				draw_circle(Vector2(bx, by), 3.5, colors[(i + d) % 4] if on else Color("333a44"))
		"cabinet":
			_box(r, Color("596273"), Color("6d7789"))
			var n := 3
			for i in range(1, n):
				if vertical:
					var x := r.position.x + r.size.x * i / n
					draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color("2d333d"), 2.0)
				else:
					var y := r.position.y + r.size.y * i / n
					draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color("2d333d"), 2.0)
			draw_rect(Rect2(r.get_center() - Vector2(8, 2), Vector2(16, 4)), Color("c7ccd6"))
		"locker":
			_box(r, Color("2f5e4e"), Color("3b7462"))
			var n := 3
			for i in range(1, n):
				if vertical:
					var y := r.position.y + r.size.y * i / n
					draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("173028"), 3.0)
				else:
					var x := r.position.x + r.size.x * i / n
					draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("173028"), 3.0)
		"crate":
			_box(r, Color("5a5233"), Color("6e6540"))
			draw_line(inner.position, inner.end, Color("3b351f"), 5.0)
			draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), Color("3b351f"), 5.0)
			draw_rect(inner, Color("3b351f"), false, 3.0)
			_text_center("CLASSIFIED" if d % 2 == 0 else "TOP SECRET", r.get_center(), 9, Color("e8463a", 0.85))
		"shelf":
			_box(r, Color("3a2e26"), Color("4a3c32"))
			var palette := [Color("c0392b"), Color("2980b9"), Color("f1c40f"), Color("27ae60"), Color("ecf0f1"), Color("8e44ad")]
			var count := int((r.size.y if vertical else r.size.x) / 14)
			for i in count:
				var col: Color = palette[(i * 7 + d) % palette.size()]
				if vertical:
					draw_rect(Rect2(inner.position.x, inner.position.y + i * 14, inner.size.x, 11), col.darkened(0.2))
				else:
					draw_rect(Rect2(inner.position.x + i * 14, inner.position.y, 11, inner.size.y), col.darkened(0.2))
		"safe":
			_box(r, Color("2b2f36"), Color("3a3f48"))
			var c := r.get_center()
			draw_circle(c, 15.0, Color("9aa3b0"))
			draw_circle(c, 11.0, Color("50575f"))
			draw_line(c, c + Vector2.from_angle(d * 0.37) * 10.0, Color("e6e9ee"), 2.0)
		"plant":
			draw_circle(r.get_center(), r.size.x * 0.32, Color("6b4a33"))
			for i in 6:
				var a := i * TAU / 6.0 + d * 0.1
				draw_circle(r.get_center() + Vector2.from_angle(a) * 12.0, 12.0, Color("2f8f46"))
			draw_circle(r.get_center(), 10.0, Color("3fae58"))
		"rack":
			_box(r, Color("1f2329"), Color("2a2f37"))
			var n := 4
			for i in n:
				var t := (i + 0.5) / n
				if vertical:
					var y := r.position.y + r.size.y * t
					draw_line(Vector2(inner.position.x + 2, y), Vector2(inner.end.x - 2, y), Color("8e98a6"), 4.0)
				else:
					var x := r.position.x + r.size.x * t
					draw_line(Vector2(x, inner.position.y + 2), Vector2(x, inner.end.y - 2), Color("8e98a6"), 4.0)
		"sofa":
			_box(r, Color("5c1f2a"), Color("7a2b39"))
			var cushions := 3
			for i in cushions:
				var cr: Rect2
				if vertical:
					cr = Rect2(inner.position.x + 8, inner.position.y + i * inner.size.y / cushions + 3, inner.size.x - 10, inner.size.y / cushions - 6)
				else:
					cr = Rect2(inner.position.x + i * inner.size.x / cushions + 3, inner.position.y + 8, inner.size.x / cushions - 6, inner.size.y - 10)
				draw_rect(cr, Color("8f3545"))
		_:
			_box(r, Color("444"), Color("555"))


func _box(r: Rect2, body: Color, top: Color) -> void:
	draw_rect(r, body.darkened(0.35))
	draw_rect(r.grow(-3), body)
	draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 4)), top)


func _text_center(text: String, at: Vector2, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, at + Vector2(-w / 2, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
