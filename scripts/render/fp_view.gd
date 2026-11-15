extends Node3D
## First-person view of the room the local agent is in: real 3D walls, floor
## and Blender-modelled furniture, with the other agents as Doom-style
## cut-outs picked from their 8-direction sprite sheets.
##
## Floor (x, y) in game units maps to 3D (x, height, y); one 3D unit is one
## game unit, so the furniture models and footprints line up exactly.

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")
const FpEffects = preload("res://scripts/render/fp_effects.gd")
const RoomView = preload("res://scripts/render/room_view.gd")
const Style = preload("res://scripts/ui/style.gd")
const FpDecor = preload("res://scripts/render/fp_decor.gd")

## Taller than the isometric cut-away walls, so the room feels enclosed.
const WALL_H := 210.0
const DOOR_H := 150.0
const EYE_H := 104.0
## The room textures cover 128 units each way (the wall is 110 high).
const TEX_UNITS := 128.0
## How high off the floor the band of wall decorations starts.
const DECOR_Y := 22.0
## The short passage between neighbouring rooms, seen through doorways.
const GAP := 60.0
## How far the corridors run on out of the rooms next door.
const STUB := 150.0
## How far you can look up or down (radians).
const MAX_PITCH := 0.75
const WALL_ROT := {"top": 0.0, "bottom": 180.0, "left": 90.0, "right": -90.0, "free": 0.0}

static var _ceiling_cache: ImageTexture

var world: World
var room := Vector2i(-1, -1)
## Detailed mode builds the rooms next door and animates the wall screens;
## the light mode (for slower phones) leaves both out.
var detail_high := true
## Looking up (+) or down (-), in radians.
var pitch := 0.0
## Nacho the dog, shown as a cut-out like the agents.
var dog: Node
var camera: Camera3D
var _dog_sprite: Sprite3D
var _room_root: Node3D
## Where new room pieces go: the room itself, or a neighbour beyond a door.
var _target: Node3D
var _env: WorldEnvironment
var _furniture: Array = []        # MeshInstance3D roots, by furniture index
var _cutouts := {}                # Agent -> Sprite3D
var _labels := {}                 # Agent -> Label3D
var _highlight_mat: StandardMaterial3D
var _models := {}
var _t := 0.0
var _fx: FpEffects
var _vents := {}                  # vent index -> grille MeshInstance3D
var _vent_mat: StandardMaterial3D
var _markers := {}                # trap key -> Node3D
var _cam_drop := 0.0              # eye lowered while knocked down
var _painters: Array = []         # wall-decor painters, refreshed for animated screens
var _decor_t := 0.0
var _darts: Array = []            # MeshInstance3D pool for darts in flight
var _cam_roll := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 2.0
	camera.far = 3000.0
	add_child(camera)
	_env = WorldEnvironment.new()
	_env.environment = Environment.new()
	_env.environment.background_mode = Environment.BG_COLOR
	_env.environment.background_color = Color(0.01, 0.01, 0.015)
	_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# A little haze, so the rooms and corridors beyond fade into the dark.
	_env.environment.fog_enabled = true
	_env.environment.fog_light_color = Color(0.03, 0.03, 0.04)
	_env.environment.fog_density = 0.0012
	add_child(_env)
	_room_root = Node3D.new()
	add_child(_room_root)
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fx = FpEffects.new()
	add_child(_fx)
	_vent_mat = StandardMaterial3D.new()
	_vent_mat.albedo_color = Color(0.1, 0.11, 0.13)
	_vent_mat.metallic = 0.6
	_vent_mat.roughness = 0.5


## Turns the view on or off (the 2D isometric view is used when off).
func set_active(on: bool) -> void:
	visible = on
	camera.current = on
	_env.environment = _env.environment if on else _env.environment


## Tilts the view up (+) or down (-) by `amount` radians, within limits.
func look(amount: float) -> void:
	pitch = clampf(pitch + amount, -MAX_PITCH, MAX_PITCH)


