extends Node2D
## Isometric renderer for the room the local agent is standing in.
## Draw order: floor -> back walls -> furniture & agents (depth sorted) -> front ledges.
## Wall decorations live in wall_decor.gd and explosions etc. in room_effects.gd.

const World = preload("res://scripts/core/world.gd")
const Icons = preload("res://scripts/ui/icons.gd")
const Art = preload("res://scripts/render/art.gd")
const Style = preload("res://scripts/ui/style.gd")
const LightLayer = preload("res://scripts/render/light_layer.gd")
const RoomLights = preload("res://scripts/render/room_lights.gd")
const WallDecor = preload("res://scripts/render/wall_decor.gd")
const RoomEffects = preload("res://scripts/render/room_effects.gd")

const DOOR_TOP := 82.0
const LEDGE_H := 16.0
const HEIGHTS := {
	"desk": 40.0, "console": 52.0, "cabinet": 72.0, "locker": 120.0, "crate": 58.0,
	"shelf": 112.0, "safe": 62.0, "plant": 24.0, "rack": 100.0, "sofa": 24.0,
}

static var _furn_meta := {}
static var _furn_tex := {}
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
## Trap explosions, hits, vent dust and their comic-book words.
var effects := RoomEffects.new()

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
	effects.tick(delta)
	queue_redraw()


func add_effect(kind: String, effect_room: Vector2i, pos: Vector2) -> void:
	effects.add(kind, effect_room, pos)
	if effect_room == room and lights:
		if kind == "BOMB":
			lights.flash(pos, Color(1.0, 0.55, 0.2), 2.2)
		elif kind == "DOWN":
			lights.flash(pos, Color(1.0, 0.9, 0.6), 1.0)


static func _iso(x: float, y: float, z := 0.0) -> Vector2:
	return World.iso(Vector2(x, y), z)


func _draw() -> void:
	if world == null:
		return
	var area := World.ROOM
	var tint: Color = world.rooms[room]["tint"]
	_draw_floor(area, tint)
	for e in effects.in_room(room):
		if e["kind"] == "BOMB":
			effects.draw_scorch(self, e)
	_draw_back_walls(area, tint)

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
			_draw_furniture(t["f"])
			if t["i"] == highlight:
				_draw_highlight(t["f"])
			var tk := World.furniture_key(room, t["i"])
			if my_traps.has(tk):
				_draw_trap_marker(t["f"], my_traps[tk])

	for d in darts:
		if d["room"] == room:
			_draw_dart(d)
	_draw_front_ledges(area)
	_draw_my_tripwires()
	for e in effects.in_room(room):
		effects.draw(self, e)


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

func _draw_floor(area: Rect2, tint: Color) -> void:
	var x0 := area.position.x
	var y0 := area.position.y
	var x1 := area.end.x
	var y1 := area.end.y
	var font := ThemeDB.fallback_font
	draw_set_transform_matrix(_floor_xf())
	# Steel tread plate, tinted a touch by the room's lighting.
	draw_texture_rect(Art.floor_tex(), area, true, Color(0.95, 0.97, 1.0).lerp(tint, 0.08))
	# Room name stencilled on the floor.
	var name_text: String = world.rooms[room]["name"].to_upper()
	draw_string(Style.stencil(), Vector2(x0 + 70, y1 - 70), name_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1, 1, 1, 0.05))
	# Hazard stripes on the threshold of each doorway.
	var rc := area.get_center()
	var door_half := World.DOOR_HALF
	for dir in World.DIR_VEC:
		if world.opening(room, dir) == 0:
			continue
		var v := Vector2(World.DIR_VEC[dir])
		var side := Vector2(-v.y, v.x)
		var mid := rc + v * (area.size / 2.0 - Vector2(18, 18))
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
			var c := area.get_center()
			var dh := World.DOOR_HALF
			for i in 4:
				var depth := 40.0 + i * 35.0
				var spread := dh + i * 18.0
				var col := Color(1.0, 0.93, 0.7, 0.07)
				if dir == World.Dir.UP:
					_quad(_iso(c.x - dh, y0), _iso(c.x + dh, y0), _iso(c.x + spread, y0 + depth), _iso(c.x - spread, y0 + depth), col)
				else:
					_quad(_iso(x0, c.y - dh), _iso(x0, c.y + dh), _iso(x0 + depth, c.y + spread), _iso(x0 + depth, c.y - spread), col)
	# Floor arrows towards each door
	for dir in [World.Dir.UP, World.Dir.DOWN, World.Dir.LEFT, World.Dir.RIGHT]:
		match world.opening(room, dir):
			1: _floor_arrow(dir, tint)
			2: _floor_arrow(dir, Color("5dff8a"))


