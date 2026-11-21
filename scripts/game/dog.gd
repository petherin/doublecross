extends Node
## Nacho, the base's dog. He waits in his kennel until someone searches it,
## then follows them everywhere (through vents too), sniffing round each
## room. He growls at trapped furniture and wired doorways (he never sets
## them off) and barks and wags his tail at furniture with something hidden
## in it. Anyone who attacks his agent, or him, gets chased and bitten until
## they stop. He can be hurt: three hits and he runs home to his kennel. He
## also runs home if his agent is taken out. Either way he's nobody's dog
## until someone finds him again. Now and then (in about two matches in five)
## he stops for a poo, and what he leaves behind is as good as a trap.
##
## Who he belongs to is decided by the referee (the host) and arrives as
## events; every device walks him about itself, following his agent.

signal alerted(key: String, kind: String)

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")
const Art = preload("res://scripts/render/art.gd")
const Style = preload("res://scripts/ui/style.gd")

const SPEED := 400.0
## Rendered with the agents' camera; drawn a fifth larger than true scale
## so he reads clearly beside them.
const SPRITE_HEIGHT := 145.0
const SPRITE_METRES := 1.95
const SNIFF_TIME := 1.3
const ALERT_TIME := 2.4
## How far he'll wander from his agent to sniff something.
const LEASH := 720.0
## Hits aimed at Nacho are sent to the referee with this as the target.
const DOG_ID := -7
## He bites his attacker this often while they keep at it, and gives up once
## they've left off for FOE_MEMORY seconds.
const BITE_EVERY := 1.2
const FOE_MEMORY := 3.0
## How long a bite knocks the attacker over.
const BITE_STUN := 0.7
## Close enough to bite.
const BITE_REACH := 80.0
## Hits he can take before he runs home (agents take three, too).
const MAX_HP := 3
## How long a poo takes, and how close you have to tread to slip in one.
const POO_TIME := 3.0
const TURD_RADIUS := 24.0

static var _meta := {}
static var _tex: Texture2D

var game: Node
var world: World
## Who found him (0 while he's at home in his kennel).
var owner_id := 0
## Who he's going for (0: nobody).
var foe_id := 0
var hp := MAX_HP
## Flashes red when hit; can't be hit again for a moment.
var hurt_time := 0.0
var protect_time := 0.0
var room := Vector2i.ZERO
var position := Vector2.ZERO
var facing := PI / 2.0
var moving := false
## What he's pointed out to his agent: furniture or door key -> "item"/"trap".
var flags := {}
var _state := "home"       # home, follow, go, sniff, alert, guard, bite, poo
var _state_t := 0.0
var _target := Vector2.ZERO
var _key := ""
var _alert := ""
var _sniffed := {}
var _walk := 0.0
var _in_duct := false
var _rng := RandomNumberGenerator.new()


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_rng.seed = hash(["nacho", world.seed_value])
	go_home()


## Back to his kennel, to wait for whoever finds him next.
func go_home() -> void:
	owner_id = 0
	foe_id = 0
	hp = MAX_HP
	hurt_time = 0.0
	protect_time = 0.0
	flags.clear()
	_sniffed.clear()
	_in_duct = false
	room = world.kennel[0]
	position = kennel_front()
	facing = _into_room()
	_set_state("home")


## Found! He follows `pid` from now on.
func found_by(pid: int) -> void:
	owner_id = pid
	flags.clear()
	_sniffed.clear()
	_alert = "happy"
	_set_state("alert", 1.4)


## Someone's attacked his agent (or him): he goes for them (0: calls it off).
func set_foe(pid: int) -> void:
	foe_id = pid
	if pid == 0 and _state in ["guard", "bite"]:
		_set_state("follow", 0.4)
	elif pid != 0:
		_set_state("guard")


## He's been hit (he has `p_hp` left).
func hit(p_hp: int) -> void:
	hp = p_hp
	hurt_time = 0.3
	protect_time = 0.4


