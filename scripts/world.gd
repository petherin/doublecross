extends RefCounted
## The secret base: a grid of rooms with furniture, generated from a seed.
## Both tablets generate the same base from the same seed, so only the seed
## needs to be sent over the network.

const COLS := 3
const ROWS := 3
## Walkable floor area of a room, in screen pixels (viewport is 1280x800).
const ROOM := Rect2(100, 110, 1080, 640)
const WALL := 40.0
const DOOR_HALF := 75.0

## Isometric projection. Gameplay happens on a flat floor (ROOM, in floor
## units); these turn floor positions + height into screen positions.
## Floor "up" (towards the UP door) points to the upper-right of the screen.
const ISO_K := 0.68
const WALL_H := 110.0
const ISO_ORIGIN := Vector2(640.0 - (1080.0 - 640.0) * 0.68 * 0.5, 60.0 + 110.0 + 20.0)

enum Dir { UP, DOWN, LEFT, RIGHT }
const DIR_VEC := {
	Dir.UP: Vector2i(0, -1),
	Dir.DOWN: Vector2i(0, 1),
	Dir.LEFT: Vector2i(-1, 0),
	Dir.RIGHT: Vector2i(1, 0),
}
const OPPOSITE := {Dir.UP: Dir.DOWN, Dir.DOWN: Dir.UP, Dir.LEFT: Dir.RIGHT, Dir.RIGHT: Dir.LEFT}

const ROOM_NAMES := [
	"Command Centre", "Comms Array", "Armoury", "Laboratory", "Reactor Core",
	"Server Vault", "Hangar Bay", "Briefing Room", "Detention Block",
]
const ROOM_TINTS := [
	Color("3fd0ff"), Color("ff6b3d"), Color("7dff6b"), Color("c86bff"),
	Color("ffd23f"), Color("3dffc8"), Color("ff3f8e"), Color("6b8cff"), Color("ff9f3f"),
]

## Furniture footprint when standing against the top or bottom wall.
const TYPES := {
	"desk": Vector2(150, 70),
	"console": Vector2(180, 60),
	"cabinet": Vector2(70, 60),
	"locker": Vector2(110, 50),
	"crate": Vector2(80, 80),
	"shelf": Vector2(160, 45),
	"safe": Vector2(75, 75),
	"plant": Vector2(55, 55),
	"rack": Vector2(140, 40),
	"sofa": Vector2(170, 70),
}
const WALL_TYPES := ["desk", "console", "cabinet", "locker", "shelf", "safe", "plant", "rack", "sofa"]
## Front walls (bottom/right) sit nearest the camera, so only low furniture
## goes there; tall pieces would hide the agents behind them.
const FRONT_TYPES := ["desk", "crate", "safe", "plant", "sofa", "console"]
const FREE_TYPES := ["crate", "desk", "plant", "crate"]

const INTEL := ["PASSPORT", "CASH", "MICROFILM", "KEYCARD"]
const BRIEFCASE := "BRIEFCASE"
## Gadgets go on your tool belt (they don't count towards the carry limit).
const GADGETS := ["WIRE CUTTERS", "EXTINGUISHER", "TOOLKIT"]
## Trap -> the gadget that defuses it.
const TRAPS := {"BOMB": "EXTINGUISHER", "SPRING": "TOOLKIT", "WIRE": "WIRE CUTTERS"}
const TRAP_NAMES := {"BOMB": "PAINT BOMB", "SPRING": "SPRING TRAP", "WIRE": "TRIPWIRE"}

var seed_value := 0
## The one room with a way out, and which (outer, back) wall it's on.
var exit_room := Vector2i(1, 0)
var exit_dir: int = Dir.UP
## Starting contents of the furniture: furniture_key -> item name.
var hidden := {}
## Vector2i -> { "name": String, "tint": Color, "furniture": Array[Dictionary] }
var rooms := {}


func _init(seed_in: int) -> void:
	seed_value = seed_in
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_in
	var names := _shuffled(ROOM_NAMES, rng)
	var tints := _shuffled(ROOM_TINTS, rng)
	var i := 0
	for y in ROWS:
		for x in COLS:
			rooms[Vector2i(x, y)] = {
				"name": names[i],
				"tint": tints[i],
				"furniture": _make_furniture(rng),
			}
			i += 1
	# The exit is on a back (upper) outer wall so it's always in view,
	# and never in a starting room.
	var exits := [
		[Vector2i(1, 0), Dir.UP], [Vector2i(2, 0), Dir.UP],
		[Vector2i(0, 1), Dir.LEFT], [Vector2i(0, 2), Dir.LEFT],
	]
	var e: Array = exits[rng.randi_range(0, exits.size() - 1)]
	exit_room = e[0]
	exit_dir = e[1]
	_hide_items(rng)


func has_door(room: Vector2i, dir: int) -> bool:
	var n: Vector2i = room + DIR_VEC[dir]
	return n.x >= 0 and n.y >= 0 and n.x < COLS and n.y < ROWS


func is_exit(room: Vector2i, dir: int) -> bool:
	return room == exit_room and dir == exit_dir


