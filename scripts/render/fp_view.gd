extends Node3D
## First-person view of the room the local agent is in: real 3D walls, floor
## and Blender-modelled furniture, with the other agents as Doom-style
## cut-outs picked from their 8-direction sprite sheets.
##
## Floor (x, y) in game units maps to 3D (x, height, y); one 3D unit is one
## game unit, so the furniture models and footprints line up exactly.

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")

## Taller than the isometric cut-away walls, so the room feels enclosed.
const WALL_H := 210.0
const DOOR_H := 150.0
const EYE_H := 104.0
## The room textures cover 128 units each way (the wall is 110 high).
const TEX_UNITS := 128.0
const WALL_ROT := {"top": 0.0, "bottom": 180.0, "left": 90.0, "right": -90.0, "free": 0.0}

var world: World
var room := Vector2i(-1, -1)
var camera: Camera3D
var _room_root: Node3D
var _env: WorldEnvironment
var _furniture: Array = []        # MeshInstance3D roots, by furniture index
var _cutouts := {}                # Agent -> Sprite3D
var _labels := {}                 # Agent -> Label3D
var _highlight_mat: StandardMaterial3D
var _models := {}
var _t := 0.0


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
	add_child(_env)
	_room_root = Node3D.new()
	add_child(_room_root)
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


## Turns the view on or off (the 2D isometric view is used when off).
func set_active(on: bool) -> void:
	visible = on
	camera.current = on
	_env.environment = _env.environment if on else _env.environment


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
	var tint: Color = world.rooms[room]["tint"]
	_env.environment.ambient_light_color = Color(0.32, 0.33, 0.38).lerp(tint, 0.2)
	_env.environment.ambient_light_energy = 0.9
	_build_shell(tint)
	_build_lights(tint)
	var items: Array = world.furniture(room)
	for f in items:
		_furniture.append(_place_furniture(f))


## Follows the local agent and draws the others; `highlight` is the
## furniture index the player can search (or -1).
func update_view(me: Agent, agents: Array, highlight: int, delta: float) -> void:
	_t += delta
	camera.position = Vector3(me.position.x, EYE_H + sin(_t * 9.0) * (2.0 if me.moving else 0.0), me.position.y)
	camera.rotation = Vector3(0.0, -me.facing - PI / 2.0, 0.0)
	for i in _furniture.size():
		_set_highlight(_furniture[i], i == highlight)
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

func _build_shell(tint: Color) -> void:
	var r := World.ROOM
	var floor_mat := _surface_mat("floor", Color(0.5, 0.52, 0.56).lerp(tint, 0.04))
	floor_mat.uv1_scale = Vector3(r.size.x / TEX_UNITS, r.size.y / TEX_UNITS, 1.0)
	_quad(Vector2(r.size.x, r.size.y), Vector3(r.get_center().x, 0.0, r.get_center().y),
			Vector3(-PI / 2.0, 0.0, 0.0), floor_mat)
	var ceiling := StandardMaterial3D.new()
	ceiling.albedo_color = Color(0.09, 0.09, 0.11)
	_quad(Vector2(r.size.x, r.size.y), Vector3(r.get_center().x, WALL_H, r.get_center().y),
			Vector3(PI / 2.0, 0.0, 0.0), ceiling)
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
		var opening := world.opening(room, dir)
		var along := (b - a).normalized()
		var length := a.distance_to(b)
		var mid_t := length / 2.0
		var spans := [[0.0, length]] if opening == 0 else [[0.0, mid_t - dh], [mid_t + dh, length]]
		for sp in spans:
			_wall(a + along * sp[0], a + along * sp[1], 0.0, WALL_H, w[2], tint)
		if opening != 0:
			_wall(a + along * (mid_t - dh), a + along * (mid_t + dh), DOOR_H, WALL_H, w[2], tint)
			_doorway(a + along * mid_t, w[2], opening == 2)


func _wall(a: Vector2, b: Vector2, bottom: float, top: float, yaw: float, tint: Color) -> void:
	var length := a.distance_to(b)
	var mat := _surface_mat("wall", Color(0.62, 0.64, 0.7).lerp(tint, 0.05))
	var h := top - bottom
	# The texture is one 110-unit panel high: stack panels up the wall.
	mat.uv1_scale = Vector3(length / TEX_UNITS, h / 110.0, 1.0)
	var mid := (a + b) / 2.0
	_quad(Vector2(length, h), Vector3(mid.x, bottom + h / 2.0, mid.y), Vector3(0.0, yaw, 0.0), mat)


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
		_room_root.add_child(glow)


func _build_lights(tint: Color) -> void:
	var r := World.ROOM
	var warm := Color(1.0, 0.86, 0.66).lerp(tint, 0.25)
	for fx in [0.3, 0.72]:
		var l := OmniLight3D.new()
		l.light_color = warm
		l.light_energy = 1.6
		l.omni_range = 620.0
		l.omni_attenuation = 1.2
		l.position = Vector3(r.position.x + r.size.x * fx, WALL_H - 20.0, r.get_center().y)
		_room_root.add_child(l)
	var spill := OmniLight3D.new()
	spill.light_color = tint
	spill.light_energy = 0.7
	spill.omni_range = 700.0
	spill.position = Vector3(r.get_center().x, WALL_H * 0.5, r.position.y + 40.0)
	_room_root.add_child(spill)


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
	_room_root.add_child(mi)
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
	_room_root.add_child(node)
	return node


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
	_labels[a].position = Vector3(a.position.x, 138.0, a.position.y)
