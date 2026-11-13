extends Node2D
## A player-controlled agent. The tablet that owns it simulates movement and
## streams its state; the other tablet just shows the received state.

signal room_changed(room: Vector2i)

const World = preload("res://scripts/world.gd")
const SPEED := 340.0
const RADIUS := 26.0
const SEND_RATE := 1.0 / 20.0

var world: World
var room := Vector2i.ZERO
var facing := 0.0
var moving := false
var is_local := false
var move_input := Vector2.ZERO

var display_name := "Agent"
var coat := Color("b3262e")
var hat := Color("2a0d10")
var accent := Color("ff5a5f")

var _target := Vector2.ZERO
var _walk := 0.0
var _send_timer := 0.0


func configure(p_world: World, p_room: Vector2i, p_local: bool, style: Dictionary) -> void:
	world = p_world
	room = p_room
	is_local = p_local
	position = World.ROOM.get_center()
	_target = position
	display_name = style["name"]
	coat = style["coat"]
	hat = style["hat"]
	accent = style["accent"]


func _physics_process(delta: float) -> void:
	if is_local:
		_local_move(delta)
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = SEND_RATE
			_send_state()
	else:
		position = position.lerp(_target, minf(1.0, delta * 15.0))
	if moving:
		_walk += delta * 12.0


func _local_move(delta: float) -> void:
	var v := move_input.limit_length(1.0) * SPEED
	moving = v.length() > 25.0
	if moving:
		facing = v.angle()
	var p := position + v * delta
	p = _resolve_furniture(p)
	p = _resolve_walls(p)
	if p != Vector2.INF:
		position = p


## Keeps the agent inside the room, except through doorways. Walking far
## enough into a doorway moves the agent to the neighbouring room and
## returns Vector2.INF to signal that the position was already set.
func _resolve_walls(p: Vector2) -> Vector2:
	var R := World.ROOM
	var c := R.get_center()
	var gap := World.DOOR_HALF - RADIUS
	# Top / bottom walls
	if p.y < R.position.y + RADIUS:
		if world.has_door(room, World.Dir.UP) and absf(position.x - c.x) <= gap:
			p.x = clampf(p.x, c.x - gap, c.x + gap)
			if p.y < R.position.y - 20.0:
				return _enter(World.Dir.UP)
		else:
			p.y = R.position.y + RADIUS
	elif p.y > R.end.y - RADIUS:
		if world.has_door(room, World.Dir.DOWN) and absf(position.x - c.x) <= gap:
			p.x = clampf(p.x, c.x - gap, c.x + gap)
			if p.y > R.end.y + 20.0:
				return _enter(World.Dir.DOWN)
		else:
			p.y = R.end.y - RADIUS
	# Left / right walls
	if p.x < R.position.x + RADIUS:
		if world.has_door(room, World.Dir.LEFT) and absf(position.y - c.y) <= gap:
			p.y = clampf(p.y, c.y - gap, c.y + gap)
			if p.x < R.position.x - 20.0:
				return _enter(World.Dir.LEFT)
		else:
			p.x = R.position.x + RADIUS
	elif p.x > R.end.x - RADIUS:
		if world.has_door(room, World.Dir.RIGHT) and absf(position.y - c.y) <= gap:
			p.y = clampf(p.y, c.y - gap, c.y + gap)
			if p.x > R.end.x + 20.0:
				return _enter(World.Dir.RIGHT)
		else:
			p.x = R.end.x - RADIUS
	return p


func _resolve_furniture(p: Vector2) -> Vector2:
	for f in world.furniture(room):
		var r: Rect2 = f["rect"]
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := p - q
		var dist := d.length()
		if dist < RADIUS:
			if dist > 0.001:
				p = q + d / dist * RADIUS
			else:
				p = position
	return p


func _enter(dir: int) -> Vector2:
	room += World.DIR_VEC[dir]
	position = World.entry_point(dir, RADIUS)
	_target = position
	_send_state()
	room_changed.emit(room)
	return Vector2.INF