func _floor_arrow(dir: int, tint: Color) -> void:
	var area := World.ROOM
	var c := area.get_center()
	var v := Vector2(World.DIR_VEC[dir])
	var base := c + v * Vector2(area.size.x * 0.5 - 50, area.size.y * 0.5 - 50)
	var side := Vector2(-v.y, v.x)
	var tip := base + v * 22
	var l := base - v * 10 + side * 20
	var r := base - v * 10 - side * 20
	draw_colored_polygon(PackedVector2Array([World.iso(tip), World.iso(l), World.iso(r)]), Color(tint, 0.4))


# ---------------------------------------------------------------- walls

func _draw_back_walls(area: Rect2, tint: Color) -> void:
	var x0 := area.position.x
	var y0 := area.position.y
	var x1 := area.end.x
	var y1 := area.end.y
	var c := area.get_center()
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
		_quad(_iso(c.x - dh, y0, DOOR_TOP), _iso(c.x + dh, y0, DOOR_TOP),
				_iso(c.x + dh, y0, h), _iso(c.x - dh, y0, h), col_up.darkened(0.1))
		_doorway(_iso(c.x - dh, y0), _iso(c.x + dh, y0), up_kind == 2)
	if left_door:
		_quad(_iso(x0, c.y - dh, DOOR_TOP), _iso(x0, c.y + dh, DOOR_TOP),
				_iso(x0, c.y + dh, h), _iso(x0, c.y - dh, h), col_left.darkened(0.1))
		_doorway(_iso(x0, c.y - dh), _iso(x0, c.y + dh), left_kind == 2)
	# Wall panels, light strips and skirting
	var pulse := 0.75 + 0.25 * sin(_t * 2.0)
	for s in up_spans:
		_wall_details(Vector2(s[0], y0), Vector2(s[1], y0), tint, pulse)
	for s in left_spans:
		_wall_details(Vector2(x0, s[0]), Vector2(x0, s[1]), tint, pulse)
	WallDecor.draw(self, _up_wall_xf(), up_spans, tint, 0, world.seed_value, room, _t)
	WallDecor.draw(self, _left_wall_xf(), left_spans, tint, 1, world.seed_value, room, _t)
	for i in world.vents.size():
		if world.vents[i]["room"] == room:
			_draw_vent(i)
	# Top caps (wall thickness) and the corner post
	var cap := Color("3d4759")
	var t := 14.0
	_quad(_iso(x0, y0, h), _iso(x1, y0, h), _iso(x1, y0 - t, h), _iso(x0 - t, y0 - t, h), cap)
	_quad(_iso(x0, y0, h), _iso(x0 - t, y0 - t, h), _iso(x0 - t, y1, h), _iso(x0, y1, h), cap.darkened(0.1))
	draw_line(_iso(x0, y0, 0), _iso(x0, y0, h), Color(0, 0, 0, 0.4), 2.0)


func _textured_wall(xf: Transform2D, spans: Array, modulate_col: Color) -> void:
	var h := World.WALL_H
	draw_set_transform_matrix(xf)
	for sp in spans:
		var r := Rect2(sp[0], -h, sp[1] - sp[0], h)
		draw_texture_rect(Art.wall_tex(), r, true, modulate_col)
		# Grime and shadow at the base, a little light at the top.
		draw_polygon(PackedVector2Array([
					Vector2(r.position.x, -34), Vector2(r.end.x, -34), Vector2(r.end.x, 0), Vector2(r.position.x, 0)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45)]))
	draw_set_transform_matrix(Transform2D.IDENTITY)


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
		var arrow := PackedVector2Array([tip, tip + Vector2(-9, -14), tip + Vector2(9, -14)])
		draw_colored_polygon(arrow, Color(1.0, 0.86, 0.15, pulse))
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
	var area := World.ROOM
	var c := area.get_center()
	var dh := World.DOOR_HALF
	for dir in World.DIR_VEC:
		if world.opening(room, dir) != 1 or not my_traps.has(World.door_key(room, dir)):
			continue
		var v := Vector2(World.DIR_VEC[dir])
		var mid := c + v * area.size / 2.0
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


