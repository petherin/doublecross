extends Node2D
## A player-controlled agent. The tablet that owns it simulates movement and
## streams its state; the other tablet just shows the received state.

signal room_changed(room: Vector2i)
signal exit_touched
signal search_finished(room: Vector2i, idx: int)
signal trap_finished(info: Dictionary)
signal door_passed(from_room: Vector2i, dir: int)
## Emitted when a knock-out wears off (kind: "BOMB", "SPRING", "WIRE" or "DOWN").
signal recovered(kind: String)
## Emitted when the agent ducks into a vent (true) or pops out of one (false).
signal vent_moved(entering: bool)

const World = preload("res://scripts/core/world.gd")
const Ui = preload("res://scripts/ui/ui.gd")
const Art = preload("res://scripts/render/art.gd")
const SPEED := 340.0
const RADIUS := 26.0
const SEND_RATE := 1.0 / 20.0

## Agent height on screen, in pixels, at normal size.
const SPRITE_HEIGHT := 120.0
const SPRITE_METRES := 1.95
static var _meta := {}
static var _sheets := {}
var world: World
var room := Vector2i.ZERO
var facing := 0.0
var moving := false
## Moving at (nearly) full speed: uses the run animation.
var running := false
## Plays the victory animation (set when this agent wins).
var celebrating := false
var is_local := false
var move_input := Vector2.ZERO

var display_name := "Agent"
## Which sprite sheet to draw ("crimson" / "cobalt").
var sheet_name := ""
var accent := Color("ff5a5f")

## Set by the game: no movement at all (e.g. after the match ends).
var frozen := false
var has_case := false
## True while rummaging through furniture (sent to the other tablet too).
var searching := false
var search_progress := 0.0

## Knocked out by a trap: can't move while this counts down.
var ko_time := 0.0
var ko_kind := ""
## 1.0 right after a bomb, fading to 0: blackened with soot and smouldering.
var soot := 0.0
## Combat. hp/darts mirror the host's match state (for drawing).
var hp := 3
var max_hp := 3
var attack_anim := 0.0       # counts down while swinging the cosh
var hurt_time := 0.0         # red flash after being hit
## Can't be hit for a moment after getting back up (flickers).
var protect_time := 0.0
## Index (world.vents) of the vent this agent is crawling through, or -1.
var vent := -1
var _ko_total := 1.0
var _vent_fx := 0.0   # ducking-in animation
var _pop_fx := 0.0    # popping-out animation
var _last_vent := -1
var _knock := Vector2.ZERO   # knock-back velocity

var _busy_kind := ""       # "search" or "trap"
var _trap_info := {}
var _search_time := 0.0
var _search_left := 0.0
var _search_room := Vector2i.ZERO
var _search_idx := -1
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
	accent = style["accent"]
	sheet_name = style.get("sheet", "")


func _physics_process(delta: float) -> void:
	if is_local:
		_local_move(delta)
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = SEND_RATE
			_send_state()
	else:
		position = position.lerp(_target, minf(1.0, delta * 15.0))
	if moving or searching:
		_walk += delta * (15.0 if running else 12.0)
	attack_anim = maxf(0.0, attack_anim - delta)
	_vent_fx = maxf(0.0, _vent_fx - delta)
	_pop_fx = maxf(0.0, _pop_fx - delta)
	if ko_time <= 0.0:
		protect_time = maxf(0.0, protect_time - delta)
	hurt_time = maxf(0.0, hurt_time - delta)
	if ko_time > 0.0:
		ko_time = maxf(0.0, ko_time - delta)
		_walk += delta * 6.0
		if ko_time == 0.0:
			recovered.emit(ko_kind)
	elif soot > 0.0:
		# The soot wears off a while after you come round.
		soot = maxf(0.0, soot - delta / 10.0)


func knock_out(kind: String, seconds: float) -> void:
	cancel_busy()
	ko_kind = kind
	ko_time = seconds
	_ko_total = seconds
	if kind == "BOMB":
		soot = 1.0


## Ducks into vent `idx` (the agent is hidden and can't be hit until it
## comes out again).
func enter_vent(idx: int) -> void:
	cancel_busy()
	vent = idx
	_last_vent = idx
	_vent_fx = 0.35
	_send_state()
	vent_moved.emit(true)


## Pops out of vent `idx` in another room.
func exit_vent(idx: int) -> void:
	var v: Dictionary = world.vents[idx]
	vent = -1
	room = v["room"]
	position = v["front"]
	_target = position
	_pop_fx = 0.35
	_send_state()
	room_changed.emit(room)
	vent_moved.emit(false)


