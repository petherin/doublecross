extends Node2D
## Isometric renderer for the room the local agent is standing in.
## Draw order: floor -> back walls -> furniture & agents (depth sorted) -> front ledges.
## Everything is drawn in code for now; real art can replace each piece later.

const World = preload("res://scripts/world.gd")
const Icons = preload("res://scripts/icons.gd")
const Art = preload("res://scripts/art.gd")
const Style = preload("res://scripts/style.gd")
const LightLayer = preload("res://scripts/light_layer.gd")
const RoomLights = preload("res://scripts/room_lights.gd")
const POSTERS := ["TRUST NO ONE", "WALLS HAVE EARS", "SHRED AFTER READING", "LOOK BUSY"]
const SIGNS := ["RESTRICTED", "AUTHORISED ONLY", "NO ENTRY", "DANGER: HIGH VOLTAGE"]

const DOOR_TOP := 82.0
const LEDGE_H := 16.0
const HEIGHTS := {
	"desk": 40.0, "console": 52.0, "cabinet": 72.0, "locker": 120.0, "crate": 58.0,
	"shelf": 112.0, "safe": 62.0, "plant": 24.0, "rack": 100.0, "sofa": 24.0,
}

var world: World
var room := Vector2i.ZERO:
	set(v):
		room = v
		if lights and world:
			lights.rebuild(world, room)
		queue_redraw()
var lights: RoomLights
## Agents to draw; only those in `room` are shown.
var agents: Array = []
## Index of the furniture the local agent can search right now (-1 = none).
var highlight := -1
var highlight_color := Color.WHITE
## Index of the vent the local agent is standing at (-1 = none).
var vent_highlight := -1
var my_id := 1
## Traps the local player has set: furniture/doorway key -> trap kind.
var my_traps := {}
## Darts in flight (shared with the game): { owner, room, pos, vel, live }
var darts: Array = []
## Trap explosions etc: { kind, room, pos, t }
var _effects: Array = []

var _t := 0.0


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Smooth down-scaling of the agent sprite sheets (they're rendered large).
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lights = RoomLights.new()
	add_child(lights)
	var glow := LightLayer.new()
	glow.view = self
	add_child(glow)


## Affine transforms for drawing "flat" in the isometric world:
## floor space uses floor coordinates; wall space uses (along the wall, -height).
func _floor_xf() -> Transform2D:
	var k := World.ISO_K
	return Transform2D(Vector2(k, k * 0.5), Vector2(-k, k * 0.5), World.iso(Vector2.ZERO))


func _up_wall_xf() -> Transform2D:
	var k := World.ISO_K
	return Transform2D(Vector2(k, k * 0.5), Vector2(0, 1), World.iso(Vector2(0, World.ROOM.position.y)))


func _left_wall_xf() -> Transform2D:
	var k := World.ISO_K
	return Transform2D(Vector2(-k, k * 0.5), Vector2(0, 1), World.iso(Vector2(World.ROOM.position.x, 0)))


func _process(delta: float) -> void:
	_t += delta
	for e in _effects:
		e["t"] += delta
	_effects = _effects.filter(func(e): return e["t"] < _life(e["kind"]))
	queue_redraw()


static func _life(kind: String) -> float:
	match kind:
		"BOMB": return 3.2
		"HIT": return 0.5
		"PUFF": return 0.7
		_: return 1.6


func add_effect(kind: String, effect_room: Vector2i, pos: Vector2) -> void:
	_effects.append({"kind": kind, "room": effect_room, "pos": pos, "t": 0.0})
	if effect_room == room and lights:
		if kind == "BOMB":
			lights.flash(pos, Color(1.0, 0.55, 0.2), 2.2)
		elif kind == "DOWN":
			lights.flash(pos, Color(1.0, 0.9, 0.6), 1.0)


static func P(x: float, y: float, z := 0.0) -> Vector2:
	return World.iso(Vector2(x, y), z)


func _draw() -> void:
	if world == null:
		return
	var R := World.ROOM
	var tint: Color = world.rooms[room]["tint"]
	_draw_floor(R, tint)
	for e in _effects:
		if e["room"] == room and e["kind"] == "BOMB":
			_draw_scorch(e)
	_draw_back_walls(R, tint)

	# Depth sorting. Furniture is sorted among itself, then each agent is
	# slotted in just after the last piece of furniture it stands in front of.
	var things := []
	var items: Array = world.furniture(room)
	for i in items.size():
		things.append({"rect": items[i]["rect"], "f": items[i], "i": i})
	things.sort_custom(_box_behind)
	var here := agents.filter(func(a): return a.room == room)
	here.sort_custom(func(a, b): return a.position.x + a.position.y < b.position.x + b.position.y)
	for a in here:
		var slot := 0
		for j in things.size():
			if things[j].has("f") and _agent_in_front(a.position, things[j]["rect"]):
				slot = j + 1
		things.insert(slot, {"agent": a})
	for t in things:
		if t.has("agent"):
			t["agent"].paint(self)
		else:
			_draw_furniture(t["f"], tint)
			if t["i"] == highlight:
				_draw_highlight(t["f"])
			var tk := World.furniture_key(room, t["i"])
			if my_traps.has(tk):
				_draw_trap_marker(t["f"], my_traps[tk])

	for d in darts:
		if d["room"] == room:
			_draw_dart(d)
	_draw_front_ledges(R, tint)
	_draw_my_tripwires()
	for e in _effects:
		if e["room"] == room:
			_draw_effect(e)


## An agent standing at floor point `p` is in front of a box if it's past the
## box's front-left face (larger y) or its front-right face (larger x).
static func _agent_in_front(p: Vector2, r: Rect2) -> bool:
	return p.x >= r.end.x or p.y >= r.end.y


## Sort comparator for furniture: true when box `a` should be drawn before `b`.
static func _box_behind(a: Dictionary, b: Dictionary) -> bool:
	var ra: Rect2 = a["rect"]
	var rb: Rect2 = b["rect"]
	var b_front := rb.position.x >= ra.end.x or rb.position.y >= ra.end.y
	var a_front := ra.position.x >= rb.end.x or ra.position.y >= rb.end.y
	if b_front != a_front:
		return b_front
	return ra.get_center().x + ra.get_center().y < rb.get_center().x + rb.get_center().y


# ---------------------------------------------------------------- floor

func _draw_floor(R: Rect2, tint: Color) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var x1 := R.end.x
	var y1 := R.end.y
	var font := ThemeDB.fallback_font
	draw_set_transform_matrix(_floor_xf())
	# Steel tread plate, tinted a touch by the room's lighting.
	draw_texture_rect(Art.floor_tex(), R, true, Color(0.95, 0.97, 1.0).lerp(tint, 0.08))
	# Room name stencilled on the floor.
	var name_text: String = world.rooms[room]["name"].to_upper()
	draw_string(Style.stencil(), Vector2(x0 + 70, y1 - 70), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1, 1, 1, 0.05))
	# Hazard stripes on the threshold of each doorway.
	var rc := R.get_center()
	var door_half := World.DOOR_HALF
	for dir in World.DIR_VEC:
		if world.opening(room, dir) == 0:
			continue
		var v := Vector2(World.DIR_VEC[dir])
		var side := Vector2(-v.y, v.x)
		var mid := rc + v * (R.size / 2.0 - Vector2(18, 18))
		for i in 8:
			var a := mid + side * (-door_half + 6 + i * (door_half * 2 - 12) / 8.0)
			var stripe := PackedVector2Array([a - v * 14, a - v * 14 + side * 9, a + v * 14 + side * 15, a + v * 14 + side * 6])
			draw_colored_polygon(stripe, Color(0.88, 0.69, 0.04, 0.35) if i % 2 == 0 else Color(0, 0, 0, 0.25))
	# Darkening where the floor meets the back walls.
	var ao := Color(0, 0, 0, 0.5)
	var clear := Color(0, 0, 0, 0)
	draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y0 + 80), Vector2(x0, y0 + 80)]),
		PackedColorArray([ao, ao, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + 80, y0), Vector2(x0 + 80, y1), Vector2(x0, y1)]),
		PackedColorArray([ao, clear, clear, ao]))
	# Soft shadows under the furniture.
	var soft := Art.soft()
	for f in world.furniture(room):
		var r: Rect2 = f["rect"]
		draw_texture_rect(soft, Rect2(r.position + Vector2(-10, -10), r.size + Vector2(44, 44)), false, Color(0, 0, 0, 0.65))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Daylight spilling in from the exit
	for dir in [World.Dir.UP, World.Dir.LEFT]:
		if world.is_exit(room, dir):
			var c := R.get_center()
			var dh := World.DOOR_HALF
			for i in 4:
				var depth := 40.0 + i * 35.0
				var spread := dh + i * 18.0
				var col := Color(1.0, 0.93, 0.7, 0.07)
				if dir == World.Dir.UP:
					_quad(P(c.x - dh, y0), P(c.x + dh, y0), P(c.x + spread, y0 + depth), P(c.x - spread, y0 + depth), col)
				else:
					_quad(P(x0, c.y - dh), P(x0, c.y + dh), P(x0 + depth, c.y + spread), P(x0 + depth, c.y - spread), col)
	# Floor arrows towards each door
	for dir in [World.Dir.UP, World.Dir.DOWN, World.Dir.LEFT, World.Dir.RIGHT]:
		match world.opening(room, dir):
			1: _floor_arrow(dir, tint)
			2: _floor_arrow(dir, Color("5dff8a"))