func _send_state() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		net_state.rpc(room, position, facing, moving)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_state(r: Vector2i, pos: Vector2, f: float, m: bool) -> void:
	if r != room:
		room = r
		position = pos
	_target = pos
	facing = f
	moving = m


## Draws this agent onto the room renderer `ci` (so it can be depth-sorted
## with the furniture). Upright, stylised spy in a trench coat and fedora.
func paint(ci: CanvasItem) -> void:
	var foot := World.iso(position)
	var sdir := World.floor_to_screen_dir(Vector2.from_angle(facing))
	var flip := -1.0 if sdir.x < 0.0 else 1.0
	var back_view := sdir.y < -0.15
	var stride := sin(_walk) * 7.0 if moving else 0.0
	var bob := absf(sin(_walk)) * 2.0 if moving else 0.0
	var skin := Color("e0b48f")
	var dark := coat.darkened(0.4)
	var trousers := Color("1b1e25")

	# Shadow and team ring on the floor
	ci.draw_set_transform(foot, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.4))
	ci.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 40, Color(accent, 0.6), 3.0, true)

	ci.draw_set_transform(foot - Vector2(0, bob), 0.0, Vector2(flip, 1.0))
	# Legs and shoes
	ci.draw_line(Vector2(-5, -30), Vector2(-5 + stride, -3), trousers, 7.0, true)
	ci.draw_line(Vector2(5, -30), Vector2(5 - stride, -3), trousers, 7.0, true)
	ci.draw_circle(Vector2(-3 + stride, -2), 4.5, Color("0c0d10"))
	ci.draw_circle(Vector2(7 - stride, -2), 4.5, Color("0c0d10"))
	# Back arm (behind the coat)
	ci.draw_line(Vector2(-11, -60), Vector2(-13 - stride * 0.8, -36), dark, 7.0, true)
	# Trench coat: flared hem, belt, lapels
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-16, -26), Vector2(16, -26), Vector2(13, -64), Vector2(-13, -64)]), coat)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-16, -26), Vector2(-4, -26), Vector2(-3, -64), Vector2(-13, -64)]), dark.lightened(0.1))
	ci.draw_line(Vector2(-15, -44), Vector2(15, -44), dark, 4.0)
	ci.draw_rect(Rect2(-3, -46, 6, 5), accent)
	if not back_view:
		ci.draw_line(Vector2(0, -64), Vector2(6, -50), coat.lightened(0.25), 2.5, true)
		ci.draw_line(Vector2(9, -64), Vector2(6, -50), coat.lightened(0.25), 2.5, true)
	# Head
	ci.draw_circle(Vector2(1, -72), 9.5, skin)
	if back_view:
		ci.draw_circle(Vector2(0, -73), 9.0, Color("2a1d16"))
	else:
		ci.draw_rect(Rect2(2, -76, 9, 4), Color("0c0c10"))
	# Fedora: brim, crown, band
	ci.draw_set_transform(foot - Vector2(0, bob) + Vector2(0, -80), 0.0, Vector2(flip, 0.28))
	ci.draw_circle(Vector2.ZERO, 17.0, hat.lightened(0.1))
	ci.draw_set_transform(foot - Vector2(0, bob), 0.0, Vector2(flip, 1.0))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-10, -81), Vector2(10, -81), Vector2(8, -95), Vector2(-8, -95)]), hat)
	ci.draw_rect(Rect2(-10, -85, 20, 4), accent)
	# Front arm with hand
	ci.draw_line(Vector2(8, -60), Vector2(12 + stride * 0.8, -36), dark, 7.0, true)
	ci.draw_circle(Vector2(12 + stride * 0.8, -35), 4.0, skin)

	# Name tag (unflipped)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	var size := 16
	var w := font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, foot + Vector2(-w / 2, -104), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, accent)