func swing() -> void:
	attack_anim = 0.3


## Flinch from a hit coming from direction `from_dir` (floor space).
func hurt(from_dir: Vector2) -> void:
	hurt_time = 0.3
	cancel_busy()
	if is_local:
		_knock = from_dir.normalized() * 700.0


## Back on your feet in `start_room` after being taken out.
func respawn(start_room: Vector2i) -> void:
	room = start_room
	position = World.ROOM.get_center()
	_target = position
	_knock = Vector2.ZERO
	_send_state()
	room_changed.emit(room)


func cancel_busy() -> void:
	if searching:
		searching = false
		search_progress = 0.0
		_busy_kind = ""
		if is_local:
			_send_state()


## Spends `duration` setting a trap; emits trap_finished(info) afterwards.
func start_trap(info: Dictionary, duration: float) -> void:
	start_search(-1, duration)
	_busy_kind = "trap"
	_trap_info = info


func start_search(idx: int, duration: float) -> void:
	_busy_kind = "search"
	searching = true
	_search_time = duration
	_search_left = duration
	_search_room = room
	_search_idx = idx
	_send_state()


func _local_move(delta: float) -> void:
	if searching:
		_search_left -= delta
		search_progress = 1.0 - _search_left / _search_time
		if _search_left <= 0.0:
			searching = false
			search_progress = 0.0
			_send_state()
			# Clear the busy state *before* emitting: listeners may start a new action.
			var kind := _busy_kind
			_busy_kind = ""
			if kind == "trap":
				trap_finished.emit(_trap_info)
			else:
				search_finished.emit(_search_room, _search_idx)
	var v := move_input.limit_length(1.0) * SPEED
	if frozen or searching or ko_time > 0.0 or vent >= 0:
		v = Vector2.ZERO
	moving = v.length() > 25.0
	running = v.length() > SPEED * 0.8
	if moving:
		facing = v.angle()
	var p := position + (v + _knock) * delta
	_knock = _knock.move_toward(Vector2.ZERO, 3500.0 * delta)
	p = _resolve_furniture(p)
	p = _resolve_walls(p)
	if p != Vector2.INF:
		position = p


## Keeps the agent inside the room, except through openings. Walking far
## enough into a doorway moves the agent to the neighbouring room and
## returns Vector2.INF to signal that the position was already set.
## Walking into the exit emits `exit_touched` (the game decides what happens).
func _resolve_walls(p: Vector2) -> Vector2:
	var R := World.ROOM
	var c := R.get_center()
	var gap := World.DOOR_HALF - RADIUS
	var through := 20.0
	# [dir, axis (0 = x wall position / 1 = y), wall coordinate, sign pointing outwards]
	var walls := [
		[World.Dir.UP, 1, R.position.y, -1.0],
		[World.Dir.DOWN, 1, R.end.y, 1.0],
		[World.Dir.LEFT, 0, R.position.x, -1.0],
		[World.Dir.RIGHT, 0, R.end.x, 1.0],
	]
	for w in walls:
		var dir: int = w[0]
		var ax: int = w[1]
		var wall: float = w[2]
		var out: float = w[3]
		var other := 1 - ax
		# How far past the "touching the wall" line the agent is trying to go.
		if (p[ax] - (wall - out * RADIUS)) * out <= 0.0:
			continue
		var kind := world.opening(room, dir)
		if kind != 0 and absf(position[other] - c[other]) <= gap:
			p[other] = clampf(p[other], c[other] - gap, c[other] + gap)
			if (p[ax] - wall) * out > through:
				if kind == 1:
					return _enter(dir)
				p[ax] = wall + out * through
				exit_touched.emit()
		else:
			p[ax] = wall - out * RADIUS
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
	door_passed.emit(room, dir)
	room += World.DIR_VEC[dir]
	position = World.entry_point(dir, RADIUS)
	_target = position
	_send_state()
	room_changed.emit(room)
	return Vector2.INF


func _send_state() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		net_state.rpc(room, position, facing, (2 if running else 1) if moving else 0, searching, vent)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_state(r: Vector2i, pos: Vector2, f: float, m: int, s: bool, v := -1) -> void:
	if v != vent:
		# The other tablet's agent went into, or came out of, a vent.
		if v >= 0:
			vent = v
			_vent_fx = 0.35
			vent_moved.emit(true)
		else:
			vent = -1
			room = r
			position = pos
			_target = pos
			_pop_fx = 0.35
			vent_moved.emit(false)
	searching = s
	if r != room:
		room = r
		position = pos
	_target = pos
	facing = f
	moving = m > 0
	running = m == 2