func _floor_arrow(dir: int, tint: Color) -> void:
	var R := World.ROOM
	var c := R.get_center()
	var v := Vector2(World.DIR_VEC[dir])
	var base := c + v * Vector2(R.size.x * 0.5 - 50, R.size.y * 0.5 - 50)
	var side := Vector2(-v.y, v.x)
	var tip := base + v * 22
	var l := base - v * 10 + side * 20
	var r := base - v * 10 - side * 20
	draw_colored_polygon(PackedVector2Array([World.iso(tip), World.iso(l), World.iso(r)]), Color(tint, 0.4))


# ---------------------------------------------------------------- walls

func _draw_back_walls(R: Rect2, tint: Color) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var x1 := R.end.x
	var y1 := R.end.y
	var c := R.get_center()
	var h := World.WALL_H
	var dh := World.DOOR_HALF
	var col_up := Color("2c3443")   # faces down-left, catches the light
	var col_left := Color("222935")
	# UP wall runs along x at y = y0 (upper-right on screen)
	var up_kind := world.opening(room, World.Dir.UP)
	var up_door := up_kind != 0
	var up_spans := [[x0, c.x - dh], [c.x + dh, x1]] if up_door else [[x0, x1]]
	_textured_wall(_up_wall_xf(), up_spans, Color(1.0, 1.0, 1.05).lerp(tint, 0.06))
	# LEFT wall runs along y at x = x0 (upper-left on screen)
	var left_kind := world.opening(room, World.Dir.LEFT)
	var left_door := left_kind != 0
	var left_spans := [[y0, c.y - dh], [c.y + dh, y1]] if left_door else [[y0, y1]]
	_textured_wall(_left_wall_xf(), left_spans, Color(0.72, 0.74, 0.8).lerp(tint, 0.05))
	# Lintels and doorways
	if up_door:
		_quad(P(c.x - dh, y0, DOOR_TOP), P(c.x + dh, y0, DOOR_TOP), P(c.x + dh, y0, h), P(c.x - dh, y0, h), col_up.darkened(0.1))
		_doorway(P(c.x - dh, y0), P(c.x + dh, y0), up_kind == 2)
	if left_door:
		_quad(P(x0, c.y - dh, DOOR_TOP), P(x0, c.y + dh, DOOR_TOP), P(x0, c.y + dh, h), P(x0, c.y - dh, h), col_left.darkened(0.1))
		_doorway(P(x0, c.y - dh), P(x0, c.y + dh), left_kind == 2)
	# Wall panels, light strips and skirting
	var pulse := 0.75 + 0.25 * sin(_t * 2.0)
	for s in up_spans:
		_wall_details(Vector2(s[0], y0), Vector2(s[1], y0), tint, pulse)
	for s in left_spans:
		_wall_details(Vector2(x0, s[0]), Vector2(x0, s[1]), tint, pulse)
	_draw_decor(_up_wall_xf(), up_spans, tint, 0)
	_draw_decor(_left_wall_xf(), left_spans, tint, 1)
	for i in world.vents.size():
		if world.vents[i]["room"] == room:
			_draw_vent(i)
	# Top caps (wall thickness) and the corner post
	var cap := Color("3d4759")
	var t := 14.0
	_quad(P(x0, y0, h), P(x1, y0, h), P(x1, y0 - t, h), P(x0 - t, y0 - t, h), cap)
	_quad(P(x0, y0, h), P(x0 - t, y0 - t, h), P(x0 - t, y1, h), P(x0, y1, h), cap.darkened(0.1))
	draw_line(P(x0, y0, 0), P(x0, y0, h), Color(0, 0, 0, 0.4), 2.0)