## Builds the 3D room (called on entering a room, while the view is active).
func rebuild(p_world: World, p_room: Vector2i) -> void:
	world = p_world
	room = p_room
	for c in _room_root.get_children():
		c.queue_free()
	_furniture.clear()
	for a in _cutouts:
		if is_instance_valid(_cutouts[a]):
			_cutouts[a].queue_free()
			_labels[a].queue_free()
	_cutouts.clear()
	_labels.clear()
	_dog_sprite = null
	_fx.clear()
	_vents.clear()
	_markers.clear()
	_painters.clear()
	_darts.clear()
	var tint: Color = world.rooms[room]["tint"]
	_env.environment.ambient_light_color = Color(0.32, 0.33, 0.38).lerp(tint, 0.2)
	_env.environment.ambient_light_energy = 0.9
	_target = _room_root
	_build_shell(room, tint, -1)
	_build_lights(tint, 1.0)
	var items: Array = world.furniture(room)
	for f in items:
		_furniture.append(_place_furniture(f))
	# The rooms next door, seen through the doorways (their furniture and
	# lights, but not who's in them: that stays hidden, as it is overhead).
	for dir in World.DIR_VEC:
		if not detail_high or world.opening(room, dir) != 1:
			continue
		var n: Vector2i = room + World.DIR_VEC[dir]
		var nroot := Node3D.new()
		var v := Vector2(World.DIR_VEC[dir])
		var r := World.ROOM
		nroot.position = Vector3(v.x * (r.size.x + GAP), 0.0, v.y * (r.size.y + GAP))
		_room_root.add_child(nroot)
		_target = nroot
		var ntint: Color = world.rooms[n]["tint"]
		_build_shell(n, ntint, World.OPPOSITE[dir])
		_build_lights(ntint, 0.7)
		for f in world.furniture(n):
			_place_furniture(f)
		_target = _room_root
		_passage(dir, tint)
	for i in world.vents.size():
		if world.vents[i]["room"] == room:
			_vents[i] = _place_vent(world.vents[i])


## Follows the local agent and draws the others; `highlight` is the
## furniture index the player can search (or -1).
func update_view(me: Agent, agents: Array, highlight: int, delta: float) -> void:
	_t += delta
	# Your own knockouts, felt: the view reels when stunned, judders when
	# shocked, and drops to the floor when you're taken out.
	var ko := me.ko_time > 0.0
	var drop := EYE_H - 26.0 if ko and me.ko_kind == "DOWN" else 0.0
	_cam_drop = lerpf(_cam_drop, drop, minf(1.0, delta * 10.0))
	var roll := 0.0
	var jitter := Vector3.ZERO
	if ko and me.ko_kind == "DOWN":
		roll = 0.5
	elif ko and me.ko_kind == "SHOCK":
		jitter = Vector3(sin(_t * 97.0), cos(_t * 83.0), 0.0) * 3.0
	elif ko:
		roll = sin(_t * 3.0) * 0.14
	if Settings.reduced_motion:
		roll = 0.0
		jitter = Vector3.ZERO
	_cam_roll = lerpf(_cam_roll, roll, minf(1.0, delta * 6.0))
	var bob := sin(_t * 9.0) * (2.0 if me.moving and not Settings.reduced_motion else 0.0)
	camera.position = Vector3(me.position.x, EYE_H + bob - _cam_drop, me.position.y) + jitter
	camera.rotation = Vector3(0.0 if ko else pitch, -me.facing - PI / 2.0, _cam_roll)
	for i in _furniture.size():
		_set_highlight(_furniture[i], i == highlight)
	_show_dog()
	for a: Agent in agents:
		if a == me:
			continue
		var show := a.room == room and not a.out and a.vent < 0
		if show and not _cutouts.has(a):
			_add_cutout(a)
		if _cutouts.has(a):
			_cutouts[a].visible = show
			_labels[a].visible = show
			if show:
				_update_cutout(a)


# ------------------------------------------------------------------ the room

