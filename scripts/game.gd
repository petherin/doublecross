extends Node2D
## One match: builds the base, spawns both agents, wires up the HUD and runs
## the rules. The host is the referee: searches and escapes are requested from
## the host, which decides the outcome and broadcasts it to both tablets.
## Each tablet only draws the room its own agent is in; the rival is visible
## only while you're in the same room.

signal leave_requested
signal rematch_requested

const World = preload("res://scripts/world.gd")
const Agent = preload("res://scripts/agent.gd")
const RoomView = preload("res://scripts/room_view.gd")
const Hud = preload("res://scripts/hud.gd")
const Ui = preload("res://scripts/ui.gd")
const Bot = preload("res://scripts/bot.gd")

## Peer id used for the computer-controlled rival in one-player games.
const BOT_ID := 2

const SEARCH_TIME := 0.8
const SEARCH_REACH := 46.0

const STYLES := [
	{"name": "AGENT CRIMSON", "coat": Color("b3262e"), "hat": Color("2a0d10"), "accent": Color("ff5a5f")},
	{"name": "AGENT COBALT", "coat": Color("1f5fae"), "hat": Color("0b1a33"), "accent": Color("5ab0ff")},
]

var world: World
var local_agent: Agent
var agents: Array[Agent] = []
var my_id := 1

## What's in each piece of furniture right now: furniture_key -> item.
var contents := {}
## peer id -> { "items": Array[String], "case": bool }
var inventories := {}
var over := false

var _agent_by_id := {}
var _view: RoomView
var _hud: Hud
var _exit_cooldown := 0.0
var bot: Bot


## `ids` holds every peer id in the match; the host (lowest id, 1) is Crimson.
func setup(seed_value: int, p_my_id: int, ids: Array, vs_bot := false) -> void:
	my_id = p_my_id
	world = World.new(seed_value)
	contents = world.hidden.duplicate()
	_view = RoomView.new()
	_view.world = world
	add_child(_view)
	_view.position = Ui.center_offset(self)
	get_viewport().size_changed.connect(func(): _view.position = Ui.center_offset(self))

	if vs_bot:
		ids.append(BOT_ID)
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var a := Agent.new()
		a.name = "Agent_%d" % id
		a.set_multiplayer_authority(id)
		var start := Vector2i(0, 0) if i == 0 else Vector2i(World.COLS - 1, World.ROWS - 1)
		var style: Dictionary = STYLES[i % STYLES.size()].duplicate()
		var is_bot := vs_bot and id == BOT_ID
		if is_bot:
			style["name"] += " (BOT)"
		# The bot's agent is simulated on this device, like the player's own.
		a.configure(world, start, id == my_id or is_bot, style)
		add_child(a)
		agents.append(a)
		_agent_by_id[id] = a
		inventories[id] = {"items": [], "case": false}
		if id == my_id:
			local_agent = a
	_view.agents = agents
	_view.highlight_color = local_agent.accent

	if vs_bot:
		var ba: Agent = _agent_by_id[BOT_ID]
		bot = Bot.new()
		add_child(bot)
		bot.setup(self, ba, BOT_ID)
		ba.search_finished.connect(func(r, i): _handle_search(BOT_ID, r, i))
		ba.exit_touched.connect(func(): _handle_escape(BOT_ID))

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(world, local_agent.display_name, local_agent.accent)
	_hud.leave_requested.connect(func(): leave_requested.emit())
	_hud.rematch_requested.connect(func(): rematch_requested.emit())
	_hud.search_pressed.connect(_try_search)
	local_agent.room_changed.connect(_on_room_changed)
	local_agent.search_finished.connect(_on_search_finished)
	local_agent.exit_touched.connect(_on_exit_touched)
	_on_room_changed(local_agent.room, false)
	_hud.toast("Find the PASSPORT, CASH, MICROFILM and KEYCARD,\nthen get to the EXIT. Without a briefcase you can only carry one thing.", Color.WHITE, 5.0)


func _process(delta: float) -> void:
	if local_agent == null:
		return
	_exit_cooldown -= delta
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var wasd := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var move := kb + wasd
	if _hud.joystick.output != Vector2.ZERO:
		move = _hud.joystick.output
	# Controls are screen-relative: up on the stick = up the screen.
	local_agent.move_input = World.screen_to_floor_dir(move.limit_length(1.0))

	var near := -1 if over or local_agent.searching else _nearest_furniture()
	_view.highlight = near
	_hud.search_button.enabled = near != -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_SPACE:
			_try_search()