func _textured_wall(xf: Transform2D, spans: Array, modulate_col: Color) -> void:
	var h := World.WALL_H
	draw_set_transform_matrix(xf)
	for sp in spans:
		var r := Rect2(sp[0], -h, sp[1] - sp[0], h)
		draw_texture_rect(Art.wall_tex(), r, true, modulate_col)
		# Grime and shadow at the base, a little light at the top.
		draw_polygon(PackedVector2Array([Vector2(r.position.x, -34), Vector2(r.end.x, -34), Vector2(r.end.x, 0), Vector2(r.position.x, 0)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45)]))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Things hung on the back walls: screens, maps, clocks, vents, signs, posters.
## Chosen per room from the world seed, so both tablets see the same decor.
func _draw_decor(xf: Transform2D, spans: Array, tint: Color, wall: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world.seed_value, room, wall])
	var font := ThemeDB.fallback_font
	draw_set_transform_matrix(xf)
	for sp in spans:
		var a: float = sp[0] + 95.0
		while a < sp[1] - 70.0:
			if rng.randf() < 0.6:
				var kind: String = ["monitor", "monitor", "map", "clock", "map", "sign", "poster", "fusebox"][rng.randi_range(0, 7)]
				var w := _decor(kind, a, tint, rng.randi(), font)
				a += w + 50.0
			else:
				a += 120.0
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Draws one decoration centred at `a` along the wall; returns its width.
func _decor(kind: String, a: float, tint: Color, seed_v: int, font: Font) -> float:
	match kind:
		"monitor":
			var r := Rect2(a - 38, -76, 76, 48)
			draw_rect(r, Color("0a0d12"))
			draw_rect(r, Color("3a4456"), false, 2.0)
			var sc := r.grow(-5)
			draw_rect(sc, tint.darkened(0.82))
			if seed_v % 2 == 0:
				# Scrolling signal trace.
				var pts := PackedVector2Array()
				for i in 25:
					var x := sc.position.x + i * sc.size.x / 24.0
					pts.append(Vector2(x, sc.get_center().y + sin(i * 0.7 + _t * 4.0 + seed_v) * 8.0 * sin(i * 0.23 + _t)))
				draw_polyline(pts, tint.lightened(0.4), 1.5, true)
			else:
				# Radar sweep with blips.
				var cc := sc.get_center()
				draw_arc(cc, 15, 0, TAU, 24, Color(tint.lightened(0.3), 0.6), 1.0)
				draw_arc(cc, 8, 0, TAU, 16, Color(tint.lightened(0.3), 0.4), 1.0)
				var ang := _t * 2.0 + seed_v
				draw_line(cc, cc + Vector2.from_angle(ang) * 15, tint.lightened(0.5), 1.5)
				for b in 3:
					var bp := cc + Vector2.from_angle(seed_v * 0.7 + b * 2.1) * (5 + b * 4)
					var fade := fposmod(ang - (seed_v * 0.7 + b * 2.1), TAU) / TAU
					draw_circle(bp, 1.6, Color(1, 0.4, 0.4, 1.0 - fade))
			return 76.0
		"map":
			var r := Rect2(a - 62, -78, 124, 58)
			draw_rect(r, Color("0d2236"))
			draw_rect(r, Color("8a6a3a"), false, 3.0)
			for i in 5:
				draw_line(Vector2(r.position.x + i * r.size.x / 4.0, r.position.y), Vector2(r.position.x + i * r.size.x / 4.0, r.end.y), Color(1, 1, 1, 0.06), 1.0)
			var land := Color("2e6b57")
			for blob in [[-38, -58, 10], [-30, -50, 8], [-20, -40, 6], [-2, -60, 9], [4, -50, 8], [10, -40, 7], [30, -58, 11], [40, -50, 9], [44, -34, 6]]:
				draw_circle(Vector2(a + blob[0], blob[1]), blob[2], land)
			for i in 3:
				var dot := Vector2(a - 40 + ((seed_v >> (i * 4)) % 80), -64 + ((seed_v >> (i * 3)) % 30))
				if int(_t * 2.0 + i) % 2 == 0:
					draw_circle(dot, 2.2, Color("ff4d4d"))
			return 124.0
		"clock":
			var cc := Vector2(a, -58)
			draw_circle(cc, 18, Color("2b2f36"))
			draw_circle(cc, 15, Color("e6e2d3"))
			for i in 12:
				draw_line(cc + Vector2.from_angle(i * TAU / 12.0) * 12, cc + Vector2.from_angle(i * TAU / 12.0) * 14, Color("2b2f36"), 1.0)
			var tm := Time.get_time_dict_from_system()
			var mins: float = tm["minute"] + tm["second"] / 60.0
			var hrs: float = (tm["hour"] % 12) + mins / 60.0
			draw_line(cc, cc + Vector2.from_angle(hrs / 12.0 * TAU - PI / 2) * 8, Color("15151a"), 2.0)
			draw_line(cc, cc + Vector2.from_angle(mins / 60.0 * TAU - PI / 2) * 12, Color("15151a"), 1.5)
			draw_line(cc, cc + Vector2.from_angle(tm["second"] / 60.0 * TAU - PI / 2) * 13, Color("d32f2f"), 1.0)
			return 40.0
		"vent":
			var r := Rect2(a - 26, -44, 52, 32)
			draw_rect(r, Color("0d1015"))
			draw_rect(r, Color("4a5568"), false, 2.0)
			for i in 6:
				var y := r.position.y + 4 + i * 4.6
				draw_line(Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), Color("3a4456"), 2.0)
			return 52.0
		"sign":
			var txt: String = SIGNS[seed_v % SIGNS.size()]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18
			var r := Rect2(a - w / 2, -70, w, 24)
			draw_rect(r, Color("e0b10b"))
			draw_rect(r.grow(-2), Color("15151a"), false, 1.5)
			draw_string(font, Vector2(r.position.x + 9, r.end.y - 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("15151a"))
			return w
		"poster":
			var txt: String = POSTERS[seed_v % POSTERS.size()]
			var r := Rect2(a - 28, -84, 56, 70)
			draw_rect(r, Color("e8dfc8"))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color("b3262e"))
			# Spy silhouette: fedora and coat collar.
			var cc := Vector2(a, -50)
			draw_circle(cc, 8, Color("15151a"))
			draw_rect(Rect2(cc.x - 13, cc.y - 9, 26, 3), Color("15151a"))
			draw_rect(Rect2(cc.x - 7, cc.y - 17, 14, 9), Color("15151a"))
			draw_colored_polygon(PackedVector2Array([cc + Vector2(-14, 22), cc + Vector2(14, 22), cc + Vector2(8, 6), cc + Vector2(-8, 6)]), Color("15151a"))
			var words := txt.split(" ")
			for i in mini(words.size(), 3):
				var ww := font.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
				draw_string(font, Vector2(a - ww / 2, r.position.y + 10 + (i * 0)), "" if i > 0 else words[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
			var rest := " ".join(words.slice(1))
			var rw := font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(font, Vector2(a - rw / 2, r.end.y - 4), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("b3262e"))
			return 56.0
		"fusebox":
			var r := Rect2(a - 22, -70, 44, 54)
			draw_rect(r, Color("4a5260"))
			draw_rect(r, Color("2b3038"), false, 2.0)
			for i in 6:
				var on := int(_t * 2.5 + i * 1.3 + seed_v) % 3 != 0
				draw_circle(Vector2(r.position.x + 9 + (i % 3) * 13, r.position.y + 12 + (i / 3) * 10), 2.5, (Color("4dff9a") if i % 2 == 0 else Color("ff4d4d")) if on else Color("1c2026"))
			draw_rect(Rect2(r.position.x + 8, r.end.y - 18, 28, 8), Color("e0b10b"))
			return 44.0
	return 60.0


## A crawl-through air vent at floor level in a back wall.
func _draw_vent(i: int) -> void:
	var v: Dictionary = world.vents[i]
	var xf := _up_wall_xf() if v["dir"] == World.Dir.UP else _left_wall_xf()
	draw_set_transform_matrix(xf)
	var a: float = v["along"]
	var h := World.VENT_HALF
	var outer := Rect2(a - h - 6, -56, h * 2 + 12, 52)
	var inner := outer.grow(-6)
	draw_rect(outer, Color("2b3038"))
	draw_rect(outer, Color("596273"), false, 2.0)
	draw_rect(inner, Color("06080b"))
	# Slats, angled down.
	for k in 6:
		var y := inner.position.y + 4 + k * (inner.size.y - 8) / 5.0
		draw_line(Vector2(inner.position.x + 2, y - 2), Vector2(inner.end.x - 2, y + 2), Color("4a5260"), 3.0)
	for corner in [outer.position + Vector2(4, 4), Vector2(outer.end.x - 4, outer.position.y + 4),
			Vector2(outer.position.x + 4, outer.end.y - 4), outer.end - Vector2(4, 4)]:
		draw_circle(corner, 2.0, Color("9aa3b0"))
	if i == vent_highlight:
		var pulse := 0.55 + 0.45 * sin(_t * 6.0)
		draw_rect(outer.grow(4), Color(1.0, 0.86, 0.15, pulse), false, 3.0)
		# A little arrow pointing in.
		var tip := Vector2(a, outer.position.y - 10)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9, -14), tip + Vector2(9, -14)]), Color(1.0, 0.86, 0.15, pulse))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _wall_details(a: Vector2, b: Vector2, tint: Color, pulse: float) -> void:
	var len := a.distance_to(b)
	if len < 40:
		return
	var dir := (b - a) / len
	# Skirting stripe
	_quad(World.iso(a, 0), World.iso(b, 0), World.iso(b, 8), World.iso(a, 8), Color(0, 0, 0, 0.3))
	# Recessed panels
	var n := int(len / 120.0)
	for i in n:
		var pa := a + dir * (i * len / n + 12)
		var pb := a + dir * ((i + 1) * len / n - 12)
		_quad_outline(World.iso(pa, 18), World.iso(pb, 18), World.iso(pb, 70), World.iso(pa, 70), Color(1, 1, 1, 0.06))
	# Glowing light strip
	var la := a + dir * 16
	var lb := b - dir * 16
	_quad(World.iso(la, 86), World.iso(lb, 86), World.iso(lb, 92), World.iso(la, 92), Color(tint, 0.85 * pulse))
	_quad(World.iso(la, 80), World.iso(lb, 80), World.iso(lb, 98), World.iso(la, 98), Color(tint, 0.12 * pulse))