## The floor, ceiling and walls of room `r_room`. `from_dir` is the door we
## look in through when it's a neighbour (-1 for the room we're in); every
## other doorway out of a neighbour is shown as a dark opening.
func _build_shell(r_room: Vector2i, tint: Color, from_dir: int) -> void:
	var r := World.ROOM
	var floor_mat := _surface_mat("floor", Color(0.5, 0.52, 0.56).lerp(tint, 0.04))
	floor_mat.uv1_scale = Vector3(r.size.x / TEX_UNITS, r.size.y / TEX_UNITS, 1.0)
	_quad(Vector2(r.size.x, r.size.y), Vector3(r.get_center().x, 0.0, r.get_center().y),
			Vector3(-PI / 2.0, 0.0, 0.0), floor_mat)
	_build_ceiling(tint, from_dir == -1)
	var c := r.get_center()
	var dh := World.DOOR_HALF
	# Each wall: where it runs, which way its face points, and its door.
	var walls := {
		World.Dir.UP: [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), 0.0, c.x],
		World.Dir.DOWN: [Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), PI, c.x],
		World.Dir.LEFT: [Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), PI / 2.0, c.y],
		World.Dir.RIGHT: [Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), -PI / 2.0, c.y],
	}
	for dir in walls:
		var w: Array = walls[dir]
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var opening := world.opening(r_room, dir)
		var along := (b - a).normalized()
		var length := a.distance_to(b)
		var mid_t := length / 2.0
		var spans := [[0.0, length]] if opening == 0 else [[0.0, mid_t - dh], [mid_t + dh, length]]
		for sp in spans:
			_wall(a + along * sp[0], a + along * sp[1], 0.0, WALL_H, w[2], tint)
		if from_dir == -1:
			_decor(a, b, w[2], spans, tint, dir)
		if opening != 0:
			_wall(a + along * (mid_t - dh), a + along * (mid_t + dh), DOOR_H, WALL_H, w[2], tint)
			# Doors from the room we're in lead to rooms we've built; others are dark.
			if opening == 1 and from_dir != -1 and dir != from_dir:
				# Out of a room next door: a dim corridor running on into the base.
				_stub(dir, tint)
				continue
			var built: bool = opening == 1 and ((from_dir == -1 and detail_high) or dir == from_dir)
			if not built:
				_doorway(a + along * mid_t, w[2], opening == 2)


func _wall(a: Vector2, b: Vector2, bottom: float, top: float, yaw: float, tint: Color) -> void:
	var length := a.distance_to(b)
	var mat := _surface_mat("wall", Color(0.62, 0.64, 0.7).lerp(tint, 0.05))
	var h := top - bottom
	# The texture is one 110-unit panel high: stack panels up the wall.
	mat.uv1_scale = Vector3(length / TEX_UNITS, h / 110.0, 1.0)
	var mid := (a + b) / 2.0
	_quad(Vector2(length, h), Vector3(mid.x, bottom + h / 2.0, mid.y), Vector3(0.0, yaw, 0.0), mat)


## The decorations on one wall of the room we're in, as a picture hung just
## in front of it (painted by the same code as the overhead view).
func _decor(a: Vector2, b: Vector2, yaw: float, spans: Array, tint: Color, dir: int) -> void:
	var length := a.distance_to(b)
	# Overhead, the back walls are walls 0 and 1; the front walls get their own.
	var wall: int = {World.Dir.UP: 0, World.Dir.LEFT: 1, World.Dir.DOWN: 2, World.Dir.RIGHT: 3}[dir]
	var painter := FpDecor.paint(_room_root, length, spans, tint, wall, world.seed_value, room)
	_painters.append(painter)
	var tex: Texture2D = painter.texture()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.3
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mid := (a + b) / 2.0
	# Just in front of the wall, so it doesn't flicker against it.
	var inward := Vector3(sin(yaw), 0.0, cos(yaw)) * 0.8
	_quad(Vector2(length, FpDecor.BAND_H), Vector3(mid.x, DECOR_Y + FpDecor.BAND_H / 2.0, mid.y) + inward,
			Vector3(0.0, yaw, 0.0), m)


## A dark passage beyond a doorway, or daylight beyond the exit.
func _doorway(at: Vector2, yaw: float, is_exit: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.8) if is_exit else Color(0.02, 0.02, 0.025)
	var out := Vector3(sin(yaw), 0.0, -cos(yaw)) * 60.0
	_quad(Vector2(World.DOOR_HALF * 2.0 + 20.0, DOOR_H + 20.0), Vector3(at.x, DOOR_H / 2.0, at.y) + out,
			Vector3(0.0, yaw, 0.0), mat)
	if is_exit:
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.95, 0.78)
		glow.light_energy = 2.0
		glow.omni_range = 380.0
		glow.position = Vector3(at.x, DOOR_H * 0.6, at.y) - out * 0.5
		_target.add_child(glow)