## Where he'd squat if he went now, which way he'd face, and where the
## turd would land (just behind him): [stand, facing, turd]. At home he
## wanders a little way from his kennel first.
func poo_plan() -> Array:
	var stand := position
	var face := facing
	if owner_id == 0:
		var side := Vector2.from_angle(_into_room() + PI / 2.0)
		stand = _clamp_in(kennel_front() + side * 100.0 + Vector2.from_angle(_into_room()) * 30.0)
		face = _into_room() + PI / 2.0
	return [stand, face, _clamp_in(stand - Vector2.from_angle(face) * 30.0)]


## Squats where the referee says, for POO_TIME (unless someone starts on him).
func start_poo(stand: Vector2, face: float) -> void:
	position = stand
	facing = face
	_set_state("poo", POO_TIME + 1.0)


func is_pooing() -> bool:
	return _state == "poo"


## Done: back to following, or to sitting by the kennel.
func finish_poo() -> void:
	if _state != "poo":
		return
	if owner_id == 0:
		position = kennel_front()
		facing = _into_room()
		_set_state("home")
	else:
		_set_state("follow", 0.6)


## A bite lands: a snap of the jaws.
func bite(_victim: Agent) -> void:
	_set_state("bite", 0.45)


## Where he sits when he's at home: just outside the kennel door.
func kennel_front() -> Vector2:
	if world.kennel[1] < 0:
		return World.ROOM.get_center()
	var f: Dictionary = world.furniture(world.kennel[0])[world.kennel[1]]
	var r: Rect2 = f["rect"]
	if f["wall"] == "left":
		return Vector2(r.end.x + 34.0, r.get_center().y)
	return Vector2(r.get_center().x, r.end.y + 34.0)


func _into_room() -> float:
	if world.kennel[1] < 0:
		return PI / 2.0
	return 0.0 if world.furniture(world.kennel[0])[world.kennel[1]]["wall"] == "left" else PI / 2.0


## Hidden while he's crawling through a duct with his agent.
func visible_now() -> bool:
	return not _in_duct


func busy_furniture() -> int:
	return -1


func _set_state(s: String, t := 0.0) -> void:
	_state = s
	_state_t = t


func _process(delta: float) -> void:
	hurt_time = maxf(0.0, hurt_time - delta)
	protect_time = maxf(0.0, protect_time - delta)
	moving = false
	if world == null or owner_id == 0 or _state == "poo":
		# At home, or busy: he stays put (and catches up with his agent after).
		return
	var me: Agent = game.agent_of(owner_id)
	if me == null or me.out:
		go_home()
		return
	moving = false
	if me.vent >= 0:
		_in_duct = true
		return
	if me.room != room or _in_duct:
		# Through the door (or out of the vent) right behind his agent.
		_in_duct = false
		room = me.room
		position = _clamp_in(me.position - Vector2.from_angle(me.facing) * 50.0)
		_sniffed.clear()
		_set_state("follow")
	_state_t -= delta
	var foe: Agent = game.agent_of(foe_id) if foe_id != 0 else null
	match _state:
		"guard", "bite":
			# Chases his attacker, growling, and stays on them.
			if foe == null or foe.room != room or foe.out:
				_set_state("follow")
			else:
				var to := foe.position - position
				facing = to.angle()
				if to.length() > BITE_REACH * 0.6:
					_move_to(foe.position - to.normalized() * BITE_REACH * 0.5, delta, 1.6)
				if _state == "bite" and _state_t <= 0.0:
					_set_state("guard")
		"follow":
			var spot := _clamp_in(me.position - Vector2.from_angle(me.facing) * 70.0
					+ Vector2.from_angle(me.facing + PI / 2) * 30.0)
			if position.distance_to(spot) > 40.0:
				_move_to(spot, delta, 1.0 if position.distance_to(me.position) < 220.0 else 1.25)
			elif _state_t <= 0.0:
				_state_t = 0.5
				_pick_something_to_sniff(me)
		"go":
			# Give up on anything he can't get to within a few seconds.
			if me.position.distance_to(_target) > LEASH:
				_set_state("follow")
			elif _move_to(_target, delta, 0.9) or _state_t <= 0.0:
				_set_state("sniff", SNIFF_TIME)
		"sniff":
			if _state_t <= 0.0:
				_sniffed[_key] = true
				var kind := ""
				if game.traps.has(_key):
					kind = "trap"
				elif game.contents.has(_key):
					kind = "item"
				if kind == "":
					_set_state("follow")
				else:
					_alert = kind
					_set_state("alert", ALERT_TIME)
					if flags.get(_key, "") != kind:
						flags[_key] = kind
						alerted.emit(_key, kind)
		"alert":
			if _state_t <= 0.0:
				_set_state("follow", 0.4)
	_walk += delta * (9.0 if moving else 0.0)