## A doorway cut into a back wall, from floor point `a` to floor point `b`
## (already projected). The exit glows with daylight and has a sign.
func _doorway(a: Vector2, b: Vector2, is_exit: bool) -> void:
	var top_a := a - Vector2(0, DOOR_TOP)
	var top_b := b - Vector2(0, DOOR_TOP)
	if not is_exit:
		_quad(a, b, top_b, top_a, Color("07090c"))
		_door_frame(a, b)
		return
	var glow := 0.85 + 0.15 * sin(_t * 3.0)
	_quad(a, b, top_b, top_a, Color("fff6d8"))
	for i in 4:
		var f := (i + 1) / 5.0
		_quad(a.lerp(top_a, f), b.lerp(top_b, f), top_b, top_a, Color("ffe7a3", 0.25))
	for p: Vector2 in [a, b]:
		draw_rect(Rect2(p.x - 4, p.y - DOOR_TOP, 8, DOOR_TOP), Color("2e7d32"))
	var mid := (top_a + top_b) / 2 - Vector2(0, 16)
	draw_rect(Rect2(mid - Vector2(34, 13), Vector2(68, 26)), Color("1b5e20"))
	draw_rect(Rect2(mid - Vector2(34, 13), Vector2(68, 26)), Color("5dff8a", glow), false, 2.0)
	var font := ThemeDB.fallback_font
	var w := font.get_string_size("EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, mid + Vector2(-w / 2, 7), "EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("eaffea"))