## The short passage through the doorway in direction `dir`.
func _passage(dir: int, tint: Color, length := GAP) -> void:
	var r := World.ROOM
	var v := Vector2(World.DIR_VEC[dir])
	var dh := World.DOOR_HALF
	var mid := r.get_center() + v * (r.size / 2.0 + Vector2(length, length) / 2.0)
	var along_y := v.x == 0.0
	var size := Vector2(dh * 2.0, length) if along_y else Vector2(length, dh * 2.0)
	var floor_mat := _surface_mat("floor", Color(0.4, 0.42, 0.45))
	floor_mat.uv1_scale = Vector3(size.x / TEX_UNITS, size.y / TEX_UNITS, 1.0)
	_quad(size, Vector3(mid.x, 0.0, mid.y), Vector3(-PI / 2.0, 0.0, 0.0), floor_mat)
	var top := StandardMaterial3D.new()
	top.albedo_color = Color(0.06, 0.06, 0.07)
	_quad(size, Vector3(mid.x, DOOR_H, mid.y), Vector3(PI / 2.0, 0.0, 0.0), top)
	for side in [-1.0, 1.0]:
		if along_y:
			var x: float = mid.x + side * dh
			_wall(Vector2(x, mid.y - length / 2.0), Vector2(x, mid.y + length / 2.0), 0.0, DOOR_H,
					-side * PI / 2.0, tint)
		else:
			var z: float = mid.y + side * dh
			_wall(Vector2(mid.x - length / 2.0, z), Vector2(mid.x + length / 2.0, z), 0.0, DOOR_H,
					0.0 if side < 0.0 else PI, tint)


## The ceiling: tiles, beams, strip lights, pipes and a duct, so looking
## up shows a working base. `full` adds the small fittings (only worth it
## in the room you're in).
func _build_ceiling(tint: Color, full: bool) -> void:
	var r := World.ROOM
	var c := r.get_center()
	var tiles := StandardMaterial3D.new()
	tiles.albedo_texture = _ceiling_tex()
	tiles.albedo_color = Color(0.5, 0.5, 0.52).lerp(tint, 0.06)
	tiles.roughness = 0.9
	tiles.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tiles.uv1_scale = Vector3(r.size.x / TEX_UNITS, r.size.y / TEX_UNITS, 1.0)
	_quad(r.size, Vector3(c.x, WALL_H, c.y), Vector3(PI / 2.0, 0.0, 0.0), tiles)
	var steel := _plain_mat(Color(0.26, 0.27, 0.3), 0.6)
	var paint := _plain_mat(Color(0.36, 0.37, 0.4).lerp(tint, 0.1), 0.0)
	# A moulding where the walls meet the ceiling.
	_box(Vector3(r.size.x, 12, 10), Vector3(c.x, WALL_H - 6, r.position.y + 5), paint)
	_box(Vector3(r.size.x, 12, 10), Vector3(c.x, WALL_H - 6, r.end.y - 5), paint)
	_box(Vector3(10, 12, r.size.y), Vector3(r.position.x + 5, WALL_H - 6, c.y), paint)
	_box(Vector3(10, 12, r.size.y), Vector3(r.end.x - 5, WALL_H - 6, c.y), paint)
	# Steel beams across the room, between the lights.
	for fx in [0.12, 0.51, 0.9]:
		_box(Vector3(22, 18, r.size.y), Vector3(r.position.x + r.size.x * fx, WALL_H - 9, c.y), steel)
	# Strip lights, where the room's lamps hang.
	var housing := _plain_mat(Color(0.7, 0.7, 0.68), 0.3)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.95, 0.82).lerp(tint, 0.15)
	for fx in [0.3, 0.72]:
		var x: float = r.position.x + r.size.x * fx
		for dz in [-90.0, 90.0]:
			_box(Vector3(34, 8, 150), Vector3(x, WALL_H - 4, c.y + dz), housing)
			_box(Vector3(24, 2, 138), Vector3(x, WALL_H - 9, c.y + dz), glow)
	# Pipes along the back wall, and an air duct down the right-hand side.
	var pipe := _plain_mat(Color(0.42, 0.3, 0.22), 0.7)
	_pipe(r.size.x, 6.0, Vector3(c.x, WALL_H - 18, r.position.y + 18), pipe)
	_pipe(r.size.x, 3.5, Vector3(c.x, WALL_H - 34, r.position.y + 30), steel)
	_box(Vector3(36, 26, r.size.y), Vector3(r.end.x - 52, WALL_H - 14, c.y), _plain_mat(Color(0.5, 0.52, 0.54), 0.8))
	if not full:
		return
	for i in 6:
		var x := r.position.x + 90.0 + float(i) * (r.size.x - 180.0) / 5.0
		_box(Vector3(4, 40, 32), Vector3(x, WALL_H - 20, r.position.y + 22), steel)
	# Smoke detectors, each with a little red light.
	var led := StandardMaterial3D.new()
	led.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led.albedo_color = Color(1.0, 0.12, 0.08)
	for at in [Vector2(r.position.x + r.size.x * 0.4, c.y - 150.0), Vector2(r.position.x + r.size.x * 0.62, c.y + 170.0)]:
		var disc := CylinderMesh.new()
		disc.top_radius = 9.0
		disc.bottom_radius = 10.0
		disc.height = 5.0
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = _plain_mat(Color(0.85, 0.85, 0.82), 0.0)
		mi.position = Vector3(at.x, WALL_H - 2.5, at.y)
		_target.add_child(mi)
		_box(Vector3(2, 1, 2), Vector3(at.x + 5, WALL_H - 5.5, at.y), led)


