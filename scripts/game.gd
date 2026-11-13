extends Node2D
## One match: builds the base, spawns the agents, wires up the HUD and runs
## the rules.
##
## The host is the referee. Players (and the bot) ask the host to search,
## set a trap, walk through a door or escape; the host decides what happens,
## updates the match state and broadcasts the whole state plus an "event"
## describing what just happened. Every tablet then shows that event.
## Each tablet only draws the room its own agent is in.

signal leave_requested
signal rematch_requested
## Every match event, after it's been applied (handy for tests and effects).
signal event_happened(event: Dictionary)

const World = preload("res://scripts/world.gd")
const Agent = preload("res://scripts/agent.gd")
const RoomView = preload("res://scripts/room_view.gd")
const Hud = preload("res://scripts/hud.gd")
const Ui = preload("res://scripts/ui.gd")
const Bot = preload("res://scripts/bot.gd")

## Peer id used for the computer-controlled rival in one-player games.
const BOT_ID := 2

const SEARCH_TIME := 0.8
const TRAP_TIME := 1.2
const SEARCH_REACH := 46.0
const DOOR_REACH := 120.0
const KO_TIME := 4.0
const MAX_TRAPS := 3

const STYLES := [
	{"name": "AGENT CRIMSON", "coat": Color("b3262e"), "hat": Color("2a0d10"), "accent": Color("ff5a5f")},
	{"name": "AGENT COBALT", "coat": Color("1f5fae"), "hat": Color("0b1a33"), "accent": Color("5ab0ff")},
]

var world: World
var local_agent: Agent
var agents: Array[Agent] = []
var my_id := 1

# ---- Match state (owned by the host, mirrored on every tablet) ----
## What's in each piece of furniture: furniture_key -> item.
var contents := {}
## peer id -> { "items": [intel...], "case": bool, "gadgets": [gadget...] }
var inventories := {}
## furniture_key or door_key -> { "kind": "BOMB"|"SPRING"|"WIRE", "owner": peer id }
var traps := {}
var over := false

var bot: Bot
var _agent_by_id := {}
var _view: RoomView
var _hud: Hud
var _exit_cooldown := 0.0
var _rng := RandomNumberGenerator.new()


