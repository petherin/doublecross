extends Node2D
## Additive light drawn over the room: ceiling-lamp pools and shafts, dust in
## the light, screen and exit glows, and the flash from explosions.

const World = preload("res://scripts/core/world.gd")
const Art = preload("res://scripts/render/art.gd")

var view: Node2D   # the RoomView this belongs to


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _process(_delta: float) -> void:
	queue_redraw()


func _floor_xf() -> Transform2D:
	var k := World.ISO_K
	return Transform2D(Vector2(k, k * 0.5), Vector2(-k, k * 0.5), World.iso(Vector2.ZERO))


func _draw() -> void:
	if view == null or view.world == null:
		return
	var world: World = view.world
	var room: Vector2i = view.room
	var t: float = view._t
	var R := World.ROOM
	var tint: Color = world.rooms[room]["tint"]
	var soft := Art.soft()
	var warm := Color(1.0, 0.88, 0.7).lerp(tint, 0.35)

	# Ceiling lamps: a pool on the floor and a faint shaft of light above it.
	var lamps := [Vector2(R.position.x + R.size.x * 0.3, R.get_center().y), Vector2(R.position.x + R.size.x * 0.72, R.get_center().y)]
	var hash_v := room.x * 7 + room.y * 13 + world.seed_value % 97
	for i in lamps.size():
		var lp: Vector2 = lamps[i]
		# One lamp in some rooms flickers.
		var flicker := 1.0
		if (hash_v + i) % 4 == 0:
			flicker = 0.75 + 0.25 * signf(sin(t * 13.0 + sin(t * 3.1) * 4.0))
		var top := World.iso(lp, 210.0)
		var l := World.iso(lp + Vector2(-140, 140), 0.0)
		var r := World.iso(lp + Vector2(140, -140), 0.0)
		draw_polygon(PackedVector2Array([top, l, r]),
			PackedColorArray([Color(warm, 0.07 * flicker), Color(warm, 0.0), Color(warm, 0.0)]))
		# Dust drifting through the light.
		for d in 9:
			var ph := float(d) * 1.7 + i * 3.0
			var dp := lp + Vector2(sin(t * 0.3 + ph) * 90.0, cos(t * 0.23 + ph * 1.3) * 90.0)
			var z := 60.0 + fmod(t * 8.0 + d * 37.0, 260.0)
			draw_circle(World.iso(dp, z), 1.4, Color(warm, 0.35 * flicker * (1.0 - z / 330.0)))

	# Coloured spill from the wall light strips.
	draw_set_transform_matrix(_floor_xf())
	draw_texture_rect(soft, Rect2(R.position.x - 200, R.position.y - 160, R.size.x + 400, 320), false, Color(tint, 0.09))
	draw_texture_rect(soft, Rect2(R.position.x - 160, R.position.y - 200, 320, R.size.y + 400), false, Color(tint, 0.07))


	# Daylight from the exit.
	for dir in [World.Dir.UP, World.Dir.LEFT]:
		if world.is_exit(room, dir):
			var v := Vector2(World.DIR_VEC[dir])
			var door := R.get_center() + v * R.size / 2.0
			draw_texture_rect(soft, Rect2(door - Vector2(220, 220), Vector2(440, 440)), false, Color(1.0, 0.95, 0.75, 0.25))

	# Explosions light up the room.
	for e in view._effects:
		if e["room"] == room and e["kind"] == "BOMB":
			var a := clampf(1.0 - e["t"] / 0.9, 0.0, 1.0)
			var p: Vector2 = e["pos"]
			draw_texture_rect(soft, Rect2(p - Vector2(500, 500), Vector2(1000, 1000)), false, Color(1.0, 0.55, 0.2, 0.55 * a))
	draw_set_transform_matrix(Transform2D.IDENTITY)