func _plain_mat(col: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.55
	return m


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	_target.add_child(mi)
	return mi


## A pipe `length` long running along x.
func _pipe(length: float, radius: float, at: Vector3, mat: Material) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 10
	cyl.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = at
	mi.rotation = Vector3(0.0, 0.0, PI / 2.0)
	_target.add_child(mi)


## Ceiling tiles: two-by-two acoustic panels, speckled, with dark joins.
static func _ceiling_tex() -> ImageTexture:
	if _ceiling_cache:
		return _ceiling_cache
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	for y in 128:
		for x in 128:
			var v := 0.82 + rng.randf_range(-0.05, 0.05)
			if rng.randf() < 0.04:
				v -= 0.18  # the pinholes in acoustic tiles
			var ex := mini(x % 64, 63 - x % 64)
			var ey := mini(y % 64, 63 - y % 64)
			var edge := mini(ex, ey)
			if edge < 2:
				v = 0.22  # the metal grid between tiles
			elif edge < 4:
				v *= 0.86  # a bevel
			img.set_pixel(x, y, Color(v, v, v * 0.98))
	img.generate_mipmaps()
	_ceiling_cache = ImageTexture.create_from_image(img)
	return _ceiling_cache


## A corridor leading on out of a room next door: a short passage, a wall
## where it turns out of sight, and one weak lamp, so the base carries on.
func _stub(dir: int, tint: Color) -> void:
	_passage(dir, tint.darkened(0.3), STUB)
	var r := World.ROOM
	var v := Vector2(World.DIR_VEC[dir])
	var end := r.get_center() + v * (r.size / 2.0 + Vector2(STUB, STUB))
	var dh := World.DOOR_HALF
	var side := Vector2(-v.y, v.x) * dh
	# The far end faces back at you (yaw as the room's own walls use).
	_wall(end + side, end - side, 0.0, DOOR_H, atan2(-v.x, -v.y), tint.darkened(0.3))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.85, 0.9, 1.0).lerp(tint, 0.3)
	lamp.light_energy = 2.2
	lamp.omni_range = 260.0
	var at := end - v * (STUB * 0.45)
	lamp.position = Vector3(at.x, DOOR_H - 15.0, at.y)
	_target.add_child(lamp)


func _build_lights(tint: Color, strength: float) -> void:
	var r := World.ROOM
	var warm := Color(1.0, 0.86, 0.66).lerp(tint, 0.25)
	for fx in [0.3, 0.72]:
		var l := OmniLight3D.new()
		l.light_color = warm
		l.light_energy = 1.6 * strength
		l.omni_range = 620.0
		l.omni_attenuation = 1.2
		l.position = Vector3(r.position.x + r.size.x * fx, WALL_H - 20.0, r.get_center().y)
		_target.add_child(l)
	var spill := OmniLight3D.new()
	spill.light_color = tint
	spill.light_energy = 0.7 * strength
	spill.omni_range = 700.0
	spill.position = Vector3(r.get_center().x, WALL_H * 0.5, r.position.y + 40.0)
	_target.add_child(spill)