## Draws this agent onto the room renderer `ci` (so it can be depth-sorted
## with the furniture), using the Blender-rendered sprite sheet if there is one.
func paint(ci: CanvasItem) -> void:
	if _sheet() != null:
		_paint_sprite(ci)


# ---------------------------------------------------------------- sprites


static func _load_meta() -> Dictionary:
	if _meta.is_empty() and FileAccess.file_exists("res://assets/sprites/agents.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/agents.json"))
		if parsed is Dictionary:
			_meta = parsed
	return _meta


func _sheet() -> Texture2D:
	if sheet_name == "":
		return null
	if not _sheets.has(sheet_name):
		var m := _load_meta()
		var tex: Texture2D = null
		if m.has("sheets") and m["sheets"].has(sheet_name) and ResourceLoader.exists(m["sheets"][sheet_name]):
			var ct := CanvasTexture.new()
			ct.diffuse_texture = load(m["sheets"][sheet_name])
			# A normal map lets the room's lights shade the agent.
			var normals: Dictionary = m.get("normals", {})
			if normals.has(sheet_name) and ResourceLoader.exists(normals[sheet_name]):
				ct.normal_texture = load(normals[sheet_name])
			tex = ct
		_sheets[sheet_name] = tex
	return _sheets[sheet_name]


## Which animation and frame to show right now.
func _sprite_frame() -> Array:
	var ko := ko_time > 0.0
	if ko and ko_kind == "DOWN":
		return ["down", 0]
	if hurt_time > 0.0 or ko:
		return ["hurt", 0]
	if attack_anim > 0.0:
		return ["swing", int(clampf(1.0 - attack_anim / 0.3, 0.0, 0.999) * 4.0)]
	if searching:
		return ["search", int(_walk * 0.6) % 4]
	var m := _load_meta()
	if celebrating and m["anims"].has("victory"):
		return ["victory", int(Time.get_ticks_msec() / 110) % int(m["anims"]["victory"]["count"])]
	if moving:
		var anim := "run" if running and m["anims"].has("run") else "walk"
		var n: int = m["anims"][anim]["count"]
		return [anim, int(fposmod(_walk, TAU) / TAU * n) % n]
	return ["idle", int(Time.get_ticks_msec() / 700) % 2]