## The nearest piece of furniture or doorway in this room he hasn't sniffed.
func _pick_something_to_sniff(me: Agent) -> void:
	var best := ""
	var best_spot := Vector2.ZERO
	var best_d := INF
	var items: Array = world.furniture(room)
	for i in items.size():
		var key := World.furniture_key(room, i)
		if _sniffed.has(key) or world.is_kennel(room, i):
			continue
		var spot := _front_of(items[i])
		var d := spot.distance_to(position) + spot.distance_to(me.position) * 0.5
		if d < best_d:
			best = key
			best_spot = spot
			best_d = d
	for dir in World.DIR_VEC:
		if world.opening(room, dir) != 1:
			continue
		var key := World.door_key(room, dir)
		if _sniffed.has(key):
			continue
		var c := World.ROOM.get_center()
		var v := Vector2(World.DIR_VEC[dir])
		var spot := c + v * (World.ROOM.size / 2.0 - Vector2(60, 60))
		var d := spot.distance_to(position) + spot.distance_to(me.position) * 0.5
		if d < best_d:
			best = key
			best_spot = spot
			best_d = d
	if best != "" and best_spot.distance_to(me.position) < LEASH:
		_key = best
		_target = _clamp_in(best_spot)
		_set_state("go", 4.0)


func _front_of(f: Dictionary) -> Vector2:
	var r: Rect2 = f["rect"]
	var c := r.get_center()
	match f["wall"]:
		"top": return Vector2(c.x, r.end.y + 48.0)
		"bottom": return Vector2(c.x, r.position.y - 48.0)
		"left": return Vector2(r.end.x + 48.0, c.y)
		"right": return Vector2(r.position.x - 48.0, c.y)
	return Vector2(c.x, r.end.y + 48.0)


## Trots towards `to`; true once he's there.
func _move_to(to: Vector2, delta: float, pace := 1.0) -> bool:
	var d := to - position
	if d.length() < 12.0:
		return true
	moving = true
	facing = d.angle()
	var before := position
	position = _clamp_in(position + d.limit_length(SPEED * pace * delta))
	# Blocked (furniture or a wall in the way)? Near enough will do.
	return position.distance_to(before) < SPEED * pace * delta * 0.2


## Keeps him in the room and out of the furniture.
func _clamp_in(p: Vector2) -> Vector2:
	var area := World.ROOM.grow(-26.0)
	p = p.clamp(area.position, area.end)
	for f in world.furniture(room):
		var r: Rect2 = (f["rect"] as Rect2).grow(16.0)
		if r.has_point(p):
			var push := [p.x - r.position.x, r.end.x - p.x, p.y - r.position.y, r.end.y - p.y]
			var m: float = push.min()
			match push.find(m):
				0: p.x = r.position.x
				1: p.x = r.end.x
				2: p.y = r.position.y
				3: p.y = r.end.y
	return p


# ---------------------------------------------------------------- drawing

static func _load_meta() -> Dictionary:
	if _meta.is_empty() and FileAccess.file_exists("res://assets/sprites/dog.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/dog.json"))
		if parsed is Dictionary:
			_meta = parsed
	return _meta


static func sheet() -> Texture2D:
	if _tex == null:
		var m := _load_meta()
		if m.has("sheets") and ResourceLoader.exists(m["sheets"]["dog"]):
			var ct := CanvasTexture.new()
			ct.diffuse_texture = load(m["sheets"]["dog"])
			if ResourceLoader.exists(m["normals"]["dog"]):
				ct.normal_texture = load(m["normals"]["dog"])
			_tex = ct
	return _tex


