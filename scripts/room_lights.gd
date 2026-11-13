extends Node2D
## Real 2D lights for the room the local agent is in. They shade the agents
## and furniture through their normal maps (rendered in Blender), and light
## the floor and walls evenly where there's no normal map.
##
## Positions are in the room view's screen space; `height` is how high the
## light hangs above the floor (in pixels), which sets the shading angle.

const World = preload("res://scripts/world.gd")

var _light_tex: Texture2D
var _flashes: Array = []     # [light, age]
var _flicker: Array = []     # [light, base energy, phase]
var _t := 0.0


func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_light_tex = t


func _light(floor_pos: Vector2, radius: float, color: Color, energy: float, height: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _light_tex
	l.position = World.iso(floor_pos)
	# A circle on the floor looks like a 2:1 ellipse on screen.
	l.texture_scale = radius * World.ISO_K * 2.0 / 256.0 * 1.42
	l.scale = Vector2(1.0, 0.5)
	l.color = color
	l.energy = energy
	l.height = height
	add_child(l)
	return l


## Sets up the lights for `room` (called whenever the view changes room).
func rebuild(world: World, room: Vector2i) -> void:
	for c in get_children():
		c.queue_free()
	_flicker.clear()
	_flashes.clear()
	var R := World.ROOM
	var tint: Color = world.rooms[room]["tint"]
	var warm := Color(1.0, 0.86, 0.66).lerp(tint, 0.25)
	var h := room.x * 7 + room.y * 13 + world.seed_value % 97
	# Ceiling lamps, high up so tops catch more light than sides.
	for i in 2:
		var lp := Vector2(R.position.x + R.size.x * (0.3 if i == 0 else 0.72), R.get_center().y)
		var l := _light(lp, 420.0, warm, 0.85, 220.0)
		if (h + i) % 4 == 0:
			_flicker.append([l, l.energy, float(i) * 3.0])
	# Coloured spill from the light strips along the two back walls.
	_light(Vector2(R.get_center().x, R.position.y + 40), 520.0, tint, 0.55, 90.0)
	_light(Vector2(R.position.x + 40, R.get_center().y), 420.0, tint, 0.45, 90.0)
	# Screens glow onto whoever is standing at them.
	for f in world.furniture(room):
		if f["type"] == "console" or f["type"] == "desk":
			var c: Rect2 = f["rect"]
			var out := (R.get_center() - c.get_center()).normalized() * 50.0
			_light(c.get_center() + out, 170.0, Color(0.45, 1.0, 0.7).lerp(tint, 0.4), 0.55, 50.0)
	# Daylight through the exit.
	for dir in [World.Dir.UP, World.Dir.LEFT]:
		if world.is_exit(room, dir):
			var v := Vector2(World.DIR_VEC[dir])
			_light(R.get_center() + v * (R.size / 2.0 - Vector2(40, 40)), 360.0, Color(1.0, 0.95, 0.78), 1.4, 120.0)


## A burst of light (e.g. an explosion) at a floor position.
func flash(floor_pos: Vector2, color: Color, energy: float) -> void:
	var l := _light(floor_pos, 560.0, color, energy, 80.0)
	_flashes.append([l, 0.0, energy])


func _process(delta: float) -> void:
	_t += delta
	for f in _flicker:
		var l: PointLight2D = f[0]
		if is_instance_valid(l):
			l.energy = f[1] * (0.7 + 0.3 * signf(sin(_t * 13.0 + f[2] + sin(_t * 3.1) * 4.0)))
	var keep := []
	for f in _flashes:
		var l: PointLight2D = f[0]
		f[1] += delta
		if not is_instance_valid(l):
			continue
		if f[1] > 0.9:
			l.queue_free()
			continue
		l.energy = f[2] * (1.0 - f[1] / 0.9) * (0.85 + 0.15 * sin(f[1] * 60.0))
		keep.append(f)
	_flashes = keep