## Pulsing outline round the furniture you can search, plus a magnifier.
func _draw_highlight(f: Dictionary) -> void:
	var r: Rect2 = f["rect"].grow(4)
	var h: float = HEIGHTS.get(f["type"], 50.0) + (20.0 if f["type"] == "plant" else 0.0)
	var a := 0.55 + 0.45 * sin(_t * 6.0)
	var col := Color(highlight_color, a)
	var top := PackedVector2Array([
		_iso(r.position.x, r.position.y, h), _iso(r.end.x, r.position.y, h),
		_iso(r.end.x, r.end.y, h), _iso(r.position.x, r.end.y, h), _iso(r.position.x, r.position.y, h)])
	draw_polyline(top, col, 3.0, true)
	var edge := PackedVector2Array([
		_iso(r.position.x, r.end.y, 0), _iso(r.end.x, r.end.y, 0), _iso(r.end.x, r.position.y, 0)])
	draw_polyline(edge, col, 3.0, true)
	draw_line(_iso(r.position.x, r.end.y, 0), _iso(r.position.x, r.end.y, h), col, 3.0)
	draw_line(_iso(r.end.x, r.end.y, 0), _iso(r.end.x, r.end.y, h), col, 3.0)
	draw_line(_iso(r.end.x, r.position.y, 0), _iso(r.end.x, r.position.y, h), col, 3.0)
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


func _draw_front_ledges(area: Rect2) -> void:
	var x0 := area.position.x
	var y0 := area.position.y
	var x1 := area.end.x
	var y1 := area.end.y
	var c := area.get_center()
	var dh := World.DOOR_HALF
	var h := LEDGE_H
	var face := Color("39424f")
	var top := Color("4b5566")
	# DOWN ledge along x at y = y1
	var down_spans := [[x0, c.x - dh], [c.x + dh, x1]] if world.has_door(room, World.Dir.DOWN) else [[x0, x1]]
	for s in down_spans:
		_quad(_iso(s[0], y1, 0), _iso(s[1], y1, 0), _iso(s[1], y1, h), _iso(s[0], y1, h), face)
		_quad(_iso(s[0], y1, h), _iso(s[1], y1, h), _iso(s[1], y1 + 14, h), _iso(s[0], y1 + 14, h), top)
		_quad(_iso(s[0], y1 + 14, 0), _iso(s[1], y1 + 14, 0),
				_iso(s[1], y1 + 14, h), _iso(s[0], y1 + 14, h), face.darkened(0.25))
	# RIGHT ledge along y at x = x1
	var right_spans := [[y0, c.y - dh], [c.y + dh, y1 + 14]] if world.has_door(room, World.Dir.RIGHT) else [[y0, y1 + 14]]
	for s in right_spans:
		_quad(_iso(x1, s[0], 0), _iso(x1, s[1], 0), _iso(x1, s[1], h), _iso(x1, s[0], h), face.darkened(0.15))
		_quad(_iso(x1, s[0], h), _iso(x1, s[1], h), _iso(x1 + 14, s[1], h), _iso(x1 + 14, s[0], h), top)
		_quad(_iso(x1 + 14, s[0], 0), _iso(x1 + 14, s[1], 0),
				_iso(x1 + 14, s[1], h), _iso(x1 + 14, s[0], h), face.darkened(0.4))
	# Hazard markings on front doorways
	if world.has_door(room, World.Dir.DOWN):
		for x in [c.x - dh, c.x + dh]:
			_quad(_iso(x - 4, y1, h), _iso(x + 4, y1, h), _iso(x + 4, y1 + 14, h), _iso(x - 4, y1 + 14, h), Color("e0b10b"))
	if world.has_door(room, World.Dir.RIGHT):
		for y in [c.y - dh, c.y + dh]:
			_quad(_iso(x1, y - 4, h), _iso(x1, y + 4, h), _iso(x1 + 14, y + 4, h), _iso(x1 + 14, y - 4, h), Color("e0b10b"))


# ---------------------------------------------------------------- furniture


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
	var anchor: Array = _furn_meta["sprites"][key]["anchor"]
	return [_furn_tex[key], Vector2(anchor[0], anchor[1]), float(_furn_meta.get("scale", 1.0))]


func _draw_furniture(f: Dictionary) -> void:
	var sprite := _furniture_sprite(f["type"], f["wall"])
	if not sprite.is_empty():
		var at := World.iso((f["rect"] as Rect2).get_center())
		var sc: float = sprite[2]
		draw_set_transform(at, 0.0, Vector2(sc, sc))
		draw_texture(sprite[0], -sprite[1])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), col)


func _quad_outline(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	draw_polyline(PackedVector2Array([a, b, c, d, a]), col, 1.5)