func _on_room_changed(room: Vector2i, animate := true) -> void:
	_view.room = room
	_hud.show_room(room, animate)


# ------------------------------------------------------------------ searching

## The closest furniture within arm's reach of the local agent, or -1.
func _nearest_furniture() -> int:
	var best := -1
	var best_d := INF
	var items: Array = world.furniture(local_agent.room)
	var p := local_agent.position
	for i in items.size():
		var r: Rect2 = items[i]["rect"]
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := p.distance_to(q)
		if d <= Agent.RADIUS + SEARCH_REACH and d < best_d:
			best = i
			best_d = d
	return best


func _try_search() -> void:
	if over or local_agent.searching:
		return
	var idx := _nearest_furniture()
	if idx != -1:
		local_agent.start_search(idx, SEARCH_TIME)


func _on_search_finished(room: Vector2i, idx: int) -> void:
	if not over:
		request_search.rpc_id(1, room, idx)


## Runs on the host: decides what the searcher finds.
@rpc("any_peer", "call_local", "reliable")
func request_search(room: Vector2i, idx: int) -> void:
	if multiplayer.is_server():
		_handle_search(_sender(), room, idx)


func _handle_search(pid: int, room: Vector2i, idx: int) -> void:
	if over or not inventories.has(pid):
		return
	var found: String = contents.get(World.furniture_key(room, idx), "")
	var left := ""
	var inv: Dictionary = inventories[pid]
	if found != "" and found != World.BRIEFCASE and not inv["case"] and inv["items"].size() >= 1:
		# Hands full and no briefcase: swap what you're holding for what you found.
		left = inv["items"][0]
	apply_search.rpc(pid, room, idx, found, left)


## Runs everywhere: applies the host's decision.
@rpc("authority", "call_local", "reliable")
func apply_search(pid: int, room: Vector2i, idx: int, found: String, left: String) -> void:
	var key := World.furniture_key(room, idx)
	var inv: Dictionary = inventories[pid]
	contents.erase(key)
	if left != "":
		inv["items"].erase(left)
		contents[key] = left
	if found == World.BRIEFCASE:
		inv["case"] = true
	elif found != "":
		inv["items"].append(found)
	_agent_by_id[pid].has_case = inv["case"]
	if bot and pid == BOT_ID:
		bot.on_search_result(key, found, left)
	if pid != my_id:
		return
	_hud.set_inventory(inv["items"], inv["case"])
	var col := local_agent.accent.lightened(0.3)
	if found == "":
		_hud.toast("Nothing here.", Color(1, 1, 1, 0.8), 1.2)
	elif found == World.BRIEFCASE:
		_hud.toast("Found a BRIEFCASE! Now you can carry everything.", col)
	elif left != "":
		_hud.toast("Found the %s, but your hands are full,\nso you left the %s here. Find a briefcase!" % [found, left], Color("ffd23f"), 4.0)
	else:
		var n := 0
		for item in inv["items"]:
			if item in World.INTEL:
				n += 1
		var msg := "Found the %s!  (%d/%d)" % [found, n, World.INTEL.size()]
		if n == World.INTEL.size():
			msg = "Got the lot! Now get to the EXIT!"
		_hud.toast(msg, col)


# ------------------------------------------------------------------ escaping

func _missing(pid: int) -> Array:
	var out := []
	for item in World.INTEL:
		if not inventories[pid]["items"].has(item):
			out.append(item)
	return out


func _on_exit_touched() -> void:
	if over or _exit_cooldown > 0.0:
		return
	_exit_cooldown = 2.0
	var missing := _missing(my_id)
	if missing.is_empty():
		request_escape.rpc_id(1)
	else:
		_hud.toast("The exit won't open yet. Still missing: %s" % ", ".join(PackedStringArray(missing)), Color("ffd23f"), 3.0)


@rpc("any_peer", "call_local", "reliable")
func request_escape() -> void:
	if multiplayer.is_server():
		_handle_escape(_sender())


func _handle_escape(pid: int) -> void:
	if over:
		return
	if inventories.has(pid) and _missing(pid).is_empty():
		game_over.rpc(pid)


@rpc("authority", "call_local", "reliable")
func game_over(winner: int) -> void:
	over = true
	for a in agents:
		a.frozen = true
	_hud.show_end(winner == my_id, _agent_by_id[winner].display_name, multiplayer.is_server())


func _sender() -> int:
	var pid := multiplayer.get_remote_sender_id()
	return pid if pid != 0 else multiplayer.get_unique_id()