## A small reminder of where you've hidden a trap (only you see it).
func _draw_trap_marker(f: Dictionary, kind: String) -> void:
	var r: Rect2 = f["rect"]
	var h: float = HEIGHTS.get(f["type"], 50.0)
	var p := World.iso(r.get_center(), h + 8)
	draw_circle(p, 11.0, Color(0, 0, 0, 0.5))
	draw_arc(p, 11.0, 0, TAU, 20, Color(highlight_color, 0.8), 2.0, true)
	Icons.draw(self, kind, p, 16.0, true)


func _draw_my_tripwires() -> void:
	var R := World.ROOM
	var c := R.get_center()
	var dh := World.DOOR_HALF
	for dir in World.DIR_VEC:
		if world.opening(room, dir) != 1 or not my_traps.has(World.door_key(room, dir)):
			continue
		var v := Vector2(World.DIR_VEC[dir])
		var mid := c + v * R.size / 2.0
		var side := Vector2(-v.y, v.x) * dh
		var a := World.iso(mid - side, 10.0)
		var b := World.iso(mid + side, 10.0)
		draw_line(a, b, Color(highlight_color, 0.6 + 0.3 * sin(_t * 5.0)), 2.0, true)
		draw_circle(a, 3.0, highlight_color)
		draw_circle(b, 3.0, highlight_color)


func _draw_dart(d: Dictionary) -> void:
	var p: Vector2 = d["pos"]
	var v: Vector2 = (d["vel"] as Vector2).normalized()
	var head := World.iso(p, 50.0)
	var tail := World.iso(p - v * 26.0, 50.0)
	draw_line(World.iso(p - v * 60.0, 50.0), tail, Color(1, 1, 1, 0.18), 3.0, true)
	draw_line(tail, head, Color("c7ccd6"), 3.0, true)
	draw_circle(tail, 3.5, Color("ff5a5f"))
	draw_circle(World.iso(p, 0.0), 4.0, Color(0, 0, 0, 0.3))


func _draw_effect(e: Dictionary) -> void:
	var t: float = e["t"]
	var p := World.iso(e["pos"], 40.0)
	var font := Style.stencil()
	var word := "TWANG!"
	var col := Color("eef1f5")
	match e["kind"]:
		"PUFF":
			# Dust kicked out of a vent.
			var k := t / 0.7
			for i in 10:
				var ang := i * 2.4
				var q := World.iso(e["pos"], 20.0 + 30.0 * k) + Vector2(cos(ang), sin(ang) * 0.5) * (12.0 + 40.0 * k)
				draw_circle(q, 8.0 + 10.0 * k, Color(0.6, 0.58, 0.55, 0.45 * (1.0 - k)))
			return
		"HIT":
			# Quick impact burst.
			var k := t / 0.5
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(p + Vector2.from_angle(a) * (12.0 + 30.0 * k), p + Vector2.from_angle(a) * (20.0 + 44.0 * k), Color(1, 0.9, 0.4, 1.0 - k), 3.0, true)
			return
		"DOWN":
			word = "WHAM!"
			col = Color("ff5a5f")
			var k := minf(1.0, t * 5.0)
			var pts := PackedVector2Array()
			for i in 16:
				var r := (60.0 if i % 2 == 0 else 30.0) * k
				pts.append(p + Vector2.from_angle(i * TAU / 16.0) * r)
			draw_colored_polygon(pts, Color(1, 0.85, 0.2, clampf(1.6 - t, 0.0, 1.0) * 0.8))
		"BOMB":
			word = "KABOOM!"
			col = Color("ffb13b")
			_draw_explosion(e)
		"SPRING":
			word = "BOING!"
			col = Color("ffd23f")
			var base := World.iso(e["pos"])
			var coil := PackedVector2Array()
			var hgt := minf(1.0, t * 5.0) * 70.0
			for i in 11:
				coil.append(base + Vector2(10 if i % 2 == 0 else -10, -i * hgt / 10.0))
			draw_polyline(coil, Color("c7ccd6"), 3.0, true)
	# Comic-book word that pops and floats up
	var size := int(40 + 20 * minf(1.0, t * 8.0))
	var a := clampf(_life(e["kind"]) - 0.4 - t, 0.0, 1.0)
	if e["kind"] == "BOMB":
		size = int(52 + 26 * minf(1.0, t * 8.0))
		p.y -= 50.0
	var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := p + Vector2(-w / 2, -60 - t * 40)
	draw_string_outline(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Color(0, 0, 0, a))
	draw_string(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, a))