func _surface_mat(name: String, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/sprites/room/%s.png" % name)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/sprites/room/%s_n.png" % name)
	m.albedo_color = col
	m.roughness = 0.75
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func _quad(size: Vector2, at: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	_target.add_child(mi)
	return mi


# ------------------------------------------------------------------ furniture

func _place_furniture(f: Dictionary) -> Node3D:
	var kind: String = f["type"]
	if not _models.has(kind):
		var path := "res://assets/models/furniture/%s.glb" % kind
		_models[kind] = load(path) if ResourceLoader.exists(path) else null
	var node: Node3D
	if _models[kind] != null:
		node = (_models[kind] as PackedScene).instantiate()
	else:
		node = Node3D.new()
	var c: Vector2 = (f["rect"] as Rect2).get_center()
	node.position = Vector3(c.x, 0.0, c.y)
	node.rotation.y = deg_to_rad(WALL_ROT.get(f["wall"], 0.0))
	_target.add_child(node)
	return node


## Effects, your trap markers, the vent you're at and darts in flight (all
## from the overhead view).
func show_extras(effects: Array, my_traps: Dictionary, vent_highlight: int, darts: Array) -> void:
	_fx.sync(effects)
	_show_darts(darts)
	# Screens on the walls scroll and sweep, a few times a second.
	_decor_t += get_process_delta_time()
	if _decor_t > 0.12 and detail_high:
		_decor_t = 0.0
		for p in _painters:
			if is_instance_valid(p):
				p.refresh(_t)
	for i in _vents:
		var on: bool = i == vent_highlight
		var a := (0.25 + 0.2 * sin(_t * 6.0)) if on else 0.0
		_highlight_mat.albedo_color = Color(1.0, 0.86, 0.15, a)
		(_vents[i] as MeshInstance3D).material_overlay = _highlight_mat if on else null
	_sync_markers(my_traps)


## Darts in this room as small glinting needles, from a reused pool.
func _show_darts(darts: Array) -> void:
	var here := darts.filter(func(d): return d["room"] == room)
	while _darts.size() < here.size():
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(26.0, 2.5, 2.5)
		mi.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.88, 0.95)
		m.metallic = 0.8
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.35)
		m.emission_energy_multiplier = 0.6
		mi.material_override = m
		_room_root.add_child(mi)
		_darts.append(mi)
	for i in _darts.size():
		var mi: MeshInstance3D = _darts[i]
		mi.visible = i < here.size()
		if mi.visible:
			var p: Vector2 = here[i]["pos"]
			var v: Vector2 = here[i]["vel"]
			mi.position = Vector3(p.x, 70.0, p.y)
			mi.rotation = Vector3(0.0, -v.angle(), 0.0)


## A crawl-through vent: a slatted grille at floor level in a back wall.
func _place_vent(v: Dictionary) -> MeshInstance3D:
	var r := World.ROOM
	var w := World.VENT_HALF * 2.0
	var q := BoxMesh.new()
	q.size = Vector3(w, 46.0, 3.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _vent_mat
	if v["dir"] == World.Dir.UP:
		mi.position = Vector3(v["along"], 27.0, r.position.y + 1.0)
	else:
		mi.position = Vector3(r.position.x + 1.0, 27.0, v["along"])
		mi.rotation.y = PI / 2.0
	_room_root.add_child(mi)
	# Slats.
	for k in 5:
		var s := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(w - 6.0, 2.0, 2.0)
		s.mesh = sm
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.36, 0.4, 0.46)
		s.material_override = lm
		s.position = Vector3(0, -18.0 + k * 9.0, 2.0)
		mi.add_child(s)
	return mi


## Your own traps: a small warning sign over trapped furniture, and a
## glowing wire across trapped doorways. Only you see them.
func _sync_markers(my_traps: Dictionary) -> void:
	var want := {}
	for key: String in my_traps:
		if key.begins_with("D"):
			for dir in World.DIR_VEC:
				if world.opening(room, dir) == 1 and World.door_key(room, dir) == key:
					want[key] = [dir, my_traps[key]]
		elif key.begins_with("%d,%d," % [room.x, room.y]):
			want[key] = [int(key.get_slice(",", 2)), my_traps[key]]
	for key in _markers.keys():
		if not want.has(key):
			_markers[key].queue_free()
			_markers.erase(key)
	for key in want:
		if not _markers.has(key):
			_markers[key] = _door_wire(want[key][0]) if key.begins_with("D") else _trap_sign(want[key][0], want[key][1])
			_room_root.add_child(_markers[key])