## The animation and frame he's showing.
func _frame() -> Array:
	var now := Time.get_ticks_msec()
	var fr := []
	match _state:
		"home":
			fr = ["sit", int(now / 900) % 2]
		"poo":
			fr = ["poo", int(now / 450) % 2] if _load_meta()["anims"].has("poo") else ["sit", 0]
		"sniff":
			fr = ["sniff", int(now / 160) % 4]
		"alert":
			fr = ["growl", int(now / 200) % 2] if _alert == "trap" else ["bark", int(now / 120) % 4]
		"bite":
			fr = ["bite", mini(2, int((0.45 - _state_t) / 0.15))]
		"guard":
			if not moving:
				fr = ["growl", int(now / 200) % 2]
	if not fr.is_empty():
		return fr
	if moving:
		return ["walk", int(fposmod(_walk, TAU) / TAU * 8.0) % 8]
	return ["idle", int(now / 700) % 2]


## The current frame as the first-person camera at (cx, cy) sees it (as
## Agent.frame_for_view).
func frame_for_view(cx: float, cy: float) -> Dictionary:
	var m := _load_meta()
	var dirs: int = m["directions"]
	var fr := _frame()
	var view := atan2(position.y - cy, position.x - cx)
	var d := posmod(int(round((facing - view + deg_to_rad(225.0)) / (TAU / dirs))), dirs)
	var fid: int = d * int(m["frames_per_direction"]) + int(m["anims"][fr[0]]["start"]) + int(fr[1])
	var r: Array = m["rects"]["dog"][fid]
	var size := Vector2(r[2], r[3])
	var anchor := Vector2(m["anchor"][0], m["anchor"][1])
	return {
		"region": Rect2(r[0], r[1], r[2], r[3]),
		"scale": SPRITE_HEIGHT / (SPRITE_METRES * float(m["pixels_per_metre"])),
		"centre": -anchor + Vector2(r[4], r[5]) + size / 2.0,
	}