## A fiery, smoky blast: flash, fireball, flying sparks, then rolling smoke.
func _draw_explosion(e: Dictionary) -> void:
	var t: float = e["t"]
	var ground := World.iso(e["pos"])
	var c := World.iso(e["pos"], 45.0)
	var seed_v := int(e["pos"].x * 7.0 + e["pos"].y * 13.0)
	# 1) White-hot flash
	if t < 0.18:
		var f := t / 0.18
		draw_circle(c, 40.0 + f * 120.0, Color(1.0, 0.97, 0.8, 0.85 * (1.0 - f)))
	# 2) Sparks and debris flying out
	if t < 0.9:
		for i in 16:
			var ang := i * TAU / 16.0 + float((seed_v + i * 31) % 10) * 0.05
			var spd := 160.0 + float((seed_v + i * 17) % 90)
			var d := spd * t
			var start := c + Vector2(cos(ang), sin(ang) * 0.7) * d
			var tail := c + Vector2(cos(ang), sin(ang) * 0.7) * maxf(0.0, d - 22.0)
			var fall := Vector2(0, 160.0 * t * t)
			draw_line(tail + fall, start + fall, Color(1.0, 0.75, 0.25, 1.0 - t / 0.9), 3.0, true)
	# 3) Smoke: dark puffs that billow up and spread out
	if t > 0.12:
		var st := t - 0.12
		for i in 22:
			var k := float((seed_v + i * 53) % 100) / 100.0
			var born := k * 0.35
			if st < born:
				continue
			var age := st - born
			var drift := Vector2((k - 0.5) * 120.0 + sin(age * 2.0 + i) * 14.0, -40.0 - age * (55.0 + k * 40.0))
			var r := 18.0 + age * 26.0 + k * 10.0
			var a := clampf(1.0 - age / 2.7, 0.0, 1.0) * 0.75
			var grey := 0.1 + k * 0.16
			draw_circle(c + drift, r, Color(grey, grey * 0.96, grey * 0.93, a))
	# 4) Fireball: layered, flickering, swelling then collapsing into the smoke
	if t < 0.75:
		var grow := minf(1.0, t / 0.12)
		var fade := 1.0 - clampf((t - 0.25) / 0.5, 0.0, 1.0)
		var layers := [[Color("ff3b1f"), 1.0], [Color("ff7a1a"), 0.78], [Color("ffb13b"), 0.55], [Color("fff1a8"), 0.3]]
		for li in layers.size():
			var lc: Color = layers[li][0]
			var lr: float = layers[li][1]
			for j in 7:
				var ang := j * TAU / 7.0 + t * 3.0 + li
				var wob := 0.75 + 0.25 * sin(t * 40.0 + j * 2.1 + li)
				var off := Vector2(cos(ang), sin(ang) * 0.75) * 34.0 * lr * grow
				draw_circle(c + off - Vector2(0, t * 30.0), 46.0 * lr * grow * wob, Color(lc, fade))
	# 5) Ground glow
	if t < 0.6:
		draw_set_transform(ground, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 110.0, Color(1.0, 0.5, 0.15, 0.35 * (1.0 - t / 0.6)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Black scorch mark left on the floor by a bomb (fades with the smoke).
func _draw_scorch(e: Dictionary) -> void:
	var t: float = e["t"]
	var a := clampf(minf(t * 6.0, (3.2 - t) / 1.2), 0.0, 1.0)
	var g := World.iso(e["pos"])
	draw_set_transform(g, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 70.0, Color(0.05, 0.04, 0.03, 0.55 * a))
	for i in 9:
		var ang := i * TAU / 9.0
		draw_line(Vector2.from_angle(ang) * 50.0, Vector2.from_angle(ang) * 95.0, Color(0.05, 0.04, 0.03, 0.4 * a), 7.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Pulsing outline round the furniture you can search, plus a magnifier.
func _draw_highlight(f: Dictionary) -> void:
	var r: Rect2 = f["rect"].grow(4)
	var h: float = HEIGHTS.get(f["type"], 50.0) + (20.0 if f["type"] == "plant" else 0.0)
	var a := 0.55 + 0.45 * sin(_t * 6.0)
	var col := Color(highlight_color, a)
	var top := PackedVector2Array([
		P(r.position.x, r.position.y, h), P(r.end.x, r.position.y, h),
		P(r.end.x, r.end.y, h), P(r.position.x, r.end.y, h), P(r.position.x, r.position.y, h)])
	draw_polyline(top, col, 3.0, true)
	draw_polyline(PackedVector2Array([P(r.position.x, r.end.y, 0), P(r.end.x, r.end.y, 0), P(r.end.x, r.position.y, 0)]), col, 3.0, true)
	draw_line(P(r.position.x, r.end.y, 0), P(r.position.x, r.end.y, h), col, 3.0)
	draw_line(P(r.end.x, r.end.y, 0), P(r.end.x, r.end.y, h), col, 3.0)
	draw_line(P(r.end.x, r.position.y, 0), P(r.end.x, r.position.y, h), col, 3.0)
	var above := World.iso(r.get_center(), h + 34 + 4 * sin(_t * 4.0))
	draw_circle(above, 15.0, Color(0, 0, 0, 0.55))
	Icons.magnifier(self, above, 26.0, Color.WHITE)


func _door_frame(a: Vector2, b: Vector2) -> void:
	for p: Vector2 in [a, b]:
		var w := 6.0
		var top: Vector2 = p - Vector2(0, DOOR_TOP)
		draw_rect(Rect2(p.x - w / 2, top.y, w, DOOR_TOP), Color("e0b10b"))
		for i in 6:
			if i % 2 == 1:
				draw_rect(Rect2(p.x - w / 2, top.y + i * DOOR_TOP / 6.0, w, DOOR_TOP / 6.0), Color("1a1a1a"))
	var lamp := Color("5dff8a") if int(_t * 2.0) % 2 == 0 else Color("3bbf62")
	var mid := (a + b) / 2 - Vector2(0, DOOR_TOP + 10)
	draw_circle(mid, 4.0, lamp)
	draw_circle(mid, 8.0, Color(lamp, 0.25))


func _draw_front_ledges(R: Rect2, tint: Color) -> void:
	var x0 := R.position.x
	var y0 := R.position.y
	var x1 := R.end.x
	var y1 := R.end.y
	var c := R.get_center()
	var dh := World.DOOR_HALF
	var h := LEDGE_H
	var face := Color("39424f")
	var top := Color("4b5566")
	# DOWN ledge along x at y = y1
	var down_spans := [[x0, c.x - dh], [c.x + dh, x1]] if world.has_door(room, World.Dir.DOWN) else [[x0, x1]]
	for s in down_spans:
		_quad(P(s[0], y1, 0), P(s[1], y1, 0), P(s[1], y1, h), P(s[0], y1, h), face)
		_quad(P(s[0], y1, h), P(s[1], y1, h), P(s[1], y1 + 14, h), P(s[0], y1 + 14, h), top)
		_quad(P(s[0], y1 + 14, 0), P(s[1], y1 + 14, 0), P(s[1], y1 + 14, h), P(s[0], y1 + 14, h), face.darkened(0.25))
	# RIGHT ledge along y at x = x1
	var right_spans := [[y0, c.y - dh], [c.y + dh, y1 + 14]] if world.has_door(room, World.Dir.RIGHT) else [[y0, y1 + 14]]
	for s in right_spans:
		_quad(P(x1, s[0], 0), P(x1, s[1], 0), P(x1, s[1], h), P(x1, s[0], h), face.darkened(0.15))
		_quad(P(x1, s[0], h), P(x1, s[1], h), P(x1 + 14, s[1], h), P(x1 + 14, s[0], h), top)
		_quad(P(x1 + 14, s[0], 0), P(x1 + 14, s[1], 0), P(x1 + 14, s[1], h), P(x1 + 14, s[0], h), face.darkened(0.4))
	# Hazard markings on front doorways
	if world.has_door(room, World.Dir.DOWN):
		for x in [c.x - dh, c.x + dh]:
			_quad(P(x - 4, y1, h), P(x + 4, y1, h), P(x + 4, y1 + 14, h), P(x - 4, y1 + 14, h), Color("e0b10b"))
	if world.has_door(room, World.Dir.RIGHT):
		for y in [c.y - dh, c.y + dh]:
			_quad(P(x1, y - 4, h), P(x1, y + 4, h), P(x1 + 14, y + 4, h), P(x1 + 14, y - 4, h), Color("e0b10b"))


# ---------------------------------------------------------------- furniture

static var _furn_meta := {}
static var _furn_tex := {}


## The Blender-rendered sprite for this furniture (with normal map), if any.
static func _furniture_sprite(kind: String, wall: String) -> Array:
	if _furn_meta.is_empty():
		_furn_meta = {"sprites": {}}
		if FileAccess.file_exists("res://assets/sprites/furniture.json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/furniture.json"))
			if parsed is Dictionary:
				_furn_meta = parsed
	var key := kind + "_" + wall
	if not _furn_tex.has(key):
		var info: Dictionary = _furn_meta["sprites"].get(key, {})
		var tex: CanvasTexture = null
		if not info.is_empty() and ResourceLoader.exists(info["color"]):
			tex = CanvasTexture.new()
			tex.diffuse_texture = load(info["color"])
			if ResourceLoader.exists(info["normal"]):
				tex.normal_texture = load(info["normal"])
		_furn_tex[key] = tex
	if _furn_tex[key] == null:
		return []
	return [_furn_tex[key], Vector2(_furn_meta["sprites"][key]["anchor"][0], _furn_meta["sprites"][key]["anchor"][1]), float(_furn_meta.get("scale", 1.0))]


func _draw_furniture(f: Dictionary, tint: Color) -> void:
	var sprite := _furniture_sprite(f["type"], f["wall"])
	if not sprite.is_empty():
		var at := World.iso((f["rect"] as Rect2).get_center())
		var sc: float = sprite[2]
		draw_set_transform(at, 0.0, Vector2(sc, sc))
		draw_texture(sprite[0], -sprite[1])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_draw_furniture_drawn(f, tint)


## The original drawn-in-code furniture (used if the sprites are missing).
func _draw_furniture_drawn(f: Dictionary, tint: Color) -> void:
	var r: Rect2 = f["rect"]
	var d: int = f["detail"]
	var h: float = HEIGHTS.get(f["type"], 50.0)
	var along_x := r.size.x >= r.size.y
	match f["type"]:
		"desk":
			_box(r, h, Color("4f5d72"))
			var m := Rect2(r.get_center() - Vector2(22, 6) if along_x else r.get_center() - Vector2(6, 22), Vector2(44, 12) if along_x else Vector2(12, 44))
			_box(m, 30, Color("1c2129"), h)
			var glow := Color(tint, 0.6 + 0.2 * sin(_t * 3.0 + d))
			if along_x:
				_face_rect_y(m.end.y, m.position.x + 3, m.end.x - 3, h + 4, h + 26, glow)
			else:
				_face_rect_x(m.end.x, m.position.y + 3, m.end.y - 3, h + 4, h + 26, glow)
			_box(Rect2(r.position + Vector2(10, 10), Vector2(24, 16)), 2, Color("d8d2c0"), h)
		"console":
			_box(r, h, Color("2f4252"))
			var colors := [Color("ff4d4d"), Color("ffd84d"), Color("4dff9a"), Color("4dc4ff")]
			for i in 10:
				var s := (i + 0.5) / 10.0
				var p := Vector2(lerpf(r.position.x + 10, r.end.x - 10, s), r.get_center().y + (6 if i % 2 == 0 else -6)) if along_x \
					else Vector2(r.get_center().x + (6 if i % 2 == 0 else -6), lerpf(r.position.y + 10, r.end.y - 10, s))
				var on := int(_t * 3.0 + i + d) % 4 != 0
				draw_circle(World.iso(p, h), 3.0, colors[(i + d) % 4] if on else Color("333a44"))
			# Upright screen at the back edge
			var sr := Rect2(r.position, Vector2(r.size.x, 8)) if along_x else Rect2(r.position, Vector2(8, r.size.y))
			_box(sr, 34, Color("10161c"), h)
			var lines := Color("4dff9a", 0.8)
			for i in 3:
				var z := h + 10 + i * 8
				if along_x:
					draw_line(P(sr.position.x + 10, sr.end.y, z), P(sr.position.x + 10 + (sr.size.x - 20) * fposmod(sin(d + i + _t), 1.0), sr.end.y, z), lines, 2.0)
				else:
					draw_line(P(sr.end.x, sr.position.y + 10, z), P(sr.end.x, sr.position.y + 10 + (sr.size.y - 20) * fposmod(sin(d + i + _t), 1.0), z), lines, 2.0)
		"cabinet":
			_box(r, h, Color("6d7789"))
			for t in [h / 3.0, h * 2.0 / 3.0]:
				_face_line_y(r.end.y, r.position.x + 3, r.end.x - 3, t, Color("2d333d"))
				_face_line_x(r.end.x, r.position.y + 3, r.end.y - 3, t, Color("2d333d"))
			for t in [h / 6.0, h / 2.0, h * 5.0 / 6.0]:
				draw_line(P(r.get_center().x - 8, r.end.y, t), P(r.get_center().x + 8, r.end.y, t), Color("c7ccd6"), 3.0)
		"locker":
			_box(r, h, Color("3b7462"))
			var n := 3
			for i in range(1, n):
				if along_x:
					var x := lerpf(r.position.x, r.end.x, float(i) / n)
					draw_line(P(x, r.end.y, 0), P(x, r.end.y, h), Color("173028"), 2.0)
				else:
					var y := lerpf(r.position.y, r.end.y, float(i) / n)
					draw_line(P(r.end.x, y, 0), P(r.end.x, y, h), Color("173028"), 2.0)
			for i in n:
				for k in 3:
					var z := h - 18 - k * 6
					if along_x:
						var xa := lerpf(r.position.x, r.end.x, (i + 0.25) / n)
						var xb := lerpf(r.position.x, r.end.x, (i + 0.75) / n)
						draw_line(P(xa, r.end.y, z), P(xb, r.end.y, z), Color("173028"), 1.5)
					else:
						var ya := lerpf(r.position.y, r.end.y, (i + 0.25) / n)
						var yb := lerpf(r.position.y, r.end.y, (i + 0.75) / n)
						draw_line(P(r.end.x, ya, z), P(r.end.x, yb, z), Color("173028"), 1.5)
		"crate":
			_box(r, h, Color("6e6540"))
			var dark := Color("3b351f")
			draw_line(P(r.position.x, r.end.y, 0), P(r.end.x, r.end.y, h), dark, 4.0)
			draw_line(P(r.position.x, r.end.y, h), P(r.end.x, r.end.y, 0), dark, 4.0)
			draw_line(P(r.end.x, r.position.y, 0), P(r.end.x, r.end.y, h), dark, 4.0)
			draw_line(P(r.end.x, r.position.y, h), P(r.end.x, r.end.y, 0), dark, 4.0)
			draw_line(P(r.position.x + 10, r.get_center().y, h), P(r.end.x - 10, r.get_center().y, h), Color("e8463a", 0.7), 3.0)
		"shelf":
			_box(r, h, Color("4a3c32"))
			var palette := [Color("c0392b"), Color("2980b9"), Color("f1c40f"), Color("27ae60"), Color("ecf0f1"), Color("8e44ad")]
			for row in 3:
				var z0 := 8.0 + row * (h - 12) / 3.0
				var z1 := z0 + (h - 12) / 3.0 - 6
				var count := int((r.size.x if along_x else r.size.y) / 13)
				for i in count:
					var col: Color = palette[(i * 7 + row * 3 + d) % palette.size()]
					var a := (r.position.x if along_x else r.position.y) + 4 + i * 13
					if along_x:
						_face_rect_y(r.end.y, a, a + 10, z0, z1 - (i % 3) * 3, col.darkened(0.15))
					else:
						_face_rect_x(r.end.x, a, a + 10, z0, z1 - (i % 3) * 3, col.darkened(0.15))
		"safe":
			_box(r, h, Color("3a3f48"))
			var center := P(r.get_center().x, r.end.y, h * 0.5) if along_x else P(r.end.x, r.get_center().y, h * 0.5)
			draw_circle(center, 12.0, Color("9aa3b0"))
			draw_circle(center, 8.0, Color("50575f"))
			draw_line(center, center + Vector2.from_angle(d * 0.37) * 8.0, Color("e6e9ee"), 2.0)
		"plant":
			var pot := r.grow(-12)
			_box(pot, h, Color("7a5238"))
			var top := World.iso(r.get_center(), h + 14)
			for i in 7:
				var a := i * TAU / 7.0 + d * 0.1
				draw_circle(top + Vector2(cos(a) * 14, sin(a) * 7 - 4), 11.0, Color("2f8f46"))
			draw_circle(top - Vector2(0, 14), 12.0, Color("3fae58"))
			draw_circle(top - Vector2(4, 22), 8.0, Color("52c46b"))
		"rack":
			_box(r, h, Color("2a2f37"))
			for i in 4:
				var s := (i + 0.5) / 4.0
				if along_x:
					var x := lerpf(r.position.x, r.end.x, s)
					draw_line(P(x, r.end.y + 1, 14), P(x, r.end.y + 1, h - 14), Color("8e98a6"), 4.0)
					draw_line(P(x, r.end.y + 1, h - 30), P(x + 10, r.end.y + 1, h - 30), Color("8e98a6"), 3.0)
				else:
					var y := lerpf(r.position.y, r.end.y, s)
					draw_line(P(r.end.x + 1, y, 14), P(r.end.x + 1, y, h - 14), Color("8e98a6"), 4.0)
					draw_line(P(r.end.x + 1, y, h - 30), P(r.end.x + 1, y + 10, h - 30), Color("8e98a6"), 3.0)
		"sofa":
			var seat := Color("8f3545")
			var back: Rect2
			var wall: String = f["wall"]
			match wall:
				"top": back = Rect2(r.position, Vector2(r.size.x, 18))
				"bottom": back = Rect2(Vector2(r.position.x, r.end.y - 18), Vector2(r.size.x, 18))
				"left": back = Rect2(r.position, Vector2(18, r.size.y))
				_: back = Rect2(Vector2(r.end.x - 18, r.position.y), Vector2(18, r.size.y))
			if wall == "bottom" or wall == "right":
				_box(r, h, seat)
				_box(back, 50, Color("7a2b39"))
			else:
				_box(back, 50, Color("7a2b39"))
				_box(r, h, seat)
		_:
			_box(r, h, Color("555555"))


## An isometric box: footprint `r` on the floor, from height `z0` to `z0 + h`.
func _box(r: Rect2, h: float, col: Color, z0 := 0.0) -> void:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var z1 := z0 + h
	# Shaded faces: darker towards the floor, lit from the top-left.
	var fl_top := col.darkened(0.15)
	var fl_bot := col.darkened(0.45)
	var fr_top := col.darkened(0.38)
	var fr_bot := col.darkened(0.62)
	draw_polygon(PackedVector2Array([P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)]),
		PackedColorArray([fl_bot, fl_bot, fl_top, fl_top]))   # front-left face
	draw_polygon(PackedVector2Array([P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)]),
		PackedColorArray([fr_bot, fr_bot, fr_top, fr_top]))   # front-right face
	draw_polygon(PackedVector2Array([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)]),
		PackedColorArray([col.lightened(0.02), col.lightened(0.1), col.lightened(0.18), col.lightened(0.1)]))  # top
	var edge := col.lightened(0.3)
	draw_line(P(x0, y1, z1), P(x1, y1, z1), edge, 1.5)
	draw_line(P(x1, y0, z1), P(x1, y1, z1), edge, 1.5)
	draw_line(P(x1, y1, z0), P(x1, y1, z1), col.darkened(0.6), 1.0)


## A rectangle painted on a face that runs along x at floor y = `y`.
func _face_rect_y(y: float, xa: float, xb: float, za: float, zb: float, col: Color) -> void:
	_quad(P(xa, y, za), P(xb, y, za), P(xb, y, zb), P(xa, y, zb), col)


## A rectangle painted on a face that runs along y at floor x = `x`.
func _face_rect_x(x: float, ya: float, yb: float, za: float, zb: float, col: Color) -> void:
	_quad(P(x, ya, za), P(x, yb, za), P(x, yb, zb), P(x, ya, zb), col)


func _face_line_y(y: float, xa: float, xb: float, z: float, col: Color) -> void:
	draw_line(P(xa, y, z), P(xb, y, z), col, 2.0)


func _face_line_x(x: float, ya: float, yb: float, z: float, col: Color) -> void:
	draw_line(P(x, ya, z), P(x, yb, z), col, 2.0)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), col)


func _quad_outline(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	draw_polyline(PackedVector2Array([a, b, c, d, a]), col, 1.5)
