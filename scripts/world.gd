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
const FREE_TYPES := ["crate", "desk", "plant", "crate"]

var seed_value := 0
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


func has_door(room: Vector2i, dir: int) -> bool:
	var n: Vector2i = room + DIR_VEC[dir]
	return n.x >= 0 and n.y >= 0 and n.x < COLS and n.y < ROWS


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
		var pool: Array = FREE_TYPES if s["wall"] == "free" else WALL_TYPES
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


static func _shuffled(arr: Array, rng: RandomNumberGenerator) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a