func _paint_sprite(ci: CanvasItem) -> void:
	if vent >= 0 and _vent_fx <= 0.0:
		return
	var m := _load_meta()
	var tex := _sheet()
	var dirs: int = m["directions"]
	var anchor := Vector2(m["anchor"][0], m["anchor"][1])
	var scale_f := SPRITE_HEIGHT / (SPRITE_METRES * float(m["pixels_per_metre"]))
	var foot := World.iso(position)
	var squash := 1.0
	if vent >= 0 and _vent_fx > 0.0:
		# Ducking into the vent: shrink down towards the grille.
		var k := 1.0 - _vent_fx / 0.35
		var v: Dictionary = world.vents[vent]
		var mouth: Vector2 = v["front"] + (Vector2(0, -60) if v["dir"] == World.Dir.UP else Vector2(-60, 0))
		foot = foot.lerp(World.iso(mouth, 12.0), k)
		squash = 1.0 - 0.75 * k
	elif _pop_fx > 0.0:
		squash = 1.0 - 0.5 * (_pop_fx / 0.35)
	var ko := ko_time > 0.0
	var ko_age := _ko_total - ko_time
	if ko and ko_kind == "SPRING" and ko_age < 0.9:
		foot.y -= sin(ko_age / 0.9 * PI) * 160.0

	# Shadow and team ring on the floor.
	ci.draw_set_transform(World.iso(position), 0.0, Vector2(1.0, 0.5))
	ci.draw_texture_rect(Art.soft(), Rect2(-40, -40, 80, 80), false, Color(0, 0, 0, 0.7))
	ci.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 40, Color(accent, 0.6), 3.0, true)

	var fr := _sprite_frame()
	var anim: Dictionary = m["anims"][fr[0]]
	var d := posmod(int(round(facing / (TAU / dirs))), dirs)
	# Tightly packed atlas: each frame is trimmed, so draw it at its offset.
	var fid: int = d * int(m["frames_per_direction"]) + int(anim["start"]) + int(fr[1])
	var r: Array = m["rects"][sheet_name][fid]
	var region := Rect2(r[0], r[1], r[2], r[3])
	var offset := Vector2(r[4], r[5])
	# Dizzy wobble while knocked out by a trap.
	var tilt := sin(_walk * 1.3) * 0.18 if ko and ko_kind != "DOWN" else 0.0
	var tint := Color.WHITE
	if soot > 0.0:
		tint = tint.lerp(Color(0.28, 0.25, 0.23), minf(1.0, soot * 1.4))
	if hurt_time > 0.0:
		tint = tint.lerp(Color(1.0, 0.45, 0.45), hurt_time / 0.3)
	if protect_time > 0.0 and ko_time <= 0.0:
		tint.a = 0.35 if int(Time.get_ticks_msec() / 90) % 2 == 0 else 0.85
	ci.draw_set_transform(foot, tilt, Vector2(scale_f, scale_f * squash))
	ci.draw_texture_rect_region(tex, Rect2(-anchor + offset, region.size), region, tint)
	if has_case and not searching and attack_anim <= 0.0 and not ko:
		# The briefcase, carried at the side.
		var side := Vector2.from_angle(facing + PI / 2)
		var hand := World.floor_to_screen_dir(side) * 26.0 / scale_f + Vector2(0, -52.0 / scale_f)
		ci.draw_set_transform(foot + hand * scale_f, 0.0, Vector2.ONE)
		ci.draw_rect(Rect2(-10, -2, 20, 14), Color("7a5238"))
		ci.draw_rect(Rect2(-10, -2, 20, 3), Color("946645"))
		ci.draw_rect(Rect2(-2, 0, 4, 3), Color("e8c25a"))
		ci.draw_rect(Rect2(-10, -2, 20, 14), Color(0, 0, 0, 0.6), false, 1.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if vent >= 0:
		return
	_paint_overlays(ci, foot, ko, SPRITE_HEIGHT + 24.0 if not (ko and ko_kind == "DOWN") else 50.0)


## Name tag, health pips, smoke, dizzy stars and the search bubble.
func _paint_overlays(ci: CanvasItem, foot: Vector2, ko: bool, top := 104.0) -> void:
	# Name tag (unflipped)
	var font := ThemeDB.fallback_font
	var size := int(16 * Ui.scale())
	var w := font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, foot + Vector2(-w / 2, -top), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, accent)
	for i in max_hp:
		var pip := foot + Vector2((i - (max_hp - 1) / 2.0) * 12.0, -top + 6.0)
		ci.draw_circle(pip, 4.0, Color(0, 0, 0, 0.6))
		ci.draw_circle(pip, 3.0, accent if i < hp else Color(1, 1, 1, 0.15))

	# Smouldering: smoke wisps curl up and the odd ember glows.
	if soot > 0.05:
		var now := Time.get_ticks_msec() / 1000.0
		for i in 5:
			var life := fmod(now * 0.8 + i * 0.2, 1.0)
			var wp := foot + Vector2(sin(now * 2.0 + i * 1.7) * 10.0 + (i - 2) * 6.0, -60.0 - life * 70.0)
			ci.draw_circle(wp, 5.0 + life * 9.0, Color(0.35, 0.33, 0.32, (1.0 - life) * 0.45 * soot))
		for i in 3:
			var flick := 0.5 + 0.5 * sin(now * 9.0 + i * 2.3)
			ci.draw_circle(foot + Vector2(-8 + i * 8, -40 - i * 9), 1.8, Color(1.0, 0.55, 0.1, flick * soot))

	# Dizzy stars while knocked out
	if ko:
		for i in 4:
			var a := _walk * 1.5 + i * TAU / 4.0
			var sp := foot + Vector2(cos(a) * 26.0, -top + 2.0 + sin(a) * 8.0)
			_star(ci, sp, 7.0, Color("ffd23f"))

	# Thought bubble while searching (with a progress ring for your own agent)
	if searching:
		var b := foot + Vector2(30, -top - 24.0)
		ci.draw_circle(foot + Vector2(18, -top), 3.0, Color.WHITE)
		ci.draw_circle(b, 17.0, Color.WHITE)
		if is_local:
			ci.draw_arc(b, 21.0, -PI / 2, -PI / 2 + TAU * search_progress, 32, accent, 4.0, true)
		var q := "?"
		var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		ci.draw_string(font, b + Vector2(-qw / 2, 8), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("15171c"))


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + i * TAU / 10.0) * rr)
	ci.draw_colored_polygon(pts, col)
