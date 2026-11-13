extends Node2D
## One match: builds the base, spawns both agents and wires up the HUD.
## Each tablet only draws the room its own agent is in; the rival is
## visible only while you're in the same room.

signal leave_requested

const World = preload("res://scripts/world.gd")
const Agent = preload("res://scripts/agent.gd")
const RoomView = preload("res://scripts/room_view.gd")
const Hud = preload("res://scripts/hud.gd")

const STYLES := [
	{"name": "AGENT CRIMSON", "coat": Color("b3262e"), "hat": Color("2a0d10"), "accent": Color("ff5a5f")},
	{"name": "AGENT COBALT", "coat": Color("1f5fae"), "hat": Color("0b1a33"), "accent": Color("5ab0ff")},
]

var world: World
var local_agent: Agent
var agents: Array[Agent] = []
var _view: RoomView
var _hud: Hud


## `ids` holds every peer id in the match; the host (id 1) is always Crimson.
func setup(seed_value: int, my_id: int, ids: Array) -> void:
	world = World.new(seed_value)
	_view = RoomView.new()
	_view.world = world
	add_child(_view)

	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var a := Agent.new()
		a.name = "Agent_%d" % id
		a.set_multiplayer_authority(id)
		var start := Vector2i(0, 0) if i == 0 else Vector2i(World.COLS - 1, World.ROWS - 1)
		a.configure(world, start, id == my_id, STYLES[i % STYLES.size()])
		add_child(a)
		agents.append(a)
		if id == my_id:
			local_agent = a

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(world, local_agent.display_name, local_agent.accent)
	_hud.leave_requested.connect(func(): leave_requested.emit())
	local_agent.room_changed.connect(_on_room_changed)
	_on_room_changed(local_agent.room, false)


func _process(_delta: float) -> void:
	if local_agent == null:
		return
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var wasd := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var move := kb + wasd
	if _hud.joystick.output != Vector2.ZERO:
		move = _hud.joystick.output
	local_agent.move_input = move
	for a in agents:
		a.visible = a.room == local_agent.room


func _on_room_changed(room: Vector2i, animate := true) -> void:
	_view.room = room
	_hud.show_room(room, animate)