func _trap_sign(idx: int, kind: String) -> Node3D:
	var f: Dictionary = world.furniture(room)[idx]
	var c: Vector2 = (f["rect"] as Rect2).get_center()
	var l := Label3D.new()
	l.text = "TRAP: " + World.TRAP_NAMES.get(kind, kind)
	l.font = Style.stencil()
	l.font_size = 30
	l.pixel_size = 0.25
	l.outline_modulate = Color.BLACK
	l.outline_size = 6
	l.modulate = Color(1.0, 0.82, 0.2)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(c.x, RoomView.HEIGHTS.get(f["type"], 50.0) + 22.0, c.y)
	return l


func _door_wire(dir: int) -> Node3D:
	var r := World.ROOM
	var v := Vector2(World.DIR_VEC[dir])
	var mid := r.get_center() + v * r.size / 2.0 - v * 6.0
	var b := BoxMesh.new()
	var along_x := v.y != 0.0
	b.size = Vector3(World.DOOR_HALF * 2.0, 1.5, 1.5) if along_x else Vector3(1.5, 1.5, World.DOOR_HALF * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.25, 0.2)
	mi.material_override = m
	mi.position = Vector3(mid.x, 10.0, mid.y)
	return mi


## A pulsing glow over the furniture you can search.
func _set_highlight(node: Node3D, on: bool) -> void:
	var a := (0.12 + 0.1 * sin(_t * 6.0)) if on else 0.0
	_highlight_mat.albedo_color = Color(1.0, 0.9, 0.45, a)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _highlight_mat if on else null


# ------------------------------------------------------------------ agents

func _add_cutout(a: Agent) -> void:
	var s := Sprite3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.shaded = false
	s.region_enabled = true
	var tex: Texture2D = a.sprite_sheet()
	s.texture = (tex as CanvasTexture).diffuse_texture if tex is CanvasTexture else tex
	_room_root.add_child(s)
	_cutouts[a] = s
	var l := Label3D.new()
	l.text = a.display_name
	l.modulate = a.accent
	l.font_size = 28
	l.outline_size = 6
	l.pixel_size = 0.22
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	_room_root.add_child(l)
	_labels[a] = l


## Nacho, if he's in this room (his sheet is drawn the same way as an agent's).
func _show_dog() -> void:
	var here: bool = dog != null and dog.room == room and dog.visible_now() and dog.sheet() != null
	if not here:
		if _dog_sprite:
			_dog_sprite.visible = false
		return
	if _dog_sprite == null:
		_dog_sprite = Sprite3D.new()
		_dog_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_dog_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_dog_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_dog_sprite.shaded = false
		_dog_sprite.region_enabled = true
		var tex: Texture2D = dog.sheet()
		_dog_sprite.texture = (tex as CanvasTexture).diffuse_texture if tex is CanvasTexture else tex
		_room_root.add_child(_dog_sprite)
	var frame: Dictionary = dog.frame_for_view(camera.position.x, camera.position.z)
	var centre: Vector2 = frame["centre"]
	_dog_sprite.visible = true
	_dog_sprite.region_rect = frame["region"]
	_dog_sprite.pixel_size = frame["scale"]
	_dog_sprite.position = Vector3(dog.position.x, -centre.y * frame["scale"], dog.position.y)
	_dog_sprite.offset = Vector2(centre.x, 0.0)
	_dog_sprite.modulate = Color(0.85, 0.85, 0.85)


## Picks the sprite frame for how this agent looks from the camera.
func _update_cutout(a: Agent) -> void:
	var s: Sprite3D = _cutouts[a]
	var frame: Dictionary = a.frame_for_view(camera.position.x, camera.position.z)
	s.region_rect = frame["region"]
	s.pixel_size = frame["scale"]
	# Sprite3D draws its region centred on the node; shift so the feet sit
	# on the agent's floor position.
	var centre: Vector2 = frame["centre"]
	s.position = Vector3(a.position.x, -centre.y * frame["scale"], a.position.y)
	s.offset = Vector2(centre.x, 0.0)
	var dim := 0.82
	s.modulate = Color(dim, dim, dim, 1.0).lerp(Color(1.0, 0.45, 0.45), clampf(a.hurt_time / 0.3, 0.0, 1.0))
	if a.ko_time > 0.0 and a.ko_kind == "SHOCK" and int(_t * 16.0) % 2 == 0:
		s.modulate = Color(0.75, 0.97, 1.0) if int(_t * 32.0) % 2 == 0 else Color(0.05, 0.06, 0.08)
	_labels[a].position = Vector3(a.position.x, 138.0, a.position.y)