## 0 = solid wall, 1 = door to another room, 2 = the exit.
func opening(room: Vector2i, dir: int) -> int:
	if has_door(room, dir):
		return 1
	if is_exit(room, dir):
		return 2
	return 0


static func furniture_key(room: Vector2i, idx: int) -> String:
	return "%d,%d,%d" % [room.x, room.y, idx]


static func key_room(key: String) -> Vector2i:
	var p := key.split(",")
	return Vector2i(int(p[0]), int(p[1]))


static func key_index(key: String) -> int:
	return int(key.split(",")[2])


## One key per doorway, the same from both sides of it.
static func door_key(room: Vector2i, dir: int) -> String:
	if dir == Dir.UP or dir == Dir.LEFT:
		room += DIR_VEC[dir]
		dir = OPPOSITE[dir]
	return "D%d,%d,%d" % [room.x, room.y, dir]


func furniture(room: Vector2i) -> Array:
	return rooms[room]["furniture"]


## Where a player appears after walking through a door in direction `dir`.
static func entry_point(dir: int, radius: float) -> Vector2:
	var c := ROOM.get_center()
	match dir:
		Dir.UP: return Vector2(c.x, ROOM.end.y - radius - 6)
		Dir.DOWN: return Vector2(c.x, ROOM.position.y + radius + 6)
		Dir.LEFT: return Vector2(ROOM.end.x - radius - 6, c.y)
		_: return Vector2(ROOM.position.x + radius + 6, c.y)


## Floor position (room coordinates) + height above the floor -> screen.
static func iso(p: Vector2, z := 0.0) -> Vector2:
	var u := p.x - ROOM.position.x
	var v := p.y - ROOM.position.y
	return ISO_ORIGIN + Vector2((u - v) * ISO_K, (u + v) * ISO_K * 0.5 - z)


## Converts a direction the player pushes on screen into a floor direction,
## so "up on the joystick" always means "up the screen".
static func screen_to_floor_dir(s: Vector2) -> Vector2:
	if s == Vector2.ZERO:
		return Vector2.ZERO
	var d := Vector2(s.x + 2.0 * s.y, 2.0 * s.y - s.x) * 0.5
	return d.normalized() * minf(s.length(), 1.0)


## Floor direction -> screen direction (for choosing which way a sprite faces).
static func floor_to_screen_dir(d: Vector2) -> Vector2:
	return Vector2(d.x - d.y, (d.x + d.y) * 0.5)


func _make_furniture(rng: RandomNumberGenerator) -> Array:
	var slots := []
	for x in [230.0, 410.0, 870.0, 1050.0]:
		slots.append({"wall": "top", "c": x})
		slots.append({"wall": "bottom", "c": x})
	for y in [230.0, 630.0]:
		slots.append({"wall": "left", "c": y})
		slots.append({"wall": "right", "c": y})
	slots.append({"wall": "free", "c": Vector2(400, 430)})
	slots.append({"wall": "free", "c": Vector2(880, 430)})
	slots = _shuffled(slots, rng)

	var want := rng.randi_range(4, 6)
	var out := []
	for s in slots:
		if out.size() >= want:
			break
		var pool: Array = WALL_TYPES
		if s["wall"] == "free":
			pool = FREE_TYPES
		elif s["wall"] == "bottom" or s["wall"] == "right":
			pool = FRONT_TYPES
		var t: String = pool[rng.randi_range(0, pool.size() - 1)]
		var sz: Vector2 = TYPES[t]
		var r: Rect2
		match s["wall"]:
			"top": r = Rect2(s["c"] - sz.x / 2, ROOM.position.y, sz.x, sz.y)
			"bottom": r = Rect2(s["c"] - sz.x / 2, ROOM.end.y - sz.y, sz.x, sz.y)
			"left": r = Rect2(ROOM.position.x, s["c"] - sz.x / 2, sz.y, sz.x)
			"right": r = Rect2(ROOM.end.x - sz.y, s["c"] - sz.x / 2, sz.y, sz.x)
			_: r = Rect2(s["c"] - sz / 2, sz)
		var clash := false
		for f in out:
			if (f["rect"] as Rect2).grow(14).intersects(r):
				clash = true
				break
		if not clash:
			out.append({"type": t, "rect": r, "wall": s["wall"], "detail": rng.randi()})
	return out


## Hides each intel item and the briefcase in a different room.
func _hide_items(rng: RandomNumberGenerator) -> void:
	var spots := []
	for r in rooms:
		for i in (rooms[r]["furniture"] as Array).size():
			spots.append([r, i])
	spots = _shuffled(spots, rng)
	var used_rooms := {}
	for item in INTEL + [BRIEFCASE] + GADGETS:
		for spot in spots:
			var key := furniture_key(spot[0], spot[1])
			if hidden.has(key) or used_rooms.has(spot[0]):
				continue
			hidden[key] = item
			used_rooms[spot[0]] = true
			break


static func _shuffled(arr: Array, rng: RandomNumberGenerator) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a