## Draws him onto the room renderer (depth-sorted with the furniture).
func paint(ci: CanvasItem) -> void:
	var tex := sheet()
	if tex == null or not visible_now():
		return
	var m := _load_meta()
	var dirs: int = m["directions"]
	var anchor := Vector2(m["anchor"][0], m["anchor"][1])
	var scale_f := SPRITE_HEIGHT / (SPRITE_METRES * float(m["pixels_per_metre"]))
	var foot := World.iso(position)
	ci.draw_set_transform(foot, 0.0, Vector2(1.0, 0.5))
	ci.draw_texture_rect(Art.soft(), Rect2(-34, -34, 68, 68), false, Color(0, 0, 0, 0.6))
	var fr := _frame()
	var d := posmod(int(round(facing / (TAU / dirs))), dirs)
	var fid: int = d * int(m["frames_per_direction"]) + int(m["anims"][fr[0]]["start"]) + int(fr[1])
	var r: Array = m["rects"]["dog"][fid]
	var region := Rect2(r[0], r[1], r[2], r[3])
	var tint := Color.WHITE.lerp(Color(1.0, 0.45, 0.45), hurt_time / 0.3)
	ci.draw_set_transform(foot, 0.0, Vector2(scale_f, scale_f))
	ci.draw_texture_rect_region(tex, Rect2(-anchor + Vector2(r[4], r[5]), region.size), region, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# His health, once he's someone's dog.
	if owner_id != 0:
		for i in MAX_HP:
			var pip := foot + Vector2((i - (MAX_HP - 1) / 2.0) * 11.0, -64.0)
			ci.draw_circle(pip, 3.8, Color(0, 0, 0, 0.6))
			ci.draw_circle(pip, 2.8, Color("ffb13b") if i < hp else Color(1, 1, 1, 0.15))
	# What he's saying.
	var word := ""
	var col := Color("ffd23f")
	if _state == "alert":
		word = "GRRR…" if _alert == "trap" else "WOOF!"
		col = Color("ff5a5f") if _alert == "trap" else Color("ffd23f")
	elif _state == "bite" or _state == "guard":
		word = "GRRAH!" if _state == "bite" else "GRRR!"
		col = Color("ff5a5f")
	elif _state == "sniff":
		word = "sniff sniff"
		col = Color(1, 1, 1, 0.75)
	elif _state == "poo":
		word = "hnnng…"
		col = Color(1, 1, 1, 0.75)
	if word != "":
		var quiet := _state == "sniff" or _state == "poo"
		var font := Style.typewriter() if quiet else Style.stencil()
		var size := 15 if quiet else 22
		var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var bob := sin(Time.get_ticks_msec() / 90.0) * 2.0
		ci.draw_string_outline(font, foot + Vector2(-w / 2, -86 + bob), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5,
				Color(0, 0, 0, 0.85))
		ci.draw_string(font, foot + Vector2(-w / 2, -86 + bob), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Paw-print marks over what he's pointed out, for his agent's eyes only.
func paint_marks(ci: CanvasItem, my_id: int, heights: Dictionary) -> void:
	if owner_id != my_id or owner_id == 0:
		return
	var items: Array = world.furniture(room)
	for i in items.size():
		var key := World.furniture_key(room, i)
		if not flags.has(key):
			continue
		var f: Dictionary = items[i]
		var top := World.iso((f["rect"] as Rect2).get_center(), heights.get(f["type"], 50.0) + 34.0)
		var trap: bool = flags[key] == "trap"
		_paw(ci, top, Color("ff5a5f") if trap else Color("ffd23f"))
		var label := "GRR" if trap else "WOOF"
		var font := Style.stencil()
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		ci.draw_string_outline(font, top + Vector2(-w / 2, 30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4,
				Color(0, 0, 0, 0.8))
		ci.draw_string(font, top + Vector2(-w / 2, 30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color("ff5a5f") if trap else Color("ffd23f"))


## What he's left behind, wherever in `room` it is: a glistening brown
## swirl with a whiff coming off it.
static func paint_turds(ci: CanvasItem, turds: Array, room: Vector2i) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for t in turds:
		if t["room"] != room:
			continue
		var c := World.iso(t["pos"])
		ci.draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
		ci.draw_circle(Vector2.ZERO, 17.0, Color(0, 0, 0, 0.45))
		var layers := [[14.0, 0.0, Color("4a2c14")], [11.0, -7.0, Color("5c3719")], [7.5, -13.0, Color("6b4220")]]
		for l in layers:
			ci.draw_set_transform(c + Vector2(0, l[1]), 0.0, Vector2(1.0, 0.62))
			ci.draw_circle(Vector2.ZERO, l[0] + 1.5, Color(0.12, 0.07, 0.03))
			ci.draw_circle(Vector2.ZERO, l[0], l[2])
			ci.draw_circle(Vector2(-l[0] * 0.35, -l[0] * 0.35), l[0] * 0.28, Color(1, 0.9, 0.75, 0.25))
		ci.draw_set_transform(c, 0.0, Vector2.ONE)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-4, -17), Vector2(4, -17), Vector2(1, -24)]),
				Color("6b4220"))
		# The whiff.
		for k in 3:
			var life := fmod(now * 0.6 + k * 0.33, 1.0)
			var pts := PackedVector2Array()
			for j in 6:
				var y := -22.0 - life * 34.0 - j * 4.0
				pts.append(Vector2(-10.0 + k * 10.0 + sin(now * 4.0 + j * 1.3 + k) * 3.0, y))
			ci.draw_polyline(pts, Color(0.75, 0.85, 0.55, 0.5 * (1.0 - life)), 1.5, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A little paw print.
static func _paw(ci: CanvasItem, at: Vector2, col: Color) -> void:
	ci.draw_circle(at + Vector2(0, 6), 8.0, Color(0, 0, 0, 0.6))
	ci.draw_circle(at + Vector2(0, 6), 6.5, col)
	for k in 4:
		var a := -PI * 0.85 + k * PI * 0.23
		var p := at + Vector2(0, 6) + Vector2.from_angle(a) * 10.5
		ci.draw_circle(p, 3.6, Color(0, 0, 0, 0.6))
		ci.draw_circle(p, 2.8, col)