## `ids` holds every peer id in the match; the host (lowest id, 1) is Crimson.
func setup(seed_value: int, p_my_id: int, ids: Array, bot_level := "") -> void:
	my_id = p_my_id
	_rng.randomize()
	world = World.new(seed_value)
	contents = world.hidden.duplicate()
	_view = RoomView.new()
	_view.world = world
	add_child(_view)
	_view.position = Ui.center_offset(self)
	get_viewport().size_changed.connect(func(): _view.position = Ui.center_offset(self))

	var vs_bot := bot_level != ""
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
		inventories[id] = {"items": [], "case": false, "gadgets": []}
		if id == my_id:
			local_agent = a
	_view.agents = agents
	_view.highlight_color = local_agent.accent
	_view.my_id = my_id

	if vs_bot:
		var ba: Agent = _agent_by_id[BOT_ID]
		bot = Bot.new()
		add_child(bot)
		bot.setup(self, ba, BOT_ID, bot_level)
		ba.search_finished.connect(func(r, i): _handle_search(BOT_ID, r, i))
		ba.trap_finished.connect(func(info): _handle_trap(BOT_ID, info))
		ba.door_passed.connect(func(r, d): _handle_door(BOT_ID, r, d))
		ba.exit_touched.connect(func(): _handle_escape(BOT_ID))

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(world, local_agent.display_name, local_agent.accent)
	_hud.leave_requested.connect(func(): leave_requested.emit())
	_hud.rematch_requested.connect(func(): rematch_requested.emit())
	_hud.search_pressed.connect(_try_search)
	_hud.trap_chosen.connect(_try_trap)
	local_agent.room_changed.connect(_on_room_changed)
	local_agent.search_finished.connect(func(r, i): if not over: request_search.rpc_id(1, r, i))
	local_agent.trap_finished.connect(func(info): if not over: request_trap.rpc_id(1, info))
	local_agent.door_passed.connect(func(r, d): if not over: request_door.rpc_id(1, r, d))
	local_agent.exit_touched.connect(_on_exit_touched)
	_on_room_changed(local_agent.room, false)
	_hud.toast("Find all four pieces of intel, then reach the EXIT.\nWatch out for traps!", Color.WHITE, 4.0)


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

	var busy := over or local_agent.searching or local_agent.ko_time > 0.0
	var near := -1 if busy else nearest_furniture(local_agent)
	var door := -1 if busy else near_door(local_agent)
	_view.highlight = near
	_hud.search_button.enabled = near != -1
	_hud.set_trap_options(near != -1, door != -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E, KEY_SPACE: _try_search()
			KEY_1: _try_trap("BOMB")
			KEY_2: _try_trap("SPRING")
			KEY_3: _try_trap("WIRE")


func _on_room_changed(room: Vector2i, animate := true) -> void:
	_view.room = room
	_hud.show_room(room, animate)


# ------------------------------------------------------------------ helpers

## The closest furniture within arm's reach of `a`, or -1.
func nearest_furniture(a: Agent) -> int:
	var best := -1
	var best_d := INF
	var items: Array = world.furniture(a.room)
	var p := a.position
	for i in items.size():
		var r: Rect2 = items[i]["rect"]
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := p.distance_to(q)
		if d <= Agent.RADIUS + SEARCH_REACH and d < best_d:
			best = i
			best_d = d
	return best


## The doorway (to another room) that `a` is standing in front of, or -1.
func near_door(a: Agent) -> int:
	var R := World.ROOM
	var c := R.get_center()
	var best := -1
	var best_d := DOOR_REACH
	for dir in World.DIR_VEC:
		if world.opening(a.room, dir) != 1:
			continue
		var v := Vector2(World.DIR_VEC[dir])
		var door := c + v * R.size / 2.0
		var d := a.position.distance_to(door)
		if d < best_d:
			best_d = d
			best = dir
	return best


func _missing(pid: int) -> Array:
	var out := []
	for item in World.INTEL:
		if not inventories[pid]["items"].has(item):
			out.append(item)
	return out


func _sender() -> int:
	var pid := multiplayer.get_remote_sender_id()
	return pid if pid != 0 else multiplayer.get_unique_id()


func traps_owned_by(pid: int) -> int:
	var n := 0
	for k in traps:
		if traps[k]["owner"] == pid:
			n += 1
	return n


# ------------------------------------------------------------------ local input

func _try_search() -> void:
	if over or local_agent.searching or local_agent.ko_time > 0.0:
		return
	var idx := nearest_furniture(local_agent)
	if idx != -1:
		local_agent.start_search(idx, SEARCH_TIME)


func _try_trap(kind: String) -> void:
	if over or local_agent.searching or local_agent.ko_time > 0.0:
		return
	var key := ""
	if kind == "WIRE":
		var dir := near_door(local_agent)
		if dir == -1:
			_hud.toast("Stand by a doorway to rig a tripwire.", Color("ffd23f"), 2.0)
			return
		key = World.door_key(local_agent.room, dir)
	else:
		var idx := nearest_furniture(local_agent)
		if idx == -1:
			_hud.toast("Stand next to some furniture to hide a trap in it.", Color("ffd23f"), 2.0)
			return
		key = World.furniture_key(local_agent.room, idx)
	if traps_owned_by(my_id) >= MAX_TRAPS:
		_hud.toast("You've already got %d traps set. Use them before setting more!" % MAX_TRAPS, Color("ffd23f"), 2.5)
		return
	local_agent.start_trap({"kind": kind, "key": key}, TRAP_TIME)


func _on_exit_touched() -> void:
	if over or _exit_cooldown > 0.0:
		return
	_exit_cooldown = 2.0
	var missing := _missing(my_id)
	if missing.is_empty():
		request_escape.rpc_id(1)
	else:
		_hud.toast("The exit won't open yet. Still missing: %s" % ", ".join(PackedStringArray(missing)), Color("ffd23f"), 3.0)


# ------------------------------------------------------------------ host: requests

@rpc("any_peer", "call_local", "reliable")
func request_search(room: Vector2i, idx: int) -> void:
	if multiplayer.is_server():
		_handle_search(_sender(), room, idx)


@rpc("any_peer", "call_local", "reliable")
func request_trap(info: Dictionary) -> void:
	if multiplayer.is_server():
		_handle_trap(_sender(), info)


@rpc("any_peer", "call_local", "reliable")
func request_door(from_room: Vector2i, dir: int) -> void:
	if multiplayer.is_server():
		_handle_door(_sender(), from_room, dir)


@rpc("any_peer", "call_local", "reliable")
func request_escape() -> void:
	if multiplayer.is_server():
		_handle_escape(_sender())


# ------------------------------------------------------------------ host: rules

func _handle_search(pid: int, room: Vector2i, idx: int) -> void:
	if over or not inventories.has(pid):
		return
	var key := World.furniture_key(room, idx)
	var inv: Dictionary = inventories[pid]
	var disarmed := ""
	if traps.has(key):
		var kind: String = traps[key]["kind"]
		var remedy: String = World.TRAPS[kind]
		if inv["gadgets"].has(remedy):
			disarmed = kind
			traps.erase(key)
			_use_gadget(pid, remedy)
		else:
			_spring_trap(pid, key, room)
			return
	var found: String = contents.get(key, "")
	var left := ""
	contents.erase(key)
	if found in World.GADGETS:
		inv["gadgets"].append(found)
	elif found == World.BRIEFCASE:
		inv["case"] = true
	elif found != "":
		if not inv["case"] and inv["items"].size() >= 1:
			# Hands full, no briefcase: swap what you're holding for what you found.
			left = inv["items"][0]
			inv["items"].erase(left)
			contents[key] = left
		inv["items"].append(found)
	_broadcast({"type": "search", "pid": pid, "key": key, "found": found, "left": left, "disarmed": disarmed})


func _handle_trap(pid: int, info: Dictionary) -> void:
	if over or not inventories.has(pid):
		return
	var key: String = info.get("key", "")
	var kind: String = info.get("kind", "")
	var reason := ""
	if not World.TRAPS.has(kind) or key == "":
		reason = "That trap didn't work."
	elif traps.has(key):
		reason = "Something's already rigged here. Best leave it alone…"
	elif traps_owned_by(pid) >= MAX_TRAPS:
		reason = "You've already got %d traps set." % MAX_TRAPS
	if reason != "":
		_broadcast({"type": "trap_fail", "pid": pid, "reason": reason})
		return
	traps[key] = {"kind": kind, "owner": pid}
	_broadcast({"type": "trap_set", "pid": pid, "kind": kind, "key": key})


func _handle_door(pid: int, from_room: Vector2i, dir: int) -> void:
	if over or not inventories.has(pid):
		return
	var key := World.door_key(from_room, dir)
	if not traps.has(key):
		return
	var to_room: Vector2i = from_room + World.DIR_VEC[dir]
	var remedy: String = World.TRAPS["WIRE"]
	if inventories[pid]["gadgets"].has(remedy):
		traps.erase(key)
		_use_gadget(pid, remedy)
		_broadcast({"type": "disarm", "pid": pid, "kind": "WIRE"})
	else:
		_spring_trap(pid, key, to_room)


func _handle_escape(pid: int) -> void:
	if over:
		return
	if inventories.has(pid) and _missing(pid).is_empty():
		game_over.rpc(pid)


## The victim is knocked out and the intel they carry flies into the
## furniture around the room.
func _spring_trap(pid: int, key: String, room: Vector2i) -> void:
	var trap: Dictionary = traps[key]
	traps.erase(key)
	var lost: Array = inventories[pid]["items"].duplicate()
	inventories[pid]["items"].clear()
	for item in lost:
		_hide_somewhere(item, room)
	_broadcast({"type": "ko", "pid": pid, "kind": trap["kind"], "owner": trap["owner"], "room": room, "lost": lost})


## A gadget is used up, then turns up again somewhere else in the base.
func _use_gadget(pid: int, gadget: String) -> void:
	inventories[pid]["gadgets"].erase(gadget)
	_hide_somewhere(gadget, Vector2i(-1, -1))


## Puts `item` in an empty, untrapped piece of furniture, preferring `room`.
func _hide_somewhere(item: String, room: Vector2i) -> void:
	var here := []
	var anywhere := []
	for r in world.rooms:
		for i in world.furniture(r).size():
			var k := World.furniture_key(r, i)
			if contents.has(k) or traps.has(k):
				continue
			anywhere.append(k)
			if r == room:
				here.append(k)
	var pool := here if not here.is_empty() else anywhere
	if pool.is_empty():
		return
	contents[pool[_rng.randi_range(0, pool.size() - 1)]] = item


func _broadcast(event: Dictionary) -> void:
	sync_state.rpc(contents, inventories, traps, event)


# ------------------------------------------------------------------ everyone: results

@rpc("authority", "call_local", "reliable")
func sync_state(p_contents: Dictionary, p_inventories: Dictionary, p_traps: Dictionary, event: Dictionary) -> void:
	contents = p_contents
	inventories = p_inventories
	traps = p_traps
	for id in inventories:
		if _agent_by_id.has(id):
			_agent_by_id[id].has_case = inventories[id]["case"]
	var mine := {}
	for k in traps:
		if traps[k]["owner"] == my_id:
			mine[k] = traps[k]["kind"]
	_view.my_traps = mine
	var inv: Dictionary = inventories[my_id]
	_hud.set_inventory(inv["items"], inv["case"], inv["gadgets"])
	_on_event(event)
	if bot:
		bot.on_event(event)
	event_happened.emit(event)


func _on_event(e: Dictionary) -> void:
	var pid: int = e.get("pid", 0)
	var me := pid == my_id
	var col := local_agent.accent.lightened(0.3)
	var warn := Color("ffd23f")
	match e.get("type", ""):
		"search":
			if not me:
				return
			var found: String = e["found"]
			var msg := ""
			if e["disarmed"] != "":
				msg = "Defused a %s with your %s!  " % [World.TRAP_NAMES[e["disarmed"]], World.TRAPS[e["disarmed"]]]
			if found == "":
				_hud.toast(msg + "Nothing here.", col if msg != "" else Color(1, 1, 1, 0.8), 2.0 if msg != "" else 1.2)
			elif found in World.GADGETS:
				_hud.toast(msg + "Found the %s! It beats a %s." % [found, World.TRAP_NAMES[_trap_for(found)]], col, 3.0)
			elif found == World.BRIEFCASE:
				_hud.toast(msg + "Found a BRIEFCASE! Now you can carry everything.", col)
			elif e["left"] != "":
				_hud.toast(msg + "Found the %s, but your hands are full,\nso you left the %s here. Find a briefcase!" % [found, e["left"]], warn, 4.0)
			else:
				var n: int = inventories[my_id]["items"].size()
				var line := "Found the %s!  (%d/%d)" % [found, n, World.INTEL.size()]
				if n == World.INTEL.size():
					line = "Got the lot! Now get to the EXIT!"
				_hud.toast(msg + line, col)
		"trap_set":
			if me:
				_hud.toast("%s set. Only you can see the marker." % World.TRAP_NAMES[e["kind"]], col, 2.0)
		"trap_fail":
			if me:
				_hud.toast(e["reason"], warn, 2.5)
		"disarm":
			if me:
				_hud.toast("Snipped a TRIPWIRE with your WIRE CUTTERS!", col, 2.5)
		"ko":
			var victim: Agent = _agent_by_id[pid]
			victim.knock_out(e["kind"], KO_TIME)
			_view.add_effect(e["kind"], e["room"], victim.position)
			var lost: Array = e["lost"]
			var dropped := " Your intel went flying!" if not lost.is_empty() else ""
			var trap_name: String = World.TRAP_NAMES[e["kind"]]
			if me and e["owner"] == my_id:
				_hud.toast("Caught in your own %s! Nice one.%s" % [trap_name, dropped], warn, 3.5)
				_hud.flash(Color("ff3f8e"))
			elif me:
				_hud.toast("%s!%s" % [_exclamation(e["kind"]), " You walked into a %s.%s" % [trap_name, dropped]], warn, 3.5)
				_hud.flash(Color("ff3f8e"))
			elif e["owner"] == my_id:
				_hud.toast("Your %s got %s!" % [trap_name, victim.display_name], col, 3.0)


static func _trap_for(gadget: String) -> String:
	for t in World.TRAPS:
		if World.TRAPS[t] == gadget:
			return t
	return ""


static func _exclamation(kind: String) -> String:
	match kind:
		"BOMB": return "SPLAT"
		"SPRING": return "BOING"
		_: return "TWANG"


@rpc("authority", "call_local", "reliable")
func game_over(winner: int) -> void:
	over = true
	for a in agents:
		a.frozen = true
	_hud.show_end(winner == my_id, _agent_by_id[winner].display_name, multiplayer.is_server())
